#!/bin/bash

echo "# ArchRiot Packages - Extracted from install scripts"
echo "# Core packages"

# Extract packages from all ArchRiot install scripts
find ../ArchRiot/install -name "*.sh" | while read file; do
    echo "# From $file"
    # Extract lines with yay -S or pacman -S and the packages after them
    awk '
    /yay -S --noconfirm --needed|pacman -S --noconfirm --needed/ {
        found=1
        next
    }
    found && /^[[:space:]]*[a-zA-Z0-9._+-]+[[:space:]]*\\?[[:space:]]*$/ {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        gsub(/\\[[:space:]]*$/, "")
        if ($0 != "" && $0 !~ /^[[:space:]]*$/) {
            print $0
        }
        if (!/\\[[:space:]]*$/) found=0
        next
    }
    found && /^[[:space:]]*$/ {
        found=0
    }
    ' "$file"
done | sort -u | grep -v "^#"
