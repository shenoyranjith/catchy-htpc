# Installer Specification

## Flow

1. Install project files.
2. Determine the target user.
3. Verify CachyOS.
4. Verify Btrfs.
5. Ask whether to create a snapshot.
6. If a previous installer snapshot exists, ask whether to replace it.
7. Update packages.
8. Install required packages.
9. Install Session Manager.
10. Install Kodi add-ons.
11. Install desktop shortcuts.
12. Configure automatic boot into Kodi.
13. Record installation state.
14. Verify installation.
15. Offer optional MakeMKV setup.
16. Prompt for reboot.

Step 1 (installing project files) happens before anything else, including
determining the target user: the installer re-execs itself from its
installed copy (see Project Files below) before doing any real work, so
every subsequent step already runs from the stable, installed location.

Snapshot tooling (snapper, grub-btrfs, inotify-tools, and the @snapshots
subvolume layout) is actually ensured immediately before step 5, not as
part of step 8: snapshot creation in steps 5-6 needs it ready first, and
those packages may not be present yet on a fresh install even though
CachyOS ships Btrfs+snapper by default. `htpc_packages_install` is
idempotent, so step 8 installing them again afterwards is a harmless
no-op; only the packages actually missing before step 5 are recorded as
"installed by the installer" (see Installation Record below), regardless
of which step happened to trigger their installation.

See [Recovery Specification](recovery-spec.md) for the snapshot mechanism
itself, and [MakeMKV Specification](makemkv-spec.md) for what step 15 sets
up.

## Project Files

Step 1 copies the project's bin/, lib/, systemd/, polkit/, kodi-addons/,
desktop-shortcuts/, and vendor/ directories (not docs/ or dev/, which
aren't needed at runtime) to /opt/cachyos-htpc, and the installer re-executes itself from
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

Snapshot tool: snapper, with grub-btrfs for GRUB boot menu integration. See [Recovery Specification](recovery-spec.md) for the full mechanism, including the required @snapshots subvolume layout.

Snapshot creation is optional.

If selected:

- Create a bootable Btrfs snapshot before making changes.
- Display the snapshot name.
- Continue installation.

If snapshot creation fails:

Ask whether to continue or abort.

The installer never performs an automatic rollback.

Recovery is performed by rebooting into the snapshot from GRUB, then running `htpc-recovery restore <number>` to make it permanent. See [Recovery Specification](recovery-spec.md).

## Required Packages

- kodi
- gamescope-session-cachyos
- lib32-gamescope
- mangohud / lib32-mangohud (provides `mangoapp`, which renders Steam's Quick Access Menu "Performance Overlay" under gamescope-session-cachyos; not a hard dependency of that package itself, so it must be installed separately)
- snapper
- grub-btrfs
- inotify-tools (required by grub-btrfsd)

Package sourcing prefers official CachyOS/Arch repositories, but AUR or other sources may be used where clearly better suited to a specific need.

## Session Manager Installation

- Install htpc-switch and its systemd unit files: htpc-kodi.service, htpc-steam.service, htpc-desktop.service.
- Install a polkit rule scoping passwordless control of only these three units to the target user.
- Install the `NO_AT_BRIDGE=1` environment.d drop-in for the target user's systemd --user manager, so D-Bus-activated helpers don't leak accessibility-bus units on every session switch. See "Accessibility Bus Cleanup" in [Session Services Specification](session-services-spec.md).
- Disable and mask whichever display manager is currently configured (discovered via the display-manager.service alias, not hardcoded -- CachyOS KDE installs use plasmalogin.service, not sddm.service), recording its unit name and prior enabled/disabled state. Only disables and masks it for the next boot; does not stop it immediately, since the installer is typically run from within a live session driven by that same display manager.
- Mask cachyos-gamescope-autologin.service, a systemd --user unit, for the target user.
- Replace /usr/bin/steamos-session-select with a wrapper that calls htpc-switch. See [Session Services Specification](session-services-spec.md).

## Kodi Add-on Installation

- Install the Steam Gaming Mode and Desktop Mode Program add-ons directly into the target user's Kodi addons directory.
- Seed or merge the target user's favourites.xml with entries that launch
  both add-ons, plus Play Disc (`PlayDVD(1)`) and Eject Tray (`EjectTray(1)`)
  built-ins so disc controls remain available under skins that hide them,
  preserving any existing favourites. See [Kodi Add-on Specification](kodi-addon-spec.md) for why these
  built-ins are seeded with a dummy parameter.

## Desktop Shortcuts

Install the htpc-kodi.desktop / htpc-steam.desktop shortcuts for the
target user, both into `~/.local/share/applications/` (application
launcher) and onto the target user's actual Desktop folder (as real,
directly-launchable desktop icons), so KDE Desktop also has a way back
into htpc-switch. See "Desktop Application Shortcuts" in [Session Services Specification](session-services-spec.md).

## Boot Configuration

- Enable htpc-kodi.service so it starts automatically at boot.
- No display manager is used. Boot proceeds directly from systemd into htpc-kodi.service.

## Optional MakeMKV Setup

After verification, offer to run `bin/htpc-makemkv-setup` (see [MakeMKV Specification](makemkv-spec.md)) to enable Blu-ray/UHD Blu-ray disc decryption in Kodi. Declining, or the setup failing, does not affect the rest of the installation; it can be run again on its own at any time.

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
