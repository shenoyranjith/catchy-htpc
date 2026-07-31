# Kodi Add-on Specification

Provide Program Add-ons only.

Required Add-ons

- Steam Gaming Mode
- Desktop Mode

Each add-on:

- Contains minimal Python code.
- Invokes htpc-switch.
- Displays errors returned by the Session Manager.
- Contains no transition logic.
- Makes no assumptions about the active Kodi skin.

htpc-switch only reports synchronous validation errors (invalid transition,
already running, failure to dispatch); it hands the actual switch off to a
detached process that outlives the caller (see session-manager-spec.md), so
"displays errors returned by the Session Manager" only applies to that
synchronous result, not to anything that might go wrong after the switch is
already underway.

Add-on discoverability (installation into the addons directory, menu placement, favourites) is handled by the installer, not by the add-ons themselves. See installer-spec.md. In practice this means favourites.xml only: the default Estuary skin's home menu already includes a Favourites entry, and editing a specific skin's home menu directly would be fragile and skin-version-dependent, which would work against "makes no assumptions about the active Kodi skin" above.

The installer also seeds two non-add-on favourites that call Kodi built-ins:

- Play Disc -> `PlayDVD(1)`
- Eject Tray -> `EjectTray(1)`

These exist because not every skin exposes disc play/eject outside Estuary;
Favourites is the skin-agnostic place to keep them reachable.

Both are seeded with a dummy `(1)` parameter rather than bare/empty parens.
Kodi's favourites loader (`CFavouritesURL::Parse`) rejects any non-whitelisted
built-in with zero parameters, resolving it to an empty target path instead
of erroring -- confirmed live, this made Play Disc appear but do nothing,
and made Eject Tray not appear at all (Kodi de-duplicates favourites by
resolved path, and it collided with Play Disc's empty one). Both built-ins
ignore unrecognized params, so the dummy value is harmless. See the comment
above `htpc_kodi_favourites_seed` in lib/kodi.sh for detail.

## Implementation

- Add-on IDs: script.htpc.steam (Steam Gaming Mode), script.htpc.desktop (Desktop Mode). Standard Kodi Program Add-on layout (addon.xml + default.py), xbmc.python.script extension point.
- default.py runs htpc-switch via subprocess.run, capturing stderr/stdout. On a non-zero exit, shows the captured message via xbmcgui.Dialog().notification(); on success, does nothing (Kodi is about to lose DRM master to the new session anyway).
