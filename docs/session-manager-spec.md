# Session Manager Specification

Executable:

htpc-switch

Implementation: Bash.

## Supported Commands

- htpc-switch kodi
- htpc-switch steam
- htpc-switch desktop

## Responsibilities

- Validate transitions against [Session Lifecycle](session-lifecycle.md).
- Determine the currently active session by querying the state of htpc-kodi.service, htpc-steam.service, and htpc-desktop.service.
- Stop the active session's systemd unit.
- Start the destination session's systemd unit.
- Record transition logs via journald.
- Recover to KDE Desktop when possible; if KDE Desktop also fails to start, enter Fatal Error (see [Session Lifecycle](session-lifecycle.md)).

## Self-Referential Invocation

htpc-switch is routinely invoked from *within* the session it is switching
away from: a Kodi Program Add-on, or Steam's own "Switch to Desktop" button
(via the steamos-session-select wrapper, see [Session Services Specification](session-services-spec.md)). In
that situation, htpc-switch's own process is a descendant of the very
htpc-*.service unit it needs to stop. Since these units use the default
KillMode (control-group), stopping one sends SIGTERM to its entire cgroup,
including htpc-switch itself, which would otherwise kill it before it could
start the destination session.

To avoid this, htpc-switch only performs synchronous validation inline
(invalid transition, already running, target user resolution). The actual
stop-current/start-target work is dispatched to a detached transient
`--user` unit via `systemd-run --user`, which runs under `user@<uid>.service`
-- a completely separate cgroup from any htpc-*.service -- so it is
unaffected when the old session's cgroup is torn down. Because of this,
callers only receive synchronous success/failure for validation and
dispatch; failures during the switch itself (e.g. the destination session
failing to start and recovery kicking in) are only observable via journald,
not fed back to a caller that may no longer exist by the time they happen.

If invoked as root (as pkexec does for the steamos-session-select wrapper),
htpc-switch re-execs itself as the user the htpc-*.service units are
configured to run as (read back from the installed htpc-kodi.service unit)
before doing anything else, so the `--user` dispatch always targets the
right user's session bus.

## Privilege Model

- Runs as the existing user, not root.
- Uses a narrow polkit rule, installed by the installer, granting passwordless control of only the three htpc-*.service units.
- No sudo or setuid binaries are required for normal operation.
- If invoked as root, drops to the configured user itself rather than requiring the caller to do so; see "Self-Referential Invocation" above.

## Constraints

No application-specific logic belongs here. See [Session Services Specification](session-services-spec.md) for how each session is actually launched.
