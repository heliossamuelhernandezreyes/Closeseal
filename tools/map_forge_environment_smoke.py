#!/usr/bin/env python3
"""Operate authored environment fixtures through the actual ARCONT interface."""
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--arcont', default=os.environ.get('ARCONT_ROOT'))
    p.add_argument('--engine', action='store_true')
    args = p.parse_args()
    if not args.arcont:
        raise SystemExit('ARCONT_ROOT is required')
    tool = Path(args.arcont) / 'tools/map_forge_control.py'
    calls, evidence = [], []

    def control(op, expected=True, **params):
        run = subprocess.run([sys.executable, str(tool), '--project', str(ROOT)], input=json.dumps({'protocol_version': 1, 'operation': op, **params}), text=True, capture_output=True, timeout=240)
        result = json.loads(run.stdout)
        assert result['ok'] is expected, result
        assert (run.returncode == 0) is expected, run.stderr
        calls.append({'operation': op, 'ok': result['ok'], 'map_id': params.get('map_id')})
        return result

    map_id = 'environment_alpine_lab'
    before = control('inspect', map_id=map_id)
    changed = None
    try:
        options = {'heightfield_id': 'alpine_ground', 'center': [0, 0], 'radius': 5, 'strength': 2, 'mode': 'raise'}
        dry = control('brush', map_id=map_id, if_revision=before['revision'], options=options)
        assert not dry['committed'] and dry['revision'] != before['revision']
        assert control('inspect', map_id=map_id)['revision'] == before['revision']
        control('brush', expected=False, map_id=map_id, if_revision='stale', options=options, dry_run=False)
        changed = control('brush', map_id=map_id, if_revision=before['revision'], options=options, dry_run=False)
        painted = control('brush', map_id=map_id, if_revision=changed['revision'], options={**options, 'mode': 'paint', 'material': 'snow'}, dry_run=False)
        changed = painted
        assert 'snow' in painted['state']['map']['authoring']['heightfields'][0]['paint']
        control('patch', expected=False, map_id=map_id, if_revision=painted['revision'], patch=[{'op': 'replace', 'path': '/map/authoring/heightfields/@alpine_ground/heights', 'value': [0]}], dry_run=False)
        if args.engine:
            built = control('materialize', map_id=map_id)
            sync = built['terrain3d']
            assert sync['paint_preserved'] and sync['region_files'] and sync['maximum_height_error'] < 0.001, sync
            actual = sync['reloaded_state']['map']['authoring']['heightfields'][0]
            authored = painted['state']['map']['authoring']['heightfields'][0]
            assert max(abs(a-b) for a,b in zip(actual['heights'], authored['heights'])) < 0.001
            assert actual['paint'] == authored['paint'] and actual['holes'] == authored.get('holes', [False]*256)
            pulled = control('edit', map_id=map_id, if_revision=painted['revision'], options={'action': 'terrain_pull'})
            assert not pulled['committed']
            evidence.append({'map_id': map_id, 'terrain3d': {k:v for k,v in sync.items() if k != 'reloaded_state'}})
    finally:
        if changed:
            control('restore', map_id=map_id, if_revision=changed['revision'], restore_revision=before['revision'], dry_run=False)
    for map_id in ('environment_alpine_lab', 'environment_interior_lab', 'environment_orbital_lab'):
        state = control('inspect', map_id=map_id)['state']
        assert state['map']['purpose'] == 'environment' and not state['map']['bases']
        if args.engine:
            built = control('materialize', map_id=map_id)
            camera = state['map']['evidence_camera']
            captured = control('capture', map_id=map_id, options={'views': [], 'cameras': [camera]})
            stats = captured['visual_stats']
            assert not stats['errors'] and stats['environment_objects'] > 0
            assert stats['authored_lights'] > 0 and stats['route_segments'] == 0
            assert Path(captured['images'][0]).stat().st_size > 1000
            if map_id == 'environment_interior_lab':
                assert built['navigation']['status'] == 'baked_actual_world_colliders' and built['navigation']['polygons'] > 0
            evidence.append({'map_id':map_id, 'navigation':built['navigation'], 'visual_stats':stats, 'images':captured['images']})
    output = ROOT / '.mapforge/environment-smoke.json'
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps({'ok':True, 'engine_tested':args.engine, 'calls':calls, 'evidence':evidence}, indent=2))
    print('MAP_FORGE_ENVIRONMENT_SMOKE_OK ' + json.dumps({'operations':len(calls),'engine_tested':args.engine}))


if __name__ == '__main__':
    main()
