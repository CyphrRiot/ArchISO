#!/usr/bin/env bash

# ArchRiot ISO Builder - Clean Rebuild Using ArchISO Toolkit
# Creates custom Arch Linux ISO with embedded package cache for offline installation

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$SCRIPT_DIR"
PROFILE_DIR="$WORK_DIR/archriot-profile"
CACHE_DIR="$WORK_DIR/cache"
OUTPUT_DIR="$WORK_DIR/out"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root"
        exit 1
    fi
}

# Prepare workspace by copying releng profile
prepare_workspace() {
    log_info "Preparing workspace..."

    # Remove existing profile if it exists
    if [[ -d "$PROFILE_DIR" ]]; then
        log_warning "Removing existing profile directory"
        rm -rf "$PROFILE_DIR"
    fi

    # Copy releng profile as base
    log_info "Copying releng profile from /usr/share/archiso/configs/releng/"
    cp -r /usr/share/archiso/configs/releng/ "$PROFILE_DIR"

    # Create cache directories
    mkdir -p "$CACHE_DIR/official"
    mkdir -p "$CACHE_DIR/aur"
    mkdir -p "$OUTPUT_DIR"

    log_success "Workspace prepared"
}

# Test workspace preparation
test_workspace() {
    log_info "Testing workspace setup..."

    # Check profile directory exists
    if [[ ! -d "$PROFILE_DIR" ]]; then
        log_error "Profile directory not created: $PROFILE_DIR"
        exit 1
    fi

    # Check essential profile files exist
    local essential_files=(
        "profiledef.sh"
        "packages.x86_64"
        "pacman.conf"
    )

    for file in "${essential_files[@]}"; do
        if [[ ! -f "$PROFILE_DIR/$file" ]]; then
            log_error "Essential profile file missing: $file"
            exit 1
        fi
    done

    # Check cache directories exist
    if [[ ! -d "$CACHE_DIR/official" ]]; then
        log_error "Official cache directory not created"
        exit 1
    fi

    if [[ ! -d "$CACHE_DIR/aur" ]]; then
        log_error "AUR cache directory not created"
        exit 1
    fi

    log_success "Workspace test passed"
}

