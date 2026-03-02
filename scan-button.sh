#!/bin/bash
USER_NAME="pasadena"
SCANS_DIR="/home/$USER_NAME/Documents/scans"
SESSION_FILE="/home/$USER_NAME/.scan-session"
VIEWER="evince"

export DISPLAY=:0
export XAUTHORITY=/home/$USER_NAME/.Xauthority

# Detect scanner dynamically (USB device number can change when unplugged)
SCAN_DEVICE=$(scanimage -L 2>/dev/null | grep -oE 'epjitsu:libusb:[0-9]+:[0-9]+' | head -1)
if [ -z "$SCAN_DEVICE" ]; then
  echo "Scanner not found" >&2
  exit 1
fi

mkdir -p "$SCANS_DIR"
SESSION_DIR=""
TIMESTAMP=""

[ -f "$SESSION_FILE" ] && read -r SESSION_DIR TIMESTAMP < "$SESSION_FILE"

if [ -n "$SESSION_DIR" ] && [ -d "$SESSION_DIR" ] && [ -n "$TIMESTAMP" ]; then
  # Existing session — add another page
  PAGE_NUM=$(ls "$SESSION_DIR"/page-*.png 2>/dev/null | wc -l)
  PAGE_NUM=$((PAGE_NUM + 1))

  sudo -u $USER_NAME scanimage --device "$SCAN_DEVICE" \
    --brightness=30 --contrast=10 \
    --format=png \
    -o "$SESSION_DIR/page-$PAGE_NUM.png"

  if [ -f "$SESSION_DIR/page-$PAGE_NUM.png" ]; then
    PDF_PATH="$SCANS_DIR/scan_${TIMESTAMP}.pdf"
    convert "$SESSION_DIR"/page-*.png "$PDF_PATH"
  fi
else
  # New session — first page
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  SESSION_DIR="$SCANS_DIR/scan_${TIMESTAMP}"
  mkdir -p "$SESSION_DIR"
  echo "$SESSION_DIR" "$TIMESTAMP" > "$SESSION_FILE"

  sudo -u $USER_NAME scanimage --device "$SCAN_DEVICE" \
    --brightness=30 --contrast=10 \
    --format=png \
    -o "$SESSION_DIR/page-1.png"

  if [ -f "$SESSION_DIR/page-1.png" ]; then
    PDF_PATH="$SCANS_DIR/scan_${TIMESTAMP}.pdf"
    convert "$SESSION_DIR/page-1.png" "$PDF_PATH"
    (
      sudo -u $USER_NAME $VIEWER "$PDF_PATH"
      rm -f "$SESSION_FILE"
    ) &
  else
    rm -f "$SESSION_FILE"
  fi
fi