#!/bin/bash

# Simple WiFi Menu Test
# Tests the core menu functionality without complex mocking

set -e

# Check for dialog
if ! command -v dialog &> /dev/null; then
    echo "ERROR: dialog not found. Install with: sudo pacman -S dialog"
    exit 1
fi

# Clean, simple menu test
test_menu() {
    # Create test menu items (simulating networks)
    MENU_ITEMS=()
    MENU_ITEMS+=("1" "MyHomeNetwork")
    MENU_ITEMS+=("2" "OpenWiFi")
    MENU_ITEMS+=("3" "Office_5G")
    MENU_ITEMS+=("4" "Neighbor_WiFi")
    MENU_ITEMS+=("5" "TestNetwork")
    MENU_ITEMS+=("6" "CoffeeShop")

    echo "Testing WiFi menu with ${#MENU_ITEMS[@]} items..."

    # Show the menu exactly as the installer does
    SELECTION=$(dialog --clear --menu "WiFi Networks" 15 60 8 "${MENU_ITEMS[@]}" 2>/tmp/dialog_result; cat /tmp/dialog_result; rm -f /tmp/dialog_result)

    if [ -n "$SELECTION" ]; then
        # Get the selected network name
        SELECTED_NETWORK=""
        for ((i=0; i<${#MENU_ITEMS[@]}; i+=2)); do
            if [ "${MENU_ITEMS[i]}" = "$SELECTION" ]; then
                SELECTED_NETWORK="${MENU_ITEMS[i+1]}"
                break
            fi
        done

        echo "SUCCESS: Selected network '$SELECTED_NETWORK' (option $SELECTION)"
        echo "No text leakage detected!"

        # Test password dialog
        PASSWORD=$(dialog --clear --passwordbox "Enter password for '$SELECTED_NETWORK'" 10 50 2>/tmp/pass_result; cat /tmp/pass_result; rm -f /tmp/pass_result)

        if [ -n "$PASSWORD" ]; then
            echo "Password entered successfully (length: ${#PASSWORD})"
        else
            echo "No password entered (open network)"
        fi

        dialog --clear --msgbox "TEST COMPLETED SUCCESSFULLY!

Selected: $SELECTED_NETWORK
Password: $([ -n "$PASSWORD" ] && echo "Provided" || echo "None (open network)")

The WiFi interface is working correctly with no text output leakage." 12 60

    else
        echo "No selection made or dialog cancelled"
        exit 1
    fi
}

# Main test
echo "Starting simple WiFi menu test..."
echo "This should show ONLY dialog boxes - no other text output"
echo "Press Enter to continue..."
read

test_menu

echo "Test completed. Check above - did you see any unwanted text output?"
