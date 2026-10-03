#!/usr/bin/env python3
"""Verify the frozen industrial edition's source assets before staging/export."""
import hashlib
import json
import struct
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]


def verify(root=ROOT):
    root = Path(root).resolve()
    manifest = json.loads((root / "assets/shooter/serious/manifest.json").read_text())
    errors = []
    files = manifest["delivered_files"]
    for entry in files:
        path = root / entry["path"]
        if not path.resolve().is_relative_to(root):
            errors.append(f"unsafe path: {entry['path']}")
            continue
        if not path.is_file():
            errors.append(f"missing: {entry['path']}")
            continue
        data = path.read_bytes()
        if len(data) != entry["size_bytes"] or hashlib.sha256(data).hexdigest() != entry["sha256"]:
            errors.append(f"checksum: {entry['path']}")
        model = None
        if path.suffix == ".gltf":
            model = json.loads(data)
        elif path.suffix == ".glb":
            magic, version, length = struct.unpack_from("<III", data)
            if magic != 0x46546C67 or version != 2 or length != len(data):
                errors.append(f"invalid GLB: {entry['path']}")
                continue
            size, kind = struct.unpack_from("<II", data, 12)
            if kind == 0x4E4F534A:
                model = json.loads(data[20:20 + size])
        if model:
            for item in model.get("buffers", []) + model.get("images", []):
                uri = item.get("uri", "")
                if uri and not uri.startswith("data:"):
                    dependency = (path.parent / unquote(uri)).resolve()
                    if not dependency.is_relative_to(root) or not dependency.is_file():
                        errors.append(f"missing model dependency: {entry['path']} -> {uri}")
    authored = json.loads((root / "maps/nexo_combat_01.json").read_text())
    def resources(value):
        if isinstance(value, str) and value.startswith("res://"):
            if not (root / value[6:]).is_file():
                errors.append(f"missing map resource: {value}")
        elif isinstance(value, dict):
            for item in value.values():
                resources(item)
        elif isinstance(value, list):
            for item in value:
                resources(item)
    resources(authored)
    return {"ok": not errors, "edition": manifest["edition"], "verified_files": len(files), "errors": errors}


if __name__ == "__main__":
    report = verify()
    print(json.dumps(report))
    raise SystemExit(0 if report["ok"] else 1)
