#!/bin/bash

# ArchRiot ISO Builder
# Simple script to build ArchRiot installer ISO using archiso

set -e

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
        if sudo cp "$iso_file" "$target_path"; then
            echo -e "${GREEN}✅ Successfully copied ISO to Ventoy drive${NC}"
            echo -e "${GREEN}📀 Available at: $target_path${NC}"

            # Get file size for confirmation
            ventoy_size=$(du -h "$target_path" | cut -f1)
            echo -e "${GREEN}📏 Ventoy copy size: $ventoy_size${NC}"
        else
            echo -e "${RED}❌ Failed to copy ISO to Ventoy drive${NC}"
        fi

        # Unmount if we mounted it
        if [[ "$ventoy_mount" == "/tmp/ventoy_mount" ]]; then
            echo -e "${BLUE}📤 Unmounting Ventoy drive...${NC}"
            sudo umount "$ventoy_mount"
            sudo rmdir "$ventoy_mount"
            echo -e "${GREEN}✅ Ventoy drive unmounted${NC}"
        fi

        return 0
    fi

    # Prompt for Ventoy copy if not found
    if ! $ventoy_found; then
        echo -e "${BLUE}💾 Ventoy drive not found. Would you like to copy this ISO to Ventoy?${NC}"
        echo -e "${YELLOW}💡 Connect your Ventoy USB drive now if needed. [Y/n] (n to skip)${NC}"
        read -p "Copy to Ventoy? [Y/n]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            echo -e "${BLUE}⏭️  Skipping Ventoy copy${NC}"
            echo -e "${BLUE}💡 You can manually copy: $iso_file${NC}"
            return 0
        fi
    fi

    # Wait for Ventoy drive
    echo -e "${YELLOW}⏳ Waiting for you to connect the Ventoy drive (Ctrl+C to cancel)...${NC}"
    local wait_count=0
    while ! $ventoy_found; do
        sleep 2
        wait_count=$((wait_count + 1))

        # Check for newly mounted Ventoy drives
        for mount_point in /media/$USER/* /mnt/* /run/media/$USER/*; do
            if [[ -d "$mount_point" && -d "$mount_point/ventoy" ]]; then
                ventoy_mount="$mount_point"
                ventoy_found=true
                echo -e "${GREEN}🎯 Ventoy drive connected at: $ventoy_mount${NC}"
                break
            fi
        done

        # Also check for new VENTOY labeled devices
        if ! $ventoy_found; then
            ventoy_device=$(lsblk -no NAME,LABEL | grep -i ventoy | awk '{gsub(/[├─└│ ]*/, "", $1); print $1}' | head -1)
            if [[ -n "$ventoy_device" ]]; then
                # Check if already mounted
                existing_mount=$(findmnt -no TARGET "/dev/$ventoy_device" 2>/dev/null | head -1)
                if [[ -n "$existing_mount" ]]; then
                    ventoy_mount="$existing_mount"
                    ventoy_found=true
                    echo -e "${GREEN}✅ Found mounted Ventoy drive at $ventoy_mount${NC}"
                    break
                else
                    ventoy_mount="/tmp/ventoy_mount"
                    echo -e "${YELLOW}📁 New Ventoy device detected: /dev/$ventoy_device${NC}"
                    sudo mkdir -p "$ventoy_mount"
                    if sudo mount "/dev/$ventoy_device" "$ventoy_mount" 2>/dev/null; then
                        ventoy_found=true
                        echo -e "${GREEN}✅ Mounted Ventoy drive at $ventoy_mount${NC}"
                        break
                    else
                        sudo rmdir "$ventoy_mount" 2>/dev/null || true
                    fi
                fi
            fi
        fi

        # Show progress
        if [[ $((wait_count % 10)) -eq 0 ]]; then
            echo -e "${BLUE}⏳ Checking for Ventoy drive... (${wait_count} seconds)${NC}"
        fi
    done

    if $ventoy_found; then
        # Copy the ISO
        iso_name=$(basename "$iso_file")
        target_path="$ventoy_mount/$iso_name"

        echo -e "${BLUE}📋 Copying $iso_name to Ventoy drive...${NC}"
        if sudo cp "$iso_file" "$target_path"; then
            echo -e "${GREEN}✅ Successfully copied ISO to Ventoy drive${NC}"
            echo -e "${GREEN}📀 Ready to boot: $target_path${NC}"

            # Get file size for confirmation
            ventoy_size=$(du -h "$target_path" | cut -f1)
            echo -e "${GREEN}📏 Ventoy copy size: $ventoy_size${NC}"
        else
            echo -e "${RED}❌ Failed to copy ISO to Ventoy drive${NC}"
        fi

        # Unmount if we mounted it
        if [[ "$ventoy_mount" == "/tmp/ventoy_mount" ]]; then
            echo -e "${BLUE}📤 Unmounting Ventoy drive...${NC}"
            sudo umount "$ventoy_mount"
            sudo rmdir "$ventoy_mount"
            echo -e "${GREEN}✅ Ventoy drive safely ejected${NC}"
        fi
    fi
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 ArchRiot ISO Builder${NC}"
echo -e "${BLUE}========================${NC}"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}❌ This script should NOT be run as root${NC}"
   echo -e "${YELLOW}💡 Run as regular user - it will ask for sudo when needed${NC}"
   exit 1
