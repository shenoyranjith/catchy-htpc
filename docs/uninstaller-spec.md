# Uninstaller Specification

Executable:

htpc-uninstall

## Flow

1. Verify an installation record exists (see installer-spec.md).
2. Ask whether to create a snapshot before uninstalling, using the same mechanism as the installer.
3. Stop the currently active htpc-*.service, if any.
4. Disable and remove htpc-kodi.service, htpc-steam.service, htpc-desktop.service.
5. Remove the polkit rule granting control of the htpc-*.service units.
6. Restore the recorded display manager unit to its prior enabled/disabled state and unmask it.
7. Restore /usr/bin/steamos-session-select and unmask cachyos-gamescope-autologin.service, if they were modified by the installer.
8. Remove Session Manager (htpc-switch, /usr/local/bin/htpc-recovery) and installed project files (/opt/cachyos-htpc).
9. Remove installed Kodi add-ons.
10. Remove only the favourites.xml entries added by the installer, preserving any other entries.
11. Ask whether to remove packages installed by the installer (kodi, gamescope-session-cachyos, lib32-gamescope, snapper, grub-btrfs, inotify-tools).
12. Verify removal.
13. Prompt for reboot.

## Requirements

- Safe to rerun.
- Preserve user data: Kodi library and profile data, Steam library, and any personal files are never deleted.
- Never delete or modify existing Btrfs snapshots. Snapshot rollback remains a manual action performed from GRUB.
- If a step fails, report it clearly and continue with the remaining steps where safe to do so.
- "Verify removal" performs static checks only: confirm the units, polkit rule, and project files are gone.

## Out of Scope

- Reverting package updates performed during install (the "Update packages" step in installer-spec.md).
- Automatically restoring a Btrfs snapshot.
