# ArchRiot ISO Builder

A custom Arch Linux ISO with an automated installer for the ArchRiot desktop environment.

## What is ArchRiot?

ArchRiot is a pre-configured Arch Linux system featuring:

- **Hyprland** - A modern Wayland compositor
- **Full disk encryption** (LUKS)
- **BTRFS filesystem** with compression
- **Automated installation** - No manual configuration needed
- **Tokyo Night theme** throughout the system

## Requirements

- 64-bit UEFI or Legacy BIOS system
- At least 4GB RAM (8GB recommended)
- 20GB+ free disk space
- Internet connection during installation
- Arch Linux host system to build the ISO

## Building the ISO

1. Clone this repository:

    ```bash
    git clone https://github.com/CyphrRiot/ArchISO.git
    cd ArchISO
    ```

2. Build the ISO (requires sudo):

    ```bash
    sudo ./build-iso.sh
    ```

3. Find your ISO in:
    ```
    out/archriot-2025.01.20-x86_64.iso
    ```

## Creating Installation Media

### USB Drive (Recommended)

```bash
sudo dd if=out/archriot-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Replace `/dev/sdX` with your USB device (use `lsblk` to find it).

### Virtual Machine

```bash
./testiso.sh  # Launches QEMU for testing
```

## Installation Process

1. Boot from the ISO
2. The installer will guide you through:
    - WiFi setup (if needed)
    - Timezone selection
    - Keyboard layout
    - Disk selection (⚠️ **WARNING**: Selected disk will be wiped)
    - User account creation
    - Encryption password setup

3. Installation takes 15-30 minutes depending on internet speed
4. Reboot into your new ArchRiot system

## What's Included

- **Base System**: Arch Linux with latest packages
- **Desktop**: Hyprland with full configuration
- **Terminal**: Kitty with Tokyo Night theme
- **Shell**: Fish with custom prompt
- **Editor**: Neovim with plugins
- **Browser**: Firefox
- **Audio**: PipeWire
- **Network**: NetworkManager

## Important Notes

- The installer requires an internet connection
- The entire selected disk will be encrypted and formatted
- Default partition layout: 1GB boot, rest for encrypted root
- Creates a user with sudo privileges
- Sets up both user and root passwords

## Troubleshooting

### ISO Won't Boot

- Disable Secure Boot in BIOS
- Try both UEFI and Legacy boot modes
- Verify ISO integrity after download

### Installation Fails

- Ensure stable internet connection
- Verify you have at least 20GB free space
- Check that your system meets minimum requirements

### WiFi Not Working

- The installer will scan and show available networks
- Some WiFi cards may need additional firmware

## Support

- Issues: [GitHub Issues](https://github.com/CyphrRiot/ArchISO/issues)
- Documentation: [ArchRiot Wiki](https://github.com/CyphrRiot/ArchRiot)

## License

This project is open source. See LICENSE file for details.

---

**Current Status**: Dialog system fixes implemented, testing in progress (2025-01-22)
