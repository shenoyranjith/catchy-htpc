# Session Lifecycle

## States

- Boot
- Kodi
- Steam Gaming Mode
- KDE Desktop
- Fatal Error

## Valid Transitions

Boot -> Kodi

Boot -> Desktop (boot-time fallback only, used when Kodi fails to start; not a user-facing command)

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

## Fatal Error

- Stop attempting to start any graphical session.
- Fall back to a plain TTY/getty login on tty1.
- Log the failure clearly.

## Rules

- Only one session may be active.
- All transitions go through the Session Manager.
- Kodi add-ons never launch applications directly.
