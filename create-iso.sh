#!/usr/bin/env bash

# Clean ArchRiot ISO Builder - Omarchy-Inspired Approach
# Uses system cache for reliable offline package management

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$SCRIPT_DIR/work"
PROFILE_DIR="$WORK_DIR/releng"

# Setup logging
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/build-$(date +%Y%m%d-%H%M%S).log"

# Function to log and display
log_and_display() {
    echo "$1" | tee -a "$LOG_FILE"
}

log_and_display "=== Clean ArchRiot ISO Builder ==="
log_and_display "Build started: $(date)"
log_and_display "Log file: $LOG_FILE"

# Clean previous builds
log_and_display "1. Cleaning previous builds..."
if [[ -d "$SCRIPT_DIR/out/work/x86_64/airootfs" ]]; then
    log_and_display "   Unmounting airootfs..."
    for mount_point in proc sys dev/pts dev/shm dev run tmp; do
        mount_path="$SCRIPT_DIR/out/work/x86_64/airootfs/$mount_point"
        if mountpoint -q "$mount_path" 2>/dev/null; then
            sudo umount "$mount_path" 2>/dev/null || true
        fi
    done
fi
sudo rm -rf "$WORK_DIR" "$SCRIPT_DIR/out" "$SCRIPT_DIR/isos" 2>/dev/null || true
sudo mkdir -p "$WORK_DIR" "$SCRIPT_DIR/isos"
sudo chown -R "$USER:$USER" "$WORK_DIR" "$SCRIPT_DIR/isos"

# Copy standard releng profile
log_and_display "2. Copying standard releng profile..."
cp -r /usr/share/archiso/configs/releng "$PROFILE_DIR"

# Clean up unwanted packages from releng (VM-specific packages)
log_and_display "   Removing unwanted VM packages from releng profile..."
sed -i '/^qemu-guest-agent$/d' "$PROFILE_DIR/packages.x86_64"
sed -i '/^virtualbox-guest-utils-nox$/d' "$PROFILE_DIR/packages.x86_64"
sed -i '/^hyperv$/d' "$PROFILE_DIR/packages.x86_64"
sed -i '/^open-vm-tools$/d' "$PROFILE_DIR/packages.x86_64"

# Skip cache cleaning to avoid re-downloading packages on re-runs
log_and_display "3. Skipping cache cleaning to preserve downloaded packages..."

# Read package list
log_and_display "4. Reading package list..."
PACKAGE_LIST="$SCRIPT_DIR/configs/packages.txt"
if [[ ! -f "$PACKAGE_LIST" ]]; then
    log_and_display "ERROR: Package list not found: $PACKAGE_LIST"
    exit 1
fi

