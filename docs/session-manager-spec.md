# Session Manager Specification

Executable:

htpc-switch

Implementation: Bash.

## Supported Commands

- htpc-switch kodi
- htpc-switch steam
- htpc-switch desktop
- htpc-switch --exit-fallback \<target\> (internal; see "Exit Fallback" below)

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

## Exit Fallback

htpc-kodi.service runs `htpc-switch --exit-fallback desktop` as
`ExecStopPost`, so that Kodi exiting on its own -- its own Exit/Quit, or a
crash -- lands on KDE Desktop instead of leaving tty1 blank or (as
`Restart=on-success` used to do) relaunching Kodi. This mode is not exposed
as a user-facing command; it exists purely for this unit's ExecStopPost.

This must not fire when Kodi is being stopped as *part of* a deliberate
switch already dispatched by htpc-switch (e.g. Kodi -> Steam via a
favourite), since that switch already knows where it is going and firing
the fallback too would race a second, conflicting transition against it.
`ExecStopPost` runs synchronously as part of the unit's stop job, which
means any `systemctl stop htpc-kodi.service` call -- including the one
htpc-switch's own worker issues when switching away from Kodi -- does not
return until this same ExecStopPost has finished running. So at the moment
ExecStopPost fires, an in-flight worker's own `htpc-switch-worker-*`
transient unit (see "Self-Referential Invocation" above) is guaranteed to
still be active if and only if that worker is the reason Kodi is stopping.
The exit fallback checks for exactly that (`systemctl --user list-units
'htpc-switch-worker-*' --state=active`) and skips itself if it finds one,
running the actual fallback switch (via the same detached
`systemd-run --user` worker dispatch, with `current=boot` since Kodi has
already fully stopped by this point) only when it finds none.

Steam and KDE Desktop do not have an equivalent ExecStopPost: unlike Kodi,
neither is meant to be the thing you land on if it exits unexpectedly, and
their own "switch away" paths (Steam's "Switch to Desktop" button, KDE's
logout) are already user-facing invocations of htpc-switch, not
spontaneous exits.

## Privilege Model

- Runs as the existing user, not root.
- Uses a narrow polkit rule, installed by the installer, granting passwordless control of only the three htpc-*.service units.
- No sudo or setuid binaries are required for normal operation.
- If invoked as root, drops to the configured user itself rather than requiring the caller to do so; see "Self-Referential Invocation" above.

## Constraints

No application-specific logic belongs here. See [Session Services Specification](session-services-spec.md) for how each session is actually launched.
