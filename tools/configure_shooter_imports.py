#!/usr/bin/env python3
"""Enable mipmaps on the staged 3D texture imports, including GLB extractions.

Run after the first Godot import, then import again before baking/exporting.
Fresh stages do not inherit developer .import files. This prevents shimmering
brick/metal/normal textures from being shipped with no mip chain.
"""
import argparse
import json
from pathlib import Path


def configure(stage):
    stage = Path(stage).resolve()
    marker = stage / ".nexo-shooter-stage.json"
    if not marker.is_file() or json.loads(marker.read_text()).get("owner") != "closeseal-nexo-shooter":
        raise ValueError("an independently prepared Nexo shooter stage is required")
    changed = []
    for path in sorted((stage / "assets/shooter/serious").rglob("*.import")):
        text = path.read_text()
        if 'importer="texture"' not in text or 'mipmaps/generate=false' not in text:
            continue
        path.write_text(text.replace('mipmaps/generate=false', 'mipmaps/generate=true'))
        changed.append(str(path.relative_to(stage)))
    return {"ok": True, "textures_configured": len(changed), "reimport_required": bool(changed)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(configure(args.stage)))


if __name__ == "__main__": main()