fi

# Check if archiso is installed
if ! command -v mkarchiso &> /dev/null; then
    echo -e "${YELLOW}📦 Installing archiso...${NC}"
    sudo pacman -S --needed --noconfirm archiso
fi

# Create output directory
OUTPUT_DIR="$(pwd)/out"
WORK_DIR="$(pwd)/work"

echo -e "${BLUE}🧹 Cleaning previous builds...${NC}"
sudo rm -rf "$OUTPUT_DIR" "$WORK_DIR" 2>/dev/null || true

echo -e "${BLUE}🔨 Building ArchRiot ISO...${NC}"
echo -e "${YELLOW}📁 Output directory: $OUTPUT_DIR${NC}"
echo -e "${YELLOW}🔧 Work directory: $WORK_DIR${NC}"

# Build the ISO
sudo mkarchiso -v -w "$WORK_DIR" -o "$OUTPUT_DIR" "$(pwd)"

# Find the generated ISO
ISO_FILE=$(find "$OUTPUT_DIR" -name "*.iso" -type f | head -1)

if [[ -n "$ISO_FILE" ]]; then
    echo -e "${GREEN}✅ ISO built successfully!${NC}"
    echo -e "${GREEN}📀 ISO location: $ISO_FILE${NC}"

    # Get ISO size
    ISO_SIZE=$(du -h "$ISO_FILE" | cut -f1)
    echo -e "${GREEN}📏 ISO size: $ISO_SIZE${NC}"

    # Make ISO accessible to user
    sudo chown "$USER:$USER" "$ISO_FILE"

    echo -e "${BLUE}🎯 Next steps:${NC}"
    echo -e "${YELLOW}  1. Test in VM: Use the ISO file above${NC}"
    echo -e "${YELLOW}  2. Write to USB: sudo dd if='$ISO_FILE' of=/dev/sdX bs=4M status=progress${NC}"
    echo -e "${YELLOW}  3. Boot and test the automatic ArchRiot installation${NC}"
else
    echo -e "${RED}❌ ISO build failed - no ISO file found in output directory${NC}"
    exit 1
fi

# Ask user if they want to copy to Ventoy
echo -e "${BLUE}💾 Copy ISO to Ventoy drive?${NC}"
echo -e "${YELLOW}💡 This will copy the ISO to your Ventoy drive (connect it now if needed)${NC}"
read -p "Copy to Ventoy? [Y/n]: " -n 1 -r
echo
if ! [[ $REPLY =~ ^[Nn]$ ]]; then
    copy_to_ventoy "$ISO_FILE"
else
    echo -e "${BLUE}⏭️  Skipping Ventoy copy${NC}"
    echo -e "${BLUE}💡 You can manually copy: $ISO_FILE${NC}"
fi

echo -e "${GREEN}🎉 Build complete!${NC}"
