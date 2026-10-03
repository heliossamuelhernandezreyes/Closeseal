#!/usr/bin/env python3
"""Author the explicit 256m Nexo combat map through Arcont's map writer."""
import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def contract():
    data = {"version": 1, "id": "nexo_combat_01", "purpose": "environment",
            "bounds": {"width": 256, "depth": 256}, "bases": [], "objectives": [], "routes": [], "regions": []}
    materials = [{"id": name, "albedo": color, "roughness": 0.86} for name, color in [
        ("asphalt", "253644"), ("concrete", "a7b8bd"), ("stone", "d1c7af"), ("steel", "3b5666"),
        ("dark", "152a37"), ("orange", "df813a"), ("white", "e8e1cf"), ("grass", "54735e")]]
    materials[0].update(albedo_texture="res://assets/shooter/asphalt.svg", uv_scale=[42, 42, 42])
    materials += [{"id": "blue", "albedo": "3db3d5", "emission": "2289b3"},
                  {"id": "red", "albedo": "c95547", "emission": "552a24"}]
    objects, instances, geometry = [], [], []

    def box(name, position, size, material="concrete", collision=True, visible=True):
        objects.append({"id": name, "type": "box", "position": position, "size": size,
                        "material": material, "collision": collision, "visible": visible})

    box("ground", [0, -0.3, 0], [256, 0.6, 256], "asphalt")
    for x in [-128, 128]: box("boundary_x_" + str(x), [x, 3, 0], [1, 6, 256], "steel")
    for z in [-128, 128]: box("boundary_z_" + str(z), [0, 3, z], [256, 6, 1], "steel")
    for x in [-16, 16, -87, 87]: box("walkway_" + str(x), [x, 0.025, 0], [5, 0.05, 246], "stone", False)
    for z in [-82, 0, 82]: box("crosswalk_" + str(z), [0, 0.026, z], [246, 0.05, 4], "stone", False)
    for z in range(-116, 117, 12): box("lane_mark_" + str(z), [0, 0.031, z], [0.16, 0.025, 4], "white", False)
    for x in range(-116, 117, 12): box("cross_mark_" + str(x), [x, 0.032, 0], [4, 0.025, 0.16], "white", False)
    records = json.loads((ROOT / "assets/urban/sources.lock.json").read_text())
    bounds = {m["path"]: m for pack in records["packs"] for m in pack["models"]}

    def asset(name, pack, filename, x, z, scale=1.0, y=0.0, collider=True):
        path = f"assets/urban/kenney/{pack}/{filename}.glb"
        m = bounds[path]
        instances.append({"id": name, "scene": "res://" + path, "position": [x, y - m["min"][1] * scale, z],
                          "scale": [scale] * 3})
        if collider:
            centre = [(m["min"][i] + m["max"][i]) * scale / 2 for i in range(3)]
            box(name + "_collision", [x + centre[0], y + m["size"][1] * scale / 2, z + centre[2]],
                [max(0.1, m["size"][i] * scale * (0.92 if i != 1 else 1)) for i in range(3)], visible=False)

    for quadrant, (sx, sz) in enumerate([(-1, -1), (1, -1), (-1, 1), (1, 1)]):
        for index, (dx, dz) in enumerate([(40, 34), (64, 30), (108, 30), (35, 62), (108, 62), (36, 109), (67, 109), (108, 108)]):
            pack = "industrial" if quadrant == 0 else "commercial" if quadrant in [1, 2] else "suburban"
            filename = (["building-a", "building-g", "building-j"][index % 3] if pack == "industrial" else
                        ["building-a", "building-c", "building-h"][index % 3] if pack == "commercial" else
                        ["building-type-a", "building-type-c", "building-type-g"][index % 3])
            asset(f"block_{quadrant}_{index}", pack, filename, sx * dx, sz * dz, 10 if pack == "industrial" else 12)
    for index, (x, z) in enumerate([(-111, -109), (109, -108), (-108, 110), (110, 109)]):
        asset("skyline_" + str(index), "commercial", "building-skyscraper-" + ["b", "c", "d", "e"][index], x, z, 9)
    for index, (x, z) in enumerate([(-62, -60), (-70, -42), (-49, -57), (-63, -74), (54, 35), (74, 35), (57, 69)]):
        asset("container_" + str(index), "industrial", "shipping-container-" + ("a" if index % 2 else "b"), x, z, 7)
    for index, (x, z) in enumerate([(-10, 76), (13, 43), (-13, -86), (42, 11), (-46, -11), (73, -12), (-76, 13)]):
        asset("car_" + str(index), "cars", ["sedan", "delivery", "taxi"][index % 3], x, z, 1.6)
    for index, (x, z) in enumerate([(-20, 22), (20, 22), (-20, -22), (20, -22), (54, 84), (77, 86), (-97, 52), (-96, -75)]):
        asset("tree_" + str(index), "nature", "tree_default", x, z, 5, collider=False)
        box("tree_trunk_" + str(index), [x, 1.8, z], [0.6, 3.6, 0.6], visible=False)
        box("planter_" + str(index), [x, 0.4, z], [3.5, 0.8, 3.5], "stone")
    for index, (x, z) in enumerate([(-9, 90), (9, 63), (-9, 30), (9, -8), (-9, -76), (-34, -11), (34, 11), (-57, 12), (57, -12), (75, 54), (-73, -25), (-45, 48)]):
        box("cover_" + str(index), [x, 0.7, z], [3.6, 1.4, 1.2], "steel")
        box("cover_stripe_" + str(index), [x, 1.43, z], [3.65, 0.08, 1.25], "orange", False)
    # Accessible command post with a 16-degree ramp and an elevated crossfire position.
    box("command_platform", [0, 3.8, -44], [18, 0.4, 18], "concrete")
    box("command_back", [0, 6, -53], [18, 4, 0.5], "steel")
    box("command_west", [-9, 6, -44], [0.5, 4, 18], "steel")
    box("command_east", [9, 6, -44], [0.5, 4, 18], "steel")
    box("command_roof", [0, 8.2, -46], [19, 0.4, 15], "concrete")
    box("command_rail_left", [-6.5, 4.6, -35], [5, 1.2, 0.3], "steel")
    box("command_rail_right", [6.5, 4.6, -35], [5, 1.2, 0.3], "steel")
    # Landing clears the CharacterBody collision margin before meeting the platform lip.
    verts = [[-3, 0, -21], [3, 0, -21], [-3, 4.08, -34], [3, 4.08, -34], [-3, 0, -34], [3, 0, -34], [-3, 4.08, -36], [3, 4.08, -36]]
    geometry.append({"id": "command_ramp", "vertices": verts, "indices": [0, 2, 1, 1, 2, 3, 2, 6, 3, 3, 6, 7, 0, 2, 4, 1, 5, 3], "material": "concrete", "collision": True})
    # Enterable west maintenance hangar, unlike the solid backdrop buildings.
    box("hangar_floor", [-69, 0.08, -94], [27, 0.16, 19], "concrete")
    box("hangar_back", [-69, 3.6, -103.5], [27, 7.2, 0.5], "steel")
    for x in [-82.5, -55.5]: box("hangar_side_" + str(x), [x, 3.6, -94], [0.5, 7.2, 19], "steel")
    box("hangar_roof", [-69, 7.3, -94], [28, 0.3, 20], "dark")
    for x in [-78, -60]: box("hangar_front_" + str(x), [x, 3.6, -84.5], [9, 7.2, 0.5], "steel")
    asset("west_water_tower", "industrial", "water-tower", -108, -65, 7)
    for index, (x, z) in enumerate([(-6, 111), (6, 111)]):
        box("spawn_column_" + str(index), [x, 3, z], [1, 6, 1], "white")
    box("spawn_gate", [0, 6, 111], [13, 0.7, 1], "blue")
    lights = [{"id": "sun", "type": "directional", "rotation_degrees": [-42, -28, 0], "color": "ffe1b6", "energy": 1.3, "shadows": True}]
    for index, (x, z) in enumerate([(-18, 72), (18, 18), (-18, -68), (75, 83), (-69, -90)]):
        box("lamp_" + str(index), [x, 3, z], [0.22, 6, 0.22], "steel")
        box("lamp_head_" + str(index), [x, 6, z], [1, 0.25, 0.5], "blue", False)
    data["authoring"] = {"materials": materials, "objects": objects, "instances": instances, "geometry": geometry,
        "heightfields": [], "lights": lights, "navigation": {"mode": "world", "agent_radius": 0.45, "agent_height": 1.9,
        "agent_max_climb": 0.35, "agent_max_slope": 40, "cell_size": 0.4, "cell_height": 0.2},
        "environment": {"background_color": "7799ac", "ambient_color": "cedce6", "ambient_energy": 0.65,
                        "fog_color": "7799ac", "fog_density": 0.0018}}
    data["shooter_design"] = {"name": "Nexo: zona de combate", "player_spawn": [0, 0.08, 106],
        "beacons": [{"id": "A", "name": "Patio industrial", "position": [-69, 0, -67]},
                    {"id": "B", "name": "Puesto de mando", "position": [0, 4, -44]},
                    {"id": "C", "name": "Patio residencial", "position": [68, 0, 57]}],
        "extraction": [0, 0, 113], "enemy_spawns": [[10, 0, 70], [-12, 0, 49], [8, 0, 18], [-24, 0, 5], [24, 0, -11],
            [-66, 0, -29], [-44, 0, -61], [-78, 0, -68], [-69, 0.2, -93], [0, 4, -45], [5, 0, -80],
            [62, 0, 52], [78, 0, 71], [53, 0, 90], [76, 0, -48], [-64, 0, 72]],
        "pickups": [[-15, 0, 96], [18, 0, 5], [-50, 0, -76], [0, 4, -49], [80, 0, 84]],
        "navigation_checks": [[[-2, 0, 100], [-69, 0, -67]], [[0, 0, 100], [0, 4, -44]], [[0, 0, 100], [68, 0, 57]]]}
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arcont", required=True, type=Path)
    args = parser.parse_args()
    data = contract()
    request = {"protocol_version": 1, "operation": "create", "map_id": data["id"], "dry_run": False, "state": {"map": data, "physical": None}}
    tool = [sys.executable, str(args.arcont / "tools/map_forge_control.py"), "--project", str(ROOT)]
    if (ROOT / "maps" / (data["id"] + ".json")).exists():
        inspected = subprocess.run(tool, input=json.dumps({"protocol_version": 1, "operation": "inspect", "map_id": data["id"]}), text=True, capture_output=True, check=True)
        request.update(operation="replace", if_revision=json.loads(inspected.stdout)["revision"])
    run = subprocess.run([sys.executable, str(args.arcont / "tools/map_forge_control.py"), "--project", str(ROOT)],
                         input=json.dumps(request), text=True, capture_output=True)
    result = json.loads(run.stdout)
    if not result.get("ok"): raise SystemExit(result)
    print(json.dumps({"ok": True, "revision": result.get("revision"), "objects": len(data["authoring"]["objects"]),
                      "assets": len(data["authoring"]["instances"]), "size_m": 256}))


if __name__ == "__main__": main()
