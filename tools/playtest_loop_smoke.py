#!/usr/bin/env python3
"""Create -> reopen -> input replay -> diagnose -> patch -> replay -> restore."""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

from godot_authoring_smoke import variant, reference

ROOT = Path(__file__).resolve().parents[1]


def authored_recipe():
    recipe = json.loads((ROOT / "authoring/recipes/urban_roads.json").read_text())
    recipe["id"] = "urban_playtest"
    recipe["description"] = "Editable workshop on existing roads; input-driven entrance/stair/interaction acceptance"
    end = next(index for index, step in enumerate(recipe["steps"]) if step.get("id") == "roads") + 1
    steps = recipe["steps"][:end]
    # The workshop occupies this former tree lot; keep the imported prop outside its walls.
    for step in steps:
        if step.get("id") == "tree_2":
            step["properties"]["position"] = variant("Vector3", -20, 0, 40)

    def new(identifier, klass=None, parent=None, name=None, script=None, **properties):
        step = {"op": "new", "id": identifier, "name": name or identifier, "properties": properties}
        if klass: step["class"] = klass
        if script: step["script"] = script
        if parent: step["parent"] = parent
        steps.append(step)

    def call(target, method, *args):
        steps.append({"op": "call", "target": target, "method": method, "args": list(args)})

    steps.append({"op": "set", "target": "navmesh", "properties": {"geometry_collision_mask": 5,
                  "agent_max_climb": 0.25, "cell_height": 0.1, "cell_size": 0.15}})
    new("workshop", "Node3D", "navigation", "Workshop")
    for identifier, color in [("workshop_wall", (0.29, 0.34, 0.39)), ("workshop_floor", (0.50, 0.53, 0.52)),
                               ("workshop_trim", (0.96, 0.47, 0.09)), ("workshop_glass", (0.10, 0.58, 0.64))]:
        new(identifier, "StandardMaterial3D", albedo_color=variant("Color", *color, 1), roughness=0.72)

    def box(identifier, position, size, material="workshop_wall", collision=True, parent="workshop", name=None):
        new(identifier + "_mesh", "BoxMesh", size=variant("Vector3", *size))
        new(identifier, "MeshInstance3D", parent, name, mesh=reference(identifier + "_mesh"),
            position=variant("Vector3", *position), material_override=reference(material))
        call(identifier, "set_meta", "source_id", identifier)
        if collision: call(identifier, "create_trimesh_collision")

    box("approach", [-30, 0.075, 9], [4, 0.15, 30], "workshop_floor")
    box("ground_floor", [-30, 0.075, 34], [12, 0.15, 20], "workshop_floor")
    box("front_left", [-33.75, 2.9, 24], [4.5, 5.5, 0.4])
    box("front_right", [-26.25, 2.9, 24], [4.5, 5.5, 0.4])
    box("door_lintel", [-30, 4.1, 24], [3, 3.1, 0.4])
    box("west_wall", [-36.2, 2.9, 34], [0.4, 5.5, 20.8])
    box("east_wall", [-23.8, 2.9, 34], [0.4, 5.5, 20.8])
    box("back_wall", [-30, 2.9, 44.2], [12.4, 5.5, 0.4])
    box("upper_landing", [-30, 2.45, 39.4], [12, 0.2, 9.2], "workshop_floor")
    box("roof_cutaway", [-30, 5.75, 42], [12.4, 0.2, 4.4])
    for index in range(12):
        height = (index + 1) * 0.2
        box("stair_%02d" % index, [-30, 0.15 + height / 2, 30 + (index + 0.5) * 0.4],
            [3, height, 0.4], "workshop_floor")
        box("stair_nose_%02d" % index, [-30, 0.155 + height, 30 + index * 0.4 + 0.03],
            [3, 0.02, 0.06], "workshop_trim", False)
    box("entry_trim", [-30, 2.6, 23.74], [3.3, 0.12, 0.15], "workshop_trim", False)
    box("landing_trim", [-30, 2.57, 34.85], [12, 0.03, 0.12], "workshop_trim", False)
    box("console_desk", [-28.8, 2.9, 38], [0.9, 0.7, 0.7], "workshop_wall")
    box("terminal", [-28.8, 3.45, 38], [0.75, 0.4, 0.1], "workshop_glass", False, name="Terminal")
    new("door_blocker", "StaticBody3D", "workshop", "DoorBlocker", position=variant("Vector3", -30, 1.35, 24))
    call("door_blocker", "set_meta", "source_id", "door_blocker")
    new("door_shape", "BoxShape3D", size=variant("Vector3", 3, 2.4, 0.4))
    new("door_collision", "CollisionShape3D", "door_blocker", "Collision", shape=reference("door_shape"), disabled=False)
    new("door_box_mesh", "BoxMesh", size=variant("Vector3", 3, 2.4, 0.4))
    new("door_mesh", "MeshInstance3D", "door_blocker", "Barrier", mesh=reference("door_box_mesh"),
        material_override=reference("workshop_trim"), visible=True)
    new("actors", "Node3D", "world", "Actors")
    new("explorer", parent="actors", name="Explorer", script="res://tools/playtest_explorer.gd",
        position=variant("Vector3", -30, 0.35, 8), speed=4.0, step_height=0.25)
    new("explorer_shape", "CapsuleShape3D", radius=0.35, height=1.8)
    new("explorer_collision", "CollisionShape3D", "explorer", "Collision", shape=reference("explorer_shape"),
        position=variant("Vector3", 0, 0.9, 0))
    new("explorer_mesh", "CapsuleMesh", radius=0.35, height=1.8)
    new("explorer_visual", "MeshInstance3D", "explorer", "Body", mesh=reference("explorer_mesh"),
        material_override=reference("workshop_glass"), position=variant("Vector3", 0, 0.9, 0))
    new("cameras", "Node3D", "world", "Cameras")
    for identifier, name, position, target in [
        ("exterior_camera", "Exterior", [-48, 15, 15], [-30, 2.0, 31]),
        ("entry_camera", "Entrance", [-34, 3.4, 18], [-30, 1.3, 25]),
        ("landing_camera", "Landing", [-35.5, 5.3, 36], [-29, 3.0, 38])]:
        new(identifier, "Camera3D", "cameras", name, position=variant("Vector3", *position), fov=65.0)
        call(identifier, "look_at", variant("Vector3", *target))
    new("interior_light", "OmniLight3D", "workshop", "InteriorLight", position=variant("Vector3", -30, 4.9, 32),
        light_color=variant("Color", 1, 0.77, 0.48, 1), light_energy=2.0, omni_range=14.0, shadow_enabled=True)
    steps.append({"op": "script", "id": "saved", "path": "res://tools/authoring_road_network.gd", "args": {"stage": "save", "target": "world"}})
    for name in ["editable", "baked"]:
        path = "scenes/urban_roads_" + name + ".tscn"
        steps.append({"op": "load", "id": name + "_scene", "path": {"$output": path}})
        steps.append({"op": "save", "target": name + "_scene", "path": path})
    steps.append({"op": "capture", "camera": "exterior_camera", "path": "workshop_exterior.png"})
    recipe["steps"] = steps
    return recipe


