# pi-backups-recovery

Bare-metal backup and recovery for Raspberry Pi using [`raspiBackup`](https://github.com/framps/raspiBackup). Creates compressed `dd` images (`.dd.gz` / `.ddz`) that include the partition table, bootloader, and all OS data — fully restorable to any same-size or larger drive.

---

## Repository Contents

| File | Purpose |
|------|---------|
| `raspiBackup.conf` | Sanitized raspiBackup configuration (no secrets) |
| `raspiBackup-install.sh` | One-liner installer for raspiBackup |
| `RESTORE.md` | Full restore guide (macOS, Linux, Pi) |

---

## Backup Overview

This setup uses `raspiBackup` in `dd` mode with gzip compression (`ddz`), storing backups on a NAS mount. Docker and other services are stopped cleanly before the image is taken and restarted after.

### Backup type

| Setting | Value |
|---------|-------|
| Type | `dd` (bit-for-bit image) |
| Compression | gzip (`.dd.gz`) |
| Retention | 3 backups kept |
| Destination | NAS mount (e.g. `/mnt/nas_backups`) |

### What gets backed up

A `dd` backup captures the **entire SD card or SSD** — partition table, boot partition, root filesystem, and all data. It is a complete clone, not a file-level backup.

---

## Quick Start

### 0. Clone the Repository
Clone this repo to your Raspberry Pi to access the configuration templates and installation scripts.

```bash
git clone git@github.com:KDN-Cloud/pi-backups-recovery.git
cd pi-backups-recovery
```

> **Note:** If you already have a setup for your repositories, you can clone directly into your current directory. Otherwise, use the automated setup below:

```bash
mkdir -p ~/projects && cd ~/projects && \
git clone https://github.com/KDN-Cloud/pi-backups-recovery.git && \
cd pi-backups-recovery
```

### 1. Install raspiBackup

```bash
bash raspiBackup-install.sh
```

### 2. Configure

```bash
sudo cp raspiBackup.conf /usr/local/etc/raspiBackup.conf
# Edit to set your backup path, notification tokens, and NAS mount
sudo nano /usr/local/etc/raspiBackup.conf
```

### 3. Run a backup

```bash
sudo raspiBackup.sh
```

### 4. Schedule via cron

```bash
sudo crontab -e
# Run every Sunday at 02:00
0 2 * * 0 /usr/local/bin/raspiBackup.sh
```

```bash
# Run every day at 3am and ensure services are started up
00 03 * * * /usr/local/bin/raspiBackup.sh -m 0 ; /usr/bin/systemctl restart docker cron
```

---

## Restore

See **[RESTORE.md](RESTORE.md)** for full restore instructions across macOS, Linux, and Raspberry Pi.

---

## NAS Mount Setup

raspiBackup writes to a mounted NAS share. Add to `/etc/fstab` for automatic mounting:

# NFS example
```bash
192.168.1.x:/var/nfs/shared/RaspberryPi4  /mnt/unas_backups/  nfs  defaults,_netdev,x-systemd.automount,x-systemd.idle-timeout=600  0  0
```

# SMB/CIFS example
```bash
//192.168.x.x/pi-backups  /mnt/nas_backups  cifs  credentials=/etc/nas-credentials,_netdev  0  0
```

```bash
# /etc/nas-credentials (chmod 600, never commit)
username=your_nas_user
password=your_nas_password
```

Mount and verify before first backup:

```bash
sudo mount -a
df -h /mnt/nas_backups
```

---

## Service Stop / Start

raspiBackup stops services before imaging and restarts them after to ensure a consistent snapshot:

# Stopped before backup
```bash
systemctl stop docker
systemctl stop cron
systemctl stop containerd

# Restarted after backup
systemctl start containerd
systemctl start cron
systemctl start docker
```

Adjust `DEFAULT_STOPSERVICES` and `DEFAULT_STARTSERVICES` in `raspiBackup.conf` to match your setup.

---

## References

- [raspiBackup GitHub](https://github.com/framps/raspiBackup)
- [raspiBackup Documentation](https://www.linux-tips-and-tricks.de/en/raspberry-pi-backup/)
- [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
- [balenaEtcher](https://etcher.balena.io/)
