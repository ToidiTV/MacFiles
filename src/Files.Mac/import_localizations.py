#!/usr/bin/env python3
"""Reuse the checked-out Files RESW translations for shared native UI vocabulary."""
from pathlib import Path
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / "Files.App" / "Strings"
DESTINATION = ROOT / "Sources" / "FilesApp" / "Resources"


def read(path):
    return {node.attrib["name"]: node.findtext("value", "") for node in ET.parse(path).getroot().findall("data")}


english = read(SOURCE / "en-US" / "Resources.resw")
aliases = {"Trash": "Recycle Bin", "New window": "New window", "Date modified": "Date modified",
           "Icons": "Large icons", "Columns": "Columns", "Gallery": "Gallery", "Libraries": "Libraries"}
aliases.update({'Bulk rename…': 'BulkRename', 'Choose custom icon…': 'ChooseCustomIcon', 'Clone…': 'Clone', 'Command palette…': 'CommandPalette', 'Compress…': 'Compress', 'Create library…': 'Create Library', 'Customize toolbar…': 'CustomizeToolbar', 'Edit tags…': 'EditTags', 'Flatten folder…': 'FlattenFolder', 'Keyboard shortcuts…': 'KeyboardShortcuts', 'Loading…': 'Loading...', 'New folder…': 'NewFolder', 'Open with…': 'OpenWith', 'Permissions…': 'Permissions', 'Pin to sidebar': 'Pin to Sidebar', 'Properties…': 'Properties', 'Rename…': 'Rename', 'Reopen closed tab': 'ReopenClosedTab', 'Settings…': 'Settings', 'Share…': 'Share', 'Toggle details pane': 'ToggleDetailsPane', 'Username': 'UserName'})
language_count = 0
for path in sorted(SOURCE.glob("*/Resources.resw")):
    translated = read(path)
    locale = "en" if path.parent.name == "en-US" else path.parent.name
    values = {}
    for key, value in english.items():
        translation = translated.get(key, value)
        values[key] = translation
        if value and "{" not in value and "\n" not in value:
            values.setdefault(value, translation)
    for native, original in aliases.items():
        if original in values:
            values[native] = values[original]
    native_file = ROOT / "Localization" / "translations" / (locale + ".json")
    if native_file.exists():
        native = json.loads(native_file.read_text())
        values.update({key: entry["text"] for key, entry in native.items()})
    override_file = ROOT / "Localization" / "overrides" / (locale + ".json")
    if override_file.exists(): values.update(json.loads(override_file.read_text()))
    target = DESTINATION / (locale + ".lproj")
    target.mkdir(parents=True, exist_ok=True)
    text = "/* Files Community translations; original license notices are bundled. */\n"
    text += "\n".join(json.dumps(key, ensure_ascii=False) + " = " + json.dumps(value, ensure_ascii=False) + ";"
                       for key, value in sorted(values.items())) + "\n"
    (target / "Localizable.strings").write_bytes(text.replace("\n", "\r\n").encode())
    language_count += 1
print(f"Imported {language_count} locales from Files resources")

from Localization.import_plurals import build as build_plurals
build_plurals()
