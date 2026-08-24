# Session Services Specification

Defines the systemd services backing each session described in [Session Lifecycle](session-lifecycle.md).

## Units

- htpc-kodi.service
- htpc-steam.service
- htpc-desktop.service

These are system-level systemd units. No display manager is used to start them or to switch between them.

How Steam Gaming Mode is realized depends on the GPU vendor (AMD:
dedicated htpc-steam.service + start-gamescope-session; NVIDIA: nested
gamescope Deck UI inside htpc-desktop.service). See "Steam Gaming Mode"
below and lib/gpu.sh.

## Shared Behaviour

- Run as the existing user determined by the installer (see [Installer Specification](installer-spec.md)).
- PAMName=login, establishing a full logind session equivalent to a normal graphical login.
- TTYPath=/dev/tty1.
- Conflicts= and After= getty@tty1.service.
- Conflicts= the other two htpc-*.service units, so systemd itself enforces single-session exclusivity in addition to htpc-switch.
- Only htpc-switch starts or stops these units during normal operation.
- All three use Restart=no, plus their own `ExecStopPost=/usr/local/bin/htpc-switch --exit-fallback <target>`: an app-initiated clean exit (quitting Steam outright, logging out of Plasma, Kodi's own Exit) or a genuine crash lands on a useful fallback -- KDE Desktop for Kodi/Steam, Fatal Error for Desktop -- rather than relaunching the session that just exited or stranding the user on a blank tty1. This does not conflict with htpc-switch: `ExecStopPost` runs as part of *every* stop of the unit, including the one htpc-switch's own worker issues when deliberately switching away from it, so the fallback has to (and does) detect and skip that case. See "Exit Fallback" in [Session Manager Specification](session-manager-spec.md) for exactly how, and each unit's own `ExecStopPost` comment below for its specific target.

## Kodi (htpc-kodi.service)

- Package: kodi (official repository).
- Runs as the existing user, using that user's own Kodi profile and data.
- SupplementaryGroups=input render: needed for the AMD GBM path (Kodi opens `/dev/input/event*` via libinput rather than logind's D-Bus hand-off). Harmless on the NVIDIA Wayland path. Granted here rather than via a persistent usermod so it only applies to this session and is fully reverted by removing this unit.
- Whether this unit is enabled to start automatically at boot (as opposed to htpc-steam.service or htpc-desktop.service) depends on the choice made during installation -- see "Boot Configuration" in [Installer Specification](installer-spec.md). Exactly one of the three is ever enabled at a time.
- `ExecStopPost=/usr/local/bin/htpc-switch --exit-fallback desktop`: lands on KDE Desktop, per "Shared Behaviour" above.
- ExecStart runs `bin/htpc-kodi-launch` (installed to `/usr/local/bin`) instead of the vendored `/usr/bin/kodi-standalone` directly. How it actually starts Kodi depends on the GPU vendor recorded at install time (`/etc/cachyos-htpc/gpu-vendor`):
  - **AMD:** `WINDOWING=gbm` so Kodi owns DRM/KMS directly, with no separate compositor. Same clean-exit retry convention as kodi-standalone (exit 0 or 64-66 stops retrying; anything else is retried up to 3 times), but with a real delay between attempts (8s by default) instead of near-instant ones -- after a compositor teardown, Kodi's GBM first frame present has been observed to fail and instant retries reproduced it every time.
  - **NVIDIA:** Kodi's GBM backend aborts during splash-screen `CWinSystemGbm::FlipPage` on current nvidia-open branches (`std::queue::back()` on an empty buffer queue). Confirmed live on cold boot even with multi-second delays between attempts, so this is not a settle race. Launching Kodi from Plasma's app menu works because that path is `WINDOWING=wayland` under kwin. The Kodi session therefore starts a kiosk `kwin_wayland` (no plasmashell) on tty1 and runs Kodi as a Wayland client under it -- the same graphics path that already works -- pinning `KWIN_DRM_DEVICES` to the NVIDIA DRM node on hybrid AMD iGPU + NVIDIA boxes. Still an exclusive `htpc-kodi.service` session (Conflicts= with Desktop/Steam).
- Project-owned launch script rather than a patch to kodi-standalone, since a Kodi package update would silently overwrite the latter.

## Steam Gaming Mode

How this is actually realized depends on the GPU vendor detected at
install time (`htpc_gpu_vendor_install` in lib/gpu.sh, persisted to
`/etc/cachyos-htpc/gpu-vendor`).

`/usr/bin/steamos-session-select` is always the project's thin wrapper
(bin/htpc-steamos-session-select):

- gamescope -> htpc-switch steam
- plasma -> NVIDIA: htpc-switch desktop (same Plasma session); AMD: htpc-switch kodi
- persistent / oneshot -> no-op (SDDM autologin preference modes; not applicable here)

Steam may invoke this script via pkexec; htpc-switch handles dropping back
to the existing user. See [Session Manager Specification](session-manager-spec.md).
On AMD the original gamescope-session-cachyos script is backed up for the
uninstaller; on NVIDIA the wrapper is installed fresh (no prior package file).

### AMD: htpc-steam.service + start-gamescope-session

- Packages: gamescope-session-cachyos, lib32-gamescope, mangohud, lib32-mangohud (mangoapp for the QAM Performance Overlay).
- Dedicated `htpc-steam.service` (Conflicts= with Kodi/Desktop). Whether it is enabled to start automatically at boot depends on the choice made during installation -- see "Boot Configuration" in [Installer Specification](installer-spec.md).
- `ExecStopPost=/usr/local/bin/htpc-switch --exit-fallback desktop`.
- ExecStart runs `bin/htpc-steam-launch`, which execs `/usr/bin/start-gamescope-session`.
- `Delegate=yes`: Steam's pressure-vessel/bwrap needs user namespaces inside the service cgroup.
- The package's SDDM-oriented autologin unit, cachyos-gamescope-autologin.service, is masked for the existing user.
- Steam's "Switch to Desktop" returns to Kodi (primary interface).
- A future gamescope-session-cachyos package update may overwrite steamos-session-select; re-running the installer re-applies the wrapper.

### NVIDIA: nested gamescope inside htpc-desktop.service

Exclusive DRM `gamescope` under `htpc-steam.service` failed Steam's
pressure-vessel/bwrap user-namespace check on this hardware (Steam exits
immediately; gamescope then crashes). The same `gamescope … -- steam
-steamdeck` command works when nested under Plasma -- matching the
console-proven path. So NVIDIA keeps the v1.0.1 "same Plasma session"
model, but launches Deck UI via gamescope instead of `steam -bigpicture`.

- No `htpc-steam.service` on NVIDIA; htpc-switch resolves "steam" to
  `htpc-desktop.service`.
- Packages: `gamescope`, `lib32-gamescope`.
- `bin/htpc-steamdeck-launch` quits any running Steam/gamescope first
  (Deck UI will not start cleanly over a live desktop Steam client), then
  runs nested `gamescope -f -e -- steam -steamdeck`.
- `HTPC_STEAM_BIGPICTURE=1` in `/run/cachyos-htpc/environment` means Gaming
  Mode (name kept for compatibility); `=0` is Desktop Mode.
- Autostart / boot-marker seed that marker; Desktop↔Steam toggles
  in-process without restarting Plasma.
- Steam's "Switch to Desktop" (`steamos-session-select plasma`) returns to
  Desktop Mode in the same Plasma session (not Kodi).

## KDE Desktop (htpc-desktop.service)

- Uses the existing CachyOS KDE Plasma installation already present on the system.
- ExecStart runs startplasma-wayland directly as the existing user.
- No SDDM or other display manager is involved.
- Whether this unit is enabled to start automatically at boot depends on the choice made during installation, same as Kodi above -- see "Boot Configuration" in [Installer Specification](installer-spec.md).
- On NVIDIA this unit also backs Steam Gaming Mode (nested gamescope Deck UI). `ExecStartPre` runs `htpc-steam-bigpicture-boot-marker` so a cold boot with `BOOT_SESSION=steam` seeds `HTPC_STEAM_BIGPICTURE=1` before Plasma starts; KDE autostart then launches `htpc-steamdeck-launch`.
- `ExecStopPost=/usr/local/bin/htpc-switch --exit-fallback fatal`: unlike Kodi/Steam, lands on Fatal Error rather than KDE Desktop -- Desktop is already the last resort, so there is nowhere else to fall back to. See "Exit Fallback" in [Session Manager Specification](session-manager-spec.md).

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
