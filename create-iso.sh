#!/usr/bin/env bash

# Simple ArchRiot ISO Builder
# Creates standard archiso with offline package cache and riot installer

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$SCRIPT_DIR/work"
PROFILE_DIR="$WORK_DIR/releng"
CACHE_DIR="$SCRIPT_DIR/cache"

echo "=== Simple ArchRiot ISO Builder ==="

# Clean previous builds
echo "1. Cleaning previous builds..."
# Properly unmount airootfs before cleanup
if [[ -d "$SCRIPT_DIR/out/work/x86_64/airootfs" ]]; then
    echo "   Unmounting airootfs..."
    for mount_point in proc sys dev/pts dev/shm dev run tmp; do
        mount_path="$SCRIPT_DIR/out/work/x86_64/airootfs/$mount_point"
        if mountpoint -q "$mount_path" 2>/dev/null; then
            sudo umount "$mount_path" 2>/dev/null || true
        fi
    done
fi
sudo rm -rf "$WORK_DIR" "$SCRIPT_DIR/out" "$SCRIPT_DIR/isos" 2>/dev/null || true
sudo mkdir -p "$WORK_DIR" "$CACHE_DIR/official" "$SCRIPT_DIR/isos"
sudo chown -R "$USER:$USER" "$WORK_DIR" "$CACHE_DIR" "$SCRIPT_DIR/isos"

# Copy standard releng profile
echo "2. Copying standard releng profile..."
cp -r /usr/share/archiso/configs/releng "$PROFILE_DIR"

# Download packages to cache (if not already cached)
echo "3. Checking package cache..."
PACKAGE_LIST="$SCRIPT_DIR/configs/packages.txt"
if [[ ! -f "$PACKAGE_LIST" ]]; then
    echo "ERROR: Package list not found: $PACKAGE_LIST"
    exit 1
fi

