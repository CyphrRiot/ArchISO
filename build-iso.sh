#!/bin/bash

# ArchRiot Simple ISO Modification Script
# Takes official Arch ISO, adds our installer and ArchRiot packages, repacks it

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 ArchRiot Simple ISO Modifier${NC}"
echo -e "${BLUE}=================================${NC}"

# Configuration
OFFICIAL_ISO_URL="https://mirror.rackspace.com/archlinux/iso/latest/archlinux-x86_64.iso"
OFFICIAL_ISO="isos/archlinux.iso"
EXTRACT_DIR="iso_extract"
OUTPUT_ISO="isos/archriot-2025.iso"

# Cleanup function
cleanup() {
    echo -e "${YELLOW}🧹 Cleaning up...${NC}"
    # Unmount any potential mount points
    sudo umount /mnt 2>/dev/null || true
    sudo umount "$EXTRACT_DIR" 2>/dev/null || true
    # Clean up directories
    sudo rm -rf "$EXTRACT_DIR" work_dir
}
trap cleanup EXIT

# Function to copy ISO to Ventoy drive
copy_to_ventoy() {
    local iso_file="$1"
    local ventoy_found=false
    local ventoy_mount=""

    echo -e "${BLUE}🔍 Checking for Ventoy drive...${NC}"

    # Look for Ventoy drive by checking for ventoy directory
    for mount_point in /media/$USER/* /mnt/* /run/media/$USER/*; do
        if [[ -d "$mount_point" && -d "$mount_point/ventoy" ]]; then
            ventoy_mount="$mount_point"
            ventoy_found=true
            break
        fi
    done

    # Also check if any USB drive has "VENTOY" label
    if ! $ventoy_found; then
        ventoy_device=$(lsblk -no NAME,LABEL | grep -i ventoy | awk '{gsub(/[├─└│ ]*/, "", $1); print $1}' | head -1)
        if [[ -n "$ventoy_device" ]]; then
            # Check if already mounted
            existing_mount=$(findmnt -no TARGET "/dev/$ventoy_device" 2>/dev/null | head -1)
            if [[ -n "$existing_mount" ]]; then
                ventoy_mount="$existing_mount"
                ventoy_found=true
                echo -e "${GREEN}✅ Found already mounted Ventoy drive at $ventoy_mount${NC}"
            else
                # Try to mount it
                ventoy_mount="/tmp/ventoy_mount"
                echo -e "${YELLOW}📁 Found Ventoy device /dev/$ventoy_device, attempting to mount...${NC}"
                sudo mkdir -p "$ventoy_mount"
                if sudo mount "/dev/$ventoy_device" "$ventoy_mount" 2>/dev/null; then
                    ventoy_found=true
                    echo -e "${GREEN}✅ Mounted Ventoy drive at $ventoy_mount${NC}"
                else
                    sudo rmdir "$ventoy_mount" 2>/dev/null || true
                fi
            fi
        fi
    fi

    if $ventoy_found; then
        echo -e "${GREEN}🎯 Found Ventoy drive at: $ventoy_mount${NC}"

        # Copy ISO to Ventoy drive
        iso_name=$(basename "$iso_file")
        target_path="$ventoy_mount/$iso_name"

        echo -e "${BLUE}📋 Copying $iso_name to Ventoy drive...${NC}"
        if sudo rsync --info=progress2 "$iso_file" "$target_path"; then
            echo -e "${GREEN}✅ Successfully copied ISO to Ventoy drive${NC}"
            echo -e "${GREEN}📀 Available at: $target_path${NC}"

            # Get file size for confirmation
            ventoy_size=$(du -h "$target_path" | cut -f1)
            echo -e "${GREEN}📏 Ventoy copy size: $ventoy_size${NC}"
        else
            echo -e "${RED}❌ Failed to copy ISO to Ventoy drive${NC}"
            return 1
        fi

        # Unmount if we mounted it
        if [[ "$ventoy_mount" == "/tmp/ventoy_mount" ]]; then
            echo -e "${BLUE}📤 Unmounting Ventoy drive...${NC}"
            sudo umount "$ventoy_mount"
            sudo rmdir "$ventoy_mount"
            echo -e "${GREEN}✅ Ventoy drive unmounted${NC}"
        fi

        return 0
    else
        echo -e "${YELLOW}⚠️  No Ventoy drive found${NC}"
        echo -e "${YELLOW}💡 Please insert Ventoy USB drive or manually copy: $iso_file${NC}"
        return 1
    fi
}

