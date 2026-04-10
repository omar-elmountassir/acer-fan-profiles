#!/bin/bash
# Uninstall acer-fan-profiles
# Run with: sudo ./uninstall.sh

set -euo pipefail

echo "=== acer-fan-profiles uninstaller ==="
echo ""

if [[ $EUID -ne 0 ]]; then
    echo "Error: Run with sudo: sudo ./uninstall.sh"
    exit 1
fi

echo "1. Stopping and disabling service"
systemctl stop acer-fan-profiles.service 2>/dev/null || true
systemctl disable acer-fan-profiles.service 2>/dev/null || true

echo "2. Removing service file"
rm -f /etc/systemd/system/acer-fan-profiles.service
systemctl daemon-reload

echo "3. Removing binaries"
rm -f /usr/local/bin/acer-fan-profiles
rm -f /usr/local/bin/afp

echo "4. Removing runtime directory"
rm -rf /run/acer-fan-profiles

echo ""
echo "=== Uninstalled ==="
echo ""
echo "Note: Config preserved at ~/.config/acer-fan-profiles/"
echo "Note: acer_wmi.predator_v4=1 kernel parameter NOT removed."
echo "      Remove it with: sudo kernelstub -d 'acer_wmi.predator_v4=1'"
