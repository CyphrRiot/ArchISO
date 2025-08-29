#!/usr/bin/env bash

script_cmdline() {
    local param
    for param in $(</proc/cmdline); do
        case "${param}" in
            script=*)
                echo "${param#*=}"
                return 0
                ;;
        esac
    done
}

automated_script() {
    local script rt
    script="$(script_cmdline)"
    if [[ -n "${script}" && ! -x /tmp/startup_script ]]; then
        if [[ "${script}" =~ ^((http|https|ftp|tftp)://) ]]; then
            # there's no synchronization for network availability before executing this script
            printf '%s: waiting for network-online.target\n' "$0"
            until systemctl --quiet is-active network-online.target; do
                sleep 1
            done
            printf '%s: downloading %s\n' "$0" "${script}"
            curl "${script}" --location --retry-connrefused --retry 10 --fail -s -o /tmp/startup_script
            rt=$?
        else
            cp "${script}" /tmp/startup_script
            rt=$?
        fi
        if [[ ${rt} -eq 0 ]]; then
            chmod +x /tmp/startup_script
            printf '%s: executing automated script\n' "$0"
            # note that script is executed when other services (like pacman-init) may be still in progress, please
            # synchronize to "systemctl is-system-running --wait" when your script depends on other services
            /tmp/startup_script
        fi
    fi
}

if [[ $(tty) == "/dev/tty1" ]]; then
    # Single-run lock to avoid multiple launches
    mkdir -p /run/archriot
    if [[ -e /run/archriot/riot.lock ]]; then
        exit 0
    fi
    : > /run/archriot/riot.lock

    # Run any automated script from cmdline first
    automated_script

    # Wait briefly for the system to be ready (pacman-init, keyring, etc.)
    for i in {1..20}; do
        state="$(systemctl is-system-running 2>/dev/null || true)"
        if [[ "$state" == "running" || "$state" == "degraded" ]]; then
            break
        fi
        sleep 1
    done

    # Launch ArchRiot installer automatically on tty1
    echo "Starting ArchRiot installer..."
    sleep 1
    exec /usr/local/bin/riot
fi