# Download packages to cache (handling both official and AUR)
echo "   Downloading packages to cache..."
packages=()
while IFS= read -r package; do
    [[ -z "$package" || "$package" =~ ^#.* ]] && continue
    packages+=("$package")
done < "$PACKAGE_LIST"

echo "   Processing ${#packages[@]} packages..."
mkdir -p "$CACHE_DIR/official" "$CACHE_DIR/aur"

# Separate official and AUR packages
official_packages=()
aur_packages=()

for package in "${packages[@]}"; do
    # Check if package exists in official repos
    if pacman -Si "$package" >/dev/null 2>&1; then
        # Check if already cached
        if ! find "$CACHE_DIR/official" -name "$package-*.pkg.tar.zst" | grep -q .; then
            official_packages+=("$package")
        fi
    else
        # Check if it's an AUR package and not already cached
        if ! find "$CACHE_DIR/aur" -name "$package-*.pkg.tar.zst" | grep -q . && command -v yay >/dev/null 2>&1; then
            if yay -Si "$package" >/dev/null 2>&1; then
                aur_packages+=("$package")
            else
                echo "   WARNING: Package $package not found in official repos or AUR"
            fi
        fi
    fi
done

# Download official packages
if [[ ${#official_packages[@]} -gt 0 ]]; then
    echo "   Downloading ${#official_packages[@]} official packages..."
    mkdir -p /tmp/pacman-cache /tmp/offlinedb
    sudo pacman --noconfirm -Syw "${official_packages[@]}" \
        --cachedir /tmp/pacman-cache \
        --dbpath /tmp/offlinedb

    sudo mv /tmp/pacman-cache/*.pkg.tar.zst "$CACHE_DIR/official/" 2>/dev/null || true
    sudo chown "$USER:$USER" "$CACHE_DIR/official"/*.pkg.tar.zst 2>/dev/null || true
fi

# Download AUR packages
if [[ ${#aur_packages[@]} -gt 0 ]]; then
    echo "   Downloading ${#aur_packages[@]} AUR packages..."
    export MAKEFLAGS="-j4"
    for aur_package in "${aur_packages[@]}"; do
        echo "     Building AUR package: $aur_package"
        if yay -S --noconfirm --needed --downloadonly "$aur_package" >/dev/null 2>&1; then
            # Find and copy AUR package from yay cache
            find "$HOME/.cache/yay" -name "$aur_package-*.pkg.tar.zst" -exec cp {} "$CACHE_DIR/aur/" \; 2>/dev/null || true
        fi
    done
    sudo chown "$USER:$USER" "$CACHE_DIR/aur"/*.pkg.tar.zst 2>/dev/null || true
fi

# Create repository databases
echo "4. Creating offline repository databases..."
cd "$CACHE_DIR/official"
if ls *.pkg.tar.zst 1> /dev/null 2>&1; then
    repo-add --new archriot-cache.db.tar.gz *.pkg.tar.zst
fi
cd "$SCRIPT_DIR"

if [[ -d "$CACHE_DIR/aur" ]] && ls "$CACHE_DIR/aur"/*.pkg.tar.zst 1> /dev/null 2>&1; then
    cd "$CACHE_DIR/aur"
    repo-add --new aur-cache.db.tar.gz *.pkg.tar.zst
    cd "$SCRIPT_DIR"
fi

# Copy offline repositories to ISO
echo "5. Adding package caches to ISO..."
mkdir -p "$PROFILE_DIR/airootfs/opt/archriot-cache" "$PROFILE_DIR/airootfs/opt/aur-cache"
cp -r "$CACHE_DIR/official"/* "$PROFILE_DIR/airootfs/opt/archriot-cache/" 2>/dev/null || true
cp -r "$CACHE_DIR/aur"/* "$PROFILE_DIR/airootfs/opt/aur-cache/" 2>/dev/null || true

# Add riot installer
echo "6. Adding riot installer..."
if [[ -f "$SCRIPT_DIR/airootfs/usr/local/bin/riot" ]]; then
    mkdir -p "$PROFILE_DIR/airootfs/usr/local/bin"
    cp "$SCRIPT_DIR/airootfs/usr/local/bin/riot" "$PROFILE_DIR/airootfs/usr/local/bin/"
    sudo chmod +x "$PROFILE_DIR/airootfs/usr/local/bin/riot"

    # Add riot to profile permissions to ensure it stays executable
    if [[ -f "$PROFILE_DIR/profiledef.sh" ]]; then
        # Add riot permissions to existing profiledef.sh
        sed -i '/file_permissions=(/a\  ["/usr/local/bin/riot"]="0:0:755"' "$PROFILE_DIR/profiledef.sh"
    fi

    echo "   Riot installer added and made executable"
else
    echo "   WARNING: Riot installer not found at $SCRIPT_DIR/airootfs/usr/local/bin/riot"
fi

# Configure offline pacman
echo "7. Configuring offline pacman..."
cat > "$PROFILE_DIR/airootfs/etc/pacman.conf" << 'EOF'
[options]
Architecture = auto
CheckSpace
VerbosePkgLists
ParallelDownloads = 5
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional

[aur-cache]
SigLevel = Optional TrustAll
Server = file:///opt/aur-cache

[archriot-cache]
SigLevel = Optional TrustAll
Server = file:///opt/archriot-cache

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
EOF

# Create ArchRiot motd
echo "8. Creating ArchRiot motd..."
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
echo "9. Building ISO..."
mkdir -p "$SCRIPT_DIR/out"
sudo mkarchiso -v -w "$SCRIPT_DIR/out/work" -o "$SCRIPT_DIR/out" "$PROFILE_DIR"

# Find and move ISO
iso_file=$(find "$SCRIPT_DIR/out" -maxdepth 1 -name "*.iso" | head -1)
if [[ -n "$iso_file" ]]; then
    cp "$iso_file" "$SCRIPT_DIR/isos/archriot.iso"
    iso_size=$(du -h "$SCRIPT_DIR/isos/archriot.iso" | cut -f1)

    # Generate SHA256 checksum
    (cd "$SCRIPT_DIR/isos" && sha256sum "archriot.iso" > "archriot.sha256")

    echo ""
    echo "SUCCESS: ISO built successfully!"
    echo "Location: $SCRIPT_DIR/isos/archriot.iso"
    echo "Size: $iso_size"
    echo "Checksum: $SCRIPT_DIR/isos/archriot.sha256"
    echo ""
    echo "To use:"
    echo "1. Boot from ISO"
    echo "2. Type 'riot' to install"
    echo "3. Reboot and run: curl -fsSL https://ArchRiot.org/setup.sh | bash"
else
    echo "ERROR: ISO file not found after build"
    exit 1
fi
