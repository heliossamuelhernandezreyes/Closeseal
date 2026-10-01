#!/usr/bin/env python3
"""Game-owned adapter for ARCONT editor control. No generative service."""
from __future__ import annotations
import hashlib
import importlib.util
import json
import math
import os
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / (name + ".py"))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def validate_state(state):
    if not isinstance(state, dict) or not isinstance(state.get("map"), dict):
        return {"ok": False, "errors": ["state.map must be an object"], "warnings": []}
    data = state["map"]
    errors, warnings = module("validate_maps").validate(data, Path(data.get("id", "map") + ".json"))
    physical = state.get("physical")
    if physical is not None:
        with tempfile.TemporaryDirectory() as directory:
            a, b = Path(directory) / "map.json", Path(directory) / "physical.json"
            a.write_text(json.dumps(data, allow_nan=False), encoding="utf-8")
            b.write_text(json.dumps(physical, allow_nan=False), encoding="utf-8")
            pe, pw = module("validate_physical_world").validate(a, b)
            errors.extend(pe)
            warnings.extend(pw)
    return {"ok": not errors, "errors": errors, "warnings": warnings, "physical_profile_present": physical is not None}


def analyze(state):
    data = state["map"]
    lengths = {}
    for route in data.get("routes", []):
        points = route["points"]
        lengths[route["id"]] = sum(math.dist(a[:3], b[:3]) for a, b in zip(points, points[1:]))
    authoring = data.get("authoring", {})
    return {"ok": True, "route_lengths_m": lengths, "counts": {"bases": len(data.get("bases", [])), "objectives": len(data.get("objectives", [])), "routes": len(lengths), "regions": len(data.get("regions", [])), "structures": len(authoring.get("structure_guides", [])), "scatter_zones": len(authoring.get("scatter_zones", [])), "landforms": len(authoring.get("terrain", {}).get("landforms", []))}, "map_area_m2": data["bounds"]["width"] * data["bounds"]["depth"], "limits": ["geometric analysis; gameplay balance and device performance require playtests"]}


def engine(operation, state, options):
    godot = os.environ.get("GODOT_BIN", "godot")
    digest = hashlib.sha256(json.dumps(state, sort_keys=True, allow_nan=False).encode()).hexdigest()
    directory = ROOT / ".mapforge" / "evidence" / state["map"]["id"] / digest / (operation + "-" + uuid.uuid4().hex)
    directory.mkdir(parents=True, exist_ok=True)
    request = directory / "request.json"
    request.write_text(json.dumps({"operation": operation, "state": state, "options": options}, allow_nan=False), encoding="utf-8")
    response = directory / "response.json"
    response.unlink(missing_ok=True)
    command = [godot, "--path", str(ROOT)]
    if operation != "capture":
        command.extend(["--editor", "--headless"])
    command.extend(["--script", "res://tools/map_forge_control_worker.gd", "--", str(request), str(response)])
    run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=200)
    (directory / "godot.log").write_text(run.stdout + run.stderr, encoding="utf-8")
    fatal = any(x in run.stdout + run.stderr for x in ("SCRIPT ERROR", "Parse Error", "Failed to load script"))
    if run.returncode or fatal or not response.exists():
        structured = json.loads(response.read_text(encoding="utf-8")) if response.exists() else None
        diagnostic = [line for line in (run.stdout + run.stderr).splitlines() if any(token in line for token in ("SCRIPT ERROR", "ERROR:", "MAP_FORGE_CONTROL_RESULT"))]
        return {"ok": False, "error": "Godot control worker failed", "worker_result": structured, "exit_code": run.returncode, "log": str(directory / "godot.log"), "details": "\n".join(diagnostic)[:3000]}
    result = json.loads(response.read_text(encoding="utf-8"))
    result["evidence_directory"] = str(directory)
    return result


def execute(request):
    state, operation = request.get("state"), request.get("operation")
    validation = validate_state(state)
    if not validation["ok"] or operation == "validate":
        return validation
    if operation == "analyze":
        return analyze(state)
    if operation in ("materialize", "capture", "edit"):
        return engine(operation, state, request.get("options", {}))
    return {"ok": False, "error": "unsupported adapter operation"}


def main():
    try:
        result = execute(json.loads(sys.stdin.read()))
    except (ValueError, TypeError, KeyError, AttributeError, OSError, subprocess.SubprocessError) as exc:
        result = {"ok": False, "errors": [str(exc)]}
    print(json.dumps(result, ensure_ascii=False, allow_nan=False))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
