# Raspberry Pi Restore Guide (.ddz / .dd.gz)

This repository contains (or references) compressed `dd` images created via `raspiBackup`. These images are "bare-metal" clones, meaning they include the partition table, bootloader, and all OS data.

## 🗂 Preparation
- **Target Drive:** Must be the same size or larger than the original source disk.
- **File Format:** `.dd.gz` (often referred to as `ddz`).

---

## 🍎 Method 1: Using macOS (Recommended)
The easiest way to restore a compressed image is using a GUI flasher that handles decompression on the fly.

1. **Connect your SSD/SD Card** to your Mac using a USB enclosure or adapter.
2. **Open Raspberry Pi Imager** (or BalenaEtcher).
3. **Choose OS:** Scroll to the bottom and select **"Use Custom"**.
4. **Select File:** Browse to your `.dd.gz` backup file.
5. **Choose Storage:** Select your target SSD/SD card.
6. **Write:** Wait for the process to complete and verify.

---

## 🥧 Method 2: Using a Raspberry Pi (Terminal)
If you are running the restore from a live Raspberry Pi (booted from a separate SD card), use the `raspiBackup` script.

### 1. Identify the target disk
Connect your new SSD to the Pi and run:
```bash
lsblk

