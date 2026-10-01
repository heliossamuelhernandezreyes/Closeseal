#!/usr/bin/env python3
"""Exercise the public editor interface, including a deliberately authored ramp.

This is a control test, not a map generator. Every coordinate below is explicit.
"""
import argparse
import copy
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--arcont", default=os.environ.get("ARCONT_ROOT"))
    parser.add_argument("--engine", action="store_true")
    args = parser.parse_args()
    if not args.arcont:
        raise SystemExit("--arcont or ARCONT_ROOT is required")
    tool = Path(args.arcont).resolve() / "tools/map_forge_control.py"
    map_id = "control_authored_demo"
    calls = []

    def control(operation, expected=True, **values):
        request = {"protocol_version": 1, "operation": operation, **values}
        run = subprocess.run([sys.executable, str(tool), "--project", str(ROOT)], input=json.dumps(request), capture_output=True, text=True, timeout=240)
        result = json.loads(run.stdout)
        assert result.get("ok") is expected, result
        assert (run.returncode == 0) is expected, run.stderr
        calls.append({"operation": operation, "ok": result["ok"]})
        return result

    control("capabilities")
    base = control("inspect", map_id="competitive_lab_01")["state"]
    state = copy.deepcopy(base)
    state["map"]["id"] = map_id
    state["map"]["display_name"] = "Editor control — deliberately authored geometry"
    state["physical"]["map_id"] = map_id
    state["physical"]["source_of_truth"] = "maps/" + map_id + ".json"
    state["map"]["authoring"]["geometry"] = [{"id": "authored_ramp", "position": [0, 0, 9], "vertices": [[-7, 0, -3], [-7, 0, 3], [7, 4, 3], [7, 4, -3]], "indices": [0, 1, 2, 0, 2, 3], "material": "ancient_gold", "collision": True}]
    state["map"]["authoring"]["instances"] = [{"id": "placed_asset", "scene": "res://tests/fixtures/editor_asset.tscn", "position": [8, 1.5, 10], "rotation_degrees": [0, 35, 0], "scale": [1, 1, 1]}]
    try:
        dry = control("create", map_id=map_id, state=state)
        assert not dry["committed"] and not (ROOT / "maps" / (map_id + ".json")).exists()
        created = control("create", map_id=map_id, state=state, dry_run=False)
        control("analyze", map_id=map_id)
        control("patch", expected=False, map_id=map_id, if_revision="stale", patch=[], dry_run=False)
        control("patch", expected=False, map_id=map_id, if_revision=created["revision"], patch=[{"op": "replace", "path": "/map/authoring/geometry/@authored_ramp/indices/0", "value": 999}], dry_run=False)
        assert control("inspect", map_id=map_id)["revision"] == created["revision"]
        changed = control("patch", map_id=map_id, if_revision=created["revision"], patch=[{"op": "replace", "path": "/map/authoring/geometry/@authored_ramp/position", "value": [0, 0, 12]}, {"op": "replace", "path": "/map/authoring/instances/@placed_asset/rotation_degrees/1", "value": 75}], dry_run=False)
        if args.engine:
            built = control("materialize", map_id=map_id)
            assert built["navigation"]["polygons"] > 0
            assert built["physical"]["materialized_collision_bodies"] >= 8
            captured = control("capture", map_id=map_id, options={"views": ["tactical", "north", "east", "top"]})
            assert captured["visual_stats"]["custom_meshes"] == 1
            assert captured["visual_stats"]["asset_instances"] == 1
            assert len(captured["images"]) == 4 and all(Path(p).stat().st_size > 1000 for p in captured["images"])
        restored = control("restore", map_id=map_id, if_revision=changed["revision"], restore_revision=created["revision"], dry_run=False)
        assert restored["revision"] == created["revision"]
        output = ROOT / ".mapforge" / "control-smoke.json"
        output.parent.mkdir(exist_ok=True)
        output.write_text(json.dumps({"ok": True, "engine_tested": args.engine, "calls": calls}, indent=2))
        print("MAP_FORGE_CONTROL_SMOKE_OK " + json.dumps({"operations_exercised": len(calls), "engine_tested": args.engine}))
    finally:
        for path in [ROOT / "maps" / (map_id + ".json"), ROOT / "maps/physical" / (map_id + ".json")]:
            path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