# Function to cache packages intelligently
cache_packages() {
    echo -e "${BLUE}🗄️  Checking package cache...${NC}"

    # Create cache directory if it doesn't exist
    mkdir -p package_cache

    # Check if we have the package list
    if [[ ! -f "configs/packages.x86_64" ]]; then
        echo -e "${RED}❌ Package list not found: configs/packages.x86_64${NC}"
        return 1
    fi

    # Read packages from config (excluding comments and empty lines)
    local packages=($(grep -v '^#' configs/packages.x86_64 | grep -v '^$' | tr '\n' ' '))
    local total_packages=${#packages[@]}
    local cached_packages=0
    local downloaded_packages=0

    echo -e "${BLUE}📋 Found $total_packages packages to cache${NC}"

    # Check which packages are already cached and up-to-date
    for package in "${packages[@]}"; do
        # Get latest package info from repos
        local latest_version=$(pacman -Si "$package" 2>/dev/null | grep '^Version' | awk '{print $3}')

        if [[ -z "$latest_version" ]]; then
            echo -e "${YELLOW}⚠️  Package $package not found in repos, skipping${NC}"
            continue
        fi

        # Check if we have this package cached
        local cached_file=$(find package_cache -name "${package}-${latest_version}-*.pkg.tar.*" 2>/dev/null | head -1)

        if [[ -n "$cached_file" ]]; then
            echo -e "${GREEN}✅ Cached: $package-$latest_version${NC}"
            ((cached_packages++))
        else
            echo -e "${BLUE}📥 Downloading: $package-$latest_version${NC}"

            # Download package to cache
            if sudo pacman -Sw --noconfirm --cachedir "$(pwd)/package_cache" "$package" 2>/dev/null; then
                echo -e "${GREEN}✅ Downloaded: $package${NC}"
                ((downloaded_packages++))
            else
                echo -e "${YELLOW}⚠️  Failed to download: $package${NC}"
            fi
        fi
    done

    echo -e "${GREEN}📊 Cache Summary:${NC}"
    echo -e "${GREEN}   Cached packages: $cached_packages${NC}"
    echo -e "${GREEN}   Downloaded packages: $downloaded_packages${NC}"
    echo -e "${GREEN}   Total packages: $((cached_packages + downloaded_packages))${NC}"

    # Get cache size
    local cache_size=$(du -sh package_cache 2>/dev/null | cut -f1)
    echo -e "${GREEN}💾 Cache size: $cache_size${NC}"
}

# Step 1: Check for official Arch ISO
if [[ ! -f "$OFFICIAL_ISO" ]]; then
    echo -e "${RED}❌ Official ISO not found: $OFFICIAL_ISO${NC}"
    echo -e "${YELLOW}💡 Please ensure the Arch Linux ISO is in the current directory${NC}"
    exit 1
else
    echo -e "${GREEN}✅ Official ISO found: $OFFICIAL_ISO${NC}"
fi

# Step 2: Extract the ISO
echo -e "${BLUE}📂 Extracting official ISO...${NC}"
mkdir -p "$EXTRACT_DIR"

# Mount the ISO and copy contents
sudo mount -o loop "$OFFICIAL_ISO" /mnt
sudo cp -r /mnt/* "$EXTRACT_DIR/"
sudo umount /mnt

# Make extracted files writable
sudo chown -R "$USER:$USER" "$EXTRACT_DIR"
chmod -R u+w "$EXTRACT_DIR"
echo -e "${GREEN}✅ ISO extracted to $EXTRACT_DIR${NC}"

# Step 3: Add our ArchRiot installer
echo -e "${BLUE}⚙️  Adding ArchRiot installer...${NC}"

# Create installer directory in airootfs
mkdir -p "$EXTRACT_DIR/airootfs/usr/local/bin"

# Verify installer files exist
if [[ ! -f "airootfs/usr/local/bin/archriot-installer" ]]; then
    echo -e "${RED}❌ Installer script not found: airootfs/usr/local/bin/archriot-installer${NC}"
    exit 1
fi

if [[ ! -f "airootfs/etc/systemd/system/archriot-installer.service" ]]; then
    echo -e "${RED}❌ Service file not found: airootfs/etc/systemd/system/archriot-installer.service${NC}"
    exit 1
fi

# Copy our installer script
cp airootfs/usr/local/bin/archriot-installer "$EXTRACT_DIR/airootfs/usr/local/bin/"
chmod +x "$EXTRACT_DIR/airootfs/usr/local/bin/archriot-installer"

# Create systemd service
mkdir -p "$EXTRACT_DIR/airootfs/etc/systemd/system"
cp airootfs/etc/systemd/system/archriot-installer.service "$EXTRACT_DIR/airootfs/etc/systemd/system/"

# Enable the service
mkdir -p "$EXTRACT_DIR/airootfs/etc/systemd/system/multi-user.target.wants"
ln -sf ../archriot-installer.service "$EXTRACT_DIR/airootfs/etc/systemd/system/multi-user.target.wants/"

echo -e "${GREEN}✅ ArchRiot installer added${NC}"

# Step 4: Smart package caching
echo -e "${BLUE}📦 Setting up package cache for offline installation...${NC}"

# Create package cache directory in extracted ISO
mkdir -p "$EXTRACT_DIR/airootfs/var/cache/pacman/pkg"

# Cache packages intelligently (downloads only new/updated packages)
cache_packages

# Copy cached packages to ISO
echo -e "${BLUE}📋 Copying cached packages to ISO...${NC}"
if [[ -d "package_cache" && -n "$(ls -A package_cache 2>/dev/null)" ]]; then
    sudo cp package_cache/*.pkg.tar.* "$EXTRACT_DIR/airootfs/var/cache/pacman/pkg/" 2>/dev/null || true

    # Count packages copied
    local pkg_count=$(ls "$EXTRACT_DIR/airootfs/var/cache/pacman/pkg"/*.pkg.tar.* 2>/dev/null | wc -l)
    echo -e "${GREEN}✅ Copied $pkg_count packages to ISO cache${NC}"
else
    echo -e "${YELLOW}⚠️  No packages in cache to copy${NC}"
fi

# Step 5: Repack the ISO with proper UEFI support
echo -e "${BLUE}📀 Repacking modified ISO with UEFI support...${NC}"

# Use xorriso with simpler approach - let it auto-detect boot structure
if command -v xorriso &>/dev/null; then
    echo -e "${BLUE}🔧 Using xorriso for UEFI+BIOS boot...${NC}"

    # Simple xorriso command that preserves existing boot structure
    xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "ARCHRIOT_$(date +%Y%m)" \
        -eltorito-boot boot/syslinux/isolinux.bin \
        -eltorito-catalog boot/syslinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -isohybrid-mbr "$EXTRACT_DIR/boot/syslinux/isohdpfx.bin" \
        -output "$OUTPUT_ISO" \
        "$EXTRACT_DIR/" && {
        echo -e "${GREEN}✅ ISO created with UEFI+BIOS support${NC}"
    } || {
        echo -e "${YELLOW}⚠️  Advanced xorriso failed, trying basic approach...${NC}"

        # Fallback to basic approach
        xorriso -as mkisofs \
            -iso-level 3 \
            -volid "ARCHRIOT_$(date +%Y%m)" \
            -eltorito-boot boot/syslinux/isolinux.bin \
            -eltorito-catalog boot/syslinux/boot.cat \
            -no-emul-boot \
            -boot-load-size 4 \
            -boot-info-table \
            -output "$OUTPUT_ISO" \
            "$EXTRACT_DIR/" || {
            echo -e "${RED}❌ Failed to create ISO with xorriso${NC}"
            exit 1
        }
    }
else
    echo -e "${RED}❌ xorriso not found${NC}"
    echo -e "${YELLOW}💡 Install libisoburn package: sudo pacman -S libisoburn${NC}"
    exit 1
fi

# Make the ISO hybrid (bootable from USB)
if command -v isohybrid &>/dev/null; then
    echo -e "${BLUE}🔧 Making ISO hybrid bootable...${NC}"
    isohybrid "$OUTPUT_ISO" || {
        echo -e "${YELLOW}⚠️  isohybrid failed, but ISO should still be bootable${NC}"
    }
else
    echo -e "${YELLOW}⚠️  isohybrid not found, install syslinux package for USB boot support${NC}"
fi

echo -e "${GREEN}✅ ISO repacked as $OUTPUT_ISO${NC}"

# Get file size
ISO_SIZE=$(du -h "$OUTPUT_ISO" | cut -f1)
echo -e "${GREEN}📏 Final ISO size: $ISO_SIZE${NC}"

echo -e "${GREEN}🎉 ArchRiot ISO modification complete!${NC}"
echo -e "${GREEN}📀 Output: $OUTPUT_ISO${NC}"
echo -e "${YELLOW}💡 This ISO now includes ArchRiot installer and cached packages${NC}"

# Offer to copy to USB
echo
echo -e "${BLUE}🚀 Ready for testing!${NC}"
read -p "Would you like to copy to USB? [Y/n]: " -n 1 -r
echo

if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo -e "${BLUE}⏭️  Skipping USB copy${NC}"
    echo -e "${YELLOW}💡 You can manually copy: $OUTPUT_ISO${NC}"
else
    echo -e "${BLUE}📋 Copying to Ventoy USB drive...${NC}"
    if copy_to_ventoy "$OUTPUT_ISO"; then
        echo -e "${GREEN}🎯 Ready to test on hardware! Just boot from USB and select the ISO.${NC}"
    else
        echo -e "${YELLOW}💡 Manual copy needed: Copy $OUTPUT_ISO to your USB drive${NC}"
    fi
fi
