#!/bin/bash
#
# Fujitsu ScanSnap S1100 scan-button script for scanbd
# Triggered when the scanner's physical button is pressed.
# Supports multi-page scanning: each press adds a page to the current PDF
# until the user closes the PDF viewer.
#
# When invoked by scanbd, runs as the scanbd user (no sudo needed).
# Use id -un for reliable user detection in service context (logname can return root).
#

# Effective user: when run by scanbd we're already the right user; when run via sudo, use SUDO_USER
USER_NAME="${SUDO_USER:-$(id -un)}"

# Paths relative to the user's home
SCANS_DIR="/home/$USER_NAME/Documents/scans"
SESSION_FILE="/home/$USER_NAME/.scan-session"
VIEWER="evince"

# Required for GUI apps and notifications when run from scanbd/systemd
export DISPLAY=:0
export XAUTHORITY="/home/$USER_NAME/.Xauthority"
# D-Bus session address needed for notify-send when run from service (no session bus by default)
USER_ID=$(id -u "$USER_NAME" 2>/dev/null || id -u)
[ -S "/run/user/$USER_ID/bus" ] && export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus"

# Run command as USER_NAME - no sudo when we're already that user (avoids password prompt from scanbd)
run_as_user() {
  if [ "$(id -un)" = "$USER_NAME" ]; then
    "$@"
  else
    sudo -u "$USER_NAME" "$@"
  fi
}

# Detect scanner dynamically - USB device number can change when unplugged/replugged
SCAN_DEVICE=$(scanimage -L 2>/dev/null | grep -oE 'epjitsu:libusb:[0-9]+:[0-9]+' | head -1)
if [ -z "$SCAN_DEVICE" ]; then
  echo "Scanner not found" >&2
  run_as_user notify-send -u critical "Scan Error" "Scanner not found. Check that the Fujitsu S1100 is connected and powered on." 2>/dev/null || true
  exit 1
fi

mkdir -p "$SCANS_DIR"
SESSION_DIR=""
TIMESTAMP=""

# Load session state if continuing a multi-page scan
[ -f "$SESSION_FILE" ] && read -r SESSION_DIR TIMESTAMP < "$SESSION_FILE"

if [ -n "$SESSION_DIR" ] && [ -d "$SESSION_DIR" ] && [ -n "$TIMESTAMP" ]; then
  # Existing session: add another page to the current document
  PAGE_NUM=$(ls "$SESSION_DIR"/page-*.png 2>/dev/null | wc -l)
  PAGE_NUM=$((PAGE_NUM + 1))

  run_as_user scanimage --device "$SCAN_DEVICE" \
    --brightness=30 --contrast=10 \
    --format=png \
    -o "$SESSION_DIR/page-$PAGE_NUM.png"

  # Verify image is valid (scanimage may create corrupt file when feeder is empty)
  if [ -f "$SESSION_DIR/page-$PAGE_NUM.png" ] && identify "$SESSION_DIR/page-$PAGE_NUM.png" >/dev/null 2>&1; then
    PDF_PATH="$SCANS_DIR/scan_${TIMESTAMP}.pdf"
    if convert "$SESSION_DIR"/page-*.png "$PDF_PATH" 2>/dev/null; then
      : # PDF updated successfully
    else
      run_as_user notify-send -u critical "Scan Error" "Page not loaded. Place a document in the scanner and try again." 2>/dev/null || true
    fi
  else
    rm -f "$SESSION_DIR/page-$PAGE_NUM.png" 2>/dev/null
    run_as_user notify-send -u critical "Scan Error" "Page not loaded. Place a document in the scanner and try again." 2>/dev/null || true
  fi
else
  # New session: first page of a new document
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  SESSION_DIR="$SCANS_DIR/scan_${TIMESTAMP}"
  mkdir -p "$SESSION_DIR"
  echo "$SESSION_DIR" "$TIMESTAMP" > "$SESSION_FILE"

  run_as_user scanimage --device "$SCAN_DEVICE" \
    --brightness=30 --contrast=10 \
    --format=png \
    -o "$SESSION_DIR/page-1.png"

  # Verify image is valid before creating PDF (scanimage creates corrupt file when feeder is empty)
  if [ -f "$SESSION_DIR/page-1.png" ] && identify "$SESSION_DIR/page-1.png" >/dev/null 2>&1; then
    PDF_PATH="$SCANS_DIR/scan_${TIMESTAMP}.pdf"
    if convert "$SESSION_DIR/page-1.png" "$PDF_PATH" 2>/dev/null && [ -f "$PDF_PATH" ]; then
      # Open PDF viewer; when user closes it, clear session so next press starts fresh
      (
        run_as_user $VIEWER "$PDF_PATH"
        rm -f "$SESSION_FILE"
      ) &
    else
      rm -f "$SESSION_FILE"
      run_as_user notify-send -u critical "Scan Error" "Page not loaded. Place a document in the scanner and try again." 2>/dev/null || true
    fi
  else
    rm -f "$SESSION_FILE" "$SESSION_DIR/page-1.png"
    rmdir "$SESSION_DIR" 2>/dev/null || true
    run_as_user notify-send -u critical "Scan Error" "Page not loaded. Place a document in the scanner and try again." 2>/dev/null || true
  fi
fi
