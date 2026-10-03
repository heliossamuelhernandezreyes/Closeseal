#!/usr/bin/env python3
"""Verify real production-player input replay through pinned ARCONT control."""
import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arcont", type=Path, required=True)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    project = args.project.resolve()
    tool = [sys.executable, str(args.arcont.resolve() / "tools/godot_authoring_control.py"), "--project", str(project)]
    recipe = json.loads((project / "authoring/recipes/shooter_third_person.json").read_text())
    session = json.loads((project / "authoring/scenarios/shooter_third_person.json").read_text())
    calls = []
    def control(operation, **values):
        request = {"protocol_version": 1, "operation": operation, "document_id": recipe["id"], **values}
        run = subprocess.run(tool, input=json.dumps(request), text=True, capture_output=True, timeout=300)
        result = json.loads(run.stdout)
        calls.append({"operation": operation, "ok": result.get("ok"), "passed": result.get("passed")})
        if run.returncode or not result.get("ok"):
            raise RuntimeError({"operation": operation, "error": result.get("error"), "details": result.get("details")})
        return result
    control("discover", options={"class": "SpringArm3D"})
    document = project / "authoring/documents/shooter_third_person.json"
    if document.exists():
        before = control("inspect")
        control("replace", if_revision=before["revision"], recipe=recipe, dry_run=False, options={"audio_driver": "Dummy"})
    else:
        control("create", recipe=recipe, dry_run=False, options={"audio_driver": "Dummy"})
    accepted = control("inspect")
    original = document.read_bytes()
    canonical = (project / "maps/nexo_combat_01.json").read_bytes()
    results = []
    for repeat in range(2):
        replay = control("playtest", if_revision=accepted["revision"], if_bundle=accepted["last_build"]["directory"],
                         scene="scenes/nexo_third_person.tscn", session=session, options={"audio_driver": "Dummy"})
        if not replay.get("passed") or not replay["report"]["input_released"]:
            raise RuntimeError(replay.get("report", replay))
        states = {step["id"]: step["state"] for step in replay["report"]["checkpoints"]}
        if states["cover_settle"].get("movement_state") != "cover" or not states["cover_settle"].get("crouched"):
            raise RuntimeError({"cover_state": states["cover_settle"]})
        if states["vault_midpoint"].get("movement_state") != "vault" or states["land"].get("vault_aborted"):
            raise RuntimeError({"vault_state": states["vault_midpoint"], "land": states["land"]})
        results.append(replay["report"])
    if document.read_bytes() != original or (project / "maps/nexo_combat_01.json").read_bytes() != canonical:
        raise RuntimeError("replay changed accepted source")
    positions = [r["final_state"]["position"] for r in results]
    if sum((a-b)**2 for a,b in zip(*positions)) > 0.001**2:
        raise RuntimeError({"reopened_positions_differ": positions})
    report = {"ok": True, "calls": calls, "reopened_replays": 2, "ticks": results[0]["physics_frames"],
              "final_position": positions[0], "source_map_sha256": hashlib.sha256(canonical).hexdigest(),
              "replay_reports": results, "limits": ["bounded production-player replay; not Android FPS or full gameplay coverage"]}
    output = project / ".arcont/shooter-authoring-smoke.json"
    output.write_text(json.dumps(report, indent=2))
    print(json.dumps({key:report[key] for key in ["ok", "reopened_replays", "ticks", "final_position"]}))


if __name__ == "__main__": main()
