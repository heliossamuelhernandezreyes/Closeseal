#!/usr/bin/env python3
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAP_DIR = ROOT / "maps"
REQUIRED = ("version", "id", "bounds", "bases", "objectives", "routes", "regions")
ROUTE_KINDS = {"primary", "flank", "secondary", "jungle", "connector"}
REGION_KINDS = {"formation_space", "choke", "objective_zone", "spawn_zone", "hazard", "cover", "neutral"}


def vec3(v):
    return isinstance(v, list) and len(v) >= 3 and all(isinstance(x, (int, float)) for x in v[:3])


def positive_vec3(v):
    return vec3(v) and all(float(x) > 0 for x in v[:3])


def dist(a, b):
    return math.sqrt(sum((float(a[i]) - float(b[i])) ** 2 for i in range(3)))


def validate_authoring(authoring, errors):
    if authoring is None:
        return
    if not isinstance(authoring, dict):
        errors.append("authoring must be an object")
        return

    terrain = authoring.get("terrain", {})
    if not isinstance(terrain, dict):
        errors.append("authoring.terrain must be an object")
    else:
        if "vertex_spacing" in terrain and float(terrain.get("vertex_spacing", 0)) <= 0:
            errors.append("authoring.terrain.vertex_spacing must be positive")
        if "region_size" in terrain and int(terrain.get("region_size", 0)) <= 0:
            errors.append("authoring.terrain.region_size must be positive")

    structures = authoring.get("structure_guides", [])
    if not isinstance(structures, list):
        errors.append("authoring.structure_guides must be an array")
    else:
        seen = set()
        for item in structures:
            if not isinstance(item, dict):
                errors.append("authoring.structure_guides entries must be objects")
                continue
            item_id = item.get("id")
            if not isinstance(item_id, str) or not item_id.strip():
                errors.append("authoring structure guide requires id")
            elif item_id in seen:
                errors.append(f"duplicate authoring structure guide id '{item_id}'")
            else:
                seen.add(item_id)
            if not vec3(item.get("position")):
                errors.append(f"authoring structure guide '{item_id or '?'}' requires position [x,y,z]")
            if not positive_vec3(item.get("size")):
                errors.append(f"authoring structure guide '{item_id or '?'}' requires positive size [x,y,z]")

    zones = authoring.get("scatter_zones", [])
    if not isinstance(zones, list):
        errors.append("authoring.scatter_zones must be an array")
    else:
        seen = set()
        for zone in zones:
            if not isinstance(zone, dict):
                errors.append("authoring.scatter_zones entries must be objects")
                continue
            zone_id = zone.get("id")
            if not isinstance(zone_id, str) or not zone_id.strip():
                errors.append("authoring scatter zone requires id")
            elif zone_id in seen:
                errors.append(f"duplicate authoring scatter zone id '{zone_id}'")
            else:
                seen.add(zone_id)
            if not vec3(zone.get("center")):
                errors.append(f"authoring scatter zone '{zone_id or '?'}' requires center [x,y,z]")
            if not positive_vec3(zone.get("size")):
                errors.append(f"authoring scatter zone '{zone_id or '?'}' requires positive size [x,y,z]")
            density = float(zone.get("density", 0.5))
            if not 0.0 <= density <= 1.0:
                errors.append(f"authoring scatter zone '{zone_id or '?'}' density must be between 0 and 1")


