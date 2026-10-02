#!/usr/bin/env python3
"""Exercise ARCONT's general bridge against the pinned real engine/providers."""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def variant(kind, *value):
    return {"$type": kind, "value": list(value)}


def reference(identifier):
    return {"$ref": identifier}


def authored_recipe():
    """Explicit workbench composition, not a text-to-map or random city service."""
    steps = []

    def new(identifier, klass=None, parent=None, script=None, name=None, **properties):
        step = {"op": "new", "id": identifier, "properties": properties}
        if klass: step["class"] = klass
        if parent: step["parent"] = parent
        if script: step["script"] = script
        if name: step["name"] = name
        steps.append(step)

    def call(target, method, *arguments, identifier=None):
        step = {"op": "call", "target": target, "method": method, "args": list(arguments)}
        if identifier: step["id"] = identifier
        steps.append(step)

    new("city", "Node3D", name="UrbanWorkbench")
    new("navigation", "NavigationRegion3D", parent="city", name="Navigation")
    new("navmesh", "NavigationMesh", agent_radius=0.4, agent_height=1.8,
        geometry_parsed_geometry_type=2, cell_size=0.3, cell_height=0.2)
    steps.append({"op": "set", "target": "navigation", "properties": {"navigation_mesh": reference("navmesh")}})
    new("pavement", "StandardMaterial3D", albedo_color=variant("Color", 0.15, 0.20, 0.23, 1), roughness=0.38)
    new("concrete", "StandardMaterial3D", albedo_color=variant("Color", 0.34, 0.39, 0.42, 1), roughness=0.82)
    new("bronze", "StandardMaterial3D", albedo_color=variant("Color", 0.62, 0.31, 0.14, 1), metallic=0.65, roughness=0.26)
    new("windows", "StandardMaterial3D", albedo_color=variant("Color", 0.10, 0.28, 0.37, 1), metallic=0.6, roughness=0.15,
        emission_enabled=True, emission=variant("Color", 0.05, 0.14, 0.19, 1), emission_energy_multiplier=0.7)
    new("neon", "StandardMaterial3D", albedo_color=variant("Color", 0.05, 0.72, 0.83, 1), emission_enabled=True,
        emission=variant("Color", 0.02, 0.65, 0.9, 1), emission_energy_multiplier=2.0)
    new("road", "StandardMaterial3D", albedo_color=variant("Color", 0.07, 0.09, 0.12, 1), roughness=0.24)

    def box(identifier, position, size, material, collision=False, name=None):
        new(identifier + "_mesh", "BoxMesh", size=variant("Vector3", *size))
        new(identifier, "MeshInstance3D", parent="navigation", name=name or identifier,
            mesh=reference(identifier + "_mesh"), material_override=reference(material), position=variant("Vector3", *position))
        if collision: call(identifier, "create_trimesh_collision")

    box("ground", [0, -0.2, 0], [40, 0.4, 40], "pavement", True, name="Ground")
    box("street", [0, 0.02, 8], [38, 0.04, 6], "road")
    box("west_building", [-13, 5, -6], [8, 10, 12], "concrete", True)
    box("east_building", [12, 7, -8], [10, 14, 10], "bronze", True)
    box("gallery", [0, 2.5, -13], [12, 5, 5], "concrete", True)
    box("canopy", [0, 4.8, -9.5], [12.6, 0.35, 3], "bronze")
    box("neon_sign", [0, 3.8, -10.42], [8, 0.45, 0.12], "neon")
    # Authored repeated architectural modules with every coordinate specified.
    for number, (x, y, z) in enumerate([(-13, 2, 0.03), (-13, 5, 0.03), (-13, 8, 0.03),
                                        (12, 2, -2.96), (12, 5, -2.96), (12, 8, -2.96), (12, 11, -2.96)]):
        box("window_%02d" % number, [x, y, z], [6, 1.6, 0.12], "windows")
    for number, x in enumerate([-15, -9, -3, 3, 9, 15]):
        box("lane_mark_%02d" % number, [x, 0.051, 8], [2.6, 0.025, 0.15], "concrete")

    new("scatter", parent="navigation", name="PocketTrees", script="res://addons/proton_scatter/src/scatter.gd",
        enabled=False, global_seed=713, dbg_disable_thread=True, force_rebuild_on_load=False,
        show_output_in_tree=True, enable_updates_in_game=True, render_mode=0)
    steps.append({"op": "set", "target": "scatter", "properties": {"Performance/use_chunks": False}})
    new("shape", parent="scatter", name="PlanterZone", script="res://addons/proton_scatter/src/scatter_shape.gd",
        position=variant("Vector3", 0, 0.2, -3))
    new("box_shape", script="res://addons/proton_scatter/src/shapes/box_shape.gd", size=variant("Vector3", 17, 0.05, 7))
    steps.append({"op": "set", "target": "shape", "properties": {"shape": reference("box_shape")}})
    new("item", parent="scatter", name="SourceAsset", script="res://addons/proton_scatter/src/scatter_item.gd",
        source=1, path="res://tests/fixtures/editor_asset.tscn", lod_generate=False, source_scale_multiplier=0.45)
    new("stack", script="res://addons/proton_scatter/src/stack/modifier_stack.gd")
    new("placements", script="res://addons/proton_scatter/src/modifiers/create_inside_random.gd", amount=24, restrict_height=True)
    call("stack", "add", reference("placements"))
    steps.append({"op": "set", "target": "scatter", "properties": {"modifier_stack": reference("stack")}})

    new("environment", "Environment", background_mode=1, background_color=variant("Color", 0.23, 0.34, 0.49, 1),
        ambient_light_source=3, ambient_light_color=variant("Color", 0.62, 0.72, 0.85, 1), ambient_light_energy=0.65)
    new("world_environment", "WorldEnvironment", parent="city", environment=reference("environment"))
    new("sun", "DirectionalLight3D", parent="city", rotation_degrees=variant("Vector3", -33, -32, 0),
        light_color=variant("Color", 1, 0.77, 0.52, 1), light_energy=1.5, shadow_enabled=True)
    new("accent", "OmniLight3D", parent="city", position=variant("Vector3", 0, 3.5, -8.5),
        light_color=variant("Color", 0.06, 0.64, 1, 1), light_energy=3.0, omni_range=12.0)
    new("camera", "Camera3D", parent="city", position=variant("Vector3", 32, 24, 32), fov=52.0)
    steps.append({"op": "script", "id": "audio_authored", "path": "res://tools/authoring_acceptance.gd", "args": {"stage": "audio"}})
    new("sound", "AudioStreamPlayer3D", parent="navigation", name="IndustrialHum", stream=reference("ambience_stream"),
        position=variant("Vector3", 0, 2, -9), unit_size=8.0, max_distance=40.0, volume_db=-12.0)
    steps.append({"op": "attach", "target": "city"})
    call("camera", "look_at", variant("Vector3", 0, 2.5, -3))
    steps.append({"op": "set", "target": "scatter", "properties": {"enabled": True}})
    steps.append({"op": "wait", "frames": 15})
    steps.append({"op": "describe", "target": "scatter", "properties": ["enabled", "render_mode", "global_seed"]})
    steps.append({"op": "script", "id": "acceptance", "path": "res://tools/authoring_acceptance.gd", "args": {"stage": "check"}})
    steps.append({"op": "ray", "id": "ground_ray", "from": variant("Vector3", 0, 4, 8), "to": variant("Vector3", 0, -2, 8), "require_hit": True})
    steps.append({"op": "inspect", "target": "pavement", "properties": ["roughness", "albedo_color"]})
    steps.append({"op": "save", "target": "pavement", "path": "materials/pavement.tres"})
    steps.append({"op": "save", "target": "city", "path": "scenes/urban_workbench.tscn"})
    steps.append({"op": "script", "id": "reopen", "path": "res://tools/authoring_acceptance.gd", "args": {"stage": "reopen"}})
    steps.append({"op": "profile", "id": "measurement", "frames": 30})
    return {"version": 1, "id": "urban_workbench", "description": "Authored native scene and real provider API acceptance workbench", "steps": steps}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write-example", action="store_true")
    parser.add_argument("--arcont", default=os.environ.get("ARCONT_ROOT"))
    args = parser.parse_args()
    if args.write_example:
        path = ROOT / "authoring/recipes/urban_workbench.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(authored_recipe(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(str(path))
        return
    if not args.arcont:
        raise SystemExit("ARCONT_ROOT or --arcont required")
    tool = Path(args.arcont).resolve() / "tools/godot_authoring_control.py"
    calls = []

    def control(operation, expected=True, **values):
        request = {"protocol_version": 1, "operation": operation, **values}
        process = subprocess.run([sys.executable, str(tool), "--project", str(ROOT)], input=json.dumps(request), text=True, capture_output=True, timeout=320)
        result = json.loads(process.stdout)
        calls.append({"operation": operation, "ok": result.get("ok"), "evidence": result.get("evidence", {}).get("directory")})
        if result.get("ok") is not expected or (process.returncode == 0) is not expected:
            raise AssertionError({"operation": operation, "error": result.get("error"), "details": result.get("details"), "evidence": result.get("evidence", {}).get("directory")})
        return result

    identifier = "urban_workbench"
    head = ROOT / "authoring/documents" / (identifier + ".json")
    if head.exists():
        raise SystemExit("Smoke document already exists; use a clean checkout")
    report_path = ROOT / ".arcont/authoring-smoke.json"
    try:
        control("capabilities")
        native = control("discover", options={"class": "AudioStreamPlayer3D"})
        assert any(m["name"] == "play" for m in native["api"]["methods"])
        provider = control("discover", options={"script": "res://addons/proton_scatter/src/scatter.gd"})
        assert any(m["name"] == "full_rebuild" for m in provider["api"]["methods"])
        recipe = json.loads((ROOT / "authoring/recipes/urban_workbench.json").read_text(encoding="utf-8"))
        dependency_paths = ["third_party/map_authoring.lock.json", "tools/authoring_acceptance.gd", "tests/fixtures/editor_asset.tscn"]
        recipe["dependencies"] = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in dependency_paths}
        options = {"render": True}
        dry = control("create", document_id=identifier, recipe=recipe, options=options)
        assert not dry["committed"] and not head.exists()
        created = control("create", document_id=identifier, recipe=recipe, options=options, dry_run=False)
        original = head.read_bytes()
        old_scene = ROOT / created["evidence"]["directory"] / "scenes/urban_workbench.tscn"
        old_hash = hashlib.sha256(old_scene.read_bytes()).hexdigest()
        control("patch", expected=False, document_id=identifier, if_revision="stale", patch=[], dry_run=False)
        invalid = copy.deepcopy(recipe)
        invalid["steps"].insert(5, {"op": "call", "target": "city", "method": "missing_provider_method"})
        control("replace", expected=False, document_id=identifier, if_revision=created["revision"], recipe=invalid, options=options, dry_run=False)
        assert head.read_bytes() == original
        changed = control("patch", document_id=identifier, if_revision=created["revision"], dry_run=False, options=options,
                          patch=[{"op": "replace", "path": "/steps/@pavement/properties/roughness", "value": 0.77}])
        assert hashlib.sha256(old_scene.read_bytes()).hexdigest() == old_hash
        reopened = next(s["value"] for s in changed["result"]["steps"] if s["id"] == "reopen")
        assert abs(reopened["reopened_material_roughness"] - 0.77) < 0.0001
        restored = control("restore", document_id=identifier, if_revision=changed["revision"], restore_revision=created["revision"], dry_run=False, options=options)
        assert restored["revision"] == created["revision"]
        evidence_recipe = copy.deepcopy(recipe)
        evidence_recipe["steps"].append({"op": "capture", "camera": "camera", "path": "urban_workbench.png"})
        evidence_recipe["steps"].append({"op": "call", "target": "camera", "method": "set_position", "args": [variant("Vector3", 18, 9, 16)]})
        evidence_recipe["steps"].append({"op": "call", "target": "camera", "method": "look_at", "args": [variant("Vector3", 0, 2.5, -9)]})
        evidence_recipe["steps"].append({"op": "capture", "camera": "camera", "path": "gallery_detail.png"})
        captured = control("replace", document_id=identifier, if_revision=created["revision"], recipe=evidence_recipe, options=options)
        assert not captured["committed"]
        directory = ROOT / captured["evidence"]["directory"]
        assert all((directory / name).stat().st_size > 1000 for name in ["urban_workbench.png", "gallery_detail.png", "audio/industrial_hum.wav"])
        # Exercise the real stdio process, including initialization and a tool call.
        messages = [{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "authoring-smoke", "version": "1"}}},
                    {"jsonrpc": "2.0", "method": "notifications/initialized"},
                    {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
                    {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "arcont_authoring", "arguments": {"protocol_version": 1, "operation": "inspect", "document_id": identifier}}}]
        mcp = subprocess.run([sys.executable, str(tool.with_name("godot_authoring_mcp.py")), "--project", str(ROOT)], input="".join(json.dumps(m) + "\n" for m in messages), text=True, capture_output=True, timeout=30)
        responses = [json.loads(line) for line in mcp.stdout.splitlines()]
        assert mcp.returncode == 0 and len(responses) == 3
        assert json.loads(responses[-1]["result"]["content"][0]["text"])["revision"] == created["revision"]
        acceptance = next(s["value"] for s in captured["result"]["steps"] if s["id"] == "reopen")
        report = {"ok": True, "engine": captured["result"]["engine"], "calls": calls, "acceptance": acceptance,
                  "captures_directory": str(directory.relative_to(ROOT)), "mcp_stdio_verified": True,
                  "limits": ["CPU software rendering in Linux CI; no Android or AAA art-quality claim"]}
        report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print("ARCONT_AUTHORING_SMOKE_OK " + json.dumps(report))
    except Exception:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps({"ok": False, "calls": calls}, indent=2))
        raise
    finally:
        head.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
