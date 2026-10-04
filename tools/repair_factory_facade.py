#!/usr/bin/env python3
"""Reassemble the delivered CC0 facade module on four outward-facing walls.

The source GLB remains unchanged. Preserve its materials, UVs, normals and
embedded images; extract one 3 x 3 m front module and tile a 24 x 18 x 9 m shell.
"""
import copy
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / "assets/shooter/serious"


def build():
    source = (DIRECTORY / "factory_building.glb").read_bytes()
    size = struct.unpack_from("<I", source, 12)[0]
    doc = json.loads(source[20:20 + size])
    binary = bytearray(source[28 + size:])
    lengths = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
    formats = {5126: "f", 5125: "I", 5123: "H", 5121: "B"}

    def read(index):
        a = doc["accessors"][index]
        view = doc["bufferViews"][a["bufferView"]]
        fmt = "<" + formats[a["componentType"]] * lengths[a["type"]]
        width = struct.calcsize(fmt)
        start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
        return [struct.unpack_from(fmt, binary, start + i * view.get("byteStride", width)) for i in range(a["count"])]

    def append(values, kind, component=5126, target=34962):
        while len(binary) % 4: binary.append(0)
        start = len(binary)
        fmt = "<" + formats[component] * lengths[kind]
        for value in values: binary.extend(struct.pack(fmt, *value))
        view = len(doc["bufferViews"])
        doc["bufferViews"].append({"buffer": 0, "byteOffset": start, "byteLength": len(binary) - start, "target": target})
        accessor = {"bufferView": view, "componentType": component, "count": len(values), "type": kind}
        if kind == "VEC3":
            accessor["min"] = [min(v[i] for v in values) for i in range(3)]
            accessor["max"] = [max(v[i] for v in values) for i in range(3)]
        doc["accessors"].append(accessor)
        return len(doc["accessors"]) - 1

    placements = []
    for row in range(3):
        for col in range(8):
            placements += [(0, (-12 + col * 3, row * 3, 9)), (math.pi, (-9 + col * 3, row * 3, -9))]
        for col in range(6):
            placements += [(math.pi / 2, (12, row * 3, -6 + col * 3)), (-math.pi / 2, (-12, row * 3, -9 + col * 3))]

    def rotate(value, angle):
        x, y, z = value[:3]
        return (math.cos(angle) * x + math.sin(angle) * z, y, -math.sin(angle) * x + math.cos(angle) * z)

    primitives = []
    triangle_count = 0
    module_counts = []
    for primitive in copy.deepcopy(doc["meshes"][0]["primitives"]):
        attributes = {name: read(index) for name, index in primitive["attributes"].items()}
        positions = attributes["POSITION"]
        indices = [v[0] for v in read(primitive["indices"])]
        selected = []
        for i in range(0, len(indices), 3):
            triangle = indices[i:i + 3]
            points = [positions[v] for v in triangle]
            center = [sum(p[k] for p in points) / 3 for k in range(3)]
            if 0 <= center[0] < 3 and 0 <= center[1] < 3 and all(-0.3 <= p[2] <= 0.3 for p in points):
                selected.extend(triangle)
        if not selected: raise ValueError("source front module missing for material " + str(primitive["material"]))
        used = sorted(set(selected))
        remap = {value: index for index, value in enumerate(used)}
        output = {name: [] for name in attributes}
        output_indices = []
        for angle, translation in placements:
            base = len(output["POSITION"])
            for name, values in attributes.items():
                for index in used:
                    value = values[index]
                    if name == "POSITION": value = tuple(a + b for a, b in zip(rotate(value, angle), translation))
                    elif name in {"NORMAL", "TANGENT"}: value = rotate(value, angle) + value[3:]
                    output[name].append(value)
            output_indices.extend((base + remap[index],) for index in selected)
        replacement = {"material": primitive["material"], "attributes": {}}
        for name, values in output.items():
            kind = doc["accessors"][primitive["attributes"][name]]["type"]
            replacement["attributes"][name] = append(values, kind)
        replacement["indices"] = append(output_indices, "SCALAR", 5125, 34963)
        primitives.append(replacement)
        triangle_count += len(output_indices) // 3
        module_counts.append(len(selected) // 3)
    doc["meshes"] = [{"name": "FourWallFactoryFacade", "primitives": primitives}]
    doc["nodes"] = [{"name": "FactoryFacade", "mesh": 0}]
    doc["scenes"] = [{"nodes": [0]}]
    doc["scene"] = 0
    doc["buffers"] = [{"byteLength": len(binary)}]
    metadata = json.dumps(doc, separators=(",", ":")).encode()
    metadata += b" " * (-len(metadata) % 4)
    binary += b"\0" * (-len(binary) % 4)
    target = DIRECTORY / "factory_building_fixed.glb"
    target.write_bytes(struct.pack("<III", 0x46546C67, 2, 28 + len(metadata) + len(binary)) + struct.pack("<II", len(metadata), 0x4E4F534A) + metadata + struct.pack("<II", len(binary), 0x004E4942) + binary)
    return {"file": str(target.relative_to(ROOT)), "tiles": len(placements), "triangles": triangle_count, "module_triangles_by_material": module_counts}


if __name__ == "__main__": print(json.dumps(build()))
