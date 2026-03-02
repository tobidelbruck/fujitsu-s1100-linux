#!/bin/bash
#
# Installation script for Fujitsu ScanSnap S1100 button scanning on Linux
# Sets up scanbd, dependencies, and the scan-button script.
#
# Usage:
#   sudo ./install.sh        - Install
#   sudo ./install.sh --remove  - Uninstall (revert all changes)
#

set -e

# Ensure we run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Use: sudo $0"
  exit 1
fi

# Detect the user who invoked sudo (the one who will use the scanner)
INSTALL_USER="${SUDO_USER:-$LOGNAME}"
if [ -z "$INSTALL_USER" ]; then
  INSTALL_USER=$(logname 2>/dev/null || true)
fi
if [ -z "$INSTALL_USER" ]; then
  echo "Could not determine install user. Run with: sudo -u YOUR_USER $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Uninstall (--remove, -r) ---
if [ "$1" = "--remove" ] || [ "$1" = "-r" ]; then
  echo "=============================================="
  echo "Fujitsu S1100 Linux - Uninstall"
  echo "=============================================="
  echo "This will remove scanbd, the scan-button script, firmware, and revert permissions."
  echo "User data in ~/Documents/scans will NOT be deleted."
  echo ""
  read -p "Continue with uninstall? [y/N] " -r
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
  fi

  echo ""
  echo "[1/5] Stopping scanbd..."
  systemctl stop scanbd 2>/dev/null || true

  echo ""
  echo "[2/5] Removing scanbd package..."
  apt-get remove --purge --yes scanbd 2>/dev/null || true

  echo ""
  echo "[3/5] Removing scan-button script..."
  rm -f /usr/local/bin/scan-button.sh
  echo "  Removed."

  echo ""
  echo "[4/5] Removing S1100 firmware..."
  rm -f /usr/share/sane/epjitsu/1100_0B00.nal
  echo "  Removed (if it was installed by this script)."

  echo ""
  echo "[5/5] Removing user from scanner group..."
  if getent group scanner >/dev/null && groups "$INSTALL_USER" | grep -q scanner; then
    gpasswd -d "$INSTALL_USER" scanner 2>/dev/null || true
    echo "  Removed $INSTALL_USER from scanner group."
  else
    echo "  (User was not in scanner group or group does not exist.)"
  fi

  systemctl daemon-reload 2>/dev/null || true
  echo ""
  echo "Uninstall complete."
  exit 0
fi

# --- Install ---
echo "=============================================="
echo "Fujitsu S1100 Linux - Installation"
echo "=============================================="
echo "Install user: $INSTALL_USER"
echo "Scans will be saved to: /home/$INSTALL_USER/Documents/scans"
echo "Script source: $SCRIPT_DIR"
echo ""
echo "Use: $0 --remove to uninstall"
echo ""
read -p "Continue with installation? [y/N] " -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Installation cancelled."
  exit 0
fi

# Step 1: Install dependencies
echo ""
echo "[1/7] Installing dependencies..."
apt-get update
apt-get install -y scanbd sane-utils imagemagick evince wget libnotify-bin

# Step 2: Install S1100 firmware
echo ""
echo "[2/7] Installing scanner firmware..."
FIRMWARE_DIR="/usr/share/sane/epjitsu"
FIRMWARE_FILE="1100_0B00.nal"
mkdir -p "$FIRMWARE_DIR"

if [ -f "$FIRMWARE_DIR/$FIRMWARE_FILE" ]; then
  echo "  Firmware already installed."
else
  # Build raw GitHub URL: get remote from ~/scansnap-firmware if present, else use default
  FIRMWARE_REPO="stevleibelt/scansnap-firmware"
  FIRMWARE_SOURCE="/home/$INSTALL_USER/scansnap-firmware"
  if [ -d "$FIRMWARE_SOURCE/.git" ]; then
    REMOTE_URL=$(git -C "$FIRMWARE_SOURCE" config --get remote.origin.url 2>/dev/null || true)
    if [ -n "$REMOTE_URL" ]; then
      # Parse owner/repo from https://github.com/owner/repo.git or git@github.com:owner/repo.git
      if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
        FIRMWARE_REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
      fi
    fi
  fi
  FIRMWARE_RAW_URL="https://raw.githubusercontent.com/${FIRMWARE_REPO}/master/${FIRMWARE_FILE}"
  if wget -q -O "$FIRMWARE_DIR/$FIRMWARE_FILE" "$FIRMWARE_RAW_URL"; then
    chmod 644 "$FIRMWARE_DIR/$FIRMWARE_FILE"
    echo "  Installed firmware from $FIRMWARE_RAW_URL"
  else
    echo "  Warning: Could not download firmware. URL: $FIRMWARE_RAW_URL"
  fi
