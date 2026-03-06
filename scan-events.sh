#!/bin/bash
#
# Fujitsu ScanSnap S1100 event notification script for scanbd
# Handles device insert/remove (scanner connected/disconnected) and
# paper load/unload events. Sends desktop notifications.
#

USER_NAME="${SUDO_USER:-$(id -un)}"
USER_ID=$(id -u "$USER_NAME" 2>/dev/null || id -u)

# Required for notify-send when run from scanbd/systemd
DISPLAY=$(who -u 2>/dev/null | awk -v u="$USER_NAME" '$1==u && $2~/^:[0-9]+$/ {print $2; exit}')
[ -z "$DISPLAY" ] && DISPLAY=:0
export DISPLAY
export XAUTHORITY="${XAUTHORITY:-/home/$USER_NAME/.Xauthority}"
[ -S "/run/user/$USER_ID/bus" ] && export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus"

run_as_user() {
  if [ "$(id -un)" = "$USER_NAME" ]; then
    "$@"
  else
    sudo -u "$USER_NAME" "$@"
  fi
}

notify_event() {
  local title="$1"
  local body="$2"
  run_as_user notify-send -u normal "$title" "$body" 2>/dev/null || true
}

case "${SCANBD_ACTION:-}" in
  insert)
    notify_event "Scanner" "Scanner connected and ready."
    ;;
  remove)
    notify_event "Scanner" "Scanner disconnected."
    ;;
  paperload)
    notify_event "Scanner" "Paper loaded in feeder."
    ;;
  paperunload)
    notify_event "Scanner" "Paper removed from feeder."
    ;;
  coveropen)
    notify_event "Scanner" "Scanner cover opened."
    ;;
  powersave)
    notify_event "Scanner" "Scanner entering power save."
    ;;
  *)
    # Unknown action - log for debugging
    logger -t scan-events "scanbd event: SCANBD_ACTION=$SCANBD_ACTION SCANBD_DEVICE=$SCANBD_DEVICE"
    ;;
esac
