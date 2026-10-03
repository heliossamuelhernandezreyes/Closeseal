#!/usr/bin/env python3
"""Apply the explicit industrial access-sector design through ARCONT's writer.

The canonical industrial map is the input. Rebuilding preserves its imported
assets, mission layout and other authored sectors; this replaces only hero_*
objects. No obsolete Kenney generator or private map-file writes are used.
"""
import argparse
import copy
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAP_ID = "nexo_combat_01"


def contract(source=None):
    data = copy.deepcopy(source if source is not None else json.loads((ROOT / "maps" / (MAP_ID + ".json")).read_text()))
    if data.get("shooter_design", {}).get("art_revision") not in {"military-pbr-02", "third-person-industrial-03", "third-person-industrial-04"}:
        raise ValueError("industrial canonical map required; inspect the published industrial revision first")
    authored = data["authoring"]
    for collection in ("objects", "instances", "geometry", "lights", "materials"):
        authored[collection] = [item for item in authored[collection] if not item["id"].startswith("hero_")]
    objects, instances = authored["objects"], authored["instances"]

    def solid(name, position, size, material="steel", collision=True, rotation=None, kind="box"):
        item = {"id": "hero_" + name, "type": kind, "position": position, "size": size,
                "material": material, "collision": collision, "visible": True}
        if rotation: item["rotation_degrees"] = rotation
        objects.append(item)

    def asset(name, model, position, yaw=0, scale=1):
        path = "res://assets/shooter/serious/" + model
        if not (ROOT / path.removeprefix("res://")).is_file():
            raise ValueError("unstaged industrial asset: " + path)
        instances.append({"id": "hero_" + name, "scene": path, "position": position,
                          "rotation_degrees": [0, yaw, 0], "scale": [scale] * 3})

    authored["materials"] += [
        {"id": "hero_oxide", "resource": "res://assets/shooter/serious/materials/oxide.tres"},
        {"id": "hero_glass", "albedo": "254650", "roughness": 0.24, "metallic": 0.55},
        {"id": "hero_gravel", "resource": "res://assets/shooter/serious/materials/yard.tres"},
    ]
    # Asymmetric foreground: a low service annex and a taller, enterable workshop.
    # All walls are explicit colliders; the 26m street and each doorway stay clear.
    for side, x, z, width, depth, height in [("west", -21, 89, 12, 22, 4.8), ("east", 24, 80, 22, 28, 7.2)]:
        solid(side + "_floor", [x, -0.01, z], [width, 0.12, depth], "concrete")
        solid(side + "_back", [x, height/2, z-depth/2], [width, height, 0.28])
        solid(side + "_outer", [x + (-width/2 if x < 0 else width/2), height/2, z], [0.28, height, depth])
        inner_x = x + (width/2 if x < 0 else -width/2)
        # Street-facing 6m opening at the centre, with a structural lintel.
        for offset in [-1, 1]:
            solid(side + "_street_" + str(offset), [inner_x, height/2, z+offset*(depth/4+1.5)],
                  [0.28, height, depth/2-3], "hero_oxide" if x < 0 else "steel")
        solid(side + "_lintel", [inner_x, (height+3.4)/2, z], [0.30, height-3.4, 6])
        # Front facade also has a 5m open bay.
        for offset in [-1, 1]:
            solid(side + "_front_" + str(offset), [x+offset*(width/4+1.25), height/2, z+depth/2],
                  [width/2-2.5, height, 0.28], "hero_oxide" if x < 0 else "steel")
        solid(side + "_front_lintel", [x, height-1.0, z+depth/2], [5, 2, 0.3])
        solid(side + "_roof", [x, height+0.12, z], [width+0.6, 0.24, depth+0.6], "steel")
        solid(side + "_foundation", [inner_x, 0.18, z-depth/2+3], [0.55, 0.36, 5], "concrete")
        for index, zz in enumerate([z-depth/2+0.5, z-3, z+3, z+depth/2-0.5]):
            solid(side + "_frame_" + str(index), [inner_x-0.03, height/2, zz], [0.4, height, 0.3], "dark")
            solid(side + "_roof_beam_" + str(index), [x, height-0.25, zz], [width, 0.32, 0.24], "dark")
        for index in range(4):
            yy = 3.8 if x < 0 else 5.8
            zz = z-depth/2+2+index*2.1
            solid(side + "_window_frame_" + str(index), [inner_x-0.17 if x > 0 else inner_x+0.17, yy, zz], [0.12, 1.3, 1.65], "dark", False)
            solid(side + "_glass_" + str(index), [inner_x-0.24 if x > 0 else inner_x+0.24, yy, zz], [0.06, 1.12, 1.43], "hero_glass", False)
        for offset in [-3.0, 3.0]:
            solid(side + "_bollard_" + str(offset), [x+offset, 0.65, z+depth/2+0.7], [0.18, 1.3, 0.18], "orange", True, kind="cylinder")
        solid(side + "_bay_light", [x, 3.6, z+depth/2+0.16], [2.2, 0.09, 0.12], "warm_light", False)
        authored["lights"].append({"id": "hero_" + side + "_light", "type": "omni", "position": [x, 3.2, z+depth/2-1],
                                   "color": "ffd6a2", "energy": 1.4, "range": 9, "shadows": False})

    # Structural pipe bridge makes the approach recognizable at street level.
    for x in [-13, 13]:
        solid("bridge_column_" + str(x), [x, 3.4, 60], [0.42, 6.8, 0.42], "hero_oxide")
        solid("bridge_foot_" + str(x), [x, 0.25, 60], [1.05, 0.5, 1.05], "concrete")
    solid("bridge_deck", [0, 6.5, 60], [27, 0.22, 2.5], "dark")
    for z in [58.8, 61.2]:
        for y in [6.6, 7.55]: solid("bridge_rail_" + str(z) + str(y), [0, y, z], [27, 0.09, 0.09], "hero_oxide", False)
        for x in range(-12, 13, 2): solid("bridge_post_" + str(z) + str(x), [x, 7.05, z], [0.07, 1.05, 0.07], "dark", False)
    for index, z in enumerate([59.4, 60, 60.6]):
        solid("bridge_pipe_" + str(index), [0, 7.0, z], [0.32, 27, 0.32], "steel", False, [0, 0, 90], "cylinder")
    solid("bridge_sign", [0, 7.25, 61.32], [4.4, 1.1, 0.08], "dark", False)

    # Service yard surface, gutters, lines and scattered real catalog props.
    for x in [-11.5, 11.5]:
        for index, z in enumerate(range(66, 105, 6)):
            solid("curb_" + str(x) + str(index), [x, 0.07, z], [0.3, 0.14, 5.8], "concrete")
        for index, z in enumerate([69, 82, 99]):
            solid("drain_" + str(x) + str(index), [x, 0.145, z], [0.45, 0.012, 1.1], "dark", False)
            for grate in range(7): solid("grate_" + str(x) + str(index) + str(grate), [x, 0.16, z-0.45+grate*0.15], [0.43, 0.015, 0.035], "steel", False)
    for index, (x, z, w, d) in enumerate([(-9, 99, 3, 5), (7, 89, 4, 7), (-4, 72, 5, 3), (8, 68, 3, 5)]):
        solid("surface_patch_" + str(index), [x, 0.009, z], [w, 0.015, d], "hero_gravel", False, [0, index*19, 0])
    for x in [-7.5, 7.5]:
        solid("street_edge_" + str(x), [x, 0.013, 89], [0.07, 0.018, 35], "orange", False)
    for index in range(12):
        solid("bay_hatch_" + str(index), [19+index*0.5, 0.071, 96], [0.14, 0.018, 2.3], "orange", False, [0, 32, 0])
    props = [("barrel_03", [-17.8, 0.06, 97], 14), ("barrel_03", [-18.5, 0.06, 96.5], 65),
             ("barrel_03", [29, 0.06, 69], 40), ("portable_welding_cart", [29, 0.06, 83], 20),
             ("wooden_military_crate", [31, 0.06, 88], 90), ("old_military_crate", [26, 0.06, 71], -16),
             ("wooden_military_crate", [-23, 0.06, 82], 4), ("barrel_03", [-24, 0.06, 84], 35)]
    for index, (model, position, yaw) in enumerate(props):
        asset("yard_prop_" + str(index), f"polyhaven/{model}/{model}.gltf", position, yaw)
        size = [0.65, 0.96, 0.65] if model == "barrel_03" else [0.85, 0.9, 0.7]
        solid("prop_collision_" + str(index), [position[0], position[1]+size[1]/2, position[2]], size, "dark")
        objects[-1]["visible"] = False
    for index, position in enumerate([[-14.7, 2.7, 84], [13.35, 4.6, 72], [13.35, 4.6, 87]]):
        asset("service_pipe_" + str(index), "pipe_segment.glb", position, 0, 2.1)
    for index, x in enumerate([-22, 20, 28]):
        solid("roof_vent_" + str(index), [x, 7.8 if x > 0 else 5.4, 78 if x > 0 else 85], [1.2, 1.0, 1.0], "dark")
        solid("roof_vent_cap_" + str(index), [x, 8.34 if x > 0 else 5.94, 78 if x > 0 else 85], [1.4, 0.14, 1.2], "steel")
    # Traversable low cover in the foreground; centre mission/replay route stays clear.
    for index, (x, z, width, yaw) in enumerate([(-4.7, 100, 4.0, 0), (5.2, 89, 4.6, -12), (-5.5, 77, 4.2, 14)]):
        solid("cover_body_" + str(index), [x, 0.57, z], [width, 1.14, 0.56], "concrete", True, [0, yaw, 0])
        solid("cover_cap_" + str(index), [x, 1.16, z], [width+0.08, 0.06, 0.62], "steel", False, [0, yaw, 0])
        solid("cover_band_" + str(index), [x, 0.93, z+0.29], [width-0.14, 0.065, 0.02], "orange", False, [0, yaw, 0])
        for side in [-1, 1]:
            solid("cover_foot_" + str(index) + str(side), [x+side*(width/2-0.3), 0.10, z], [0.32, 0.2, 0.8], "concrete", True)
    authored["environment"].update(fog_density=0.0032, fog_color="657782")
    for light in authored["lights"]:
        if light["id"] == "sun": light.update(rotation_degrees=[-24, -48, 0], color="ffe0b4", energy=1.15)
    data["shooter_design"].update(art_revision="third-person-industrial-04", perspective="third_person")
    labels = [item for item in data["shooter_design"].get("zone_labels", []) if not item.get("id", "").startswith("hero_")]
    labels += [{"id": "hero_bridge", "text": "SECTOR 07 / NEXO", "position": [0, 7.25, 61.42]},
               {"id": "hero_workshop", "text": "MANTENIMIENTO / 04", "position": [24, 6, 94.2]}]
    data["shooter_design"]["zone_labels"] = labels
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arcont", required=True, type=Path)
    args = parser.parse_args()
    tool = [sys.executable, str(args.arcont / "tools/map_forge_control.py"), "--project", str(ROOT)]
    def call(request):
        run = subprocess.run(tool, input=json.dumps(request), text=True, capture_output=True)
        result = json.loads(run.stdout)
        if not result.get("ok"): raise RuntimeError(result)
        return result
    inspected = call({"protocol_version": 1, "operation": "inspect", "map_id": MAP_ID})
    data = contract(inspected["state"]["map"])
    result = call({"protocol_version": 1, "operation": "replace", "map_id": MAP_ID, "dry_run": False,
                   "if_revision": inspected["revision"], "state": {"map": data, "physical": inspected["state"].get("physical")}})
    print(json.dumps({"ok": True, "revision": result["revision"], "objects": len(data["authoring"]["objects"]),
                      "assets": len(data["authoring"]["instances"]), "size_m": 256}))


if __name__ == "__main__": main()
