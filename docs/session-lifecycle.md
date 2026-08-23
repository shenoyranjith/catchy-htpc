# Session Lifecycle

## States

- Boot
- Kodi
- Steam Gaming Mode
- KDE Desktop
- Fatal Error

## Valid Transitions

Boot -> Kodi/Steam/Desktop, whichever was chosen at install time (see "Boot Configuration" in [Installer Specification](installer-spec.md)); exactly one of the three is ever enabled to start automatically.

Boot -> Desktop (boot-time fallback only, used when the enabled session was Kodi or Steam and it failed to start; not a user-facing command)

Boot -> Fatal Error (boot-time fallback only, used when the enabled session was Desktop and it failed to start; not a user-facing command)

Kodi -> Steam

Kodi -> Desktop

Steam -> Kodi

Steam -> Desktop

Desktop -> Kodi

Desktop -> Steam

## Invalid Transitions

Any request to enter the currently active session.

## Recovery

If Kodi fails to start, at boot or otherwise:
    Attempt to start KDE Desktop.

If Steam fails:
    Attempt to start KDE Desktop.

If KDE Desktop fails:
    Enter Fatal Error.

If Kodi or Steam exits on its own (its own Exit/Quit, or a crash) with no
switch already in progress:
    Automatically fall back to KDE Desktop, rather than leaving tty1
    blank or relaunching the session that just exited. Applies whether
    that session was reached via a switch or was itself the boot session
    (see "Boot Configuration" in [Installer Specification](installer-spec.md)).
    See the exit fallback in [Session Manager Specification](session-manager-spec.md).

If KDE Desktop exits on its own (logging out, or a crash) with no switch
already in progress:
    Automatically enter Fatal Error, the same as if it had failed to start
    in the first place -- Desktop is already the last resort, so there is
    nowhere else to fall back to. Applies whether Desktop was reached via
    a switch or was itself the boot session. See the exit fallback in
    [Session Manager Specification](session-manager-spec.md).

## Fatal Error

- Stop attempting to start any graphical session.
- Fall back to a plain TTY/getty login on tty1.
- Log the failure clearly.

## Rules

- Only one session may be active.
- All transitions go through the Session Manager.
- Kodi add-ons never launch applications directly.