# Read installation packages (for offline cache)
installation_packages=()
while IFS= read -r package; do
    [[ -z "$package" || "$package" =~ ^#.* ]] && continue
    installation_packages+=("$package")
done < "$PACKAGE_LIST"

# Read live environment packages (from releng profile)
live_packages=()
while IFS= read -r package; do
    [[ -z "$package" || "$package" =~ ^#.* ]] && continue
    live_packages+=("$package")
done < "$PROFILE_DIR/packages.x86_64"

log_and_display "   Found ${#installation_packages[@]} installation packages and ${#live_packages[@]} live environment packages"

# Combine all packages for unified offline cache (omarchy approach)
all_packages=("${installation_packages[@]}" "${live_packages[@]}")
log_and_display "   Creating unified offline cache with ${#all_packages[@]} total packages"

# Download all packages to system cache
log_and_display "5. Downloading all packages to system cache..."
sudo pacman -Syw --noconfirm "${all_packages[@]}"

# Create unified offline repository database
log_and_display "6. Creating unified offline repository..."
mkdir -p "$PROFILE_DIR/airootfs/opt/archriot-cache"
# Copy all downloaded packages to unified cache
for package in "${all_packages[@]}"; do
    find /var/cache/pacman/pkg -name "${package}-*.pkg.tar.zst" -exec cp {} "$PROFILE_DIR/airootfs/opt/archriot-cache/" \; 2>/dev/null || log_and_display "   WARNING: Package $package not found in cache"
done
# Create database for unified cache
cd "$PROFILE_DIR/airootfs/opt/archriot-cache"
repo-add archriot.db.tar.gz *.pkg.tar.zst
cd "$SCRIPT_DIR"
sudo chown -R "$USER:$USER" "$PROFILE_DIR/airootfs/opt/archriot-cache"

# Add riot installer
log_and_display "7. Adding riot installer..."
if [[ -f "$SCRIPT_DIR/airootfs/usr/local/bin/riot" ]]; then
    mkdir -p "$PROFILE_DIR/airootfs/usr/local/bin"
    cp "$SCRIPT_DIR/airootfs/usr/local/bin/riot" "$PROFILE_DIR/airootfs/usr/local/bin/"
    chmod +x "$PROFILE_DIR/airootfs/usr/local/bin/riot"

    # Add riot to profile permissions
    if [[ -f "$PROFILE_DIR/profiledef.sh" ]]; then
        sed -i '/file_permissions=(/a\  ["/usr/local/bin/riot"]="0:0:755"' "$PROFILE_DIR/profiledef.sh"
    fi

    log_and_display "   Riot installer added and made executable"
else
    log_and_display "   WARNING: Riot installer not found at $SCRIPT_DIR/airootfs/usr/local/bin/riot"
fi

# Configure offline pacman
log_and_display "8. Configuring offline pacman..."
cat > "$PROFILE_DIR/airootfs/etc/pacman.conf" << 'EOF'
[options]
Architecture = auto
CheckSpace
VerbosePkgLists
ParallelDownloads = 5
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional

[archriot-cache]
SigLevel = Optional TrustAll
Server = file:///opt/archriot-cache

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
EOF

# Create ArchRiot motd
log_and_display "9. Creating ArchRiot motd..."
cat > "$PROFILE_DIR/airootfs/etc/motd" << 'EOF'

=====================================
    Welcome to ArchRiot Linux ISO
=====================================

To install ArchRiot, type: riot
To reboot, type: reboot
To power off, type: poweroff

ArchRiot packages available offline.

EOF

# Build ISO
log_and_display "10. Building ISO..."
mkdir -p "$SCRIPT_DIR/out"
sudo mkarchiso -v -w "$SCRIPT_DIR/out/work" -o "$SCRIPT_DIR/out" "$PROFILE_DIR" 2>&1 | tee -a "$LOG_FILE"

# Find and move ISO
iso_file=$(find "$SCRIPT_DIR/out" -maxdepth 1 -name "*.iso" | head -1)
if [[ -n "$iso_file" ]]; then
    cp "$iso_file" "$SCRIPT_DIR/isos/archriot.iso"
    iso_size=$(du -h "$SCRIPT_DIR/isos/archriot.iso" | cut -f1)

    # Generate SHA256 checksum
    (cd "$SCRIPT_DIR/isos" && sha256sum "archriot.iso" > "archriot.sha256")

    log_and_display ""
    log_and_display "SUCCESS: ISO built successfully!"
    log_and_display "Location: $SCRIPT_DIR/isos/archriot.iso"
    log_and_display "Size: $iso_size"
    log_and_display "Checksum: $SCRIPT_DIR/isos/archriot.sha256"
    log_and_display "Build completed: $(date)"
    log_and_display ""
    log_and_display "To use:"
    log_and_display "1. Boot from ISO"
    log_and_display "2. Type 'riot' to install"
    log_and_display "3. Reboot and run: curl -fsSL https://ArchRiot.org/setup.sh | bash"
else
    log_and_display "ERROR: ISO file not found after build"
    log_and_display "Build failed: $(date)"
    exit 1
fi
