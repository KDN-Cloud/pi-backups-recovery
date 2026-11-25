# Pi backup and recovery

The Raspberry Pi 4 backs up its boot SSD to the UNAS while SSH, Docker,
containerd, and cron continue running. The job uses [raspiBackup](https://github.com/framps/raspiBackup)
to stage the boot partition, partition metadata, and root filesystem locally,
then writes a compressed archive to the UNAS. See [RESTORE.md](RESTORE.md) for
recovery from either archive format.

| Setting | Value |
| --- | --- |
| Schedule | Daily at 03:00:42 Pacific via `raspiBackup.timer` |
| Job | `raspiBackup.service`, with the online runner as its entry point |
| Destination | `/mnt/unas_backups/raspberrypi-online/` on the UNAS NFS export |
| Format | Zstandard-compressed tar archive containing a raspiBackup rsync snapshot |
| Retention | Two completed online archives |
| Results | systemd journal, Telegram completion reports, and failure email through the Pi's local SMTP hook |

## What the backup captures

- Vikunja PostgreSQL is backed up with WAL streaming and checked with
  `pg_verifybackup`.
- Uptime Kuma's embedded MariaDB is dumped in a transaction, imported into an
  isolated local instance, and checked before the copied database is archived.
- CrowdSec SQLite is copied with SQLite's online backup API and checked with
  `PRAGMA integrity_check`.

The runner places these database copies at their regular paths inside the
staged snapshot. It captures the rest of the filesystem while the Pi is live.
The database copies and filesystem have separate capture times within the
run.

Staging on local ext4 and archiving with GNU tar preserves Linux ownership,
ACLs, extended attributes, and sparse files on the UNAS export. The runner
checks the mounted NFS source, reads the compressed archive back, saves a
SHA-256 manifest, and publishes the completed directory before rotating old
online archives.

Each completed `online-YYYYMMDD-HHMMSS` directory contains four files.

- `raspibackup.tar.zst`
- `SHA256SUMS`
- `raspibackup-online.conf`
- `RESTORE.txt`

Legacy full-disk images were stored under `/mnt/unas_backups/raspberrypi/`.
During the migration, the runner can keep one named legacy image as a fallback.
It retires that image after publishing a second online archive and rechecking
the previous archive's SHA-256 checksum.

## Check or run a backup

```bash
systemctl list-timers --all raspiBackup.timer
systemctl show raspiBackup.timer -p LastTriggerUSec
systemctl show raspiBackup.service -p Result -p ExecMainStatus
sudo journalctl -u raspiBackup.service -n 60 --no-pager
```

Look for `Verified backup published` in the service journal and confirm that
the corresponding online directory contains the archive and its manifest.
Substitute the actual directory name when checking a selected archive from
the Pi.

```bash
sudo bash -c 'cd "$1" && sha256sum --check --strict SHA256SUMS' _ \
    /mnt/unas_backups/raspberrypi-online/online-YYYYMMDD-HHMMSS
```

Start the service used by the timer when you need an on-demand online backup.

```bash
sudo systemctl start raspiBackup.service
```

The old root cron entry and direct `raspiBackup.sh` backup command belong to
the legacy disk-image workflow. An older deployment's global raspiBackup
configuration may still contain service-stop hooks.

## Rebuild the backup setup

Use Raspberry Pi OS with Docker, the expected application containers and bind
mounts, Python 3, GNU tar, rsync, zstd, and NFS client tools. Allow room on the
Pi's ext4 filesystem for a full local staging copy. The live setup was
validated with raspiBackup 0.7.2.

1. Install raspiBackup if it is missing. Use the [upstream installer reference](https://framps.github.io/raspiBackupDoc/installer.html)
   or run `bash raspiBackup-install.sh` from this repository. Before enabling
   the online timer, remove any old raspiBackup entry from root's crontab.
2. Mount the correct UNAS export at `/mnt/unas_backups`. The Pi uses an
   `/etc/fstab` entry like the one below. Replace the example host and export.
3. Install the files below. Use the repository's baseline `raspiBackup.conf`
   if a global config needs to be recreated. It leaves the default destination
   blank and service hooks disabled. Keep the online overrides in their own
   file.
4. Set `expected_export` in the installed runner to the exact source reported
   by `findmnt`. The runner and the rsync exclusions expect the existing Pi's
   application paths. Update both together if an app's bind mount changes.
   Leave `legacy_name` blank for a fresh build. For a migration, set it only
   to the directory name of the specific legacy disk image selected for
   retirement.

```fstab
UNAS_HOST:/path/to/export /mnt/unas_backups nfs defaults,_netdev,x-systemd.automount,x-systemd.idle-timeout=600 0 0
```

```bash
ls /mnt/unas_backups
findmnt -rn -M /mnt/unas_backups -t nfs,nfs4 -o SOURCE

sudo install -m 0700 raspibackup-online /usr/local/sbin/raspibackup-online
sudo install -m 0700 raspibackup-telegram /usr/local/sbin/raspibackup-telegram
sudo install -m 0600 raspibackup-online.conf /usr/local/etc/raspibackup-online.conf
sudo test -f /usr/local/etc/raspiBackup.conf ||
    sudo install -D -m 0600 raspiBackup.conf /usr/local/etc/raspiBackup.conf
sudo install -D -m 0644 RESTORE.txt /usr/local/share/raspibackup-online/RESTORE.txt
sudo install -D -m 0644 systemd/raspiBackup.service.d/online.conf \
    /etc/systemd/system/raspiBackup.service.d/online.conf
sudo test -f /etc/systemd/system/raspiBackup.service ||
    sudo install -m 0644 systemd/raspiBackup.service /etc/systemd/system/raspiBackup.service
sudo install -m 0644 systemd/raspiBackup.timer /etc/systemd/system/raspiBackup.timer
sudoedit /usr/local/sbin/raspibackup-online
```

The timer uses the Pi's local timezone. Check that the Pi uses
`America/Los_Angeles` and that its old backup cron entry is gone.
Restore the Telegram and failure email credentials before enabling the timer.

```bash
timedatectl show -p Timezone
sudo crontab -l
sudo systemd-analyze verify /etc/systemd/system/raspiBackup.service \
    /etc/systemd/system/raspiBackup.timer
sudo systemctl daemon-reload
sudo systemctl enable --now raspiBackup.timer
systemctl list-timers --all raspiBackup.timer
```

## Telegram completion reports

The systemd service sends a Telegram message after the backup run ends. A
successful report follows archive verification and publication. Failed runs
send a failure report and still invoke the separate email hook. Telegram
delivery errors are logged without changing the backup result.

Store the bot token and chat ID on the Pi in the root-only file
`/etc/raspibackup-alerts/telegram.json`. The online backup excludes this file
and its provisioning scratch files. Recreate it from a secure copy after
recovery. For a token change, use the existing bot in
[BotFather](https://t.me/BotFather) so the destination chat stays the same.

```bash
sudo install -d -m 0700 /etc/raspibackup-alerts
sudo test -e /etc/raspibackup-alerts/telegram.json ||
    sudo install -m 0600 /dev/null /etc/raspibackup-alerts/telegram.json
sudoedit /etc/raspibackup-alerts/telegram.json
```

Replace the example values with the bot token and destination chat ID. Add
`message_thread_id` as a number when reporting to a Telegram topic.

```json
{
  "token": "TOKEN_FROM_BOTFATHER",
  "chat_id": 123456789
}
```

```bash
sudo /usr/local/sbin/raspibackup-telegram --check
sudo /usr/local/sbin/raspibackup-telegram --test
```

The first command checks the credential. The second sends a labeled
delivery test to the configured chat.

## Failure email

On a failed service run, systemd invokes
`/usr/local/sbin/raspibackup-failure-mail` with a nonzero exit status. Restore
the executable hook and the root-only credential at
`/etc/raspibackup-alerts/smtp-password` from the secured deployment. The
online job clears the built-in raspiBackup email and Telegram settings for
its local staging run. Systemd sends reports for the final result.
[Notification routing](https://git.kf7.dev/KDN-Home-Lab/notification-routing)

```bash
sudo test -x /usr/local/sbin/raspibackup-failure-mail
sudo test -s /etc/raspibackup-alerts/smtp-password
```

When an email delivery test is needed, the following command sends a labeled
test message through the configured route.

```bash
sudo /usr/local/sbin/raspibackup-failure-mail 1 --test
```
