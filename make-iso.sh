#!/usr/bin/env bash
#
# ArchRiot ISO Builder - Simple Offline Installer (iwd/iwctl, no NetworkManager)
# - Uses repo's archriot-profile/ as the live ISO base (version-controlled)
# - Builds a proper offline repository from configs/packages.txt at /opt/archriot-cache
# - Ensures iwd/iwctl are available in live environment; removes NetworkManager if present
# - No separate Wi-Fi helper (riot handles Wi‑Fi)
#
set -Eeuo pipefail

# -----------------------------
# Paths
# -----------------------------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$ROOT/.work"
OUT="$ROOT/out"
PROFILE="$WORK/releng"
PROFILE_SRC="$ROOT/archriot-profile"
PKG_LIST="$ROOT/configs/packages.txt"

# Caches & logs
BUILD_CACHE="$ROOT/.buildcache"
PERSIST_CACHE="$ROOT/pkgcache"
TMP_DB="$ROOT/.offlinedb"
TMP_PAC="$ROOT/tmp-pacman.conf"
ISO_REPO_DIR="$PROFILE/airootfs/opt/archriot-cache"

LOG_DIR="$ROOT/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/make-iso-$(date +%Y%m%d-%H%M%S).log"

log() { echo -e "$@" | tee -a "$LOG_FILE"; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || { log "ERROR: Missing required command: $1"; exit 1; }; }

# -----------------------------
# Preflight checks
# -----------------------------
need_cmd mkarchiso
need_cmd repo-add
need_cmd pacman
need_cmd sed
need_cmd awk
need_cmd find
need_cmd sha256sum

log "=== ArchRiot: Simple Offline ISO Builder (iwd/iwctl) ==="
log "Log file: $LOG_FILE"

[[ -d "$PROFILE_SRC" ]] || { log "ERROR: Missing profile: $PROFILE_SRC"; exit 1; }
[[ -f "$PKG_LIST"    ]] || { log "ERROR: Missing package list: $PKG_LIST"; exit 1; }

# -----------------------------
# 1) Prepare workspace
# -----------------------------
log "1) Preparing workspace..."
# Attempt to clean any previous build dirs; preserve persistent cache
sudo rm -rf "$WORK" "$OUT" 2>/dev/null || true
mkdir -p "$WORK" "$OUT" "$PERSIST_CACHE"

# -----------------------------
# 2) Copy versioned profile
# -----------------------------
log "2) Copying archriot profile..."
cp -a "$PROFILE_SRC" "$PROFILE"

# -----------------------------
# 3) Adjust live packages: ensure iwd/iwctl; remove NetworkManager if present
# -----------------------------
RELENG_PKGS="$PROFILE/packages.x86_64"
log "3) Adjusting live packages (ensure iwd/iwctl; remove NetworkManager if present)..."
# Remove NetworkManager (if present) and a few VM bits; keep trims minimal (prefer long-term edits in profile itself)
sed -i -E '/^(networkmanager|qemu-guest-agent|virtualbox-guest-utils-nox|hyperv|open-vm-tools|clonezilla|drbl)$/d' "$RELENG_PKGS" || true

ensure_in_list() { local p="$1"; grep -qxF "$p" "$RELENG_PKGS" || echo "$p" >> "$RELENG_PKGS"; }
ensure_in_list "iwd"
ensure_in_list "iw"
ensure_in_list "arch-install-scripts"
ensure_in_list "git"
ensure_in_list "curl"
ensure_in_list "nano"
ensure_in_list "jq"
ensure_in_list "ripgrep"
ensure_in_list "libnewt"

# -----------------------------
# 4) Build offline repository from configs/packages.txt
# -----------------------------
log "4) Creating offline repository from $PKG_LIST ..."
# Read packages (strip comments/blank)
mapfile -t INSTALL_PKGS < <(grep -Ev '^\s*#' "$PKG_LIST" | awk 'NF{print $1}')
log "   Found ${#INSTALL_PKGS[@]} packages for offline cache"

# Temporary pacman config/db to avoid polluting host DB
sudo rm -rf "$TMP_DB" "$TMP_PAC" "$BUILD_CACHE"
mkdir -p "$TMP_DB" "$BUILD_CACHE"
cp /etc/pacman.conf "$TMP_PAC" 2>/dev/null || true
# Force root download user (if key exists)
sed -i 's/^#\?DownloadUser.*/DownloadUser = root/' "$TMP_PAC" 2>/dev/null || true

