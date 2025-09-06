#!/bin/bash

# testdisk.sh - Test the installed ArchRiot system (boot from virtual disk)
# Boots the VM from the installed system instead of the ISO

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
VM_NAME="archriot"
MEMORY="4096" # 4GB RAM
DISK_PATH="./${VM_NAME}.qcow2"

# Check if virtual disk exists
if [ ! -f "$DISK_PATH" ]; then
  print_error "Virtual disk not found: $DISK_PATH"
  print_info "You need to install ArchRiot first using './testiso.sh'"
  print_info "The installation creates the virtual disk that this script boots from"
  exit 1
fi

print_status "Found virtual disk: $DISK_PATH"

# Check if QEMU is installed
if ! command -v qemu-system-x86_64 &>/dev/null; then
  print_error "QEMU not installed"
  print_info "Install with: sudo pacman -S qemu-desktop"
  exit 1
fi

# Get disk size for info
DISK_SIZE=$(qemu-img info "$DISK_PATH" | grep "virtual size" | awk '{print $3 " " $4}' | sed 's/[(),]//g')

print_info "Virtual disk size: $DISK_SIZE"
print_info "Starting VM with $MEMORY MB RAM..."
print_info "VM will boot from the installed ArchRiot system"
print_warning "This boots the INSTALLED system, not the live ISO"
print_info "You should see:"
print_info "  1. GRUB or systemd-boot bootloader"
print_info "  2. LUKS password prompt"
print_info "  3. ArchRiot login screen"
print_info "  4. First-boot ArchRiot setup (if first login)"

echo
print_warning "Audio disabled to avoid Bluetooth interference"
echo

# QEMU command to boot from installed system (NO ISO)
exec qemu-system-x86_64 \
  -name "$VM_NAME-installed" \
  -machine type=q35,accel=kvm \
  -cpu host \
  -smp 4 \
  -m "$MEMORY" \
  -bios /usr/share/edk2/x64/OVMF.4m.fd \
  -device virtio-vga-gl \
  -display gtk,gl=on \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0 \
  -device virtio-blk-pci,drive=hd0 \
  -drive file="$DISK_PATH",format=qcow2,id=hd0,if=none \
  -boot order=c \
  -rtc base=utc,clock=host \
  -usb \
  -device usb-tablet
