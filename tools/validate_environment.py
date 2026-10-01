"""Validate the authored environment extension before saving or rendering."""
import math
import re


def num(x):
    return type(x) in (int, float) and math.isfinite(x)


def vector(x, length=3, positive=False):
    return isinstance(x, list) and len(x) == length and all(num(n) and (not positive or n > 0) for n in x)


def validate(a):
    errors, ids, objects = [], set(), {}
    for label in ("geometry", "instances"):
        for v in a.get(label, []) if isinstance(a.get(label, []), list) else []:
            if isinstance(v, dict) and isinstance(v.get('id'), str):
                ids.add(v['id'])
    for label in ("heightfields", "objects", "lights"):
        values = a.get(label, [])
        if not isinstance(values, list):
            errors.append(label + " must be an array")
            continue
        for v in values:
            if not isinstance(v, dict):
                errors.append(label + " entries must be objects")
                continue
            identity = v.get("id")
            if not isinstance(identity, str) or not identity.strip() or identity in ids:
                errors.append(label + " requires unique nonempty ids")
            else:
                ids.add(identity)
            for key in ("position", "rotation_degrees", "scale"):
                if key in v and not vector(v[key], positive=key == "scale"):
                    errors.append(str(identity) + " has invalid " + key)
            if label == "objects" and 'top_radius' in v and (not num(v['top_radius']) or v['top_radius'] < 0):
                errors.append('top_radius must be finite and nonnegative')
            if label == "heightfields":
                c, r = v.get("columns"), v.get("rows")
                if not all(num(n) and n == int(n) and 2 <= n <= 2049 for n in (c, r)):
                    errors.append("heightfield dimensions must be in [2,2049]")
                    continue
                c, r = int(c), int(r)
                h = v.get("heights")
                if not isinstance(h, list) or len(h) != c * r or not all(num(n) for n in h):
                    errors.append("heightfield heights must match dimensions")
                if not vector(v.get("spacing", [1, 1]), 2, True):
                    errors.append("heightfield spacing must be positive")
                for key in ("paint", "holes"):
                    if key in v and (not isinstance(v[key], list) or len(v[key]) != (c - 1) * (r - 1)):
                        errors.append("heightfield " + key + " must match cell dimensions")
                if "holes" in v and isinstance(v["holes"], list) and not all(type(n) is bool for n in v["holes"]):
                    errors.append("heightfield holes must be booleans")
                if any(k in v for k in ("rotation_degrees", "scale", "parent")):
                    errors.append("heightfields use axis-aligned world spacing; transform meshes instead")
            if label == "objects":
                if v.get("type") not in {"group", "box", "sphere", "cylinder", "capsule", "plane", "prism", "torus"}:
                    errors.append("unsupported primitive type")
                if not vector(v.get("size", [1, 1, 1]), positive=True):
                    errors.append("primitive size must be positive xyz")
                objects[identity] = v
            if label == "lights":
                if 'color' in v and (not isinstance(v['color'], str) or not re.fullmatch(r'#?(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})',v['color'])):
                    errors.append('light colors must be RGB/RGBA hex')
                if v.get("type") not in {"directional", "omni", "spot"}:
                    errors.append("unsupported light type")
                for key in ("energy", "range", "angle"):
                    if key in v and (not num(v[key]) or v[key] < 0 or (key == "angle" and v[key] >= 90)):
                        errors.append("invalid light " + key)
    materials = a.get("materials", [])
    material_ids = {v.get("id") for v in materials if isinstance(v, dict)} if isinstance(materials, list) else set()
    for f in a.get("heightfields", []) if isinstance(a.get("heightfields", []), list) else []:
        if isinstance(f, dict):
            if f.get("material") not in material_ids or any(v not in material_ids for v in f.get("paint", []) if isinstance(v, str)):
                errors.append("heightfield materials must exist")
            if "paint" in f and isinstance(f["paint"], list) and not all(isinstance(v, str) for v in f["paint"]):
                errors.append("heightfield paint must contain material ids")
    for identity, v in objects.items():
        path, seen = v.get("parent"), {identity}
        while path:
            if path not in objects or path in seen:
                errors.append("object parent missing or cyclic")
                break
            seen.add(path)
            path = objects[path].get("parent")
    for label in ("geometry", "instances", "lights"):
        for v in a.get(label, []) if isinstance(a.get(label, []), list) else []:
            if isinstance(v, dict) and v.get("parent") and v["parent"] not in objects:
                errors.append(label + " parent must name an authored object")
    for v in materials if isinstance(materials, list) else []:
        if not isinstance(v, dict):
            continue
        for key in ("roughness", "metallic", "opacity"):
            if key in v and (not num(v[key]) or not 0 <= v[key] <= 1):
                errors.append("material " + key + " must be in [0,1]")
        for key in ("resource", "albedo_texture", "normal_texture", "roughness_texture", "metallic_texture"):
            if key in v and (not isinstance(v[key], str) or not v[key].startswith("res://") or ".." in v[key].split("/")):
                errors.append("texture must be a project resource")
        if "uv_scale" in v and not vector(v["uv_scale"], positive=True):
            errors.append("material uv_scale must be positive xyz")
    world = a.get("environment", {})
    if not isinstance(world, dict):
        errors.append("environment must be an object")
    else:
        for key in ("ambient_energy", "fog_density"):
            if key in world and (not num(world[key]) or world[key] < 0):
                errors.append("invalid environment " + key)
    for v in materials if isinstance(materials, list) else []:
        if isinstance(v, dict):
            for key in ('albedo', 'emission'):
                if key in v and (not isinstance(v[key], str) or not re.fullmatch(r'#?(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})', v[key])):
                    errors.append('material colors must be RGB/RGBA hex')
    for key in ('background_color', 'ambient_color', 'fog_color'):
        if isinstance(world, dict) and key in world and (not isinstance(world[key], str) or not re.fullmatch(r'#?(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})',world[key])):
            errors.append('environment colors must be RGB/RGBA hex')
    navigation = a.get('navigation', {})
    if not isinstance(navigation, dict) or navigation.get('mode', 'routes') not in ('none', 'routes', 'world'):
        errors.append('unsupported navigation mode')
    elif any(key in navigation and (not num(navigation[key]) or navigation[key] <= 0) for key in ('agent_height','agent_radius','agent_max_climb','agent_max_slope','cell_size','cell_height')):
        errors.append('navigation agent dimensions must be positive and finite')
    for g in a.get("geometry", []) if isinstance(a.get("geometry", []), list) else []:
        if isinstance(g, dict) and "uvs" in g:
            if not isinstance(g["uvs"], list) or len(g["uvs"]) != len(g.get("vertices", [])) or not all(vector(uv, 2) for uv in g["uvs"]):
                errors.append("geometry uvs must match vertices")
    return errors