log "   Downloading packages to caches (build + persistent)..."
sudo pacman --config "$TMP_PAC" -Syw --noconfirm \
  --cachedir "$BUILD_CACHE" \
  --cachedir "$PERSIST_CACHE" \
  --dbpath "$TMP_DB" \
  "${INSTALL_PKGS[@]}" >>"$LOG_FILE" 2>&1

log "   Assembling ISO offline repo at $ISO_REPO_DIR ..."
rm -rf "$ISO_REPO_DIR" && mkdir -p "$ISO_REPO_DIR"
# Pre-copy from build cache
cp -n "$BUILD_CACHE"/*.pkg.tar.zst "$ISO_REPO_DIR"/ 2>/dev/null || true
cp -n "$BUILD_CACHE"/*.pkg.tar.xz "$ISO_REPO_DIR"/ 2>/dev/null || true
find "$ISO_REPO_DIR" -type f -name '*.sig' -delete
# Ensure all deps are present by copying exact basenames from caches based on URL list
while IFS= read -r url; do
  b="$(basename "$url")"
  [[ -f "$ISO_REPO_DIR/$b" ]] && continue
  if   [[ -f "$BUILD_CACHE/$b" ]];   then cp -n "$BUILD_CACHE/$b"   "$ISO_REPO_DIR/";
  elif [[ -f "$PERSIST_CACHE/$b" ]]; then cp -n "$PERSIST_CACHE/$b" "$ISO_REPO_DIR/"; fi
done < <(sudo pacman --config "$TMP_PAC" -Sp --noconfirm --dbpath "$TMP_DB" "${INSTALL_PKGS[@]}" 2>/dev/null)

( shopt -s nullglob; cd "$ISO_REPO_DIR" && repo-add archriot-cache.db.tar.gz ./*.pkg.tar.zst ./*.pkg.tar.xz ) >>"$LOG_FILE" 2>&1
sudo chown -R "$USER:$USER" "$ISO_REPO_DIR" 2>/dev/null || true

# -----------------------------
# 5) Customize live environment: pacman.conf and motd (no Wi-Fi helper)
# -----------------------------
log "5) Customizing live environment (offline pacman + motd)..."
mkdir -p "$PROFILE/airootfs/etc" "$PROFILE/airootfs/usr/local/bin"

# Pacman config inside ISO to prefer file:// offline repo
cat > "$PROFILE/airootfs/etc/pacman.conf" <<'PAC'
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
PAC

# MOTD (keep it minimal; riot is the entry point)
cat > "$PROFILE/airootfs/etc/motd" <<'MOTD'

=====================================
      Welcome to ArchRiot ISO
=====================================
- To install ArchRiot: riot
- To reboot: reboot
- To power off: poweroff

This ISO contains an offline repository at:
  /opt/archriot-cache
MOTD

# Riot installer is now part of the versioned profile (archriot-profile/airootfs/usr/local/bin/riot)
# No overlay needed - profile is the single source of truth

# -----------------------------
# 6) Build ISO
# -----------------------------
log "6) Building ISO with mkarchiso..."
set +e
sudo mkarchiso -v -w "$OUT/work" -o "$OUT" "$PROFILE" 2>&1 | tee -a "$LOG_FILE"
MK_RES=${PIPESTATUS[0]}
set -e
if [[ $MK_RES -ne 0 ]]; then
  log "ERROR: mkarchiso failed (exit $MK_RES)"
  exit $MK_RES
fi

# -----------------------------
# 7) Finalize output
# -----------------------------
ISO_PATH="$(find "$OUT" -maxdepth 1 -type f -name '*.iso' | head -n1 || true)"
if [[ -z "${ISO_PATH:-}" ]]; then
  log "ERROR: No ISO found in $OUT"
  exit 1
fi
FINAL_DIR="$ROOT/isos"
mkdir -p "$FINAL_DIR"
FINAL_ISO="$FINAL_DIR/archriot.iso"
cp -f "$ISO_PATH" "$FINAL_ISO"
( cd "$FINAL_DIR" && sha256sum "archriot.iso" > "archriot.sha256" )
sudo chown "$USER:$USER" "$FINAL_ISO" "$FINAL_DIR/archriot.sha256" 2>/dev/null || true

log ""
log "SUCCESS: ISO built"
log "Location: $FINAL_ISO"
log "SHA256:  $(cat "$FINAL_DIR/archriot.sha256")"
log "Boot and run: riot"
