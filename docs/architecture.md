# Architecture

## Overview

CachyOS HTPC transforms a fresh CachyOS KDE installation into a console-like HTPC.

Core components:

- [Installer](installer-spec.md) / [Uninstaller](uninstaller-spec.md)
- [Recovery](recovery-spec.md)
- [Session Manager](session-manager-spec.md)
- [Systemd Services](session-services-spec.md)
- [Kodi Program Add-ons](kodi-addon-spec.md)
- [MakeMKV / Disc Playback](makemkv-spec.md) (optional add-on)

Kodi is the primary user interface.

Steam Gaming Mode and KDE Desktop are separate workspaces entered through the Session Manager.

No display manager (SDDM) is used. Sessions are managed entirely through systemd and PAM.

## Goals

- Boot directly into Kodi.
- Use the existing user account.
- Prefer well-maintained packages. Official CachyOS/Arch repositories are preferred, but AUR or other sources may be used where clearly better suited to a specific need.
- Avoid modifying Kodi skins.
- Keep the installer idempotent.
- Keep the system easy to recover.

## Design Principles

- Only one interactive session at a time, enforced both by the Session Manager and by systemd unit conflicts.
- Session transitions are centralized in the Session Manager.
- Preserve user data.
- Desktop acts as the recovery environment.
- Elevated privileges are scoped as narrowly as possible: polkit for session switching, root only during install and uninstall.
