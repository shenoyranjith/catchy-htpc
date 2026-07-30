# Session Manager Specification

Executable:

htpc-switch

Implementation: Bash.

## Supported Commands

- htpc-switch kodi
- htpc-switch steam
- htpc-switch desktop

## Responsibilities

- Validate transitions against session-lifecycle.md.
- Determine the currently active session by querying the state of htpc-kodi.service, htpc-steam.service, and htpc-desktop.service.
- Stop the active session's systemd unit.
- Start the destination session's systemd unit.
- Record transition logs via journald.
- Recover to KDE Desktop when possible; if KDE Desktop also fails to start, enter Fatal Error (see session-lifecycle.md).

## Privilege Model

- Runs as the existing user, not root.
- Uses a narrow polkit rule, installed by the installer, granting passwordless control of only the three htpc-*.service units.
- No sudo or setuid binaries are required for normal operation.

## Constraints

No application-specific logic belongs here. See session-services-spec.md for how each session is actually launched.
