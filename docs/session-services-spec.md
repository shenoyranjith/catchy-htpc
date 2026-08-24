# Session Services Specification

Defines the systemd services backing each session described in [Session Lifecycle](session-lifecycle.md).

## Units

- htpc-kodi.service
- htpc-steam.service (AMD only -- see "Steam Gaming Mode" below)
- htpc-desktop.service

These are system-level systemd units. No display manager is used to start them or to switch between them.

On NVIDIA hardware, htpc-steam.service does not exist: Steam Gaming Mode
runs inside htpc-desktop.service's own KDE Plasma session instead. See
"Steam Gaming Mode" below and lib/gpu.sh for why.

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
  - **NVIDIA:** Kodi's GBM backend aborts during splash-screen `CWinSystemGbm::FlipPage` on current nvidia-open branches (`std::queue::back()` on an empty buffer queue). Confirmed live on cold boot even with multi-second delays between attempts, so this is not a settle race. Launching Kodi from Plasma's app menu works because that path is `WINDOWING=wayland` under kwin. The Kodi session therefore starts a kiosk `kwin_wayland` (no plasmashell) on tty1 and runs Kodi as a Wayland client under it -- the same graphics path that already works -- pinning `KWIN_DRM_DEVICES` to the NVIDIA DRM node on hybrid AMD iGPU + NVIDIA boxes. Still an exclusive `htpc-kodi.service` session (Conflicts= with Desktop/Steam), not folded into Plasma the way Steam Gaming Mode is on NVIDIA.
- Project-owned launch script rather than a patch to kodi-standalone, since a Kodi package update would silently overwrite the latter.

## Steam Gaming Mode

How this is actually realized depends on the GPU vendor detected at
install time (`htpc_gpu_vendor_install` in lib/gpu.sh, persisted to
`/etc/cachyos-htpc/gpu-vendor`): AMD gets a dedicated gamescope-based
htpc-steam.service, unchanged from this project's original design; NVIDIA
gets no separate unit at all, folded into htpc-desktop.service instead.

### AMD: htpc-steam.service

- Packages: gamescope-session-cachyos, lib32-gamescope (official CachyOS repository).
- Also installs mangohud and lib32-mangohud: these provide `mangoapp`, which is what actually renders the Quick Access Menu's "Performance Overlay" (FPS/CPU/GPU stats) under gamescope-session-cachyos. gamescope-session-cachyos passes gamescope the flag that enables this overlay, but without mangoapp installed there's nothing for that flag to render, so the overlay slider silently does nothing. Not a hard dependency of gamescope-session-cachyos itself (CachyOS bundles it separately, in its own `cachyos-gaming-applications` meta-package), so it's listed here explicitly.
- Whether this unit is enabled to start automatically at boot depends on the choice made during installation, same as Kodi above -- see "Boot Configuration" in [Installer Specification](installer-spec.md).
- `ExecStopPost=/usr/local/bin/htpc-switch --exit-fallback desktop`: lands on KDE Desktop, per "Shared Behaviour" above.
- ExecStart runs the package's start-gamescope-session entrypoint as the existing user.
- The package's own SDDM-oriented autologin unit, cachyos-gamescope-autologin.service (a systemd --user unit), is masked for the existing user. It is not needed here and would otherwise attempt to modify SDDM configuration when the session exits.
- The package's steamos-session-select script (/usr/bin/steamos-session-select) is replaced with a thin wrapper (bin/htpc-steamos-session-select in this repo):
  - gamescope -> htpc-switch steam
  - plasma -> htpc-switch kodi
  - persistent / oneshot -> no-op (SDDM autologin preference modes; not applicable here)
