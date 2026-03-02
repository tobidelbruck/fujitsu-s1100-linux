# Fujitsu ScanSnap S1100 Linux - Makefile
#
# Usage:
#   make install    - Run full installation (requires sudo)
#   make uninstall  - Remove scanbd and revert changes (requires sudo)
#   make help       - Show available targets

.PHONY: install uninstall help

install:
	@echo "Running installer (requires sudo)..."
	@sudo "$(CURDIR)/install.sh"

uninstall:
	@echo "Running uninstaller (requires sudo)..."
	@sudo "$(CURDIR)/install.sh" --remove

help:
	@echo "Fujitsu S1100 Linux"
	@echo ""
	@echo "Targets:"
	@echo "  make install    - Install scanbd, dependencies, and scan-button script"
	@echo "  make uninstall  - Remove scanbd and revert all changes"
	@echo "  make help       - Show this help"
