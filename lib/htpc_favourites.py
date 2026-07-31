#!/usr/bin/env python3
"""Idempotently merges entries into, or removes entries from, a Kodi
favourites.xml file.

Used by the installer to seed shortcuts for the Steam Gaming Mode and
Desktop Mode Program add-ons, plus Kodi built-ins like PlayDVD /
EjectTray(), without disturbing any favourites the user already has. Used
by the uninstaller (in --remove mode) to remove exactly those seeded
entries again, by name, while preserving everything else. See
installer-spec.md, uninstaller-spec.md, and kodi-addon-spec.md.

Usage:
    htpc_favourites.py <favourites.xml path> <name>=<command> ...
    htpc_favourites.py --remove <favourites.xml path> <name> ...

Example:
    htpc_favourites.py /home/user/.kodi/userdata/favourites.xml \\
        "Steam Gaming Mode"=RunScript(script.htpc.steam) \\
        "Desktop Mode"=RunScript(script.htpc.desktop) \\
        "Play Disc"=PlayDVD(1) \\
        "Eject Tray"=EjectTray(1)

    htpc_favourites.py --remove /home/user/.kodi/userdata/favourites.xml \\
        "Steam Gaming Mode" "Desktop Mode" "Play Disc" "Eject Tray"

Exits non-zero (without modifying the file) if it exists but is not
parseable as XML, so a corrupt favourites.xml is never silently clobbered.
"""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def parse_entry(raw: str) -> tuple[str, str]:
    name, sep, command = raw.partition("=")
    if not sep:
        raise ValueError(f"Malformed entry (expected NAME=COMMAND): {raw!r}")
    return name, command


def load_favourites(path: Path) -> ET.Element:
    if not path.exists():
        return ET.Element("favourites")

    try:
        tree = ET.parse(path)
    except ET.ParseError as exc:
        raise RuntimeError(f"{path} exists but is not valid XML: {exc}") from exc

    root = tree.getroot()
    if root.tag != "favourites":
        raise RuntimeError(f"{path} does not have a <favourites> root element.")
    return root


def merge_entries(root: ET.Element, entries: list[tuple[str, str]]) -> int:
    """Add or update favourites. Matches by name first so a renamed
    built-in command (e.g. PlayDisc -> PlayDVD) updates in place instead
    of leaving a stale entry and adding a duplicate label. Also collapses
    any leftover duplicates for the same name -- e.g. from an older,
    buggy version of this script -- down to one, self-healing on rerun.

    Deliberately uses list comprehensions rather than `elem or other_elem`
    for the "did we find one" check: an ElementTree Element with no child
    elements (true of every <favourite>, which only has text) is falsy,
    so that pattern silently discards a real match.
    """
    changed = 0
    for name, command in entries:
        matches = [
            elem for elem in root.findall("favourite") if elem.get("name") == name
        ]
        if not matches:
            matches = [
                elem for elem in root.findall("favourite") if elem.text == command
            ]

        if matches:
            keep, *duplicates = matches
            for duplicate in duplicates:
                root.remove(duplicate)
                changed += 1
            if keep.get("name") != name or keep.text != command:
                keep.set("name", name)
                keep.text = command
                changed += 1
            continue

        favourite = ET.SubElement(root, "favourite", {"name": name})
        favourite.text = command
        changed += 1
    return changed


def remove_entries(root: ET.Element, names: list[str]) -> int:
    """Remove favourites by name. Reverses merge_entries for uninstall:
    only entries whose name exactly matches one this project seeds are
    removed, leaving any other favourite (including ones the user added
    themselves) untouched.
    """
    removed = 0
    for name in names:
        for elem in [e for e in root.findall("favourite") if e.get("name") == name]:
            root.remove(elem)
            removed += 1
    return removed


def write_favourites(root: ET.Element, path: Path) -> None:
    ET.indent(root, space="    ")
    tree = ET.ElementTree(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    tree.write(path, encoding="unicode", xml_declaration=False)
    path.write_text(path.read_text() + "\n")


def main(argv: list[str]) -> int:
    remove_mode = bool(argv) and argv[0] == "--remove"
    if remove_mode:
        argv = argv[1:]

    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 1

    path = Path(argv[0])
    try:
        if remove_mode:
            if not path.exists():
                print(f"{path} does not exist; nothing to remove.")
                return 0
            root = load_favourites(path)
            changed = remove_entries(root, argv[1:])
        else:
            entries = [parse_entry(raw) for raw in argv[1:]]
            root = load_favourites(path)
            changed = merge_entries(root, entries)

        if changed:
            write_favourites(root, path)
    except (ValueError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    verb = "Removed" if remove_mode else "Updated"
    print(f"{verb} {changed} favourite(s) in {path}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
