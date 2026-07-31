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

Add-on discoverability (installation into the addons directory, menu placement, favourites) is handled by the installer, not by the add-ons themselves. See installer-spec.md.
