# Restore the Raspberry Pi boot disk

Use the newest verified online archive under
`/mnt/unas_backups/raspberrypi-online/`. If recovering a saved raw disk image,
see [Legacy raw and gzip images](#legacy-raw-and-gzip-images).

## Restore an online archive

Use a separate Raspberry Pi booted from recovery media, or another compatible
Linux system. Install raspiBackup 0.7.2 or a compatible version, GNU tar, and
zstd. Mount the UNAS share and prepare an empty directory on a local ext4
filesystem with room for the unpacked snapshot.
[raspiBackup restore documentation](https://framps.github.io/raspiBackupDoc/restore-intro.html)

Set `backup_dir` to the chosen completed directory on the recovery system.
The checksum must pass before proceeding.

```bash
backup_dir=/mnt/unas_backups/raspberrypi-online/online-YYYYMMDD-HHMMSS
staging=/recovery/pi-snapshot

sudo bash -c 'cd "$1" && sha256sum --check --strict SHA256SUMS' _ "$backup_dir"
```

Extract as root to preserve numeric ownership, modes, ACLs, and extended
attributes. Choose another staging directory if this one contains files.

```bash
sudo mkdir -p -m 0700 "$staging"
findmnt -T "$staging" -o TARGET,FSTYPE
sudo tar --zstd --numeric-owner --acls --xattrs --xattrs-include='*' \
    -xpf "$backup_dir/raspibackup.tar.zst" -C "$staging"
sudo find "$staging" -mindepth 1 -maxdepth 1 -type d -name '*-rsync-backup-*' -print
```

The extracted rsync snapshot contains the boot image, partition metadata, root
filesystem, and the application database copies at their ordinary paths.
raspiBackup loads its configuration as root. Review the archived config
against [the repository copy](raspibackup-online.conf) before using it, or
pass your trusted copy with `-f`.

**The restore erases the entire target drive.** Identify the spare drive with
`lsblk` and make sure its partitions are unmounted. Replace `/dev/sdX` with
its whole-device path and `SNAPSHOT` with the exact directory name printed
above. The recovery system must be running from a different drive.

```bash
lsblk -b -o NAME,SIZE,MODEL,TYPE,FSTYPE,MOUNTPOINTS
sudo raspiBackup.sh -f "$backup_dir/raspibackup-online.conf" \
    -d /dev/sdX "$staging/SNAPSHOT"
```

Review the target and snapshot shown by raspiBackup before confirming.

## Validate the restored Pi

- Boot the restored Pi on an isolated network or after taking the original
  Pi offline, since the restore carries over host and network settings.
- Check the root and boot devices, SSH, Docker, Vikunja, Uptime Kuma, and
  CrowdSec. Confirm that their restored data is present.
- Confirm that the UNAS mounts as NFS, the online service and timer are in
  place, and root's crontab has no legacy backup job. An older disk image can
  restore the old cron entry that stops services. See
  [Rebuild the backup setup](README.md#rebuild-the-backup-setup).
- Recreate the root-only Telegram credential from a secure copy. Check
  [Telegram completion reports](README.md#telegram-completion-reports) and
  [failure email](README.md#failure-email), then verify the next backup in
  the service journal.

The initial live test verified the archive checksum, found a readable boot
image and partition layout, started the archived PostgreSQL and MariaDB
databases in isolated containers, and checked the archived CrowdSec database.
A complete boot from a restored spare drive is still unverified.

## Legacy raw and gzip images

Legacy backups used whole-disk `.img` or `.img.gz` files under
`/mnt/unas_backups/raspberrypi/`. Check `raspiBackup.msg` for successful
completion and use a saved checksum when available. For gzip files, run
`gzip -t` before restoring. A raw sparse image still represents the entire
source disk, so size the replacement by the image's logical bytes.

- On Linux, raspiBackup can restore from the original legacy backup
  directory with `sudo raspiBackup.sh -d /dev/sdX /path/to/backup-directory`.
- Raspberry Pi Imager's **Use Custom** or balenaEtcher's **Flash from file**
  can write a raw `.img` to the selected spare drive. When decompressing a
  gzip image first, allow room for the full logical image size.
- For a manual Linux write, unmount the target partitions and use
  `sudo dd if=/path/to/backup.img of=/dev/sdX bs=4M status=progress conv=fsync`.
  Then inspect the partition table with `sudo fdisk -l /dev/sdX`.
- On macOS, identify the target with `diskutil list`, unmount it with
  `diskutil unmountDisk /dev/diskN`, and write it with
  `sudo dd if=/path/to/backup.img of=/dev/rdiskN bs=4m status=progress`.
  Run `sync` and eject the disk after a successful write.

Use ordinary writes to the target device, including the zero blocks.
[GNU dd documentation](https://www.gnu.org/software/coreutils/manual/html_node/dd-invocation.html)

To stream a gzip image without unpacking it first, check it with `gzip -t`,
then use Bash with `pipefail` after unmounting the target.

```bash
# Linux
set -o pipefail
gzip -dc /path/to/backup.img.gz |
    sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

```bash
# macOS
set -o pipefail
gzip -dc /path/to/backup.img.gz |
    sudo dd of=/dev/rdiskN bs=4m status=progress
```

On Linux, inspect the partition table after the write. On macOS, run
`sync` and eject the disk after the write succeeds.
