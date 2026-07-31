"""Program add-on: switches from Kodi to Steam Gaming Mode via htpc-switch.

Contains no transition logic of its own; see session-manager-spec.md and
kodi-addon-spec.md.
"""

from __future__ import annotations

import subprocess

import xbmcgui

HTPC_SWITCH = "/usr/local/bin/htpc-switch"
TARGET = "steam"
ADDON_NAME = "Steam Gaming Mode"


def main() -> None:
    result = subprocess.run(
        [HTPC_SWITCH, TARGET],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        message = (
            result.stderr.strip() or result.stdout.strip() or "htpc-switch failed."
        )
        xbmcgui.Dialog().notification(ADDON_NAME, message, xbmcgui.NOTIFICATION_ERROR)


if __name__ == "__main__":
    main()
