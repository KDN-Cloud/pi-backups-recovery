# Restore Guide — raspiBackup `.dd.gz` Images

raspiBackup `dd` images are bare-metal clones — they include the partition table, bootloader, and all OS data. Restoring writes the entire image back to a target drive, byte for byte.

---

## Before You Start

- **Target drive** must be the **same size or larger** than the original source disk
- **All data on the target drive will be erased**
- Verify your backup file is not corrupt before restoring (see [Verify Backup](#verify-backup) below)
- Know your target device path — **writing to the wrong device destroys data**

---

## Method 1: macOS (Raspberry Pi Imager or balenaEtcher)

The simplest restore path — both tools decompress `.dd.gz` on the fly.

1. Connect your target SSD or SD card via USB enclosure or adapter
2. Open **Raspberry Pi Imager** or **balenaEtcher**
3. In Raspberry Pi Imager:
   - Click **Choose OS** → scroll to bottom → **Use custom**
   - Select your `.dd.gz` backup file
   - Click **Choose Storage** → select your target drive
   - Click **Next** → **Write**
4. In balenaEtcher:
   - Click **Flash from file** → select your `.dd.gz` backup file
   - Click **Select target** → select your target drive
   - Click **Flash**
5. Wait for write and verification to complete

> Raspberry Pi Imager will verify the write automatically. In balenaEtcher, verification runs after flashing.

---

## Method 2: macOS Terminal (`dd`)

For full control or scripted restores.

```bash
# identify your target disk (look for your drive size)
diskutil list

# unmount the target disk (replace diskN with your disk, e.g. disk4)
diskutil unmountDisk /dev/diskN

# restore — decompress and write in one pipeline
# rdiskN (raw disk) is significantly faster than diskN on macOS
gunzip -c /path/to/backup.dd.gz | sudo dd of=/dev/rdiskN bs=4m status=progress

# eject when done
diskutil eject /dev/diskN
```

> `bs=4m` (macOS syntax) sets the block size to 4MB for faster writes. On Linux use `bs=4M`.

---

## Method 3: Linux Terminal (`dd`)

```bash
# identify your target disk
lsblk
# or
fdisk -l

# IMPORTANT: ensure the target disk is NOT mounted
umount /dev/sdX*

# restore — decompress and write in one pipeline
gunzip -c /path/to/backup.dd.gz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync

# sync and verify
sync
lsblk /dev/sdX
```

> Replace `/dev/sdX` with your actual target device. Double-check with `lsblk` before running.

---

## Method 4: Raspberry Pi using raspiBackup

If restoring to a new drive from a live Pi (booted from a separate SD card):

### 1. Identify the target disk

Connect the new drive and run:

```bash
lsblk
```

Look for your target device (e.g. `/dev/sda` for USB SSD, `/dev/mmcblk0` for SD card).

### 2. Run the raspiBackup restore

```bash
sudo raspiBackup.sh -d /dev/sdX /path/to/backup/directory
```

raspiBackup will:
- Detect the backup type automatically
- Decompress and write the image
- Optionally resize the root filesystem to fill the target drive

### 3. Resize root filesystem (optional)

If your target drive is larger than the original, raspiBackup can expand the root partition automatically. This is controlled by `DEFAULT_RESIZE_ROOTFS=1` in `raspiBackup.conf`.

Alternatively, expand manually after booting from the restored drive:

```bash
sudo raspi-config
# → Advanced Options → Expand Filesystem
```

Or manually with `parted` / `resize2fs`:

```bash
sudo parted /dev/sdX resizepart 2 100%
sudo resize2fs /dev/sdX2
```

---

## Verify Backup

Test the integrity of your `.dd.gz` file before restoring:

```bash
# test gzip integrity (no output = OK, error = corrupt)
gunzip -t /path/to/backup.dd.gz

# check file size is reasonable (should be several GB)
ls -lh /path/to/backup.dd.gz

# preview partition table from the compressed image without fully extracting
gunzip -c /path/to/backup.dd.gz | sudo fdisk -l
```

---

## Post-Restore Checklist

After writing the image and booting:

- [ ] Pi boots successfully
- [ ] SSH accessible
- [ ] Hostname is correct (`hostnamectl`)
- [ ] Docker containers running (`docker ps`)
- [ ] NAS mount accessible (`df -h`)
- [ ] Services healthy (`systemctl status`)
- [ ] Run `sudo raspi-config` → Expand Filesystem if target drive is larger

---

## Troubleshooting

**Pi won't boot after restore**
- Verify the write completed without errors
- Check the target drive is not smaller than the original
- Try re-flashing with Raspberry Pi Imager which verifies after writing

**`dd` is slow**
- Use `/dev/rdiskN` instead of `/dev/diskN` on macOS (raw disk, much faster)
- Increase block size: `bs=4M` on Linux, `bs=4m` on macOS

**"No space left on device" during restore**
- Target drive is smaller than the original image — use a larger drive

**Partition table looks wrong after restore**
- Run `sudo parted /dev/sdX print` to inspect
- The partition table is restored as-is from the original — resize after if needed
