#!/usr/bin/env python3
"""Acquire official CC0 packs selected from Arcont; inventory before placement."""
import hashlib
import io
import json
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath

PACKS = [
    ("commercial", "ARC-ASSET-KENNEY-C909A5FD85A4D02B", "city-kit-commercial", "https://kenney.nl/media/pages/assets/city-kit-commercial/a742d900eb-1753115042/kenney_city-kit-commercial_2.1.zip"),
    ("industrial", "ARC-ASSET-KENNEY-DFA86EB98DCA72D3", "city-kit-industrial", "https://kenney.nl/media/pages/assets/city-kit-industrial/0ec35b139d-1788171848/kenney_city-kit-industrial_2.0.zip"),
    ("suburban", "ARC-ASSET-KENNEY-9C50A7D31F343F0A", "city-kit-suburban", "https://kenney.nl/media/pages/assets/city-kit-suburban/2c871b7af2-1745479373/kenney_city-kit-suburban_20.zip"),
    ("nature", "ARC-ASSET-KENNEY-B772EE99BC78B87B", "nature-kit", "https://kenney.nl/media/pages/assets/nature-kit/37ac38a37b-1677698939/kenney_nature-kit.zip"),
    ("cars", "ARC-ASSET-KENNEY-7A4676B8BFAC85F4", "car-kit", "https://kenney.nl/media/pages/assets/car-kit/1a312ec241-1775131960/kenney_car-kit.zip"),
]


def main():
    root = Path("urban-source-packs")
    root.mkdir(exist_ok=True)
    records = []
    for name, arcont_id, slug, url in PACKS:
        request = urllib.request.Request(url, headers={"User-Agent": "CloseSeal/urban-asset-review"})
        with urllib.request.urlopen(request, timeout=120) as response:
            raw = response.read()
        archive = zipfile.ZipFile(io.BytesIO(raw))
        names = archive.namelist()
        retained = []
        for path in names:
            p = PurePosixPath(path)
            if p.is_absolute() or ".." in p.parts or path.endswith("/"):
                continue
            # Retain the glTF export and its atlas dependencies, plus source license.
            if p.suffix.lower() in (".glb", ".gltf", ".bin") or (p.suffix.lower() in (".png", ".jpg") and any(f in path.lower() for f in ("gltf", "glb"))) or "license" in p.name.lower():
                data = archive.read(path)
                target = root / name / p
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                retained.append({"path": path, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
        records.append({"pack": name, "arcont_id": arcont_id, "source": "https://kenney.nl/assets/" + slug, "download": url, "license": "CC0-1.0", "archive_sha256": hashlib.sha256(raw).hexdigest(), "archive_bytes": len(raw), "archive_entries": names, "retained": retained})
        print(name, len(raw), "bytes;", len(retained), "retained files")
    (root / "inventory.json").write_text(json.dumps(records, indent=2) + "\n")


if __name__ == "__main__":
    main()
