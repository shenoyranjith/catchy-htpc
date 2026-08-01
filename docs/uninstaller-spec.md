# Uninstaller Specification

Executable:

bin/htpc-uninstall

## Flow

1. Verify an installation record exists (see [Installer Specification](installer-spec.md)).
2. Ask whether to create a snapshot before uninstalling, using the same mechanism as the installer.
3. Stop the currently active htpc-*.service, if any.
4. Disable and remove htpc-kodi.service, htpc-steam.service, htpc-desktop.service.
5. Remove the polkit rule and the `NO_AT_BRIDGE` environment.d drop-in installed for the target user.
6. Restore the recorded display manager unit to its prior enabled/disabled state and unmask it.
7. Restore /usr/bin/steamos-session-select and unmask cachyos-gamescope-autologin.service, if they were modified by the installer.
8. Remove Session Manager (htpc-switch, /usr/local/bin/htpc-recovery) and installed project files (/opt/cachyos-htpc).
9. Remove installed Kodi add-ons and the htpc-kodi.desktop / htpc-steam.desktop shortcuts, both from the application launcher directory and from the user's Desktop folder.
10. Remove only the favourites.xml entries added by the installer, preserving any other entries.
11. Remove the installation record itself.
12. Ask whether to remove packages installed by the installer (kodi, gamescope-session-cachyos, lib32-gamescope, mangohud, lib32-mangohud, snapper, grub-btrfs, inotify-tools).
13. Verify removal.
14. Prompt for reboot.

## Target User

Unlike the installer, the target user is not taken from whoever invokes
the command (`$SUDO_USER`): it's read back from the `TARGET_USER` value in
the installation record written by the installer (see [Installer Specification](installer-spec.md)),
since the uninstaller may reasonably be run by a different admin than
whoever originally ran the installer. Values needed later in the flow
(the target user, the recorded package list) are read from the record
once, up front, before anything -- including the record itself -- is
removed.

## Self-Removal

Step 8 deletes /opt/cachyos-htpc, which is typically also where
bin/htpc-uninstall itself is running from (the installer copies the whole
project tree there; see "Project Files" in [Installer Specification](installer-spec.md)).
Deleting a running script's own directory out from under it is unsafe, so
if invoked from `/opt/cachyos-htpc/bin/htpc-uninstall`, the uninstaller
first copies itself to a temporary directory and re-execs from there --
the mirror image of the installer's own self-relocation on the way in.
The temporary copy removes itself on exit. Running from anywhere else
(e.g. a dev checkout) skips this; there's nothing to relocate away from
in that case.

## Requirements

- Safe to rerun.
- Preserve user data: Kodi library and profile data, Steam library, and any personal files are never deleted.
- Never delete or modify existing Btrfs snapshots. Snapshot rollback remains a manual action performed from GRUB.
- If a step fails, report it clearly and continue with the remaining steps where safe to do so.
- "Verify removal" performs static checks only: confirm the units, polkit rule, add-ons, shortcuts, and project files are gone.

## Out of Scope

- Reverting package updates performed during install (the "Update packages" step in [Installer Specification](installer-spec.md)).
- Automatically restoring a Btrfs snapshot. See [Recovery Specification](recovery-spec.md) to do this manually.
- Removing MakeMKV, if installed via the optional add-on. See "Out of Scope" in [MakeMKV Specification](makemkv-spec.md) for manual removal steps.
