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
- Disable and mask sddm.service, recording its prior enabled/disabled state.
- Mask cachyos-gamescope-autologin.service, a systemd --user unit, for the target user.
- Replace /usr/bin/steamos-session-select with a wrapper that calls htpc-switch. See session-services-spec.md.

## Kodi Add-on Installation

- Install the Steam Gaming Mode and Desktop Mode Program add-ons directly into the target user's Kodi addons directory.
- Seed or merge the target user's favourites.xml with entries that launch both add-ons, preserving any existing favourites.

## Boot Configuration

- Enable htpc-kodi.service so it starts automatically at boot.
- No display manager is used. Boot proceeds directly from systemd into htpc-kodi.service.

## Installation Record

Record the following, for later use by the uninstaller:

- Target user.
- Packages installed by the installer.
- Prior SDDM enabled/disabled state.
- Installer snapshot name, if one was created.

## Requirements

- Safe to rerun.
- Preserve user data.
- Backup modified configuration where practical.
- "Verify installation" performs static checks only: confirm required files, units, and the polkit rule exist and are enabled. It does not launch any session.
