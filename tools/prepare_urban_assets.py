#!/usr/bin/env python3
"""Select unchanged Kenney GLBs, atlas dependencies and licenses for Urban Nexo."""
import argparse
import hashlib
import itertools
import json
import math
import shutil
import struct
from pathlib import Path

SELECTION = {
    "commercial": ["building-a", "building-c", "building-e", "building-f", "building-h", "building-skyscraper-b", "building-skyscraper-c", "building-skyscraper-d", "building-skyscraper-e"],
    "industrial": ["building-a", "building-c", "building-g", "building-j", "building-p", "shipping-container-a", "shipping-container-b", "water-tower", "chimney-large"],
    "suburban": ["building-type-a", "building-type-c", "building-type-e", "building-type-g", "building-type-i", "building-type-k"],
    "nature": ["tree_default", "tree_simple", "tree_palmTall", "tree_plateau", "plant_bush", "rock_largeA"],
    "cars": ["sedan", "taxi", "delivery"],
}


def inspect_glb(path):
    raw = path.read_bytes()
    length = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20 + length])
    binary_start = 20 + length + 8
    vertices = []
    triangles = 0

    def transformed(point, node):
        p = [point[i] * node.get('scale', [1, 1, 1])[i] for i in range(3)]
        x, y, z, w = node.get('rotation', [0, 0, 0, 1])
        cross = [y*p[2]-z*p[1], z*p[0]-x*p[2], x*p[1]-y*p[0]]
        cross2 = [y*cross[2]-z*cross[1], z*cross[0]-x*cross[2], x*cross[1]-y*cross[0]]
        p = [p[i] + 2*w*cross[i] + 2*cross2[i] + node.get('translation', [0, 0, 0])[i] for i in range(3)]
        if 'matrix' in node:
            m = node['matrix']
            p = [sum(m[i+4*j]*point[j] for j in range(3)) + m[12+i] for i in range(3)]
        return p

    def visit(index, ancestors):
        nonlocal triangles
        node = doc['nodes'][index]
        lineage = [node] + ancestors
        if 'mesh' in node:
            for primitive in doc['meshes'][node['mesh']]['primitives']:
                accessor = doc['accessors'][primitive['attributes']['POSITION']]
                assert accessor['componentType'] == 5126 and accessor['type'] == 'VEC3'
                view = doc['bufferViews'][accessor['bufferView']]
                offset = binary_start + view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
                stride = view.get('byteStride', 12)
                for i in range(accessor['count']):
                    point = struct.unpack_from('<fff', raw, offset+i*stride)
                    for transform in lineage:
                        point = transformed(point, transform)
                    vertices.append(point)
                triangles += doc['accessors'][primitive['indices']]['count']//3 if 'indices' in primitive else accessor['count']//3
        for child in node.get('children', []):
            visit(child, lineage)

    for index in doc['scenes'][doc.get('scene', 0)]['nodes']:
        visit(index, [])
    assert vertices
    low = [round(min(v[i] for v in vertices), 6) for i in range(3)]
    high = [round(max(v[i] for v in vertices), 6) for i in range(3)]
    return doc, {'min': low, 'max': high, 'size': [round(high[i]-low[i], 6) for i in range(3)], 'triangles': triangles}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    args = parser.parse_args()
    destination = Path(__file__).resolve().parents[1] / 'assets/urban/kenney'
    inventory = json.loads((args.source/'inventory.json').read_text())
    packs = []
    for record in inventory:
        pack = record['pack']
        models = []
        out = destination/pack
        out.mkdir(parents=True, exist_ok=True)
        for name in SELECTION[pack]:
            path, = (args.source/pack).rglob(name+'.glb')
            doc, bounds = inspect_glb(path)
            shutil.copyfile(path, out/path.name)
            models.append({'path': f'assets/urban/kenney/{pack}/{path.name}', 'source_path': str(path.relative_to(args.source/pack)), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), **bounds})
            for image in doc.get('images', []):
                if 'uri' in image:
                    uri = image['uri']
                    assert not Path(uri).is_absolute() and '..' not in Path(uri).parts
                    (out/uri).parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(path.parent/uri, out/uri)
        licenses = list((args.source/pack).rglob('*icense*'))
        assert licenses, pack
        shutil.copyfile(licenses[0], out/'License.txt')
        packs.append({k: record[k] for k in ['pack', 'arcont_id', 'source', 'download', 'license', 'archive_sha256', 'archive_bytes']} | {'models': models})
    files = []
    for path in sorted(destination.rglob('*')):
        if path.is_file():
            files.append({'path': str(path.relative_to(destination.parents[2])), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'bytes': path.stat().st_size})
    (destination.parent/'sources.lock.json').write_text(json.dumps({'schema_version':1, 'arcont_revision':'c59ad6b748814ce01c56aac360060c58b8534ba8', 'packs': packs, 'files': files}, indent=2)+'\n')
    for pack in packs:
        for model in pack['models']:
            print(model['path'], model['size'], model['triangles'])


if __name__ == '__main__':
    main()
