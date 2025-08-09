#!/bin/bash

# testiso-noaudio.sh - Quick VM testing for ArchRiot ISO (no audio to avoid Bluetooth interference)
# Creates QEMU VM to test the ISO without hardware

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Icons
CHECK="✓"
CROSS="✗"
WARN="⚠"

print_status() {
    echo -e "${GREEN}${CHECK}${NC} $1"
}

print_error() {
    echo -e "${RED}${CROSS}${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}${WARN}${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Configuration
ISO_PATH="isos/archriot-2025.iso"
VM_NAME="archriot-test"
MEMORY="4096"  # 4GB RAM
DISK_SIZE="20G"
DISK_PATH="./${VM_NAME}.qcow2"

# Check if ISO exists
if [ ! -f "$ISO_PATH" ]; then
    print_error "ISO not found: $ISO_PATH"
    print_info "Run './build-iso.sh' first to create the ISO"
    exit 1
fi

print_status "Found ISO: $ISO_PATH"

# Check if QEMU is installed
if ! command -v qemu-system-x86_64 &> /dev/null; then
    print_error "QEMU not installed"
    print_info "Install with: sudo pacman -S qemu-desktop"
    exit 1
fi

# Create virtual disk if it doesn't exist
if [ ! -f "$DISK_PATH" ]; then
    print_info "Creating virtual disk: $DISK_PATH ($DISK_SIZE)"
    qemu-img create -f qcow2 "$DISK_PATH" "$DISK_SIZE"
    print_status "Virtual disk created"
else
    print_warning "Using existing virtual disk: $DISK_PATH"
    print_info "Delete $DISK_PATH to start fresh"
fi

print_info "Starting VM with $MEMORY MB RAM..."
print_info "VM will boot from ISO and can install to virtual disk"
print_warning "This is for testing only - virtual installation"
print_warning "Audio disabled to avoid Bluetooth interference"

# QEMU command with optimal settings for testing (NO AUDIO)
exec qemu-system-x86_64 \
    -name "$VM_NAME" \
    -machine type=q35,accel=kvm \
    -cpu host \
    -smp 4 \
    -m "$MEMORY" \
    -device virtio-vga-gl \
    -display gtk,gl=on \
    -device virtio-net-pci,netdev=net0 \
    -netdev user,id=net0 \
    -device virtio-blk-pci,drive=hd0 \
    -drive file="$DISK_PATH",format=qcow2,id=hd0,if=none \
    -device virtio-scsi-pci \
    -device scsi-cd,drive=cd0 \
    -drive file="$ISO_PATH",format=raw,id=cd0,if=none,media=cdrom \
    -boot order=dc \
    -rtc base=utc,clock=host \
    -usb \
    -device usb-tablet
