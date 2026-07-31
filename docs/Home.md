# catchy-htpc

catchy-htpc converts a fresh installation of CachyOS KDE into an
appliance-like HTPC.

## Goals

- Boot directly into Kodi.
- Seamlessly switch between Kodi, Steam Gaming Mode, and KDE Desktop.
- Minimize desktop overhead while using Kodi.
- Preserve the user's existing account and data.
- Be easy to install, uninstall, and maintain.

Kodi is the primary interface. Steam Gaming Mode is the gaming workspace.
KDE Desktop is the maintenance and recovery workspace. See
[Architecture](architecture.md) for how these fit together, and
[Roadmap](roadmap.md) for current status.

## Getting Started

- **Using it:** [Installer Specification](installer-spec.md) explains
  what `bin/htpc-install` does and how to run it.
- **Recovering from a bad state:** [Recovery Specification](recovery-spec.md)
  covers Btrfs snapshots and `htpc-recovery`.
- **Contributing:** [Development](development.md) covers the dev/test
  workflow; [Coding Standards](coding-standards.md) and
  [Contributing](https://github.com/shenoyranjith/catchy-htpc/blob/master/CONTRIBUTING.md)
  cover conventions and testing gotchas.

## Documentation Map

### Design

- [Architecture](architecture.md) -- components and design principles.
- [Technical Design](technical-design.md) -- boot flow, runtime model, privilege model.
- [Session Lifecycle](session-lifecycle.md) -- valid session states and transitions.
- [Roadmap](roadmap.md) -- what's done, what's not.

### Specifications

- [Installer Specification](installer-spec.md)
- [Uninstaller Specification](uninstaller-spec.md)
- [Recovery Specification](recovery-spec.md)
- [Session Manager Specification](session-manager-spec.md) (`htpc-switch`)
- [Session Services Specification](session-services-spec.md) (systemd units for Kodi/Steam/Desktop)
- [Kodi Add-on Specification](kodi-addon-spec.md)
- [MakeMKV Specification](makemkv-spec.md) -- optional Blu-ray/UHD Blu-ray playback add-on

### Contributor Guides

- [Development](development.md) -- dev machine setup, sync workflow, safety net
- [Coding Standards](coding-standards.md)
