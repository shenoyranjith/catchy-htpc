# Session Services Specification

Defines the systemd services backing each session described in [Session Lifecycle](session-lifecycle.md).

## Units

- htpc-kodi.service
- htpc-steam.service
- htpc-desktop.service

These are system-level systemd units. No display manager is used to start them or to switch between them.

## Shared Behaviour

- Run as the existing user determined by the installer (see [Installer Specification](installer-spec.md)).
- PAMName=login, establishing a full logind session equivalent to a normal graphical login.
- TTYPath=/dev/tty1.
- Conflicts= and After= getty@tty1.service.
- Conflicts= the other two htpc-*.service units, so systemd itself enforces single-session exclusivity in addition to htpc-switch.
- Only htpc-switch starts or stops these units during normal operation.
- Restart=on-success, so an app-initiated clean exit (Kodi's own "Exit", quitting Steam outright) relaunches that session instead of stranding the user on a blank tty1. This does not conflict with htpc-switch: systemd never applies Restart= to a unit stopped via `systemctl stop`, which is how htpc-switch always stops the outgoing session. A genuine crash (non-zero exit or signal) is not restarted, to avoid masking real failures behind a restart loop.

## Kodi (htpc-kodi.service)

- Package: kodi (official repository).
- Runs Kodi standalone with GBM windowing, so Kodi owns DRM/KMS directly without a separate compositor.
- Runs as the existing user, using that user's own Kodi profile and data.
- SupplementaryGroups=input render: Kodi's GBM windowing opens /dev/input/event* directly via libinput rather than acquiring devices through logind's D-Bus hand-off (the mechanism KDE and gamescope use), so it needs real group membership to read them. Granted here rather than via a persistent usermod so it only applies to this session and is fully reverted by removing this unit.
- Enabled by default so it starts automatically at boot.

## Steam Gaming Mode (htpc-steam.service)

- Packages: gamescope-session-cachyos, lib32-gamescope (official CachyOS repository).
- Also installs mangohud and lib32-mangohud: these provide `mangoapp`, which is what actually renders the Quick Access Menu's "Performance Overlay" (FPS/CPU/GPU stats) under gamescope-session-cachyos. gamescope-session-cachyos passes gamescope the flag that enables this overlay, but without mangoapp installed there's nothing for that flag to render, so the overlay slider silently does nothing. Not a hard dependency of gamescope-session-cachyos itself (CachyOS bundles it separately, in its own `cachyos-gaming-applications` meta-package), so it's listed here explicitly.
- ExecStart runs the package's start-gamescope-session entrypoint as the existing user.
- The package's own SDDM-oriented autologin unit, cachyos-gamescope-autologin.service (a systemd --user unit), is masked for the existing user. It is not needed here and would otherwise attempt to modify SDDM configuration when the session exits.
- The package's steamos-session-select script (/usr/bin/steamos-session-select) is replaced with a thin wrapper (bin/htpc-steamos-session-select in this repo):
  - gamescope -> htpc-switch steam
  - plasma -> htpc-switch kodi
  - persistent / oneshot -> no-op (SDDM autologin preference modes; not applicable here)
- This makes Steam's own "Switch to Desktop" button return to Kodi, since Kodi is the primary interface. No SDDM interaction occurs at any point.
- Steam invokes this script via pkexec (pre-authorized passwordlessly for any user by gamescope-session-cachyos's own polkit policy), so it runs as root; htpc-switch itself handles dropping back to the existing user. See [Session Manager Specification](session-manager-spec.md).
- The original script is preserved via a `.htpc-backup` copy for the uninstaller to restore. Since /usr/bin/steamos-session-select is owned by the gamescope-session-cachyos package, a future package update may silently overwrite the wrapper back to upstream; re-running the installer's steam service step re-applies it.

## KDE Desktop (htpc-desktop.service)

- Uses the existing CachyOS KDE Plasma installation already present on the system.
- ExecStart runs startplasma-wayland directly as the existing user.
- No SDDM or other display manager is involved.

## Desktop Application Shortcuts

Kodi has its own Program Add-ons for switching sessions (see
[Kodi Add-on Specification](kodi-addon-spec.md)), and Steam has its own "Switch to Desktop" button (see
above), but KDE Desktop had no equivalent way back until this was found
missing during testing: nothing on the desktop invoked htpc-switch at
all. Two `.desktop` entries are installed for the existing user, in both
of the two places a KDE user would look for them:

- `~/.local/share/applications/`, showing up in Plasma's application
  launcher (Kickoff/KRunner) like any other installed app.
- The user's actual Desktop folder (resolved via `xdg-user-dir DESKTOP`,
  falling back to `~/Desktop`), as real desktop icons. These copies are
  installed with the executable bit set, which is what KDE uses to
  decide a `.desktop` file on the Desktop is trusted enough to launch
  directly instead of showing an interstitial "this file has not been
  marked as trusted" prompt.

Both entries:

- "HTPC: Switch to Kodi" -> `htpc-switch kodi`
- "HTPC: Steam Gaming Mode" -> `htpc-switch steam`

Named with an "HTPC:" prefix to be clearly distinguishable from the
CachyOS-provided kodi.desktop and steam.desktop entries already present
on the system, which launch Kodi/Steam directly rather than through
htpc-switch and are not touched by this project.

## Accessibility Bus Cleanup

Found during live testing, unrelated to any specific session's own spec but
affecting all of them: Steam's Chromium-based UI (and, less reliably,
some Plasma helper processes) connect to the AT-SPI accessibility bus on
startup, which D-Bus/systemd activates as a transient per-connection unit
(`dbus-:N.NN-org.a11y.atspi.Registry@0.service`, running
`at-spi2-registryd`). Nothing ever tears these down again once that
connection's session ends -- confirmed live, 17 had accumulated after an
afternoon of session switching, and would keep growing indefinitely until
reboot. This appliance has no accessibility/screen-reader use case, so two
things are done about it:

