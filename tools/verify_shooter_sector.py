#!/usr/bin/env python3
"""Validate the delivered native bake bytes and essential layered-atlas import metadata."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(project):
    folder=project/'assets/shooter/sector07'
    record=json.loads((folder/'bake-output.json').read_text())
    errors=[]
    for name,expected in record['files'].items():
        relative=PurePosixPath(name)
        if relative.is_absolute() or '..' in relative.parts:
            errors.append('unsafe bake output path');continue
        path=folder/name
        if path.is_symlink() or not path.is_file() or digest(path)!=expected:
            errors.append('bake output changed: '+name)
        elif path.suffix in ('.tscn','.tres') and '.arcont/runs/' in path.read_text():
            errors.append('unpublished authoring reference: '+name)
    if record['canonical_sha256']!=digest(project/'maps/nexo_combat_01.json'):
        errors.append('canonical map changed; rebuild derived presentation')
    imported=(folder/'sector_bake.exr.import').read_text()
    if 'importer="2d_array_texture"' not in imported or 'type="CompressedTexture2DArray"' not in imported:
        errors.append('lightmap atlas must use the native layered importer')
    properties=json.loads((folder/'sector_bake-bake.json').read_text())['properties']
    if any(properties.get(key,0)<=0 for key in ('textures','mesh_binding_fields','probes')):
        errors.append('native bake output is incomplete')
    return {'ok':not errors,'files':len(record['files']),'properties':properties,'errors':errors,
            'limits':['byte/import integrity; native runtime acceptance and device playtest remain separate',
                      'native editor teardown diagnostics retained in bake-output.json']}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project',type=Path,default=Path(__file__).resolve().parents[1])
    result=verify(parser.parse_args().project.resolve())
    print(json.dumps(result));raise SystemExit(0 if result['ok'] else 1)


if __name__=='__main__':main()
