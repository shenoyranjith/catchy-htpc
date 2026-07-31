# CachyOS HTPC

CachyOS HTPC converts a fresh installation of CachyOS KDE into an appliance-like HTPC.

## Goals

- Boot directly into Kodi
- Seamlessly switch between Kodi, Steam Gaming Mode and KDE Desktop
- Minimize desktop overhead while using Kodi
- Preserve the user's existing account and data
- Be easy to install, uninstall and maintain

Kodi is the primary interface.
Steam Gaming Mode is the gaming workspace.
KDE Desktop is the maintenance and recovery workspace.

## Status

Phase 1 (installer, uninstaller, session switching between all three
workspaces, recovery) and the optional MakeMKV/Blu-ray add-on are
complete. See [docs/roadmap.md](docs/roadmap.md) for details.

## Quick Start

Requires an existing CachyOS KDE installation on Btrfs (CachyOS's
default). Run as the user you want the HTPC session to run as:

```
sudo bin/htpc-install
```

The installer is interactive, safe to rerun, and offers to take a Btrfs
snapshot before making any changes. See
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
- [Recovery Specification](docs/recovery-spec.md) -- Btrfs snapshot/restore mechanism.
- [Session Lifecycle](docs/session-lifecycle.md) / [Session Services](docs/session-services-spec.md) -- how switching between Kodi, Steam, and Desktop works.
- [MakeMKV Specification](docs/makemkv-spec.md) -- optional Blu-ray/UHD Blu-ray playback add-on.
- [Development](docs/development.md) -- dev machine setup and test workflow.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
