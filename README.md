# Pi backup and recovery

The Raspberry Pi 4 uses [raspiBackup](https://github.com/framps/raspiBackup) to create full-disk images of its boot SSD on the UNAS. Each image includes the partition table, boot partition, and root filesystem. See [RESTORE.md](RESTORE.md) for recovery from the current raw images and older gzip images.

| Setting | Live value |
|---|---|
| Schedule | Every day at 03:00 Pacific via root cron |
| Format | Full-disk `dd` image (`.img`) with sparse writes |
| Destination | UNAS NFS share mounted at `/mnt/unas_backups` |
| Backup directories | `/mnt/unas_backups/raspberrypi/` |
| Retention | Three `dd` backup sets |
| Completion notices | Telegram for success and failure |
| Failure email | Fastmail to `alerts@kf7.dev`, filed in `Homelab/raspiBackup` |

## Schedule and service downtime

The root crontab contains one raspiBackup job. The separate `raspiBackup.timer` is disabled.

```cron
00 03 * * * /usr/local/bin/raspiBackup.sh -m 0 -D conv=sparse || /usr/local/sbin/raspibackup-failure-mail "$?" ; /usr/bin/systemctl restart docker cron
```

The `-D conv=sparse` option skips writing zero-filled blocks to the NAS. The resulting image still has the original disk's logical size and contents. The option belongs on the backup command. Leave `DEFAULT_DD_PARMS` empty so a restore writes every block, including zeros. [GNU dd documentation](https://www.gnu.org/software/coreutils/manual/html_node/dd-invocation.html#dd-invocation)

raspiBackup stops Docker, cron, and containerd before imaging and starts them in reverse order afterward. The cron command also restarts Docker and cron when the job finishes. Expect container downtime during the backup.

## Notifications and backup checks

raspiBackup uses `DEFAULT_TELEGRAM_NOTIFICATIONS="SF"` for Telegram completion notices. On a nonzero backup exit, the cron command calls `/usr/local/sbin/raspibackup-failure-mail` with the exit status. The hook uses a root-only Fastmail SMTP credential on the Pi and can send while Docker is down. Fastmail files `raspiBackup <notify@kf7.dev>` messages with the subject `[raspiBackup] Raspberry Pi backup failed` in `Homelab/raspiBackup`. [Notification routing](https://git.kf7.dev/ak/notification-routing)

Each completed backup directory contains the image, `raspiBackup.msg`, and `raspiBackup.log`. Confirm that the latest scheduled directory has an image and that its message file says the backup finished successfully. Compare logical size and allocated space with `ls -lh` and `du -h` on the image.

To send a clearly labeled failure email test without running a backup, use the same hook with its test flag and check the Fastmail folder.

```bash
sudo /usr/local/sbin/raspibackup-failure-mail 1 --test
```

## Rebuilding the backup setup

Use an SSH identity with access to Gitea if you need a fresh copy of the recovery repository. The installer helper sets up raspiBackup on a fresh Pi.

```bash
git clone ssh://git@git.kf7.dev:222/ak/pi-backups-recovery.git
cd pi-backups-recovery
bash raspiBackup-install.sh
```

The sanitized `raspiBackup.conf` template enables gzip. When rebuilding the live setup, use these settings in `/usr/local/etc/raspiBackup.conf` and restore the Telegram credentials separately.

```bash
DEFAULT_BACKUPPATH="/mnt/unas_backups"
DEFAULT_BACKUPTYPE="dd"
DEFAULT_ZIP_BACKUP="0"
DEFAULT_KEEPBACKUPS="3"
DEFAULT_SMART_RECYCLE="0"
DEFAULT_DD_PARMS=""
DEFAULT_EMAIL=""
DEFAULT_TELEGRAM_NOTIFICATIONS="SF"
DEFAULT_STOPSERVICES="systemctl stop docker && systemctl stop cron && systemctl stop containerd"
DEFAULT_STARTSERVICES="systemctl start containerd && systemctl start cron && systemctl start docker"
```

The Pi mounts the share through `/etc/fstab` with a systemd automount. Substitute the UNAS host and export from your network setup when rebuilding the mount.

```fstab
UNAS_HOST:/path/to/export /mnt/unas_backups nfs vers=3,_netdev,x-systemd.automount,x-systemd.idle-timeout=600 0 0
```

Check that the path resolves to the NFS mount and that the failure hook and its credential file exist before installing the single cron entry above.

```bash
ls /mnt/unas_backups
findmnt -rn -t nfs,nfs4 -T /mnt/unas_backups
sudo test -x /usr/local/sbin/raspibackup-failure-mail
sudo test -s /etc/raspibackup-alerts/smtp-password
sudo crontab -l
```

A full image taken after the alert setup includes the hook and its local configuration. When recovering from an older image or setting up a fresh Pi, restore the hook and its Fastmail credential from the secured deployment before relying on failure email.

Use `sudo crontab -e` to install the single daily entry shown above. Once the cron entry is in place, disable the separate systemd timer if the installer enabled it.

```bash
sudo systemctl disable --now raspiBackup.timer
```

For a manual backup with the live image format, run the following during a maintenance window. The scheduled cron entry supplies the failure email hook.

```bash
sudo /usr/local/bin/raspiBackup.sh -m 0 -D conv=sparse
```
