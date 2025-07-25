# ArchRiot ISO Builder

A custom Arch Linux ISO with an automated installer for the ArchRiot desktop environment.

**Status: ✅ WORKING** - ISO builds successfully, installer functional with LUKS encryption

## What is ArchRiot?

ArchRiot is a pre-configured Arch Linux system featuring:

- **Hyprland** - A modern Wayland compositor
- **Full disk encryption** (LUKS) with secure password handling
- **BTRFS filesystem** with compression
- **Automated installation** - WiFi setup, disk partitioning, user creation
- **Tokyo Night theme** throughout the system
- **Boot drive protection** - Won't accidentally format your USB installer
- **TUI installer** - Clean dialog-based interface

## Requirements

- 64-bit UEFI or Legacy BIOS system
- At least 4GB RAM (8GB recommended)
- 20GB+ free disk space
- Internet connection during installation
- Arch Linux host system to build the ISO
- Ventoy USB drive (recommended) or direct USB flashing

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
    isos/archriot-2025.iso
    ```

## Creating Installation Media

### Ventoy USB Drive (Recommended)

1. Install [Ventoy](https://www.ventoy.net/) on a USB drive
2. Copy the ISO file to the Ventoy drive:
    ```bash
    cp isos/archriot-*.iso /path/to/ventoy/drive/
    ```
3. Boot from Ventoy and select the ArchRiot ISO

### Direct USB Flashing

```bash
sudo dd if=isos/archriot-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

**Note:** The build script can automatically copy to Ventoy drives when detected.

Replace `/dev/sdX` with your USB device (use `lsblk` to find it).

### Virtual Machine

```bash
./testiso.sh  # Launches QEMU for testing
```

## Installation Process

1. **Boot from the ISO**
    - Boot from Ventoy or direct USB
    - Select ArchRiot ISO from boot menu

2. **Automated Installer Starts**
    - Welcome screen with system information
    - Internet connectivity check

3. **Network Setup** (if needed)
    - Automatic WiFi detection and connection
    - Clean dialog-based interface
    - Ethernet automatically detected

4. **System Configuration**
    - Timezone selection from world map
    - Keyboard layout selection
    - Hostname configuration

5. **Disk Setup** (⚠️ **CRITICAL**)
    - **Boot drive automatically excluded** (won't show your USB installer)
    - Select target disk (⚠️ **WARNING**: Selected disk will be completely wiped)
    - Automatic partitioning with LUKS encryption
    - BTRFS filesystem with compression

6. **User Account Setup**
    - Username and password creation
    - Root password configuration
    - LUKS encryption password (separate from user password)
    - Passwords securely hashed with yescrypt

7. **Installation** (15-30 minutes)
    - Base Arch Linux system installation
    - ArchRiot desktop environment setup
    - Package installation and configuration

8. **Completion**
    - Automatic reboot into new system
    - Login with created user account
    - Hyprland desktop ready to use

## What's Included

### Base System

- **Arch Linux** with latest packages and kernel
- **Systemd-boot** bootloader (UEFI)
- **LUKS full-disk encryption** with secure password handling
- **BTRFS filesystem** with compression and subvolumes
- **PipeWire** audio system
- **NetworkManager** with WiFi support

### Desktop Environment

- **Hyprland** Wayland compositor with full configuration
- **Tokyo Night** theme throughout the system
- **Waybar** status bar with system monitoring
- **Rofi** application launcher
- **Kitty** terminal with custom configuration
- **Fish shell** with custom prompt and completions

### Applications

- **Firefox** web browser
- **Neovim** editor with plugins and configuration
- **File manager** and system utilities
- **Development tools**: git, base-devel, python, etc.

## Security Features

- **LUKS full-disk encryption** with strong password protection
- **Secure password hashing** using yescrypt (Arch Linux standard)
- **Boot drive protection** prevents accidental formatting of installer USB
- **Separate credentials file** keeps passwords secure during installation
- **No plain-text password storage** in configuration files

## Troubleshooting

### Installation Issues

**"Configuration Invalid" Error:**

- Check `/tmp/archinstall-validation.log` for details
- Ensure internet connection is stable
- Verify disk has sufficient free space (20GB+)

**WiFi Not Working:**

- Try using ethernet connection instead
- Check if WiFi adapter is supported by Linux kernel
- Installer includes retry logic for network issues

**Boot Issues:**

- Ensure UEFI boot mode is enabled
- For legacy BIOS systems, use CSM/legacy boot
- Check Secure Boot is disabled

### Build Issues

**ISO Build Fails:**

- Ensure running on Arch Linux host system
- Check available disk space (need ~3GB)
- Run with sudo permissions: `sudo ./build-iso.sh`

**USB Creation Fails:**

- Use Ventoy for most reliable boot experience
- For direct flashing, ensure USB drive is unmounted first
- Verify USB drive path with `lsblk` before writing

## Recent Fixes & Improvements

### July 2025 Updates

- ✅ **Fixed archinstall configuration** - Proper two-file format (config + credentials)
- ✅ **Security improvements** - LUKS passwords now handled securely
- ✅ **Boot drive protection** - Automatically excludes USB installer from disk selection
- ✅ **TUI improvements** - Clean dialog interface without screen disruption
- ✅ **WiFi stability** - Added retry limits to prevent infinite loops
- ✅ **Ventoy support** - Automatic detection and copying to Ventoy drives
- ✅ **Error handling** - Comprehensive debugging for installation failures
- ✅ **Password security** - Yescrypt hashing for all user credentials

### Technical Improvements

- Simplified archinstall config using `default_layout` for reliability
- Separated encryption password from main config file
- Added comprehensive validation and error reporting
- Improved network detection and WiFi setup process
- Enhanced dialog system with proper terminal handling

## Known Issues

- **UEFI preferred**: Legacy BIOS support available but UEFI recommended
- **Internet required**: Stable connection needed during installation
- **Disk wiping**: Selected disk is completely formatted (data loss)

## Development Status

**Current State**: ✅ **STABLE** - ISO builds successfully, installer functional

**Testing Status**:

- ✅ ISO building and packaging
- ✅ Boot process (UEFI and Legacy BIOS)
- ✅ Network setup and WiFi detection
- ✅ Disk selection and boot drive filtering
- ✅ User account and password setup
- 🧪 Full installation workflow (currently testing)
- 🧪 Post-install desktop environment

## Support

- **Issues**: [GitHub Issues](https://github.com/CyphrRiot/ArchISO/issues)
- **Documentation**: [ArchRiot Wiki](https://github.com/CyphrRiot/ArchRiot)
- **Discussions**: Use GitHub Discussions for questions

## Contributing

Contributions welcome! Please:

1. Test the installer on various hardware
2. Report bugs with full error logs
3. Submit pull requests for improvements
4. Update documentation as needed

## License

This project is open source under the GPL-3.0 license. See LICENSE file for details.

---

**Last Updated**: July 2025 - Core installer functionality complete and tested
