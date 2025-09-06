# zsh login for ArchRiot live root
# Message-only login hook for tty1. Do NOT auto-run anything.

# Only show on interactive tty1
if [[ -t 1 && "$(tty)" = "/dev/tty1" ]]; then
    echo
    echo "Welcome to the ArchRiot live environment."
    echo
    echo "Type 'riot' to start the installer."
    echo "Type 'bash' or 'zsh' to use a shell."
    echo "Type 'reboot' or 'poweroff' to exit."
    echo
    echo "Installer logs (once running): /tmp/riot_debug.log"
    echo
fi