# Download required packages to local cache
download_packages() {
    log_info "Downloading packages to cache..."

    local package_list="$WORK_DIR/configs/official-packages.txt"

    if [[ ! -f "$package_list" ]]; then
        log_error "Package list not found: $package_list"
        exit 1
    fi

    log_info "Downloading packages listed in $package_list"

    # Read all packages into an array first
    local packages=()
    while IFS= read -r package; do
        # Skip empty lines and comments
        [[ -z "$package" || "$package" =~ ^#.* ]] && continue
        packages+=("$package")
    done < "$package_list"

    # Download all packages using pacman's default cache
    if [[ ${#packages[@]} -gt 0 ]]; then
        log_info "Downloading ${#packages[@]} packages to system cache..."
        if ! sudo pacman -Sw --noconfirm "${packages[@]}"; then
            log_error "Failed to download packages. Cannot continue without packages."
            exit 1
        fi
    else
        log_error "No packages found in package list"
        exit 1
    fi

    # Copy packages from system cache to our cache
    local pacman_cache="/var/cache/pacman/pkg"
    log_info "Copying packages from system cache to build cache..."

    for package in "${packages[@]}"; do
        # Find the package file(s) for this package name, excluding signature files
        find "$pacman_cache" -name "${package}-*.pkg.tar.zst" -not -name "*.sig" -exec cp {} "$CACHE_DIR/official/" \; 2>/dev/null || {
            log_warning "Could not find cached package for: $package"
        }
    done

    log_success "Package download completed"
}

# Package validation helper
validate_package_file() {
    local pkg="$1"
    if command -v bsdtar >/dev/null 2>&1; then
        if ! bsdtar -tf "$pkg" >/dev/null 2>&1; then
            log_error "Corrupted package archive: $(basename "$pkg")"
            exit 1
        fi
    elif command -v tar >/dev/null 2>&1; then
        if tar --help 2>&1 | grep -q -- "--zstd"; then
            if ! tar --zstd -tf "$pkg" >/dev/null 2>&1; then
                log_error "Corrupted package archive (tar --zstd failed): $(basename "$pkg")"
                exit 1
            fi
        elif command -v zstd >/dev/null 2>&1; then
            if ! zstd -d --stdout "$pkg" 2>/dev/null | tar -tf - >/dev/null 2>&1; then
                log_error "Corrupted package archive (zstd|tar failed): $(basename "$pkg")"
                exit 1
            fi
        else
            log_warning "Cannot validate $(basename "$pkg"): tar lacks zstd support and zstd not installed"
        fi
    else
        log_warning "No tar utility available to validate package archives"
    fi
}

# Test package download
test_packages() {
    log_info "Testing package download..."

    # Count packages in cache (excluding signature files)
    local pkg_count=$(find "$CACHE_DIR/official" -name "*.pkg.tar.zst" | wc -l)
    log_info "Found $pkg_count packages in cache"

    if [[ $pkg_count -eq 0 ]]; then
        log_error "CRITICAL: No packages found in cache after download"
        exit 1
    fi

    # Verify we have a reasonable number of packages
    if [[ $pkg_count -lt 100 ]]; then
        log_error "CRITICAL: Too few packages downloaded ($pkg_count). Expected at least 100."
        exit 1
    fi

    # Validate a sample of packages to catch corruption quickly
    local sample_limit=20
    local validated=0
    log_info "Validating up to $sample_limit package archives from cache..."
    while IFS= read -r pkg; do
        validate_package_file "$pkg"
        validated=$((validated+1))
    done < <(find "$CACHE_DIR/official" -maxdepth 1 -type f -name "*.pkg.tar.zst" | sort | head -n "$sample_limit")
    log_info "Validated $validated package archive(s) from cache"

    log_success "Package download test passed ($pkg_count packages)"
    log_info "DEBUG: Package test completed successfully, continuing to repository creation..."
}

# Create offline repository database
create_repository() {
    log_info "Creating offline repository database..."

    cd "$CACHE_DIR/official"

    # Count packages (excluding signature files)
    local pkg_count=$(find . -name "*.pkg.tar.zst" | wc -l)
    log_info "Found $pkg_count packages in cache"

    if [[ $pkg_count -eq 0 ]]; then
        log_error "No packages found in cache"
        exit 1
    fi

    # Create repository database
    log_info "Running repo-add to create database..."
    repo-add archriot-offline.db.tar.gz *.pkg.tar.zst || {
        log_error "Failed to create repository database"
        exit 1
    }

    # Verify database was created
    if [[ -f "archriot-offline.db.tar.gz" ]]; then
        log_success "Repository database created successfully"
    else
        log_error "Repository database was not created"
        exit 1
    fi

    cd "$WORK_DIR"
    log_info "DEBUG: Repository creation completed successfully"
}

# Test repository creation
test_repository() {
    log_info "Testing repository database..."

    # Check database files exist
    local db_files=(
        "$CACHE_DIR/official/archriot-offline.db.tar.gz"
        "$CACHE_DIR/official/archriot-offline.files.tar.gz"
    )

    for db_file in "${db_files[@]}"; do
        if [[ ! -f "$db_file" ]]; then
            log_error "Database file missing: $(basename "$db_file")"
            exit 1
        fi

        # Check file is not empty
        if [[ ! -s "$db_file" ]]; then
            log_error "Database file is empty: $(basename "$db_file")"
            exit 1
        fi
    done

    # Test database can be read
    if ! tar -tzf "$CACHE_DIR/official/archriot-offline.db.tar.gz" >/dev/null 2>&1; then
        log_error "Database file appears corrupted"
        exit 1
    fi

    # Count entries in database
    local db_entries=$(tar -tzf "$CACHE_DIR/official/archriot-offline.db.tar.gz" | grep -c "desc$" || true)
    local pkg_count=$(find "$CACHE_DIR/official" -name "*.pkg.tar.zst" | wc -l)

    log_info "Database entries: $db_entries, Package files: $pkg_count"

    if [[ $db_entries -eq 0 ]]; then
        log_error "No entries found in database"
        exit 1
    fi

    log_success "Repository database test passed"
    log_info "DEBUG: Repository test completed successfully, continuing to profile customization..."
}

# Customize archiso profile with our packages and configs
customize_profile() {
    log_info "Customizing archiso profile..."

    # Create directory structure in airootfs
    mkdir -p "$PROFILE_DIR/airootfs/opt/archriot-cache/official"
    mkdir -p "$PROFILE_DIR/airootfs/usr/local/bin"
    mkdir -p "$PROFILE_DIR/airootfs/etc/systemd/system"
    mkdir -p "$PROFILE_DIR/airootfs/etc/systemd/system/multi-user.target.wants"

    # Copy packages and database to profile
    # Copy curated archiso profile files if present
    if [[ -f "$WORK_DIR/configs/profiledef.sh" ]]; then
        log_info "Using curated profiledef.sh from configs/"
        cp "$WORK_DIR/configs/profiledef.sh" "$PROFILE_DIR/profiledef.sh"
    fi
    if [[ -f "$WORK_DIR/configs/packages.x86_64" ]]; then
        log_info "Using curated packages.x86_64 from configs/"
        cp "$WORK_DIR/configs/packages.x86_64" "$PROFILE_DIR/packages.x86_64"
    fi
    if [[ -f "$WORK_DIR/configs/pacman.conf" ]]; then
        log_info "Using curated pacman.conf from configs/"
        cp "$WORK_DIR/configs/pacman.conf" "$PROFILE_DIR/pacman.conf"
    fi
    log_info "Copying packages to profile..."
    cp -r "$CACHE_DIR/official/"* "$PROFILE_DIR/airootfs/opt/archriot-cache/official/"

    # Copy riot installer
    if [[ -f "$WORK_DIR/airootfs/usr/local/bin/riot" ]]; then
        log_info "Copying riot installer..."
        cp "$WORK_DIR/airootfs/usr/local/bin/riot" "$PROFILE_DIR/airootfs/usr/local/bin/"
        chmod +x "$PROFILE_DIR/airootfs/usr/local/bin/riot"
    else
        log_warning "Riot installer not found at $WORK_DIR/airootfs/usr/local/bin/riot"
    fi

    # Create pacman.conf for offline repository
    log_info "Creating offline pacman.conf..."
    if [[ -f "$WORK_DIR/airootfs/etc/pacman-offline.conf" ]]; then
        log_info "Using existing airootfs/etc/pacman-offline.conf"
        cp "$WORK_DIR/airootfs/etc/pacman-offline.conf" "$PROFILE_DIR/airootfs/etc/pacman.conf"
    else
        log_warning "airootfs/etc/pacman-offline.conf not found; generating default pacman.conf"
        cat > "$PROFILE_DIR/airootfs/etc/pacman.conf" << 'EOF'
#
# /etc/pacman.conf - ArchRiot Live Environment
#
# See the pacman.conf(5) manpage for option and repository directives

#
# GENERAL OPTIONS
#
[options]
# The following paths are commented out with their default values listed.
# If you wish to use different paths, uncomment and update the paths.
#RootDir     = /
#DBPath      = /var/lib/pacman/
#CacheDir    = /var/cache/pacman/pkg/
#LogFile     = /var/log/pacman.log
#GPGDir      = /etc/pacman.d/gnupg/
#HookDir     = /etc/pacman.d/hooks/
HoldPkg     = pacman glibc
#XferCommand = /usr/bin/curl -L -C - -f -o %o %u
#XferCommand = /usr/bin/wget --passive-ftp -c -O %o %u
#CleanMethod = KeepInstalled
Architecture = auto

# Pacman won't upgrade packages listed in IgnorePkg and members of IgnoreGroup
#IgnorePkg   =
#IgnoreGroup =

#NoUpgrade   =
#NoExtract   =

# Misc options
#UseSyslog
#Color
#NoProgressBar
CheckSpace
VerbosePkgLists
ParallelDownloads = 5

# By default, pacman accepts packages signed by keys that its local keyring
# trusts (see pacman-key and its man page), as well as unsigned packages.
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

#RemoteFileSigLevel = Required

# NOTE: You must run `pacman-key --init` before first using pacman; the local
# keyring can then be populated with the keys of all official Arch Linux
# packagers with `pacman-key --populate archlinux`.

#
# REPOSITORIES
#   - can be defined here or included from another file
#   - pacman will search repositories in the order defined here
#   - local/custom mirrors can be added here or in separate files
#   - repositories listed first will take precedence when packages
#     have identical names, regardless of version number
#   - URLs will have $repo replaced by the name of the current repo
#   - URLs will have $arch replaced by the name of the architecture
#
# Repository entries are of the format:
#       [repo-name]
#       Server = ServerName
#       Include = IncludePath
#
# The header [repo-name] is the name of the repository. It must be unique.
# It cannot contain hyphens.
#

# Offline ArchRiot repository (highest priority)
[archriot-offline]
SigLevel = Optional TrustAll
Server = file:///opt/archriot-cache/official

# Standard Arch repositories (fallback when online)
[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

# If you want to run 32 bit applications on your x86_64 system,
# enable the multilib repositories as required here.

#[multilib-testing]
#Include = /etc/pacman.d/mirrorlist

#[multilib]
#Include = /etc/pacman.d/mirrorlist

# An example of a custom package repository.  See the pacman manpage for
# tips on creating your own repositories.
#[custom]
#SigLevel = Optional TrustAll
#Server = file:///home/custompkgs
EOF
    fi

    # Create and enable systemd service for auto-starting the installer
    log_info "Creating riot-installer systemd service..."
    cat > "$PROFILE_DIR/airootfs/etc/systemd/system/riot-installer.service" << 'EOF'
[Unit]
Description=ArchRiot Installer (TTY1)
Conflicts=getty@tty1.service
Before=getty@tty1.service
After=multi-user.target

[Service]
Type=simple
TTYPath=/dev/tty1
StandardInput=tty
StandardOutput=tty
StandardError=journal+console
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
ExecStart=/usr/local/bin/riot
Restart=on-failure
RestartSec=1s

[Install]
WantedBy=multi-user.target
EOF

    # Enable the service at boot
    ln -sf ../riot-installer.service "$PROFILE_DIR/airootfs/etc/systemd/system/multi-user.target.wants/riot-installer.service"

    log_success "Profile customization completed"
    log_info "DEBUG: Profile customization completed successfully"
}

# Test profile customization
test_profile() {
    log_info "Testing profile customization..."

    # Check packages were copied
    local profile_pkg_count=$(find "$PROFILE_DIR/airootfs/opt/archriot-cache/official" -name "*.pkg.tar.zst" | wc -l)
    local cache_pkg_count=$(find "$CACHE_DIR/official" -name "*.pkg.tar.zst" | wc -l)

    if [[ $profile_pkg_count -ne $cache_pkg_count ]]; then
        log_error "Package count mismatch - Cache: $cache_pkg_count, Profile: $profile_pkg_count"
        exit 1
    fi

    # Check database files were copied
    if [[ ! -f "$PROFILE_DIR/airootfs/opt/archriot-cache/official/archriot-offline.db.tar.gz" ]]; then
        log_error "Database not copied to profile"
        exit 1
    fi

    # Check pacman.conf was created
    if [[ ! -f "$PROFILE_DIR/airootfs/etc/pacman.conf" ]]; then
        log_error "Pacman.conf not created in profile"
        exit 1
    fi

    # Verify pacman.conf contains our repository
    if ! grep -q "archriot-offline" "$PROFILE_DIR/airootfs/etc/pacman.conf"; then
        log_error "Offline repository not configured in pacman.conf"
        exit 1
    fi

    # Check if riot installer exists (optional)
    if [[ -f "$PROFILE_DIR/airootfs/usr/local/bin/riot" ]]; then
        log_info "Riot installer found and copied"
        if [[ ! -x "$PROFILE_DIR/airootfs/usr/local/bin/riot" ]]; then
            log_error "Riot installer is not executable"
            exit 1
        fi
    else
        log_error "Riot installer missing at $PROFILE_DIR/airootfs/usr/local/bin/riot"
        exit 1
    fi

    # Verify installer systemd service setup
    local service_file="$PROFILE_DIR/airootfs/etc/systemd/system/riot-installer.service"
    local wants_link="$PROFILE_DIR/airootfs/etc/systemd/system/multi-user.target.wants/riot-installer.service"

    if [[ ! -f "$service_file" ]]; then
        log_error "Installer service file missing: $(basename "$service_file")"
        exit 1
    fi

    if [[ ! -L "$wants_link" ]]; then
        log_error "Installer service not enabled (symlink missing in multi-user.target.wants)"
        exit 1
    fi

    # Verify curated profile files were copied when present
    if [[ -f "$WORK_DIR/configs/profiledef.sh" ]]; then
        if [[ ! -s "$PROFILE_DIR/profiledef.sh" ]]; then
            log_error "Curated profiledef.sh expected but missing or empty in profile"
            exit 1
        fi
    fi
    if [[ -f "$WORK_DIR/configs/packages.x86_64" ]]; then
        if [[ ! -s "$PROFILE_DIR/packages.x86_64" ]]; then
            log_error "Curated packages.x86_64 expected but missing or empty in profile"
            exit 1
        fi
    fi
    if [[ -f "$WORK_DIR/configs/pacman.conf" ]]; then
        if [[ ! -s "$PROFILE_DIR/pacman.conf" ]] ; then
            log_error "Curated pacman.conf expected but missing or empty in profile"
            exit 1
        fi
    fi
    log_success "Profile customization test passed"
    log_info "DEBUG: Profile test completed successfully, continuing to ISO build..."
}

# Build ISO using mkarchiso
build_iso() {
    log_info "Building ISO with mkarchiso..."

    # Clean output directory
    # Ensure previous airootfs mounts are unmounted before deleting
    if [[ -d "$OUTPUT_DIR/work/x86_64/airootfs" ]]; then
        unmount_airootfs_mounts
    fi
    if [[ -d "$OUTPUT_DIR" ]]; then
        sudo rm -rf "$OUTPUT_DIR"
    fi
    mkdir -p "$OUTPUT_DIR"

    # Run mkarchiso
    log_info "Running mkarchiso (this may take a while)..."
    if ! sudo mkarchiso -v -w "$OUTPUT_DIR/work" -o "$OUTPUT_DIR" "$PROFILE_DIR"; then
        log_error "CRITICAL: mkarchiso failed - ISO build unsuccessful"
        exit 1
    fi

    # Find generated ISO
    local iso_file=$(find "$OUTPUT_DIR" -name "*.iso" | head -1)
    if [[ -n "$iso_file" ]]; then
        log_success "ISO built successfully: $iso_file"

        # Prepare final output directory
        mkdir -p "$WORK_DIR/isos"

        # Copy ISO to canonical path
        local final_iso="$WORK_DIR/isos/archriot-2025.iso"
        cp -f "$iso_file" "$final_iso"

        # Show ISO size
        local iso_size=$(du -h "$final_iso" | cut -f1)
        log_info "ISO size: $iso_size"

        # Generate SHA256 checksum
        (cd "$WORK_DIR/isos" && sha256sum "archriot-2025.iso" > "archriot-2025.sha256")
        log_info "SHA256 checksum created: isos/archriot-2025.sha256"

        # Create symlink for easy access
        ln -sf "$final_iso" "$WORK_DIR/archriot-latest.iso"
        log_info "Symlink created: archriot-latest.iso"
    else
        log_error "CRITICAL: ISO file not found in output directory after successful mkarchiso"
        exit 1
    fi
}

# Test ISO build
test_iso() {
    log_info "Testing ISO build..."

    # Find ISO file
    local iso_file=$(find "$OUTPUT_DIR" -name "*.iso" | head -1)

    if [[ -z "$iso_file" ]]; then
        log_error "No ISO file found"
        exit 1
    fi

    # Check ISO file size (should be reasonable)
    local iso_size_bytes=$(stat -c%s "$iso_file")
    local iso_size_mb=$((iso_size_bytes / 1024 / 1024))

    log_info "ISO size: ${iso_size_mb}MB"

    if [[ $iso_size_mb -lt 100 ]]; then
        log_error "CRITICAL: ISO file too small (${iso_size_mb}MB), build failed"
        exit 1
    fi

    if [[ $iso_size_mb -gt 5000 ]]; then
        log_warning "ISO file very large (${iso_size_mb}MB), consider optimization"
    fi

    # Test ISO file integrity
    if command -v file >/dev/null 2>&1; then
        if ! file "$iso_file" | grep -q "ISO 9660"; then
            log_error "CRITICAL: File does not appear to be a valid ISO"
            exit 1
        fi
    fi

    # Test symlink was created
    if [[ ! -L "$WORK_DIR/archriot-latest.iso" ]]; then
        log_error "CRITICAL: Symlink not created"
        exit 1
    fi

    if [[ ! -f "$WORK_DIR/archriot-latest.iso" ]]; then
        log_error "CRITICAL: Symlink is broken"
        exit 1
    fi

    log_success "ISO build test passed"
}

# Unmount any previous airootfs mounts to allow clean removal
unmount_airootfs_mounts() {
    local mount_root="$OUTPUT_DIR/work/x86_64/airootfs"
    if [[ ! -d "$mount_root" ]]; then
        return 0
    fi

    # Absolute safety check - never unmount anything outside our build tree
    if [[ ! "$mount_root" =~ ArchISO.*out/work/x86_64/airootfs$ ]]; then
        log_error "SAFETY: Refusing to unmount suspicious path: $mount_root"
        log_error "Expected path pattern: */ArchISO/*/out/work/x86_64/airootfs"
        return 1
    fi

    log_info "Unmounting any airootfs bind mounts under: $mount_root"

    # Only unmount paths that are actually subdirectories of our target mount root
    # This ensures we never touch anything outside the build environment
    local known_relative_paths=(proc sys dev dev/pts dev/shm run var/run tmp var/tmp)
    local to_unmount=()

    # Check each known relative path for active mounts within our scope
    for rel_path in "${known_relative_paths[@]}"; do
        local full_path="$mount_root/$rel_path"
        if [[ -e "$full_path" ]]; then
            # Confirm it's a mount point before attempting to unmount
            if command -v findmnt >/dev/null 2>&1; then
                if findmnt -n "$full_path" >/dev/null 2>&1; then
                    to_unmount+=("$full_path")
                fi
            else
                # Fallback using /proc/self/mounts
                if awk '{print $2}' /proc/self/mounts | grep -Fxq "$full_path"; then
                    to_unmount+=("$full_path")
                fi
            fi
        fi
    done

    # Also scan for any additional unexpected mounts inside the tree
    if command -v findmnt >/dev/null 2>&1; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && to_unmount+=("$line")
        done < <(findmnt -R -n -o TARGET --target "$mount_root" | grep "^$mount_root" | grep -vFf <(printf '%s\n' "${to_unmount[@]}"))
    else
        while IFS= read -r line; do
            [[ -n "$line" ]] && to_unmount+=("$line")
        done < <(awk '{print $2}' /proc/self/mounts | grep "^$mount_root/" | grep -vFf <(printf '%s\n' "${to_unmount[@]}"))
    fi

    # Sort descending by path depth so deeper mounts get unmounted first
    if [[ ${#to_unmount[@]} -gt 0 ]]; then
        mapfile -t to_unmount < <(printf '%s\n' "${to_unmount[@]}" | awk '{print gsub(/\//,"/"), $0}' | sort -k1,1nr | cut -d' ' -f2-)

        # Perform the unmounts
        for mp in "${to_unmount[@]}"; do
            # Extra safety: confirm path is still within intended scope
            if [[ "$mp" == "$mount_root"/* ]]; then
                log_info "Unmounting: $mp"
                sudo umount -f "$mp" 2>/dev/null || sudo umount -l "$mp" 2>/dev/null || log_warning "Failed to unmount $mp"
            else
                log_warning "Skipping unsafe unmount target: $mp"
            fi
        done
    fi

    # Final verification pass only within our build scope
    local remaining_count=0
    if command -v findmnt >/dev/null 2>&1; then
        remaining_count=$(findmnt -R -n -o TARGET --target "$mount_root" | grep "^$mount_root" | wc -l || echo 0)
    else
        remaining_count=$(awk '{print $2}' /proc/self/mounts | grep "^$mount_root/" | wc -l || echo 0)
    fi

    if [[ $remaining_count -gt 0 ]]; then
        log_warning "There are $remaining_count mount points left under $mount_root which could not be safely unmounted."
    fi
}

# Cleanup function
cleanup() {
    log_info "Cleaning up temporary files..."

    # Unmount and remove work directory if it exists
    if [[ -d "$OUTPUT_DIR/work/x86_64/airootfs" ]]; then
        unmount_airootfs_mounts
    fi
    if [[ -d "$OUTPUT_DIR/work" ]]; then
        sudo rm -rf "$OUTPUT_DIR/work"
    fi

    log_success "Cleanup completed"
}

# EXIT trap handler to ensure cleanup runs exactly once and exit code is preserved
on_exit() {
    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        log_success "Build finished successfully"
    else
        log_error "Build failed with exit code $exit_code"
    fi
    cleanup
    exit "$exit_code"
}

# Main execution
main() {
    log_info "ArchRiot ISO Builder - Starting build process"

    # Check prerequisites
    check_root

    # Verify archiso is installed
    if ! command -v mkarchiso &> /dev/null; then
        log_error "mkarchiso command not found. Please install archiso package."
        exit 1
    fi

    # Execute build phases with testing
    prepare_workspace
    test_workspace

    download_packages
    test_packages

    create_repository
    test_repository

    customize_profile
    test_profile

    build_iso
    test_iso

    log_success "ArchRiot ISO build completed successfully!"
    log_info "ISO location: $WORK_DIR/isos/archriot-2025.iso"
    log_info "Checksum: $WORK_DIR/isos/archriot-2025.sha256"
    log_info "Quick access: $WORK_DIR/archriot-latest.iso"
}

# Handle script interruption
trap 'log_error "Script interrupted"; exit 130' INT TERM

# Ensure cleanup runs on any exit and preserve exit code
trap 'on_exit' EXIT

# Run main function
main "$@"
