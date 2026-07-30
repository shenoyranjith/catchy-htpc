# Technical Design

## Target Platform

- CachyOS KDE
- Wayland
- x86_64
- systemd

## Boot Flow

Firmware
-> GRUB (snapshot-aware via grub-btrfs)
-> Linux
-> systemd starts htpc-kodi.service (enabled by default)
-> PAM (PAMName=login) establishes a logind session for the existing user
-> Kodi

No display manager is involved in this flow.

## Components

Installer
Uninstaller
Session Manager (htpc-switch)
Systemd services (see session-services-spec.md)
Kodi add-ons

## Session Runtime Model

- Each session (Kodi, Steam Gaming Mode, KDE Desktop) is a system-level systemd service.
- The services share tty1 and conflict with getty@tty1.service and with each other, so only one can run at a time.
- No SDDM or other display manager is used anywhere on the system.
- See session-services-spec.md for full detail.

## Configuration

Centralize configuration in a single location shared by the installer and htpc-switch.
Avoid hardcoded paths.

## Logging

Log all session transitions using journald where possible.

## Privilege Model

Use the existing user.
Request elevated privileges only when required.
Session switching uses a narrow polkit rule scoped to the three htpc-*.service units. No sudo or setuid binaries are used for normal operation.
Root privileges are required only during install and uninstall.
