# Restore the Raspberry Pi boot disk

The Pi's daily raspiBackup job writes full-disk `.img` files under `/mnt/unas_backups/raspberrypi/` on the UNAS NFS share. Sparse images read back as the full original disk, including the zero-filled regions. Use the image's logical size to size the replacement drive. Older backup directories can contain gzip-compressed disk images such as `.img.gz`.

## Verify backup

1. Mount the UNAS share on the recovery computer and select a completed backup directory. On the Pi, the mount point is `/mnt/unas_backups`.
2. Check `raspiBackup.msg` for `Backup finished successfully` and confirm that the matching image is present. Review `raspiBackup.log` if the job reported errors.
3. For a raw image, use `ls -lh` to read the logical size. On Linux, `fdisk -l /path/to/backup.img` can inspect the image's partition table. For a gzip image, run `gzip -t /path/to/backup.img.gz` to check the compressed data.
4. Confirm the replacement drive has at least as many bytes as the original disk. The Pi's current SSD is 240,057,409,536 bytes. Compare exact sizes when using another drive with the same advertised capacity.

If you have a saved checksum for the image, compare it before writing. A successful backup log and readable partition table are checks on the image. A boot from the restored drive verifies recovery.

## Select the target disk

**Writing an image erases the entire target drive.** Identify the replacement by its model and byte size before writing. On macOS use `diskutil list` and `diskutil info /dev/diskN`. On Linux use `lsblk -b -o NAME,SIZE,MODEL,TYPE,FSTYPE,MOUNTPOINTS`. Boot from separate media if using a Pi as the recovery computer.

The commands below use placeholder device names. Substitute the target's whole device, such as `/dev/sdb`, rather than a partition such as `/dev/sdb1`.

## Restore with Raspberry Pi Imager or balenaEtcher

In Raspberry Pi Imager, select **Use Custom** and choose the `.img` file. In balenaEtcher, use **Flash from file**. Confirm the replacement drive, write the image, and wait for verification. If using a compressed image with the GUI, extract it to a raw file first and allow enough free space for the entire original disk. [Raspberry Pi Imager documentation](https://www.raspberrypi.com/documentation/computers/getting-started.html)

## Restore with macOS dd

After identifying the target, unmount it and write the raw image through its raw disk device.

```bash
diskutil unmountDisk /dev/diskN &&
    sudo dd if=/path/to/backup.img of=/dev/rdiskN bs=4m status=progress &&
    sync &&
    diskutil eject /dev/diskN
```

## Restore with Linux dd

Unmount any mounted partitions on the target, then write the raw image. Check the resulting partition table after the write succeeds.

```bash
sudo dd if=/path/to/backup.img of=/dev/sdX bs=4M status=progress conv=fsync &&
    sudo fdisk -l /dev/sdX
```

Use ordinary writes when restoring to a disk. A sparse write option can skip zero blocks and leave old data on the target. The live backup command uses `conv=sparse` only for image creation. [GNU dd documentation](https://www.gnu.org/software/coreutils/manual/html_node/dd-invocation.html#dd-invocation)

## Restore with raspiBackup on a separate Pi boot drive

With the UNAS share mounted and the replacement disk connected, pass the whole target device and the completed **backup directory** to raspiBackup. For an older gzip backup, select its `ddz` directory.

```bash
sudo raspiBackup.sh -d /dev/sdX /mnt/unas_backups/raspberrypi/NAME-OF-BACKUP-DIRECTORY
```

Review the device and backup details at the confirmation prompt. The normal restore settings apply, including `DEFAULT_RESIZE_ROOTFS=1` on the live Pi. [raspiBackup restore documentation](https://framps.github.io/raspiBackupDoc/restore-intro.html)

## Stream an older gzip image

To restore a gzip image without staging a full raw file, first check it with `gzip -t`. After unmounting the target, run the appropriate command in Bash with `pipefail` so decompression errors fail the pipeline.

```bash
# macOS
set -o pipefail
gzip -dc /path/to/backup.img.gz | sudo dd of=/dev/rdiskN bs=4m status=progress
```

```bash
# Linux
set -o pipefail
gzip -dc /path/to/backup.img.gz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

After a successful macOS write, run `sync` and eject the disk. On Linux, inspect the target's partition table before booting it.

## After booting the restored Pi

- Confirm the Pi boots from the replacement drive and SSH works. Use `lsblk` to verify the boot and root filesystems are on the expected device.
- Check Docker and the expected containers. Access `/mnt/unas_backups` and verify that it mounts as NFS.
- If a larger target still has unallocated space after a raw write, expand the root filesystem through `sudo raspi-config` if needed.
- Compare the restored root crontab with the daily 03:00 Pacific schedule in [README.md](README.md#schedule-and-service-downtime). An older image can carry the earlier backup schedule or alert setup.
- Check the next backup's completion log and Telegram notice. Run the [failure email test](README.md#notifications-and-backup-checks) and confirm delivery to `Homelab/raspiBackup` in Fastmail.
