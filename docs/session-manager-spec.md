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

htpc-switch reads the GPU vendor recorded at install time
(`/etc/cachyos-htpc/gpu-vendor`, written by `htpc_gpu_vendor_install` in
lib/gpu.sh) to resolve "steam" to the unit that actually backs it:

- AMD (or the vendor file missing/unreadable): "steam" resolves to its own
  htpc-steam.service, exactly as before.
- NVIDIA: "steam" resolves to htpc-desktop.service itself -- there is no
  separate htpc-steam.service on NVIDIA at all (gamescope has a confirmed
  upstream display-corruption bug with the Steam overlay on current NVIDIA
  driver branches; see [Session Services Specification](session-services-spec.md)).
  Steam autostarts with that same KDE Plasma session unconditionally, and
  "Steam Gaming Mode" vs. "KDE Desktop" becomes a question of whether Steam
  has additionally been told to open Big Picture via
  `HTPC_STEAM_BIGPICTURE=1` in `/run/cachyos-htpc/environment` rather than
  which unit is running.

This mapping is duplicated (not sourced from lib/gpu.sh) in three places
that must each keep working standalone: htpc-switch itself, and the
`htpc_session_unit_for` helper in lib/services.sh used by the installer's
own boot-configuration step. See htpc-switch's own header for why it
can't just source the project's lib/ tree.

Because "steam" and "desktop" can be the *same* unit on NVIDIA,
`htpc_current_session` cannot tell them apart just by checking which unit
is active in that case; it additionally reads `HTPC_STEAM_BIGPICTURE` from
the same environment file to disambiguate.

## Toggling Between Steam Gaming Mode and KDE Desktop on NVIDIA

When htpc-desktop.service is already running (regardless of which of the
two logical modes it's currently in), switching between "steam" and
"desktop" does **not** restart the session at all -- there would be
nothing to gain from bouncing an already-running KDE Plasma session (with
Steam already up in it) just to change whether Big Picture is open.
Instead, `htpc_bigpicture_toggle_only` detects this case and runs it
**in-process** (not via `systemd-run --user`): we are not stopping the
session, so there is no self-kill risk, and a transient user unit often
lacks `WAYLAND_DISPLAY`/`DISPLAY` from the live Plasma session -- which
made the Desktop shortcut look like a no-op. That path:

- Entering "steam" (including a second `htpc-switch steam` while already
  marked as Steam Gaming Mode): sets `HTPC_STEAM_BIGPICTURE=1` and opens
  Big Picture. Exiting Big Picture or quitting Steam does not change the
  marker, so a later Desktop shortcut / add-on click would otherwise look
  like "already running steam" and do nothing. How Steam is told to open
  Big Picture depends on whether it is still running, confirmed live:
  - Steam not running: `steam -bigpicture` (startup flag). Passing
    `steam://open/bigpicture` as the first launch argument instead showed
    Steam's "needs to be online" dialog.
  - Steam already running in desktop UI (user exited Big Picture):
    `steam steam://open/bigpicture`. A second `steam -bigpicture` only
    raises the existing desktop window and never switches back to Big
    Picture.
- Entering "desktop": sets `HTPC_STEAM_BIGPICTURE=0`. Nothing else happens -- closing
  Big Picture (or quitting Steam entirely) is deliberately not treated as
  a session-level event; see "Steam Gaming Mode" in
  [Session Services Specification](session-services-spec.md).

A transition into or out of "kodi" always goes through the normal
stop/start path regardless of GPU vendor, since Kodi is always its own
separate unit.

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
