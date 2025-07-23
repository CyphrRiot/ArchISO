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
BUILD_DIR="build"
EXTRACT_DIR="$BUILD_DIR/iso_extract"
OUTPUT_ISO="isos/archriot-2025.iso"

# Cleanup function
cleanup() {
    # Silent cleanup on exit - main cleanup happens before celebration
    sudo umount /mnt 2>/dev/null || true
    sudo umount "$EXTRACT_DIR" 2>/dev/null || true
    sudo umount "$BUILD_DIR/efi_mnt" 2>/dev/null || true
}

# Manual cleanup function for successful builds
do_cleanup() {
    echo -e "${YELLOW}🧹 Cleaning up temporary files...${NC}"
    # Only clean up on successful completion or explicit request
    if [[ "$CLEANUP_ON_EXIT" == "true" ]]; then
        sudo rm -rf "$EXTRACT_DIR" "$BUILD_DIR/work_dir" "$BUILD_DIR/efi_mnt"
        rm -f "$BUILD_DIR/efiboot.img"
        echo -e "${GREEN}✅ Cleanup complete${NC}"
    else
        echo -e "${BLUE}💡 Keeping $BUILD_DIR for debugging/resuming${NC}"
    fi
}
trap cleanup EXIT

# Set cleanup behavior (only clean up on successful completion)
CLEANUP_ON_EXIT="false"

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
        # Use dd for faster copy with progress
        if sudo dd if="$iso_file" of="$target_path" bs=4M status=progress oflag=direct; then
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

    # Create build and cache directories if they don't exist
    mkdir -p "$BUILD_DIR/package_cache"

    # Fix permissions for package cache
    sudo chown root:root "$BUILD_DIR/package_cache" 2>/dev/null || true
    sudo chmod 755 "$BUILD_DIR/package_cache" 2>/dev/null || true

    # Check if we have the package list
    if [[ ! -f "configs/packages.x86_64" ]]; then
        echo -e "${RED}❌ Package list not found: configs/packages.x86_64${NC}"
        return 1
    fi

    # Get package list and check what's already cached
    local packages=($(grep -v '^#' configs/packages.x86_64 | grep -v '^$' | tr '\n' ' '))
    local total_packages=${#packages[@]}
    local cached_count=0
    local missing_packages=()

    echo -e "${BLUE}📋 Checking cache status for $total_packages packages...${NC}"

    # Check which packages are already cached
    for package in "${packages[@]}"; do
        local cached_file=$(find "$BUILD_DIR/package_cache" -name "${package}-*.pkg.tar.*" 2>/dev/null | head -1)
        if [[ -n "$cached_file" ]]; then
            ((cached_count++))
        else
            missing_packages+=("$package")
        fi
    done

    echo -e "${GREEN}✅ Already cached: $cached_count packages${NC}"
    echo -e "${BLUE}📥 Missing: ${#missing_packages[@]} packages${NC}"

    # If all packages are cached, skip download prompt
    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        echo -e "${GREEN}🎉 All packages already cached! Using existing cache.${NC}"
        return 0
    fi

    # Ask user if they want to download missing packages
    echo -e "${YELLOW}⚠️  Downloading ${#missing_packages[@]} missing packages can take 5-15 minutes${NC}"
    read -p "Download missing packages? [Y/n]: " -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo -e "${BLUE}⏭️  Skipping package downloads - using existing cache only${NC}"
        return 0
    fi

    # Download missing packages
    local downloaded_packages=0
    local current_package=0
    local total_missing=${#missing_packages[@]}

    echo -e "${BLUE}📥 Downloading $total_missing missing packages...${NC}"

    # Process only missing packages
    for package in "${missing_packages[@]}"; do
        ((current_package++))
        echo -e "${BLUE}[$current_package/$total_missing] Processing: $package${NC}"

        # Check if package exists in official repos first
        # Get latest package info from repos
        local latest_version=$(pacman -Si "$package" 2>/dev/null | grep '^Version' | awk '{print $3}')
        local is_aur_package=false

        # If not in official repos, check if it's an AUR package
        if [[ -z "$latest_version" ]]; then
            if command -v yay >/dev/null 2>&1; then
                latest_version=$(yay -Si "$package" 2>/dev/null | grep '^Version' | awk '{print $3}')
                if [[ -n "$latest_version" ]]; then
                    is_aur_package=true
                fi
            fi
        fi

        if [[ -z "$latest_version" ]]; then
            echo -e "${YELLOW}⚠️  Package $package not found in repos or AUR, skipping${NC}"
            continue
        fi

        # Check if we have this package cached
        local cached_file=$(find "$BUILD_DIR/package_cache" -name "${package}-${latest_version}-*.pkg.tar.*" 2>/dev/null | head -1)

        # Also check for any version of the package (in case version changed)
        if [[ -z "$cached_file" ]]; then
            cached_file=$(find "$BUILD_DIR/package_cache" -name "${package}-*.pkg.tar.*" 2>/dev/null | head -1)
        fi

        echo -e "${BLUE}📥 Downloading: $package-$latest_version${NC}"

        local download_success=false
        local search_paths=("/var/cache/pacman/pkg" "$HOME/.cache/yay")

        if [[ "$is_aur_package" == "true" ]]; then
            # For AUR packages, build with yay (stores in ~/.cache/yay/)
            if yay -S --noconfirm --needed --downloadonly "$package" >/dev/null 2>&1; then
                download_success=true
            fi
        else
            # For official repo packages, use pacman
            if sudo pacman -Sw --noconfirm "$package" >/dev/null 2>&1; then
                download_success=true
            fi
        fi

        if [[ "$download_success" == "true" ]]; then
            # Find the downloaded package and copy it to our cache
            local downloaded_files=()
            for search_path in "${search_paths[@]}"; do
                if [[ -d "$search_path" ]]; then
                    while IFS= read -r -d '' file; do
                        downloaded_files+=("$file")
                    done < <(find "$search_path" -name "${package}-*.pkg.tar.*" -type f ! -name "*.sig" -print0 2>/dev/null)
                fi
            done

            if [[ ${#downloaded_files[@]} -gt 0 ]]; then
                # Copy the most recent file
                for file in "${downloaded_files[@]}"; do
                    if [[ ! -f "$BUILD_DIR/package_cache/$(basename "$file")" ]]; then
                        sudo cp "$file" "$BUILD_DIR/package_cache/" 2>/dev/null || true
                        sudo cp "$file.sig" "$BUILD_DIR/package_cache/" 2>/dev/null || true
                    fi
                done
                echo -e "${GREEN}✅ Downloaded: $package-$latest_version${NC}"
                ((downloaded_packages++))
            else
                echo -e "${RED}❌ Failed to find: $package-$latest_version${NC}"
            fi
        else
            echo -e "${RED}❌ Failed to download: $package-$latest_version${NC}"
        fi
    done

    echo -e "${GREEN}📊 Cache Summary:${NC}"
    echo -e "${GREEN}   Previously cached: $cached_count${NC}"
    echo -e "${GREEN}   Newly downloaded: $downloaded_packages${NC}"
    echo -e "${GREEN}   Total packages: $((cached_count + downloaded_packages))${NC}"

    # Get cache size
    local cache_size=$(du -sh "$BUILD_DIR/package_cache" 2>/dev/null | cut -f1)
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

# Step 2.5: Skip boot config update for now - will do post-creation
echo -e "${BLUE}🔧 Boot configuration will be updated after ISO creation...${NC}"

# Prepare EFI boot files (use existing structure from original ISO)
echo -e "${BLUE}🛠️ Preparing EFI boot structure...${NC}"
# Ensure EFI directory exists and is properly set up
if [[ -d "$EXTRACT_DIR/EFI" ]]; then
    echo -e "${GREEN}✅ EFI directory found in original ISO${NC}"
else
    echo -e "${RED}❌ EFI directory not found in original ISO${NC}"
    exit 1
fi

# Step 3: Add ArchRiot installer and packages to squashfs filesystem
echo -e "${BLUE}⚙️  Modifying squashfs filesystem...${NC}"

# Verify installer files exist
if [[ ! -f "airootfs/usr/local/bin/archriot-installer" ]]; then
    echo -e "${RED}❌ Installer script not found: airootfs/usr/local/bin/archriot-installer${NC}"
    exit 1
fi

# Extract squashfs filesystem
echo -e "${BLUE}📂 Extracting squashfs filesystem...${NC}"
SQUASHFS_FILE="$EXTRACT_DIR/arch/x86_64/airootfs.sfs"
AIROOTFS_DIR="$EXTRACT_DIR/airootfs_extracted"

if [[ ! -f "$SQUASHFS_FILE" ]]; then
    echo -e "${RED}❌ Squashfs file not found: $SQUASHFS_FILE${NC}"
    exit 1
fi

# Extract the squashfs filesystem
sudo unsquashfs -f -d "$AIROOTFS_DIR" -processors 4 "$SQUASHFS_FILE"
echo -e "${GREEN}✅ Squashfs filesystem extracted${NC}"

# Make the extracted filesystem writable
sudo chown -R "$USER:$USER" "$AIROOTFS_DIR"
chmod -R u+w "$AIROOTFS_DIR"

# Add our installer script
echo -e "${BLUE}📝 Adding ArchRiot installer...${NC}"
mkdir -p "$AIROOTFS_DIR/usr/local/bin"
cp airootfs/usr/local/bin/archriot-installer "$AIROOTFS_DIR/usr/local/bin/"
chmod +x "$AIROOTFS_DIR/usr/local/bin/archriot-installer"

# Replace getty@tty1 to directly launch installer
mkdir -p "$AIROOTFS_DIR/etc/systemd/system"
cat > "$AIROOTFS_DIR/etc/systemd/system/getty@tty1.service" << 'EOF'
[Unit]
Description=ArchRiot Installer on %I
Documentation=man:agetty(8) man:systemd-getty-generator(8)
Documentation=http://0pointer.de/blog/projects/serial-console.html
After=systemd-user-sessions.service plymouth-quit-wait.service
After=rc-local.service
Before=getty.target
IgnoreOnIsolate=yes
ConditionPathExists=/dev/tty0

[Service]
ExecStart=/usr/local/bin/archriot-installer
Type=idle
Restart=no
RestartSec=0
UtmpIdentifier=%I
TTYPath=/dev/%I
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
KillMode=process
IgnoreSIGPIPE=no
SendSIGHUP=yes
StandardInput=tty
StandardOutput=tty
StandardError=tty
User=root
Environment=TERM=linux

[Install]
WantedBy=getty.target
EOF

# Enable the service by creating symlink
mkdir -p "$AIROOTFS_DIR/etc/systemd/system/getty.target.wants"
ln -sf "/etc/systemd/system/getty@tty1.service" "$AIROOTFS_DIR/etc/systemd/system/getty.target.wants/getty@tty1.service"

# Add package cache if available
if [[ -d "$BUILD_DIR/package_cache" && -n "$(ls -A "$BUILD_DIR/package_cache" 2>/dev/null)" ]]; then
    echo -e "${BLUE}📦 Adding package cache to filesystem...${NC}"
    mkdir -p "$AIROOTFS_DIR/var/cache/pacman/pkg"
    sudo cp "$BUILD_DIR/package_cache"/*.pkg.tar.* "$AIROOTFS_DIR/var/cache/pacman/pkg/" 2>/dev/null || true

    pkg_count=$(ls "$AIROOTFS_DIR/var/cache/pacman/pkg"/*.pkg.tar.* 2>/dev/null | wc -l)
    echo -e "${GREEN}✅ Added $pkg_count packages to filesystem cache${NC}"

    # Extract dialog package for TUI functionality
    echo -e "${BLUE}🔧 Extracting dialog package for live environment...${NC}"

    # Find dialog package in cache
    dialog_pkg=$(ls "$AIROOTFS_DIR/var/cache/pacman/pkg/dialog"-*.pkg.tar.* 2>/dev/null | head -1)
    if [[ -n "$dialog_pkg" ]]; then
        echo -e "${BLUE}📦 Extracting dialog from $(basename "$dialog_pkg")...${NC}"
        # Calculate relative path before changing directories
        dialog_rel_path=$(realpath --relative-to="$AIROOTFS_DIR" "$dialog_pkg")
        cd "$AIROOTFS_DIR"
        sudo bsdtar -xf "$dialog_rel_path" --exclude='.PKGINFO' --exclude='.MTREE' --exclude='.BUILDINFO' --exclude='.INSTALL'
        if [[ -f "usr/bin/dialog" ]]; then
            echo -e "${GREEN}✅ Dialog extracted successfully${NC}"
        else
            echo -e "${RED}❌ Dialog extraction failed - binary not found${NC}"
        fi
        cd - >/dev/null
    else
        echo -e "${YELLOW}⚠️  Dialog package not found in cache${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  No package cache to add${NC}"
fi

# Repack the squashfs filesystem
echo -e "${BLUE}📦 Repacking squashfs filesystem...${NC}"
sudo mksquashfs "$AIROOTFS_DIR" "$SQUASHFS_FILE.new" -comp xz -b 1M -Xdict-size 100% -noappend -processors 4
sudo mv "$SQUASHFS_FILE.new" "$SQUASHFS_FILE"

# Update checksums
echo -e "${BLUE}🔍 Updating checksums...${NC}"
cd "$EXTRACT_DIR/arch/x86_64"
sha512sum airootfs.sfs > airootfs.sha512
cd - >/dev/null

# Clean up extracted filesystem
sudo rm -rf "$AIROOTFS_DIR"

echo -e "${GREEN}✅ ArchRiot installer and packages integrated into squashfs${NC}"

# Step 4: Package caching (already handled above)
echo -e "${BLUE}📦 Package caching integrated with squashfs modification${NC}"

# Cache packages intelligently (downloads only new/updated packages)
set +e  # Temporarily disable exit on error for package caching
cache_packages
set -e  # Re-enable exit on error

# Copy cached packages to ISO
echo -e "${BLUE}📋 Copying cached packages to ISO...${NC}"
if [[ -d "$BUILD_DIR/package_cache" && -n "$(ls -A "$BUILD_DIR/package_cache" 2>/dev/null)" ]]; then
    sudo cp "$BUILD_DIR/package_cache"/*.pkg.tar.* "$EXTRACT_DIR/airootfs/var/cache/pacman/pkg/" 2>/dev/null || true

    # Count packages copied
    pkg_count=$(ls "$EXTRACT_DIR/airootfs/var/cache/pacman/pkg"/*.pkg.tar.* 2>/dev/null | wc -l)
    echo -e "${GREEN}✅ Copied $pkg_count packages to ISO cache${NC}"
else
    echo -e "${YELLOW}⚠️  No packages in cache to copy${NC}"
fi

# Step 5: Repack the ISO with proper UEFI support
echo -e "${BLUE}📀 Repacking modified ISO with UEFI support...${NC}"

# Use xorriso with proper UEFI support (mimicking archiso approach)
if command -v xorriso &>/dev/null; then
    echo -e "${BLUE}🔧 Using xorriso for UEFI+BIOS boot...${NC}"

    # Check if EFI boot files exist (handle case variations)
    EFI_BOOT_FILE=""
    if [[ -f "$EXTRACT_DIR/EFI/BOOT/bootx64.efi" ]]; then
        EFI_BOOT_FILE="EFI/BOOT/bootx64.efi"
        echo -e "${GREEN}✅ Found bootx64.efi (lowercase)${NC}"
    elif [[ -f "$EXTRACT_DIR/EFI/BOOT/BOOTx64.EFI" ]]; then
        EFI_BOOT_FILE="EFI/BOOT/BOOTx64.EFI"
        echo -e "${GREEN}✅ Found BOOTx64.EFI (uppercase)${NC}"
    fi

    if [[ -n "$EFI_BOOT_FILE" ]]; then
        echo -e "${BLUE}🔧 Creating hybrid ISO with native EFI support...${NC}"

        # Create ISO with both BIOS and UEFI boot support
        xorriso -as mkisofs \
            -iso-level 3 \
            -full-iso9660-filenames \
            -volid "ARCH_202507" \
            -appid "ArchRiot Live/Rescue CD" \
            -publisher "ArchRiot" \
            -preparer "prepared by build-iso.sh" \
            -eltorito-boot boot/syslinux/isolinux.bin \
            -eltorito-catalog boot/syslinux/boot.cat \
            -no-emul-boot \
            -boot-load-size 4 \
            -boot-info-table \
            -eltorito-alt-boot \
            -e "$EFI_BOOT_FILE" \
            -no-emul-boot \
            -isohybrid-gpt-basdat \
            -output "$OUTPUT_ISO" \
            "$EXTRACT_DIR/" || {
            echo -e "${GREEN}✅ ISO created with UEFI+BIOS support${NC}"
        } || {
            echo -e "${YELLOW}⚠️  UEFI ISO creation failed, trying BIOS-only...${NC}"

            # Fallback to BIOS-only approach
            xorriso -as mkisofs \
                -iso-level 3 \
                -volid "ARCH_202507" \
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
        echo -e "${YELLOW}⚠️  No EFI boot files found (checked bootx64.efi and BOOTx64.EFI)${NC}"
        echo -e "${YELLOW}⚠️  Creating BIOS-only ISO...${NC}"

        # BIOS-only fallback
        xorriso -as mkisofs \
            -iso-level 3 \
            -volid "ARCH_202507" \
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
    fi
else
    echo -e "${RED}❌ xorriso not found${NC}"
    echo -e "${YELLOW}💡 Install libisoburn package: sudo pacman -S libisoburn${NC}"
    exit 1
fi

# The ISO should already be hybrid from xorriso with -isohybrid-gpt-basdat
# Only run isohybrid if we created a BIOS-only ISO
if [[ -z "$EFI_BOOT_FILE" ]] && command -v isohybrid &>/dev/null; then
    echo -e "${BLUE}🔧 Making BIOS-only ISO hybrid bootable...${NC}"
    isohybrid "$OUTPUT_ISO" || {
        echo -e "${YELLOW}⚠️  isohybrid failed, but ISO should still be bootable${NC}"
    }
fi

echo -e "${GREEN}✅ ISO repacked as $OUTPUT_ISO${NC}"

# Get file size
ISO_SIZE=$(du -h "$OUTPUT_ISO" | cut -f1)
echo -e "${GREEN}📏 Final ISO size: $ISO_SIZE${NC}"

echo -e "${GREEN}🎉 ArchRiot ISO modification complete!${NC}"
echo -e "${GREEN}📀 Output: $OUTPUT_ISO${NC}"
echo -e "${GREEN}💡 This ISO now includes ArchRiot installer and cached packages${NC}"

# Step 6: Fix UUID mismatch - update boot configs with actual ISO UUID
echo -e "${BLUE}🔧 Fixing UUID mismatch in boot configurations...${NC}"

# Extract actual UUID from created ISO
ACTUAL_UUID=$(blkid "$OUTPUT_ISO" | grep -o 'UUID="[^"]*"' | cut -d'"' -f2)

if [[ -n "$ACTUAL_UUID" ]]; then
    echo -e "${BLUE}📋 Actual ISO UUID: $ACTUAL_UUID${NC}"

    # Re-extract ISO to update boot configs
    TEMP_EXTRACT="$BUILD_DIR/temp_uuid_fix"
    mkdir -p "$TEMP_EXTRACT"
    sudo mount -o loop "$OUTPUT_ISO" /mnt
    sudo cp -r /mnt/* "$TEMP_EXTRACT/"
    sudo umount /mnt

    # Convert UUID timestamp to xorriso modification-date format (YYYY-MM-DD-HH-MM-SS-00 -> YYYYMMDDhhmmss00)
    XORRISO_TIMESTAMP=$(echo "$ACTUAL_UUID" | sed 's/-//g')

    # Make writable
    sudo chown -R "$USER:$USER" "$TEMP_EXTRACT"
    chmod -R u+w "$TEMP_EXTRACT"

    # Update ALL syslinux boot configurations with correct UUID
    for config_file in "$TEMP_EXTRACT/boot/syslinux/archiso_sys-linux.cfg" "$TEMP_EXTRACT/boot/syslinux/archiso_pxe-linux.cfg"; do
        if [[ -f "$config_file" ]]; then
            sed -i "s/archisosearchuuid=[^ ]*/archisosearchuuid=$ACTUAL_UUID/" "$config_file"
            echo -e "${GREEN}✅ Updated $(basename "$config_file") with UUID $ACTUAL_UUID${NC}"
        fi
    done

    # Update UEFI boot configuration
    if [[ -d "$TEMP_EXTRACT/loader/entries" ]]; then
        for entry_file in "$TEMP_EXTRACT/loader/entries"/*.conf; do
            if [[ -f "$entry_file" ]]; then
                sed -i "s/archisosearchuuid=[^ ]*/archisosearchuuid=$ACTUAL_UUID/" "$entry_file"
            fi
        done
        echo -e "${GREEN}✅ UEFI boot configuration updated with UUID $ACTUAL_UUID${NC}"
    fi

    # Recreate ISO with corrected boot configs
    echo -e "${BLUE}📀 Recreating ISO with corrected boot configurations...${NC}"

    if command -v xorriso &>/dev/null; then
        # Check for EFI boot files
        EFI_BOOT_FILE=""
        if [[ -f "$TEMP_EXTRACT/EFI/BOOT/bootx64.efi" ]]; then
            EFI_BOOT_FILE="EFI/BOOT/bootx64.efi"
        elif [[ -f "$TEMP_EXTRACT/EFI/BOOT/BOOTx64.EFI" ]]; then
            EFI_BOOT_FILE="EFI/BOOT/BOOTx64.EFI"
        fi

        if [[ -n "$EFI_BOOT_FILE" ]]; then
            xorriso -as mkisofs \
                -iso-level 3 \
                -full-iso9660-filenames \
                -volid "ARCH_202507" \
                -appid "ArchRiot Live/Rescue CD" \
                -publisher "ArchRiot" \
                -preparer "prepared by build-iso.sh" \
                --modification-date="$XORRISO_TIMESTAMP" \
                -eltorito-boot boot/syslinux/isolinux.bin \
                -eltorito-catalog boot/syslinux/boot.cat \
                -no-emul-boot \
                -boot-load-size 4 \
                -boot-info-table \
                -eltorito-alt-boot \
                -e "$EFI_BOOT_FILE" \
                -no-emul-boot \
                -isohybrid-gpt-basdat \
                -output "$OUTPUT_ISO" \
                "$TEMP_EXTRACT/" && {
                echo -e "${GREEN}✅ ISO recreated with corrected UUID${NC}"
            } || {
                echo -e "${RED}❌ Failed to recreate ISO${NC}"
                exit 1
            }
        else
            echo -e "${RED}❌ EFI boot file not found${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ xorriso not available${NC}"
        exit 1
    fi

    # Clean up temp extraction
    sudo rm -rf "$TEMP_EXTRACT"

    echo -e "${GREEN}✅ UUID mismatch fixed - boot configs now match actual ISO UUID${NC}"
else
    echo -e "${RED}❌ Could not extract UUID from ISO${NC}"
    exit 1
fi

# Step 7: Automatic verification of UUID fix
echo -e "${BLUE}🔍 Verifying UUID fix...${NC}"

# Extract actual ISO UUID again to verify
VERIFY_UUID=$(blkid -s UUID -o value "$OUTPUT_ISO" 2>/dev/null)
if [[ -z "$VERIFY_UUID" ]]; then
    echo -e "${RED}❌ Verification failed: Could not read ISO UUID${NC}"
    exit 1
fi

# Mount ISO and check boot configs
VERIFY_MOUNT="$BUILD_DIR/temp_verify"
mkdir -p "$VERIFY_MOUNT"
sudo mount -o loop "$OUTPUT_ISO" "$VERIFY_MOUNT" 2>/dev/null

if [[ $? -ne 0 ]]; then
    echo -e "${RED}❌ Verification failed: Could not mount ISO${NC}"
    sudo rmdir "$VERIFY_MOUNT" 2>/dev/null || true
    exit 1
fi

# Check if boot configs contain the correct UUID
BOOT_UUIDS=$(grep -r "archisosearchuuid=" "$VERIFY_MOUNT/boot/" 2>/dev/null | grep -o "archisosearchuuid=[^[:space:]]*" | cut -d'=' -f2 | sort -u)
sudo umount "$VERIFY_MOUNT"
sudo rmdir "$VERIFY_MOUNT"

# Verify all boot configs have the same UUID and it matches the ISO UUID
UUID_COUNT=$(echo "$BOOT_UUIDS" | wc -l)
UNIQUE_BOOT_UUID=$(echo "$BOOT_UUIDS" | head -1)

if [[ "$UUID_COUNT" -eq 1 && "$UNIQUE_BOOT_UUID" == "$VERIFY_UUID" ]]; then
    echo -e "${GREEN}✅ Verification PASSED: All boot configs match ISO UUID ($VERIFY_UUID)${NC}"
else
    echo -e "${RED}❌ Verification FAILED:${NC}"
    echo -e "${RED}   ISO UUID: $VERIFY_UUID${NC}"
    echo -e "${RED}   Boot config UUIDs found: $UUID_COUNT different values${NC}"
    echo "$BOOT_UUIDS" | while read uuid; do
        echo -e "${RED}   - $uuid${NC}"
    done
    exit 1
fi

# Mark for successful cleanup
CLEANUP_ON_EXIT="true"

# Clean up temporary files before celebration
do_cleanup

# Offer to copy to USB
echo
echo -e "${BLUE}🚀 Build verified and ready for testing!${NC}"
read -p "Would you like to copy to USB? [Y/n]: " -r
echo

if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo -e "${BLUE}⏭️  Skipping USB copy${NC}"
    echo -e "${YELLOW}💡 You can manually copy: $OUTPUT_ISO${NC}"
else
    echo -e "${BLUE}📋 Copying to Ventoy USB drive...${NC}"
    if copy_to_ventoy "$OUTPUT_ISO"; then
        echo -e "${GREEN}🎯 Ready to test on hardware! Just boot from USB and select the ISO.${NC}"
    else
        echo -e "${YELLOW}⚠️  USB copy failed or no Ventoy drive found${NC}"
        echo -e "${YELLOW}💡 You can manually copy: $OUTPUT_ISO${NC}"
    fi
fi

echo
echo -e "${GREEN}🎉🎉🎉 ArchRiot ISO BUILD COMPLETE! 🎉🎉🎉${NC}"
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}✅ ISO Size: $ISO_SIZE${NC}"
echo -e "${GREEN}✅ UEFI + BIOS Boot Support${NC}"
PKG_COUNT=$(ls "$BUILD_DIR/package_cache"/*.pkg.tar.* 2>/dev/null | wc -l)
echo -e "${GREEN}✅ Complete Package Cache ($PKG_COUNT packages)${NC}"
echo -e "${GREEN}✅ Seamless Installer Experience${NC}"
echo -e "${GREEN}✅ Ready for Hardware Testing${NC}"

echo
echo -e "${GREEN}🚀 Your ArchRiot installation ISO is ready!${NC}"
echo -e "${GREEN}📀 Location: $OUTPUT_ISO${NC}"
echo -e "${GREEN}🔥 Boot it up and install ArchRiot in minutes!${NC}"
echo
