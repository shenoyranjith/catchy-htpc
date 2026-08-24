# Installer Specification

## Flow

1. Install project files.
2. Determine the target user.
3. Verify CachyOS.
4. Verify Btrfs.
5. Detect the GPU vendor and record it.
6. Ask whether to create a snapshot.
7. If a previous installer snapshot exists, ask whether to replace it.
8. Ask whether to update all system packages, then update if confirmed.
9. Install required packages.
10. Install Session Manager.
11. Install Kodi add-ons.
12. Install desktop shortcuts.
13. Ask which session should start automatically at boot (Kodi, Steam Gaming Mode, or KDE Desktop) and configure it.
14. Record installation state.
15. Verify installation.
16. Offer optional MakeMKV setup.
17. Prompt for reboot.

Step 1 (installing project files) happens before anything else, including
determining the target user: the installer re-execs itself from its
installed copy (see Project Files below) before doing any real work, so
every subsequent step already runs from the stable, installed location.

Snapshot tooling (snapper, inotify-tools, the bootloader-specific sync
package -- grub-btrfs or limine-snapper-sync -- and the @snapshots
subvolume layout) is actually ensured immediately before step 6, not as
part of step 9: snapshot creation in steps 6-7 needs it ready first, and
those packages may not be present yet on a fresh install even though
CachyOS ships Btrfs+snapper by default. `htpc_packages_install` is
idempotent, so step 9 installing them again afterwards is a harmless
no-op; only the packages actually missing before step 6 are recorded as
"installed by the installer" (see Installation Record below), regardless
of which step happened to trigger their installation. The active
bootloader is auto-detected (see [Recovery Specification](recovery-spec.md))
and recorded as `BOOTLOADER` in the installation record.

See [Recovery Specification](recovery-spec.md) for the snapshot mechanism
itself, and [MakeMKV Specification](makemkv-spec.md) for what step 15 sets
up.

## Project Files

Step 1 copies the project's bin/, lib/, systemd/, polkit/, kodi-addons/,
desktop-shortcuts/, autostart/, and vendor/ directories (not docs/ or dev/, which
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

Snapshot tool: snapper, with bootloader-specific menu integration (grub-btrfs on GRUB; limine-snapper-sync on Limine). See [Recovery Specification](recovery-spec.md) for the full mechanism, including the required @snapshots subvolume layout and auto-detection.

Snapshot creation is optional.

If selected:

- Create a bootable Btrfs snapshot before making changes.
- Display the snapshot name.
- Continue installation.

If snapshot creation fails:

Ask whether to continue or abort.

The installer never performs an automatic rollback.

Recovery is performed by rebooting into the snapshot from the Limine or GRUB snapshot menu, then running `htpc-recovery restore <number>` to make it permanent. See [Recovery Specification](recovery-spec.md).

## System Update

Before installing required packages, ask whether to run a full `pacman -Syu` first. Defaults to yes, but can be declined -- e.g. if the system currently has broken or held-back package dependencies that a full upgrade would trip over. Declining only skips this one-time update; required packages are still installed either way.

## GPU Vendor Detection

Detected via `lspci -k` (`htpc_gpu_is_nvidia` in lib/gpu.sh) and persisted
to `/etc/cachyos-htpc/gpu-vendor` ("nvidia" or "amd"), so htpc-switch and
a couple of small standalone scripts can read it back without depending
on this project's own lib/ tree. This determines which of the two
"Required Packages" / "Session Manager Installation" paths below apply.
See "GPU-Dependent Unit Resolution" in [Session Manager Specification](session-manager-spec.md)
and "Steam Gaming Mode" in [Session Services Specification](session-services-spec.md)
for why NVIDIA is treated differently at all: exclusive DRM gamescope
under a system unit fails Steam's userns/bwrap check on this hardware,
while the same `gamescope … -- steam -steamdeck` command works nested
under Plasma. NVIDIA therefore keeps Steam Gaming Mode inside
`htpc-desktop.service` via `bin/htpc-steamdeck-launch` (Steam must be
quit first), not a dedicated `htpc-steam.service`.

## Required Packages

- kodi
- snapper
- inotify-tools
- GRUB only: grub-btrfs
- Limine only: limine-snapper-sync, limine-mkinitcpio-hook

AMD only, additionally:

- gamescope-session-cachyos
- lib32-gamescope
- mangohud / lib32-mangohud (provides `mangoapp`, which renders Steam's Quick Access Menu "Performance Overlay" under gamescope-session-cachyos; not a hard dependency of that package itself, so it must be installed separately)

NVIDIA only, additionally:

- gamescope
- lib32-gamescope

Package sourcing prefers official CachyOS/Arch repositories, but AUR or other sources may be used where clearly better suited to a specific need.

## Session Manager Installation

- Install htpc-switch, htpc-kodi-launch, and htpc-kodi.service / htpc-desktop.service.
- AMD: also install htpc-steam-launch and htpc-steam.service.
- NVIDIA: do not install htpc-steam.service; install htpc-steamdeck-launch, the Steam Gaming Mode runtime dir (tmpfiles.d), boot-marker, and KDE autostart instead.
- Install a polkit rule scoping passwordless control of the htpc-*.service units to the target user.
- Install the `NO_AT_BRIDGE=1` environment.d drop-in for the target user's systemd --user manager, so D-Bus-activated helpers don't leak accessibility-bus units on every session switch. See "Accessibility Bus Cleanup" in [Session Services Specification](session-services-spec.md).
- Disable and mask whichever display manager is currently configured (discovered via the display-manager.service alias, not hardcoded -- CachyOS KDE installs use plasmalogin.service, not sddm.service), recording its unit name and prior enabled/disabled state. Only disables and masks it for the next boot; does not stop it immediately, since the installer is typically run from within a live session driven by that same display manager.
- Install /usr/bin/steamos-session-select as the htpc-switch wrapper (replacing gamescope-session-cachyos's copy on AMD; installing fresh on NVIDIA). AMD only: also mask cachyos-gamescope-autologin.service. See [Session Services Specification](session-services-spec.md).

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

- Prompt for which session -- Kodi, Steam Gaming Mode, or KDE Desktop -- should start automatically at boot, defaulting to Kodi (or whatever was chosen on a previous run, if rerunning). Enable that session's unit (resolved via `htpc_session_unit_for`, same mapping htpc-switch itself uses) and disable the others, so exactly one is ever enabled; a rerun with a different choice cleanly switches which one that is instead of leaving the old one enabled alongside it.
- No display manager is used. Boot proceeds directly from systemd into whichever htpc-*.service unit is enabled.

## Optional MakeMKV Setup

After verification, offer to run `bin/htpc-makemkv-setup` (see [MakeMKV Specification](makemkv-spec.md)) to enable Blu-ray/UHD Blu-ray disc decryption in Kodi. Declining, or the setup failing, does not affect the rest of the installation; it can be run again on its own at any time.

## Installation Record

Record the following, for later use by the uninstaller (and, for the boot
session choice, to default to it again on a rerun instead of always
re-defaulting to Kodi):

- Target user.
- Packages installed by the installer.
- The display manager's unit name and its prior enabled/disabled state.
- Installer snapshot name, if one was created.
- Which session (kodi, steam, or desktop) was chosen to start at boot.

The GPU vendor itself is recorded separately, at `/etc/cachyos-htpc/gpu-vendor` rather than in this file -- see "GPU Vendor Detection" above.

## Requirements

- Safe to rerun.
- Preserve user data.
- Backup modified configuration where practical.
- "Verify installation" performs static checks only: confirm required files, units, and the polkit rule exist and are enabled. It does not launch any session.
