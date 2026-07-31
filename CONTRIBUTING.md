# Contributing

- Follow the architecture documents before writing code.
- Keep code modular.
- Update documentation with behaviour changes.
- Test on a clean CachyOS installation whenever possible.
- Preserve backwards compatibility where reasonable.

## Testing notes

- **Close SSH sessions before testing polkit-guarded actions in a graphical
  session.** `polkitd` resolves the session of D-Bus-activated processes
  (e.g. `plasmashell`, which runs under `user@<uid>.service`, not a
  session scope) by cgroup, and this resolution fails for such processes.
  When it fails, polkit appears to fall back to *some other* session
  belonging to the same user rather than reliably picking the active
  graphical one. If you have an SSH shell open as the same target user
  while testing `htpc-desktop.service`, actions like NetworkManager's
  Wi-Fi scan/network-control can get misattributed to that (inactive) SSH
  session instead of the active seat0 session, so `allow_active=yes`
  policy rules never match and you get a real, repeated authentication
  prompt that re-appears even after entering the correct password. This
  is not a bug in `htpc-desktop.service` itself: it reproduces even under
  the stock `plasmalogin` session, and disappears once no other session
  exists for that user. Fully exit any SSH terminal logged in as the
  target user before testing graphical, polkit-guarded actions.