def authored_session():
    return {"version": 1, "id": "workshop_route", "actor": "Actors/Explorer", "seed": 41,
            "stop_on_failure": True, "commands": [
                {"id": "settle", "frames": 30, "actions": {}, "capture": "Cameras/Exterior"},
                {"id": "entrance", "frames": 270, "actions": {"arcont_forward": 1}, "capture": "Cameras/Entrance",
                 "expect": {"position": [-30, 0.15, 26], "tolerance_m": 0.8}},
                {"id": "stairs", "frames": 180, "actions": {"arcont_forward": 1}, "capture": "Cameras/Landing",
                 "expect": {"position": [-30, 2.55, 38], "tolerance_m": 1.0, "height_min": 2.4}},
                {"id": "interact", "frames": 3, "actions": {"arcont_interact": 1}, "capture": "Cameras/Landing",
                 "expect": {"interactions_min": 1}},
                {"id": "release", "frames": 2, "actions": {}}]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write-example", action="store_true")
    parser.add_argument("--arcont", default=os.environ.get("ARCONT_ROOT"))
    args = parser.parse_args()
    if args.write_example:
        for path, value in [("authoring/recipes/urban_playtest.json", authored_recipe()), ("authoring/scenarios/workshop_route.json", authored_session())]:
            target = ROOT / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(json.dumps(value, indent=2) + "\n")
        return
    if not args.arcont: raise SystemExit("ARCONT_ROOT required")
    tool = Path(args.arcont).resolve() / "tools/godot_authoring_control.py"
    recipe = json.loads((ROOT / "authoring/recipes/urban_playtest.json").read_text())
    dependencies = ["third_party/map_authoring.lock.json", "tools/authoring_road_network.gd", "tools/godot_playtest_runner.gd", "tools/playtest_explorer.gd", "assets/urban/sources.lock.json"]
    recipe["dependencies"] = {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in dependencies}
    session = json.loads((ROOT / "authoring/scenarios/workshop_route.json").read_text())
    head = ROOT / "authoring/documents/urban_playtest.json"
    if head.exists(): raise SystemExit("use clean checkout: urban_playtest document exists")
    options = {"render": True, "audio_driver": "Dummy"}
    calls = []
    canonical = {path: path.read_bytes() for path in (ROOT / "maps").glob("*.json")}
    report = {"ok": False, "calls": calls}

    def control(operation, expected=True, **values):
        request = {"protocol_version": 1, "operation": operation, "document_id": "urban_playtest", **values}
        run = subprocess.run([sys.executable, str(tool), "--project", str(ROOT)], input=json.dumps(request), text=True, capture_output=True, timeout=320)
        result = json.loads(run.stdout)
        calls.append({"operation": operation, "ok": result.get("ok"), "passed": result.get("passed"), "evidence": result.get("evidence", {}).get("directory")})
        if result.get("ok") is not expected:
            raise AssertionError({"operation": operation, "result": result})
        return result

    def play(created):
        result = control("playtest", if_revision=created["revision"], scene="scenes/urban_roads_editable.tscn", session=session, options=options)
        observed = result["report"]
        print("ARCONT_PLAYTEST_OBSERVED " + json.dumps({key: observed[key] for key in
              ["passed", "physics_frames", "input_released", "final_state", "navigation"]}), flush=True)
        return result

    def contacts(result):
        trace = ROOT / result["evidence"]["directory"] / "playtest/trace.jsonl"
        samples = [json.loads(line) for line in trace.read_text().splitlines()]
        assert len(samples) == result["report"]["physics_frames"]
        assert [sample["state"]["tick"] for sample in samples] == list(range(1, len(samples) + 1))
        return {contact["source_id"] for sample in samples for contact in sample["state"]["contacts"]}

    try:
        created = control("create", recipe=recipe, dry_run=False, options=options)
        original_head = head.read_bytes()
        original_scene = ROOT / created["evidence"]["directory"] / "scenes/urban_roads_editable.tscn"
        original_hash = hashlib.sha256(original_scene.read_bytes()).hexdigest()
        blocked = play(created)
        assert blocked["passed"] is False and blocked["report"]["input_released"]
        assert "door_blocker" in contacts(blocked)
        assert blocked["report"]["final_state"]["position"][2] < 24
        assert head.read_bytes() == original_head
        control("playtest", expected=False, if_revision="stale", scene="scenes/urban_roads_editable.tscn", session=session, options=options)
        corrected = control("patch", if_revision=created["revision"], dry_run=False, options=options, patch=[
            {"op": "replace", "path": "/steps/@door_collision/properties/disabled", "value": True},
            {"op": "replace", "path": "/steps/@door_mesh/properties/visible", "value": False}])
        repaired_head = head.read_bytes()
        repaired = play(corrected)
        assert repaired["passed"] and repaired["report"]["input_released"]
        assert repaired["report"]["final_state"]["interactions"] == 1
        assert repaired["report"]["final_state"]["physical_step_ups"] >= 10
        assert repaired["report"]["navigation"]["reaches_terminal"]
        repaired_contacts = contacts(repaired)
        assert any(identifier.startswith("stair_") for identifier in repaired_contacts)
        repeated = play(corrected)
        assert repeated["passed"] and repeated["report"]["input_released"]
        for first, second in zip(repaired["report"]["checkpoints"], repeated["report"]["checkpoints"]):
            assert first["state"]["tick"] == second["state"]["tick"]
            assert max(abs(a - b) for a, b in zip(first["state"]["position"], second["state"]["position"])) < 0.001
        assert head.read_bytes() == repaired_head
        restored = control("restore", if_revision=corrected["revision"], restore_revision=created["revision"], dry_run=False, options=options)
        restored_play = play(restored)
        assert restored_play["passed"] is False and "door_blocker" in contacts(restored_play)
        assert hashlib.sha256(original_scene.read_bytes()).hexdigest() == original_hash
        assert all(path.read_bytes() == before for path, before in canonical.items())
        report.update({"ok": True, "blocked": blocked["report"], "corrected": repaired["report"], "repeated": repeated["report"],
                       "restored": restored_play["report"], "blocked_bundle": blocked["evidence"]["directory"],
                       "corrected_bundle": repaired["evidence"]["directory"], "accepted_scene_bundle": corrected["evidence"]["directory"],
                       "repeat_position_tolerance_m": 0.001, "same_session_reused": True, "document_unchanged_during_playtest": True,
                       "original_bundle_immutable": True, "canonical_maps_unchanged": True,
                       "engine": created["result"]["engine"], "limits": ["Input-driven fixture controller, not production combat/AI", "Linux runner; no target-device performance or cross-platform determinism claim"]})
        print("ARCONT_PLAYTEST_LOOP_OK " + json.dumps(report))
    finally:
        path = ROOT / ".arcont/playtest-loop-smoke.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(report, indent=2) + "\n")
        head.unlink(missing_ok=True)


if __name__ == "__main__": main()