fi

# Step 3: Add user to scanner group for device access
echo ""
echo "[3/7] Setting user and group permissions..."
if getent group scanner >/dev/null; then
  usermod -aG scanner "$INSTALL_USER"
  echo "  Added $INSTALL_USER to scanner group."
else
  echo "  Warning: 'scanner' group not found. Adding to 'lp' group instead."
  usermod -aG lp "$INSTALL_USER" 2>/dev/null || true
fi

# Pre-create scans directory with correct ownership
SCANS_DIR="/home/$INSTALL_USER/Documents/scans"
mkdir -p "$SCANS_DIR"
chown "$INSTALL_USER:$INSTALL_USER" "$SCANS_DIR"
echo "  Created $SCANS_DIR with ownership $INSTALL_USER:$INSTALL_USER"

# Step 4: Fix scanbd fujitsu.conf - it uses SANE syntax that scanbd doesn't understand
echo ""
echo "[4/7] Fixing scanbd configuration..."
if [ -f /etc/scanbd/scanbd.conf ]; then
  if grep -q '^include(scanner.d/fujitsu.conf)' /etc/scanbd/scanbd.conf; then
    sed -i 's|^include(scanner.d/fujitsu.conf)|# include(scanner.d/fujitsu.conf)|' /etc/scanbd/scanbd.conf
    echo "  Commented out fujitsu.conf include (S1100 uses epjitsu backend)."
  fi
  # Ensure scanbd runs as the install user
  sed -i "s/\(user[[:space:]]*=[[:space:]]*\)[^[:space:]]*/\1$INSTALL_USER/" /etc/scanbd/scanbd.conf
  # Use scanner group if it exists, otherwise lp (for USB device access)
  SCANBD_GROUP="scanner"
  getent group scanner >/dev/null || SCANBD_GROUP="lp"
  sed -i "s/\(group[[:space:]]*=[[:space:]]*\)[^[:space:]]*/\1$SCANBD_GROUP/" /etc/scanbd/scanbd.conf
  echo "  Set scanbd user=$INSTALL_USER, group=$SCANBD_GROUP."
  # Set scan action to use our script (default is test.script which may not exist)
  sed -i '/^[[:space:]]*action scan {/,/^[[:space:]]*action /{
    s|script = "test\.script"|script = "/usr/local/bin/scan-button.sh"|
  }' /etc/scanbd/scanbd.conf
  echo "  Set scan action script to /usr/local/bin/scan-button.sh"
fi

# Step 4: Fix D-Bus policy so scanbd can register its service
echo ""
echo "[5/7] Updating D-Bus policy..."
if [ -f /etc/dbus-1/system.d/scanbd_dbus.conf ]; then
  sed -i "s/<policy user=\"[^\"]*\">/<policy user=\"$INSTALL_USER\">/" /etc/dbus-1/system.d/scanbd_dbus.conf
  echo "  Set D-Bus policy user to $INSTALL_USER."
fi

# Step 6: Install scan-button script
echo ""
echo "[6/7] Installing scan-button.sh to /usr/local/bin..."
cp "$SCRIPT_DIR/scan-button.sh" /usr/local/bin/scan-button.sh
chmod 755 /usr/local/bin/scan-button.sh
echo "  Installed."

# Step 7: Restart services
echo ""
echo "[7/7] Restarting scanbd..."
systemctl daemon-reload
systemctl reload dbus 2>/dev/null || true
systemctl restart scanbd

echo ""
echo "=============================================="
echo "Installation complete."
echo "=============================================="
echo ""
echo "To test:"
echo "  1. Log out and back in (or reboot) so group membership takes effect."
echo "  2. Ensure the scanner is connected and powered on."
echo "  3. Monitor scanbd: sudo journalctl -u scanbd -f"
echo "  4. Press the scan button on the scanner."
echo "  5. You should see 'trigger action for scan' in the journal."
echo "  6. A PDF should open; add more pages by pressing the button again."
echo "  7. Close the PDF viewer when done to start a new document next time."
echo ""
