#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="archriot"
iso_label="ARCHRIOT_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="ArchRiot Project <https://archriot.org>"
iso_application="ArchRiot Installer ISO"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito'
           'uefi-ia32.systemd-boot.esp' 'uefi-x64.systemd-boot.esp'
           'uefi-ia32.systemd-boot.eltorito' 'uefi-x64.systemd-boot.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '100%' '-processors' '4' '-wildcards' '-e' 'proc/*' '-e' 'sys/*' '-e' 'dev/*' '-e' 'run/*' '-e' 'tmp/*' '-e' 'var/run/*' '-e' 'var/tmp/*' '-e' 'var/cache/*' '-e' 'usr/share/man/*' '-e' 'usr/share/doc/*' '-e' 'usr/share/info/*')
bootstrap_tarball_compression=('zstd' '-c' '-T4' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/usr/local/bin/riot"]="0:0:755"
)
