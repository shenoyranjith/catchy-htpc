# catchy-htpc

catchy-htpc converts a fresh installation of CachyOS KDE into an appliance-like HTPC.

## Goals

- Boot directly into the chosen session (Kodi by default; configurable at install time)
- Seamlessly switch between Kodi, Steam Gaming Mode and KDE Desktop
- Minimize desktop overhead while using Kodi
- Preserve the user's existing account and data
- Be easy to install, uninstall and maintain

Kodi is the primary interface.
Steam Gaming Mode is the gaming workspace.
KDE Desktop is the maintenance and recovery workspace.

How those sessions are realized depends on the GPU:

- **AMD:** exclusive systemd sessions for Kodi (GBM), Steam (`start-gamescope-session`), and Plasma.
- **NVIDIA:** exclusive Kodi (kiosk `kwin_wayland`) and Plasma; Steam Gaming Mode is nested gamescope + Steam Deck UI (`--mangoapp`, `-steamos3`) inside that same Plasma session.

See [Session Services](docs/session-services-spec.md) for the full split.

## Status

- Installer and uninstaller
- Session switching between Kodi, Steam Gaming Mode, and KDE Desktop (AMD and NVIDIA)
- Recovery snapshots (Limine or GRUB)
- Desktop shortcuts back to Kodi and Steam
- Optional MakeMKV / Blu-ray playback add-on

Released versions are listed in [CHANGELOG.md](CHANGELOG.md).

## Quick Start

Requires an existing CachyOS KDE installation on Btrfs (CachyOS's
default), with Limine or GRUB as the bootloader. Run as the user you
want the HTPC session to run as:

```
sudo bin/htpc-install
```

The installer is interactive, safe to rerun, and offers to take a Btrfs
snapshot before making any changes. Snapshot boot-menu integration is
wired for whichever bootloader is active (Limine via `limine-snapper-sync`,
GRUB via `grub-btrfs`). See
[docs/installer-spec.md](docs/installer-spec.md) for exactly what it
does, and [docs/recovery-spec.md](docs/recovery-spec.md) for how to roll
back if something goes wrong.

To reverse the installation and return to a stock CachyOS KDE desktop
login:

```
sudo bin/htpc-uninstall
```

See [docs/uninstaller-spec.md](docs/uninstaller-spec.md) for exactly what
it removes (and what it deliberately leaves alone, like your Kodi/Steam
libraries).

## Documentation

Full documentation lives in [docs/](docs/), starting at
[docs/Home.md](docs/Home.md). It's written so it can also be browsed as a
GitHub wiki. Highlights:

- [Architecture](docs/architecture.md) -- components and design principles.
- [Installer Specification](docs/installer-spec.md) -- what `bin/htpc-install` does.
- [Recovery Specification](docs/recovery-spec.md) -- Btrfs snapshot/restore (Limine or GRUB).
- [Session Lifecycle](docs/session-lifecycle.md) / [Session Services](docs/session-services-spec.md) -- how switching between Kodi, Steam, and Desktop works (including AMD vs NVIDIA).
- [MakeMKV Specification](docs/makemkv-spec.md) -- optional Blu-ray/UHD Blu-ray playback add-on.
- [Development](docs/development.md) -- dev machine setup, test sync, and Kodi config migrate across OS reinstalls.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