- This makes Steam's own "Switch to Desktop" button return to Kodi, since Kodi is the primary interface. No SDDM interaction occurs at any point.
- Steam invokes this script via pkexec (pre-authorized passwordlessly for any user by gamescope-session-cachyos's own polkit policy), so it runs as root; htpc-switch itself handles dropping back to the existing user. See [Session Manager Specification](session-manager-spec.md).
- The original script is preserved via a `.htpc-backup` copy for the uninstaller to restore. Since /usr/bin/steamos-session-select is owned by the gamescope-session-cachyos package, a future package update may silently overwrite the wrapper back to upstream; re-running the installer's steam service step re-applies it.
- None of the above are installed at all on NVIDIA.

### NVIDIA: folded into htpc-desktop.service

gamescope has a confirmed, actively-tracked upstream regression affecting
its Steam overlay rendering in embedded DRM mode on current NVIDIA driver
branches (ValveSoftware/gamescope#1964, #2171) -- reproduced live as
display corruption whenever the Steam Overlay is toggled while a game is
running. Rather than depend on gamescope at all on NVIDIA hardware, "Steam
Gaming Mode" there is redefined as: the existing htpc-desktop.service KDE
Plasma session, with Steam autostarting and, only in this mode,
immediately being told to open Big Picture. This also sidesteps a second,
unrelated problem hit while gamescope was still in the loop here: Steam's
own "requires user namespaces" / bwrap sandboxing failures turned out to
be sensitive to exactly how the session hosting it was started (see git
history on this file for the investigation) -- letting KDE's own,
well-trodden Plasma startup launch Steam exactly the way a normal desktop
login would avoids all of that by construction.

- No htpc-steam.service unit exists on NVIDIA at all; htpc-switch resolves
  "steam" directly to htpc-desktop.service (see [Session Manager Specification](session-manager-spec.md)).
- None of gamescope-session-cachyos, lib32-gamescope, mangohud, or
  lib32-mangohud are installed (no gamescope Quick Access Menu Performance
  Overlay exists in this mode), cachyos-gamescope-autologin.service is not
  masked, and /usr/bin/steamos-session-select is not touched -- none of
  that package's own files exist on this system in the first place.
- `~/.config/autostart/htpc-steam-autostart.desktop` (installed by
  `htpc_steam_autostart_install` in lib/gpu.sh) is a KDE autostart entry
  that runs bin/htpc-steam-autostart once, automatically, every time this
  session's own Plasma starts fresh. It sources
  `/run/cachyos-htpc/environment` (see below) and either runs
  `steam` (Desktop Mode) or `steam -bigpicture` (Steam Gaming Mode).
  Autostart always uses `-bigpicture` rather than `steam://open/bigpicture`
  because the protocol URL requires Steam to already be signed in online
  -- confirmed live, a cold boot with the URI showed Steam's "needs to be
  online" dialog and never opened Big Picture. Re-entering Big Picture
  later while Steam is already running is handled by htpc-switch instead
  (see "Toggling Between Steam Gaming Mode and KDE Desktop on NVIDIA" in
  [Session Manager Specification](session-manager-spec.md)).
- `/run/cachyos-htpc` is created on every boot, owned by the existing
  user, by a tmpfiles.d drop-in (`/etc/tmpfiles.d/cachyos-htpc.conf`,
  installed by `htpc_steam_bigpicture_runtime_dir_install`) -- before any
  htpc-*.service unit starts, and cleared exactly once per real reboot.
  `environment` inside it holds `HTPC_STEAM_BIGPICTURE=1` (Steam Gaming
  Mode, open Big Picture) or `=0` (Desktop Mode). htpc-switch always
  writes a definite value here immediately before starting or toggling
  into this session (see [Session Manager Specification](session-manager-spec.md)).
- `bin/htpc-steam-bigpicture-boot-marker`, installed as
  htpc-desktop.service's own `ExecStartPre` (see below), derives this
  environment file from the installer-recorded `BOOT_SESSION` the *one*
  time it can possibly be missing: a cold boot, before htpc-switch has run
  at all. In every other case htpc-switch has already written a definite
  value, so this script leaves it alone.
- Quitting Steam entirely, or just closing/minimizing Big Picture, is
  deliberately treated as nothing more than an ordinary app in an ordinary
  KDE Desktop session -- no lifecycle hook of any kind ties Steam's own
  process to this session's. An earlier NVIDIA design (Big Picture running
  under its own dedicated, dynamically-torn-down session unit) repeatedly
  left Plasma stuck or unresponsive across exit/re-entry; not attempting
  any of that in the first place avoids all of it.
- Switching between Steam Gaming Mode and KDE Desktop while this session
  is already running does not restart Plasma at all -- see "Toggling
  Between Steam Gaming Mode and KDE Desktop on NVIDIA" in [Session Manager Specification](session-manager-spec.md).

## KDE Desktop (htpc-desktop.service)

- Uses the existing CachyOS KDE Plasma installation already present on the system.
- `ExecStartPre=-/usr/local/bin/htpc-steam-bigpicture-boot-marker`: only meaningful on NVIDIA, where this same unit also backs Steam Gaming Mode -- see "NVIDIA: folded into htpc-desktop.service" above. No-op on AMD. The leading `-` ignores any failure here rather than blocking Plasma from starting.
- ExecStart runs startplasma-wayland directly as the existing user.
- No SDDM or other display manager is involved.
- Whether this unit is enabled to start automatically at boot depends on the choice made during installation, same as Kodi above -- see "Boot Configuration" in [Installer Specification](installer-spec.md).
- `ExecStopPost=/usr/local/bin/htpc-switch --exit-fallback fatal`: unlike Kodi/Steam, lands on Fatal Error rather than KDE Desktop -- Desktop is already the last resort, so there is nowhere else to fall back to. See "Exit Fallback" in [Session Manager Specification](session-manager-spec.md). On NVIDIA this applies equally whether the session was in Steam Gaming Mode or Desktop Mode at the time -- both are this same unit, and quitting Steam itself never stops it (see above).

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
