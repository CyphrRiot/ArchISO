#!/bin/bash

# ArchRiot First Boot Setup Reminder
# This script runs once on first user login to remind about ArchRiot setup

# Check if this is the first boot by looking for our marker file
MARKER_FILE="$HOME/.archriot-setup-complete"

if [[ ! -f "$MARKER_FILE" ]]; then
    # Clear screen and show welcome message
    clear

    echo
    echo "Welcome to ArchRiot!"
    echo "=========================="
    echo
    echo "Your base Arch Linux system is ready, but you need to complete"
    echo "the ArchRiot setup to get the full desktop environment."
    echo
    echo "To finish setting up ArchRiot, run this command:"
    echo
    echo "  curl -fsSL https://ArchRiot.org/setup.sh | bash"
    echo
    echo "This will install:"
    echo "  - Hyprland desktop environment"
    echo "  - ArchRiot configurations and themes"
    echo "  - Essential applications"
    echo
    echo "After setup completes, you'll have the full ArchRiot experience!"
    echo
    echo -n "Press Enter to continue..."
    read

    # Create marker file to prevent showing this again
    touch "$MARKER_FILE"

    echo
    echo "Run the setup command above when you're ready!"
    echo
fi