def validate(data, path):
    errors = []
    warnings = []
    for key in REQUIRED:
        if key not in data:
            errors.append(f"missing top-level key '{key}'")
    if data.get("version") != 1:
        errors.append(f"unsupported version {data.get('version')!r}")
    if not isinstance(data.get("id"), str) or not data.get("id", "").strip():
        errors.append("id must be a non-empty string")

    bounds = data.get("bounds")
    if not isinstance(bounds, dict):
        errors.append("bounds must be an object")
    else:
        if float(bounds.get("width", 0)) <= 0 or float(bounds.get("depth", 0)) <= 0:
            errors.append("bounds width/depth must be positive")

    seen = set()
    for collection in ("bases", "objectives", "routes", "regions"):
        items = data.get(collection, [])
        if not isinstance(items, list):
            errors.append(f"{collection} must be an array")
            continue
        for item in items:
            if not isinstance(item, dict):
                errors.append(f"{collection} entries must be objects")
                continue
            item_id = item.get("id")
            if not isinstance(item_id, str) or not item_id.strip():
                errors.append(f"{collection} entry missing id")
            elif item_id in seen:
                errors.append(f"duplicate id '{item_id}'")
            else:
                seen.add(item_id)

    bases = data.get("bases", [])
    if isinstance(bases, list):
        if len(bases) < 2:
            errors.append("at least two bases are required")
        for base in bases:
            if isinstance(base, dict) and not vec3(base.get("position")):
                errors.append(f"base '{base.get('id', '?')}' requires position [x,y,z]")
            if isinstance(base, dict) and "hero_spawn" in base and not vec3(base["hero_spawn"]):
                errors.append(f"base '{base.get('id', '?')}' has invalid hero_spawn")

    routes = data.get("routes", [])
    if isinstance(routes, list):
        for route in routes:
            if not isinstance(route, dict):
                continue
            rid = route.get("id", "?")
            if route.get("kind") not in ROUTE_KINDS:
                errors.append(f"route '{rid}' has unsupported kind '{route.get('kind')}'")
            points = route.get("points")
            if not isinstance(points, list) or len(points) < 2 or not all(vec3(p) for p in points):
                errors.append(f"route '{rid}' requires at least two valid [x,y,z] points")
            if float(route.get("width", 0)) <= 0:
                errors.append(f"route '{rid}' width must be positive")

    regions = data.get("regions", [])
    if isinstance(regions, list):
        for region in regions:
            if not isinstance(region, dict):
                continue
            rid = region.get("id", "?")
            if region.get("kind") not in REGION_KINDS:
                errors.append(f"region '{rid}' has unsupported kind '{region.get('kind')}'")
            if not vec3(region.get("center")):
                errors.append(f"region '{rid}' requires center [x,y,z]")
            if region.get("kind") == "choke" and float(region.get("width", 0)) <= 0:
                errors.append(f"choke '{rid}' width must be positive")

    validate_authoring(data.get("authoring", {}), errors)

    if len(bases) >= 2 and all(isinstance(b, dict) and vec3(b.get("position")) for b in bases[:2]):
        midpoint = [(bases[0]["position"][i] + bases[1]["position"][i]) * 0.5 for i in range(3)]
        span = max(float(data.get("bounds", {}).get("width", 1)), float(data.get("bounds", {}).get("depth", 1)))
        if math.hypot(midpoint[0], midpoint[2]) > span * 0.03:
            warnings.append("primary bases are not centered around map origin")

    lengths = {}
    for route in routes if isinstance(routes, list) else []:
        if isinstance(route, dict) and isinstance(route.get("points"), list) and len(route["points"]) >= 2 and all(vec3(p) for p in route["points"]):
            lengths[route.get("id", "?")] = sum(dist(route["points"][i - 1], route["points"][i]) for i in range(1, len(route["points"])))
    if "north_flank" in lengths and "south_flank" in lengths:
        delta = abs(lengths["north_flank"] - lengths["south_flank"]) / max(lengths["north_flank"], lengths["south_flank"])
        if delta > 0.08:
            warnings.append(f"north/south flank length delta is {delta:.1%}")

    return errors, warnings


def main():
    paths = sorted(MAP_DIR.glob("*.json"))
    if not paths:
        print("ERROR: no maps/*.json files found", file=sys.stderr)
        return 1
    failed = 0
    for path in paths:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:
            print(f"FAIL {path.relative_to(ROOT)}: invalid JSON: {exc}")
            failed += 1
            continue
        if not isinstance(data, dict):
            print(f"FAIL {path.relative_to(ROOT)}: root must be object")
            failed += 1
            continue
        errors, warnings = validate(data, path)
        if errors:
            failed += 1
            print(f"FAIL {path.relative_to(ROOT)}")
            for error in errors:
                print(f"  ERROR: {error}")
        else:
            print(f"PASS {path.relative_to(ROOT)}")
        for warning in warnings:
            print(f"  WARN: {warning}")
    print(f"\nMap contract validation: {len(paths) - failed}/{len(paths)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())