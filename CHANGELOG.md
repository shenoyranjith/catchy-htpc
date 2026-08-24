# Changelog

All notable changes to catchy-htpc are documented here.

## [1.0.1] - 2026-08-24

NVIDIA session support, configurable boot, and exit-fallback that matches the recovery rules.

### Added

- Installer prompt for which session starts at boot (Kodi, Steam Gaming Mode, or KDE Desktop). The previous choice is remembered on reruns; Kodi remains the default.
- NVIDIA Steam Gaming Mode inside the existing Plasma session (no gamescope). Steam autostarts with Desktop; Big Picture is gated by `HTPC_STEAM_BIGPICTURE` and opened with `steam -bigpicture` or `steam://open/bigpicture` as appropriate.
- NVIDIA Kodi session as a kiosk `kwin_wayland` plus Kodi as a Wayland client. Kodi stays its own `htpc-kodi.service`; AMD still uses GBM standalone.
- Exit-fallback on all three session units: Kodi or Steam quitting/crashing lands on KDE Desktop; Desktop quitting/crashing lands on Fatal Error (getty on tty1).
- `bin/htpc-kodi-launch`, wrapping `kodi --standalone` with delayed retries instead of kodi-standalone's near-instant crash loop.

### Changed

- `script.htpc.steam` is categorized as a Kodi Game add-on so it appears under Games rather than Programs.
- The installer's `pacman -Syu` step is optional.

### Fixed

- Steam overlay display corruption on current NVIDIA drivers (gamescope is skipped on NVIDIA entirely; ValveSoftware/gamescope#1964).
- Kodi GBM aborting on splash (`CWinSystemGbm::FlipPage`) on current nvidia-open drivers, including cold boot into Kodi.
- Switching Desktop → Kodi leaving Plasma 6's `kwin_wayland` holding DRM (it lives under `plasma-workspace.target`, not `htpc-desktop.service`).
- Exit-fallback firing during a normal shutdown/reboot and fighting systemd's teardown.
- Desktop ↔ Steam Big Picture toggle dropping display environment when dispatched via `systemd-run`; it now runs in-process.
- Cold-start Big Picture using `steam://open/bigpicture` as the first argument, which showed Steam's "needs to be online" dialog; startup now uses `steam -bigpicture`.

## [1.0] - 2026-08-01

Initial release: installer and uninstaller, exclusive systemd sessions for Kodi / Steam Gaming Mode / KDE Desktop, recovery snapshots, Kodi add-ons and Desktop shortcuts, and optional MakeMKV/Blu-ray setup.
