#!/usr/bin/env python3
"""Build and capture the canonical city through Arcont; verify real dependencies."""
import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--arcont',default=os.environ.get('ARCONT_ROOT'))
    p.add_argument('--engine',action='store_true')
    args=p.parse_args()
    if not args.arcont:
        p.error('ARCONT_ROOT is required')
    lock=json.loads((ROOT/'assets/urban/sources.lock.json').read_text())
    for f in lock['files']:
        path=ROOT/f['path']
        assert path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest()==f['sha256'],f['path']
    locked={m['path'] for pack in lock['packs'] for m in pack['models']}
    calls=[]
    def control(op,**kwargs):
        r=subprocess.run([sys.executable,str(Path(args.arcont)/'tools/map_forge_control.py'),'--project',str(ROOT)],input=json.dumps(dict(protocol_version=1,operation=op,map_id='urban_nexo_01',**kwargs)),capture_output=True,text=True,timeout=240)
        data=json.loads(r.stdout)
        assert r.returncode==0 and data.get('ok'),data
        calls.append({'operation':op,'ok':True})
        return data
    inspected=control('inspect')
    m=inspected['state']['map']
    assert all(i['scene'].removeprefix('res://') in locked for i in m['authoring']['instances'])
    control('validate')
    report=dict(ok=True,revision=inspected['revision'],engine_tested=args.engine,source_models=len(locked),asset_instances=len(m['authoring']['instances']),source_bytes=sum(f['bytes'] for f in lock['files']),calls=calls)
    if args.engine:
        built=control('materialize')
        assert built['navigation']['polygons']>0,built
        captured=control('capture',options={'views':[],'cameras':m['evidence_cameras']})
        assert len(captured['images'])==len(m['evidence_cameras']) and not captured['visual_stats']['errors'],captured
        report.update(navigation=built['navigation'],visual_stats=captured['visual_stats'],images=captured['images'])
    out=ROOT/'.mapforge/urban-build.json'
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(report,indent=2)+'\n')
    print('URBAN_NEXO_BUILD_OK',json.dumps(report))


if __name__=='__main__':
    main()
