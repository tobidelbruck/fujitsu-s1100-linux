# Config File Changes (from chat history)

## Installer modifies these files:

### /etc/scanbd/scanbd.conf
- **Comment out** `include(scanner.d/fujitsu.conf)` — fujitsu.conf uses SANE syntax that causes "no such option 'option'" error; S1100 uses epjitsu backend anyway
- **Set** `user = INSTALL_USER` (e.g. pasadena)
- **Set** `group = scanner` (or `lp` if scanner group doesn't exist)

### /etc/dbus-1/system.d/scanbd_dbus.conf
- **Set** `<policy user="INSTALL_USER">` — allows scanbd to register its D-Bus service (fixes "Connection is not allowed to own the service")

## Files we do NOT modify:
- **/etc/scanbd/scanner.d/fujitsu.conf** — Fix is to disable it via include, not edit it
- **saned** — Part of sane-utils; we need sane-utils for scanimage. Saned service is typically masked/not used.
