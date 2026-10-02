#!/usr/bin/env python3
"""Run the project-owned general Godot bridge; ARCONT controls publication."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def execute(payload):
    directory = Path(payload["output_directory"]).resolve()
    expected = (ROOT / ".arcont/runs").resolve()
    if expected not in directory.parents or not directory.is_dir():
        raise ValueError("output_directory must be a fresh ARCONT run bundle")
    request = directory / "engine-request.json"
    response = directory / "engine-response.json"
    request.write_text(json.dumps(payload, ensure_ascii=False, allow_nan=False), encoding="utf-8")
    options = payload.get("options", {})
    command = [os.environ.get("GODOT_BIN", "godot"), "--path", str(ROOT)]
    if payload["operation"] == "discover" or options.get("editor", False):
        command.append("--editor")
    if not options.get("render", False):
        command.append("--headless")
    command += ["--script", "res://tools/godot_authoring_worker.gd", "--", str(request), str(response)]
    run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=270)
    log = run.stdout + run.stderr
    (directory / "engine.log").write_text(log, encoding="utf-8")
    if run.returncode or any(marker in log for marker in ("SCRIPT ERROR", "Parse Error", "Failed to load script", "ERROR:")):
        return {"ok": False, "error": "Godot execution failed", "log": str(directory / "engine.log"), "details": log[-6000:]}
    if not response.is_file():
        return {"ok": False, "error": "Godot did not return a structured response", "log": str(directory / "engine.log")}
    result = json.loads(response.read_text(encoding="utf-8"))
    result["log"] = str(directory / "engine.log")
    return result


def main():
    try:
        result = execute(json.load(sys.stdin))
    except (ValueError, OSError, subprocess.SubprocessError, KeyError) as exc:
        result = {"ok": False, "error": str(exc)}
    print(json.dumps(result, ensure_ascii=False, allow_nan=False))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
