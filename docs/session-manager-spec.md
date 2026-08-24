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

## GPU-Dependent Unit Resolution

- AMD: kodi / steam / desktop are three distinct units. Steam uses
  `start-gamescope-session` via `bin/htpc-steam-launch`.
- NVIDIA: "steam" and "desktop" share `htpc-desktop.service`. Gaming Mode
  is nested gamescope + Steam Deck UI (`bin/htpc-steamdeck-launch`), which
  always quits Steam first. Toggles between steam and desktop run
  in-process without restarting Plasma. Steam's "Switch to Desktop" maps
  to `htpc-switch desktop` (same session), not Kodi.

Leaving Plasma for Kodi still stops `plasma-workspace.target` and waits
for kwin to exit so the next exclusive DRM client can take the display.

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

Each htpc-*.service unit runs `htpc-switch --exit-fallback <target>` as its
own `ExecStopPost`, so that session exiting on its own -- its own Exit/Quit,
a crash, or (now that any of the three can be the boot session; see "Boot
Configuration" in [Installer Specification](installer-spec.md)) simply
failing to start at boot -- lands somewhere useful instead of leaving tty1
blank, relaunching itself (as `Restart=on-success` used to do for Steam and
Desktop), or looping back into a session that just failed (Kodi). This mode
is not exposed as a user-facing command; it exists purely for these units'
ExecStopPost. The target differs per unit, matching the Recovery rules in
[Session Lifecycle](session-lifecycle.md):

- htpc-kodi.service and htpc-steam.service both use `--exit-fallback desktop`: Kodi or Steam exiting on their own falls back to KDE Desktop.
- htpc-desktop.service uses `--exit-fallback fatal`: Desktop is already the
  last resort, so exiting on its own enters Fatal Error (a plain getty on
  tty1, via `htpc_start_getty_fallback`) instead of falling back to another
  session. This is the only target that isn't itself a session name; see
  the "fatal" pseudo-target in `htpc_worker_main`.

This must not fire when the system itself is shutting down or rebooting:
stopping the active htpc-*.service unit is then just one step of that
larger transaction, not a spontaneous exit, and the target user's own
systemd --user manager (`user@<uid>.service`) is itself mid-teardown by
that point too -- confirmed live, dispatching a fallback in this case
reliably either fails outright (`systemd-run --user` errors with
"$DBUS_SESSION_BUS_ADDRESS and $XDG_RUNTIME_DIR not defined") or actively
contends with the shutdown transaction already tearing that same manager
down ("Transaction ... is destructive"). Checked via `systemctl
is-system-running` == `stopping`, systemd's own state for exactly this.

This must also not fire when a session is being stopped as *part of* a deliberate
switch already dispatched by htpc-switch (e.g. Kodi -> Steam via a
favourite), since that switch already knows where it is going and firing
the fallback too would race a second, conflicting transition against it.
`ExecStopPost` runs synchronously as part of the unit's stop job, which
means any `systemctl stop` call against one of these units -- including the
one htpc-switch's own worker issues when switching away from it -- does not
return until this same ExecStopPost has finished running. So at the moment
ExecStopPost fires, an in-flight worker's own `htpc-switch-worker-*`
transient unit (see "Self-Referential Invocation" above) is guaranteed to
still be active if and only if that worker is the reason the unit is
stopping. The exit fallback checks for exactly that (`systemctl --user
list-units 'htpc-switch-worker-*' --state=active`) and skips itself if it
finds one, running the actual fallback (via the same detached
`systemd-run --user` worker dispatch, with `current=boot` since the session
has already fully stopped by this point) only when it finds none.

## Privilege Model

- Runs as the existing user, not root.
- Uses a narrow polkit rule, installed by the installer, granting passwordless control of only the three htpc-*.service units, plus getty@tty1.service for the Fatal Error fallback above.
- No sudo or setuid binaries are required for normal operation.
- If invoked as root, drops to the configured user itself rather than requiring the caller to do so; see "Self-Referential Invocation" above.

## Constraints

No application-specific logic belongs here. See [Session Services Specification](session-services-spec.md) for how each session is actually launched.
