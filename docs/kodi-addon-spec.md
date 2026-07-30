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

Add-on discoverability (installation into the addons directory, menu placement, favourites) is handled by the installer, not by the add-ons themselves. See installer-spec.md.
