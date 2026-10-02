#!/usr/bin/env python3
"""Operate pinned RoadGenerator through ARCONT; verify actual scene output."""
import argparse
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

from godot_authoring_smoke import variant, reference

ROOT = Path(__file__).resolve().parents[1]


def authored_recipe():
    def point(identifier, position, tangent, handle=22):
        return {"id": identifier, "position": position, "tangent": tangent,
                "handle_in": handle, "handle_out": handle}
    network = {"version": 1, "roads": [
        {"id": "boulevard", "lanes": ["reverse", "reverse", "forward", "forward"],
         "lane_width": 3.5, "shoulder_width": 1.2, "thickness": 0.3, "density": 1.5,
         "points": [point("west_entry", [-110, 0.08, -20], [1, 0, 0]),
                    point("west_bend", [-55, 0.08, -20], [1, 0, 0.7]),
                    point("central_crossing", [0, 0.08, 12], [1, 0, 0]),
                    point("east_bend", [55, 0.08, 12], [1, 0, -0.7]),
                    point("east_exit", [110, 0.08, -20], [1, 0, 0])]},
        {"id": "flyover", "lanes": ["reverse", "forward"], "lane_width": 3.5,
         "shoulder_width": 0.8, "thickness": 0.6, "density": 1.5,
         "points": [point("south_entry", [0, 0.08, -100], [0, 0, 1], 18),
                    point("south_deck", [0, 8.08, -40], [0, 0, 1], 18),
                    point("north_deck", [0, 8.08, 45], [0, 0, 1], 24),
                    point("north_exit", [0, 0.08, 105], [0, 0, 1], 18)]}]}
    steps = []
    def new(identifier, klass, parent=None, name=None, **properties):
        step = {"op": "new", "id": identifier, "class": klass, "properties": properties}
        if parent: step["parent"] = parent
        if name: step["name"] = name
        steps.append(step)
    def call(target, method, *args):
        steps.append({"op": "call", "target": target, "method": method, "args": list(args)})
    new("world", "Node3D", name="UrbanRoads")
    new("navigation", "NavigationRegion3D", "world", "Navigation")
    new("navmesh", "NavigationMesh", agent_radius=0.45, agent_height=1.8, agent_max_climb=0.35,
        geometry_parsed_geometry_type=1, geometry_collision_mask=4, cell_size=0.25, cell_height=0.2)
    steps.append({"op": "set", "target": "navigation", "properties": {"navigation_mesh": reference("navmesh")}})
    new("scenery", "Node3D", "world", "Scenery")
    new("concrete", "StandardMaterial3D", albedo_color=variant("Color", 0.44, 0.46, 0.43, 1), roughness=0.88)
    new("ground_material", "StandardMaterial3D", albedo_color=variant("Color", 0.32, 0.38, 0.31, 1), roughness=1.0)
    def box(identifier, pos, size, material="concrete", collision=False):
        new(identifier + "_mesh", "BoxMesh", size=variant("Vector3", *size))
        new(identifier, "MeshInstance3D", "scenery", mesh=reference(identifier + "_mesh"),
            position=variant("Vector3", *pos), material_override=reference(material))
        if collision: call(identifier, "create_trimesh_collision")
    box("district_ground", [0, -0.25, 0], [250, 0.5, 250], "ground_material", True)
    for i, z in enumerate([-40, 45]):
        for side in [-1, 1]: box("pier_%d_%s" % (i, "east" if side > 0 else "west"), [side*3.2, 3.5, z], [0.8, 7, 2.5])
        box("crossbeam_%d" % i, [0, 7.1, z], [9.4, 0.9, 2.5])
    # Existing game assets with exact CC0 source/license lock; every placement
    # and scale is authored here, not chosen by the road provider.
    placements = [("building-f", [-80, 0, 30], 18), ("building-h", [-45, 0, 45], 18),
                  ("building-skyscraper-b", [-75, 0, -65], 22), ("building-skyscraper-c", [-35, 0, -65], 16),
                  ("building-a", [35, 0, -60], 18), ("building-f", [75, 0, -65], 22),
                  ("building-h", [42, 0, 60], 20), ("building-skyscraper-b", [85, 0, 45], 23)]
    for i, (asset, pos, scale) in enumerate(placements):
        steps.append({"op": "load", "id": "building_%d" % i, "path": "res://assets/urban/kenney/commercial/" + asset + ".glb",
                      "instantiate": True, "parent": "scenery", "name": "Building_%d" % i,
                      "properties": {"position": variant("Vector3", *pos), "scale": variant("Vector3", scale, scale, scale)}})
    for i, pos in enumerate([[-95, 0, 6], [-85, 0, 6], [-25, 0, 40], [-15, 0, 40], [25, 0, 42], [35, 0, 40], [95, 0, 6], [105, 0, 6]]):
        steps.append({"op": "load", "id": "tree_%d" % i, "path": "res://assets/urban/kenney/nature/tree_default.glb",
                      "instantiate": True, "parent": "scenery", "name": "Tree_%d" % i,
                      "properties": {"position": variant("Vector3", *pos), "scale": variant("Vector3", 5, 5, 5)}})
    new("environment", "Environment", background_mode=1, background_color=variant("Color", 0.46, 0.62, 0.78, 1),
        ambient_light_source=3, ambient_light_color=variant("Color", 0.68, 0.77, 0.9, 1), ambient_light_energy=0.7)
    new("world_environment", "WorldEnvironment", "world", environment=reference("environment"))
    new("sun", "DirectionalLight3D", "world", rotation_degrees=variant("Vector3", -32, -40, 0),
        light_color=variant("Color", 1, 0.85, 0.65, 1), light_energy=1.2, shadow_enabled=True,
        directional_shadow_max_distance=350.0)
    new("camera", "Camera3D", "world", position=variant("Vector3", 180, 145, 190), fov=48.0, far=600.0)
    steps.append({"op": "attach", "target": "world"})
    call("camera", "look_at", variant("Vector3", 0, 2, 0))
    call("camera", "make_current")
    steps.append({"op": "script", "id": "roads", "path": "res://tools/authoring_road_network.gd",
                  "args": {"stage": "build", "target": "navigation", "network": network}})
    steps.append({"op": "script", "id": "acceptance", "path": "res://tools/road_network_acceptance.gd", "args": {"stage": "check"}})
    steps.append({"op": "script", "id": "saved", "path": "res://tools/authoring_road_network.gd", "args": {"stage": "save", "target": "world"}})
    # Register the already-packed scene resources through ordinary bridge saves
    # so the Control panel can open them from result.artifacts.
    for name in ["editable", "baked"]:
        path = "scenes/urban_roads_" + name + ".tscn"
        steps.append({"op": "load", "id": name + "_scene", "path": {"$output": path}})
        steps.append({"op": "save", "target": name + "_scene", "path": path})
    steps.append({"op": "script", "id": "reopen", "path": "res://tools/road_network_acceptance.gd", "args": {"stage": "reopen"}})
    call("camera", "look_at", variant("Vector3", 0, 2, 0))
    steps.append({"op": "capture", "camera": "camera", "path": "roads_overview.png"})
    steps.append({"op": "set", "target": "camera", "properties": {"position": variant("Vector3", 65, 23, -42), "fov": 60.0}})
    call("camera", "look_at", variant("Vector3", -3, 4, 8))
    steps.append({"op": "capture", "camera": "camera", "path": "roads_underpass.png"})
    steps.append({"op": "profile", "id": "measurement", "frames": 30})
    return {"version": 1, "id": "urban_roads", "description": "Authored curved boulevard and grade-separated ramp, real RoadGenerator output", "steps": steps}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write-example", action="store_true")
    parser.add_argument("--arcont", default=os.environ.get("ARCONT_ROOT"))
    args = parser.parse_args()
    if args.write_example:
        path = ROOT / "authoring/recipes/urban_roads.json"
        path.write_text(json.dumps(authored_recipe(), indent=2) + "\n")
        return
    if not args.arcont: raise SystemExit("ARCONT_ROOT or --arcont required")
    arcont = Path(args.arcont).resolve()
    spec = importlib.util.spec_from_file_location("road_network_contract", arcont / "tools/road_network_contract.py")
    contract = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(contract)
    tool = arcont / "tools/godot_authoring_control.py"
    recipe = json.loads((ROOT / "authoring/recipes/urban_roads.json").read_text())
    network = next(s for s in recipe["steps"] if s.get("id") == "roads")["args"]["network"]
    assert not contract.validate(network), contract.validate(network)
    dependencies = ["third_party/map_authoring.lock.json", "tools/authoring_road_network.gd", "tools/road_network_acceptance.gd", "assets/urban/sources.lock.json"]
    recipe["dependencies"] = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in dependencies}
    calls = []
    head = ROOT / "authoring/documents/urban_roads.json"
    if head.exists(): raise SystemExit("use clean checkout: smoke document exists")
    canonical = ROOT / "maps/urban_nexo_01.json"
    before = canonical.read_bytes()
    def control(operation, expected=True, **values):
        request = {"protocol_version": 1, "operation": operation, **values}
        process = subprocess.run([sys.executable, str(tool), "--project", str(ROOT)], input=json.dumps(request), text=True, capture_output=True, timeout=320)
        result = json.loads(process.stdout)
        calls.append({"operation": operation, "ok": result.get("ok"), "evidence": result.get("evidence", {}).get("directory")})
        if result.get("ok") is not expected:
            raise AssertionError({"request": operation, "error": result.get("error"), "details": result.get("details"), "evidence": result.get("evidence")})
        return result
    def step(result, identifier):
        return next(s["value"] for s in result["result"]["steps"] if s.get("id") == identifier)
    options = {"render": True, "audio_driver": "Dummy"}
    report = {"ok": False, "calls": calls}
    try:
        discover = control("discover", options={"script": "res://addons/road-generator/nodes/road_point.gd"})
        assert any(m["name"] == "connect_roadpoint" for m in discover["api"]["methods"])
        created = control("create", document_id="urban_roads", recipe=recipe, options=options, dry_run=False)
        old = head.read_bytes()
        bundle = ROOT / created["evidence"]["directory"]
        old_scene = bundle / "scenes/urban_roads_editable.tscn"
        old_hash = hashlib.sha256(old_scene.read_bytes()).hexdigest()
        control("patch", expected=False, document_id="urban_roads", if_revision="stale", patch=[], dry_run=False)
        invalid = copy.deepcopy(recipe)
        invalid["steps"].insert(2, {"op": "call", "target": "world", "method": "missing_road_method"})
        control("replace", expected=False, document_id="urban_roads", if_revision=created["revision"], recipe=invalid, options=options, dry_run=False)
        assert head.read_bytes() == old
        changed = control("patch", document_id="urban_roads", if_revision=created["revision"], options=options, dry_run=False,
                          patch=[{"op": "replace", "path": "/steps/@roads/args/network/roads/@boulevard/points/@west_bend/position", "value": [-55, 0.08, -14]},
                                 {"op": "replace", "path": "/steps/@roads/args/network/roads/@boulevard/lane_width", "value": 3.8}])
        assert step(changed, "reopen")["editable_geometry_signature"] != step(created, "reopen")["editable_geometry_signature"]
        assert hashlib.sha256(old_scene.read_bytes()).hexdigest() == old_hash
        restored = control("restore", document_id="urban_roads", if_revision=changed["revision"], restore_revision=created["revision"], options=options, dry_run=False)
        assert step(restored, "reopen")["editable_geometry_signature"] == step(created, "reopen")["editable_geometry_signature"]
        assert canonical.read_bytes() == before
        report.update({"ok": True, "engine": created["result"]["engine"], "provider_pin": next(p["commit"] for p in json.loads((ROOT / "third_party/map_authoring.lock.json").read_text())["providers"] if p["id"] == "road_generator"),
                       "build": step(created, "roads"), "acceptance": step(created, "acceptance"), "reopen": step(created, "reopen"),
                       "bundle": created["evidence"]["directory"], "revision": created["revision"], "source_patch_verified": True,
                       "restore_geometry_verified": True, "canonical_bytes_unchanged": True,
                       "limits": ["No automatic intersections, terrain flattening or traffic simulation accepted", "Linux authoring runner; target Android FPS unmeasured"]})
        print("ARCONT_ROAD_NETWORK_OK " + json.dumps(report))
    finally:
        path = ROOT / ".arcont/road-network-smoke.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(report, indent=2) + "\n")
        head.unlink(missing_ok=True)


if __name__ == "__main__": main()