- `Environment=NO_AT_BRIDGE=1` on all three htpc-*.service units, plus the
  same variable in a systemd `environment.d` drop-in
  (`/etc/environment.d/90-cachyos-htpc.conf`, installed by
  `htpc_environment_no_at_bridge_install` in lib/services.sh) for the
  target user's systemd --user manager, so D-Bus-activated helpers that
  aren't direct children of the session's own unit (Plasma's kwallet,
  powerdevil helpers, etc.) also see it. This variable is meant to tell
  GTK/Qt to skip connecting to the accessibility bus in the first place.
  `environment.d` is normally only read once at the user manager's own
  startup; since sessions here share one long-lived manager across
  switches rather than getting a fresh one per login, installing this
  drop-in also runs `systemctl --user daemon-reload` (with
  `XDG_RUNTIME_DIR` set explicitly, since plain `runuser` from root does
  not set it) so it takes effect immediately.
- This alone was confirmed live to be insufficient: Steam's Chromium-based
  UI connects to the accessibility bus regardless of `NO_AT_BRIDGE`. So
  `htpc-switch` also actively reaps any leftover
  `dbus-*-org.a11y.atspi.Registry@0.service` units as part of every
  switch (`htpc_cleanup_accessibility_bus`), right after stopping the
  outgoing session -- by that point it has had its whole lifetime to
  leak one, so there's no race with a not-yet-connected new session. This
  is the actual guaranteed fix, regardless of whatever ends up
  triggering the connection; `NO_AT_BRIDGE` is kept alongside it as a
  reasonable attempt at prevention rather than just cleanup.

Confirmed live: count went from 17 accumulated leaks down to zero after
this fix, across a full round of session switching.

## Display Manager

- Whichever display manager is configured (discovered via the display-manager.service alias at install time, not hardcoded to any specific one) is disabled and masked during install.
- Its unit name and prior enabled/disabled state are recorded so the uninstaller can restore it.
