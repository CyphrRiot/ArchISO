# zsh login hook for ArchRiot live root
# Auto-start riot installer on tty1

if [[ $(tty) == "/dev/tty1" ]]; then
    # Single-run lock to avoid multiple launches
    mkdir -p /run/archriot
    if [[ -e /run/archriot/riot.lock ]]; then
        exit 0
    fi
    : > /run/archriot/riot.lock

    # Ensure /usr/local/bin is in PATH (where riot lives)
    if [[ -d /usr/local/bin ]] && [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
        export PATH="/usr/local/bin:$PATH"
    fi

    # Wait briefly for the system to be ready
    echo "Waiting for system to be ready..."
    for i in {1..5}; do
        state="$(systemctl is-system-running 2>/dev/null || true)"
        if [[ "$state" == "running" || "$state" == "degraded" ]]; then
            break
        fi
        sleep 1
    done

    # Launch ArchRiot installer
    echo "Starting ArchRiot installer..."
    sleep 1

    # Start riot directly
    /usr/local/bin/riot
fi
