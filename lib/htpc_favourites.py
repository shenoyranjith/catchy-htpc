#!/usr/bin/env python3
"""Idempotently merges entries into a Kodi favourites.xml file.

Used by the installer to seed shortcuts for the Steam Gaming Mode and
Desktop Mode Program add-ons without disturbing any favourites the user
already has. See installer-spec.md.

Usage:
    htpc_favourites.py <favourites.xml path> <name>=<RunScript command> ...

Example:
    htpc_favourites.py /home/user/.kodi/userdata/favourites.xml \\
        "Steam Gaming Mode"=RunScript(script.htpc.steam) \\
        "Desktop Mode"=RunScript(script.htpc.desktop)

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


def has_command(root: ET.Element, command: str) -> bool:
    return any(elem.text == command for elem in root.findall("favourite"))


def merge_entries(root: ET.Element, entries: list[tuple[str, str]]) -> int:
    added = 0
    for name, command in entries:
        if has_command(root, command):
            continue
        favourite = ET.SubElement(root, "favourite", {"name": name})
        favourite.text = command
        added += 1
    return added


def write_favourites(root: ET.Element, path: Path) -> None:
    ET.indent(root, space="    ")
    tree = ET.ElementTree(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    tree.write(path, encoding="unicode", xml_declaration=False)
    path.write_text(path.read_text() + "\n")


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 1

    path = Path(argv[0])
    try:
        entries = [parse_entry(raw) for raw in argv[1:]]
        root = load_favourites(path)
        added = merge_entries(root, entries)
        if added:
            write_favourites(root, path)
    except (ValueError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"Added {added} new favourite(s) to {path}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
