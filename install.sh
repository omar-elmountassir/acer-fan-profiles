#!/bin/bash
# Install acer-fan-profiles daemon and CLI
# Run with: sudo ./install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_USER="${SUDO_USER:-$(whoami)}"
INSTALL_HOME=$(eval echo "~${INSTALL_USER}")

echo "=== acer-fan-profiles installer ==="
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
    echo "Error: Run with sudo: sudo ./install.sh"
    exit 1
fi

# Check prerequisites
if [[ ! -f /sys/firmware/acpi/platform_profile ]]; then
    echo "Error: platform_profile not found."
    echo "Ensure acer_wmi.predator_v4=1 kernel parameter is set."
    exit 1
fi

echo "1. Installing daemon to /usr/local/bin/acer-fan-profiles"
cp "${SCRIPT_DIR}/acer-fan-profiles" /usr/local/bin/acer-fan-profiles
chmod 755 /usr/local/bin/acer-fan-profiles

echo "2. Installing CLI to /usr/local/bin/afp"
cp "${SCRIPT_DIR}/afp" /usr/local/bin/afp
chmod 755 /usr/local/bin/afp

echo "3. Installing systemd service"
cp "${SCRIPT_DIR}/acer-fan-profiles.service" /etc/systemd/system/acer-fan-profiles.service

echo "4. Creating runtime directory"
mkdir -p /run/acer-fan-profiles
chmod 755 /run/acer-fan-profiles

echo "5. Installing default config"
sudo -u "$INSTALL_USER" mkdir -p "${INSTALL_HOME}/.config/acer-fan-profiles"
if [[ ! -f "${INSTALL_HOME}/.config/acer-fan-profiles/config.yaml" ]]; then
    sudo -u "$INSTALL_USER" cp "${SCRIPT_DIR}/config.yaml" "${INSTALL_HOME}/.config/acer-fan-profiles/config.yaml"
    echo "   Config written to ${INSTALL_HOME}/.config/acer-fan-profiles/config.yaml"
else
    echo "   Config already exists, skipping (not overwriting)"
fi

echo "6. Enabling and starting service"
systemctl daemon-reload
systemctl enable acer-fan-profiles.service
systemctl start acer-fan-profiles.service

echo ""
echo "=== Installation complete ==="
echo ""
echo "Commands:"
echo "  afp status      Show current state"
echo "  afp monitor     Live monitoring view"
echo "  afp set <prof>  Lock to a profile"
echo "  afp auto        Return to automatic mode"
echo "  afp profiles    List available profiles"
echo "  afp config edit Edit thresholds"
echo ""
systemctl status acer-fan-profiles.service --no-pager
