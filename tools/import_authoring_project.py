#!/usr/bin/env python3
"""Import resource caches before enabling plugins that preload textures."""
import argparse
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ERRORS = ("SCRIPT ERROR", "Parse Error", "Failed to load script", "Unable to load addon", "ERROR:")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    args = parser.parse_args()
    project = ROOT / "project.godot"
    original = project.read_bytes()
    text = original.decode()
    section = re.search(r"(?ms)^\[editor_plugins\]\s*\n(.*?)(?=^\[|\Z)", text)
    if section is None: raise SystemExit("editor_plugins section missing")
    disabled = re.sub(r"(?m)^enabled=PackedStringArray\([^\r\n]*\)(\r?)$", r"enabled=PackedStringArray()\1", section[1])
    bootstrap = text[:section.start(1)] + disabled + text[section.end(1):]
    if bootstrap == text: raise SystemExit("cannot temporarily disable editor plugins")
    def run(name, verbose=False):
        command = [args.godot, "--path", str(ROOT), "--editor", "--headless", "--import"]
        if verbose: command.append("--verbose")
        result = subprocess.run(command,
                                text=True, capture_output=True, timeout=180)
        log = result.stdout + result.stderr
        (ROOT / name).write_text(log)
        print(log, end="")
        if result.returncode or any(marker in log for marker in ERRORS):
            raise RuntimeError("Godot import failed; see " + name)
    try:
        project.write_bytes(bootstrap.encode())
        run("authoring-bootstrap-import.log")
    finally:
        project.write_bytes(original)
    try:
        run("authoring-import.log", verbose=True)
    finally:
        project.write_bytes(original)
    print("ARCONT_PLUGIN_IMPORT_OK source_configuration_restored=true")


if __name__ == "__main__": main()
