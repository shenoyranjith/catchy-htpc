# Session Services Specification

Defines the systemd services backing each session described in session-lifecycle.md.

## Units

- htpc-kodi.service
- htpc-steam.service
- htpc-desktop.service

These are system-level systemd units. No display manager is used to start them or to switch between them.

## Shared Behaviour

- Run as the existing user determined by the installer (see installer-spec.md).
- PAMName=login, establishing a full logind session equivalent to a normal graphical login.
- TTYPath=/dev/tty1.
- Conflicts= and After= getty@tty1.service.
- Conflicts= the other two htpc-*.service units, so systemd itself enforces single-session exclusivity in addition to htpc-switch.
- Only htpc-switch starts or stops these units during normal operation.

## Kodi (htpc-kodi.service)

- Package: kodi (official repository).
- Runs Kodi standalone with GBM windowing, so Kodi owns DRM/KMS directly without a separate compositor.
- Runs as the existing user, using that user's own Kodi profile and data.
- Enabled by default so it starts automatically at boot.

## Steam Gaming Mode (htpc-steam.service)

- Packages: gamescope-session-cachyos, lib32-gamescope (official CachyOS repository).
- ExecStart runs the package's start-gamescope-session entrypoint as the existing user.
- The package's own SDDM-oriented autologin unit, cachyos-gamescope-autologin.service (a systemd --user unit), is masked for the existing user. It is not needed here and would otherwise attempt to modify SDDM configuration when the session exits.
- The package's steamos-session-select script is replaced with a thin wrapper:
  - gamescope -> htpc-switch steam
  - plasma -> htpc-switch kodi
- This makes Steam's own "Switch to Desktop" button return to Kodi, since Kodi is the primary interface. No SDDM interaction occurs at any point.

## KDE Desktop (htpc-desktop.service)

- Uses the existing CachyOS KDE Plasma installation already present on the system.
- ExecStart runs startplasma-wayland directly as the existing user.
- No SDDM or other display manager is involved.

## Display Manager

- SDDM is disabled and masked during install.
- Its prior enabled/disabled state is recorded so the uninstaller can restore it.
