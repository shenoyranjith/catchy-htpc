# Installer Specification

## Flow

1. Determine the target user.
2. Verify CachyOS.
3. Verify Btrfs.
4. Ask whether to create a snapshot.
5. If a previous installer snapshot exists, ask whether to replace it.
6. Update packages.
7. Install required packages.
8. Install project files.
9. Install Session Manager.
10. Install Kodi add-ons.
11. Configure automatic boot into Kodi.
12. Record installation state.
13. Verify installation.
14. Prompt for reboot.

Snapshot tooling (snapper, grub-btrfs, inotify-tools, and the @snapshots
subvolume layout) is actually ensured immediately before step 4, not as
part of step 7: snapshot creation in steps 4-5 needs it ready first, and
those packages may not be present yet on a fresh install even though
CachyOS ships Btrfs+snapper by default. `htpc_packages_install` is
idempotent, so step 7 installing them again afterwards is a harmless
no-op; only the packages actually missing before step 4 are recorded as
"installed by the installer" (see Installation Record below), regardless
of which step happened to trigger their installation.

## Project Files

Step 8 copies the project's bin/, lib/, systemd/, polkit/, kodi-addons/,
and desktop-shortcuts/ directories (not docs/ or dev/, which aren't
needed at runtime) to /opt/cachyos-htpc, and the installer re-executes itself from
that copy for all subsequent steps. This ensures the installed system
never depends on wherever the installer happened to be run from (e.g. a
temporary dev checkout it can't assume will still exist later). Rerunning
the installer always refreshes /opt/cachyos-htpc from the current
checkout. bin/htpc-recovery is additionally exposed as a user-facing
command via a thin wrapper at /usr/local/bin/htpc-recovery, alongside
htpc-switch (see Session Manager Installation).

## Target User

The target user is whoever invokes the installer (for example, via `$SUDO_USER`). All session services and Kodi add-ons run as this user. The installer assumes a single primary user on the machine.

## Snapshot Behaviour

Snapshot tool: snapper, with grub-btrfs for GRUB boot menu integration. See recovery-spec.md for the full mechanism, including the required @snapshots subvolume layout.

Snapshot creation is optional.

If selected:

- Create a bootable Btrfs snapshot before making changes.
- Display the snapshot name.
- Continue installation.

If snapshot creation fails:

Ask whether to continue or abort.

The installer never performs an automatic rollback.

Recovery is performed by rebooting into the snapshot from GRUB, then running `htpc-recovery restore <number>` to make it permanent. See recovery-spec.md.

## Required Packages

- kodi
- gamescope-session-cachyos
- lib32-gamescope
- snapper
- grub-btrfs
- inotify-tools (required by grub-btrfsd)

Package sourcing prefers official CachyOS/Arch repositories, but AUR or other sources may be used where clearly better suited to a specific need.

## Session Manager Installation

- Install htpc-switch and its systemd unit files: htpc-kodi.service, htpc-steam.service, htpc-desktop.service.
- Install a polkit rule scoping passwordless control of only these three units to the target user.
- Disable and mask whichever display manager is currently configured (discovered via the display-manager.service alias, not hardcoded -- CachyOS KDE installs use plasmalogin.service, not sddm.service), recording its unit name and prior enabled/disabled state. Only disables and masks it for the next boot; does not stop it immediately, since the installer is typically run from within a live session driven by that same display manager.
- Mask cachyos-gamescope-autologin.service, a systemd --user unit, for the target user.
- Replace /usr/bin/steamos-session-select with a wrapper that calls htpc-switch. See session-services-spec.md.

## Kodi Add-on Installation

- Install the Steam Gaming Mode and Desktop Mode Program add-ons directly into the target user's Kodi addons directory.
- Seed or merge the target user's favourites.xml with entries that launch both add-ons, preserving any existing favourites.
- Install the desktop application-launcher shortcuts (htpc-kodi.desktop, htpc-steam.desktop) into the target user's ~/.local/share/applications/, so KDE Desktop also has a way back into htpc-switch. See "Desktop Application Shortcuts" in session-services-spec.md.

## Boot Configuration

- Enable htpc-kodi.service so it starts automatically at boot.
- No display manager is used. Boot proceeds directly from systemd into htpc-kodi.service.

## Installation Record

Record the following, for later use by the uninstaller:

- Target user.
- Packages installed by the installer.
- The display manager's unit name and its prior enabled/disabled state.
- Installer snapshot name, if one was created.

## Requirements

- Safe to rerun.
- Preserve user data.
- Backup modified configuration where practical.
- "Verify installation" performs static checks only: confirm required files, units, and the polkit rule exist and are enabled. It does not launch any session.
