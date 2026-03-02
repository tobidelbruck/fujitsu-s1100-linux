#!/bin/bash
#
# Test script: Uninstall, then run installer to verify it works.
# Run with: sudo ./test-installer.sh
#

set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with: sudo $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Step 1: Uninstall (revert all changes) ==="
echo "Type 'y' when prompted."
"$SCRIPT_DIR/install.sh" --remove

echo ""
echo "=== Step 2: Install (fresh install) ==="
echo "Type 'y' when prompted."
"$SCRIPT_DIR/install.sh"

echo ""
echo "=== Step 3: Verify scanbd status ==="
systemctl status scanbd --no-pager || true
