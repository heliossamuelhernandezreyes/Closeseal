#!/usr/bin/env python3
"""Invoke the tested native editor bake adapter in an independently owned Nexo stage."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project',type=Path,required=True)
    parser.add_argument('--engine',type=Path,required=True)
    args=parser.parse_args();project=args.project.resolve()
    marker=json.loads((project/'.nexo-shooter-stage.json').read_text())
    if marker.get('owner')!='closeseal-nexo-shooter':raise ValueError('managed independent stage required')
    source=Path(__file__).with_name('shooter_lightmap_editor.gd')
    plugin=project/'addons/nexo_lightmap_bake'
    if plugin.exists():raise ValueError('temporary bake adapter directory already exists')
    settings=project/'project.godot';original=settings.read_bytes()
    scene='res://assets/shooter/sector07/sector_bake.tscn'
    if not (project/scene.removeprefix('res://')).is_file():raise ValueError('materialize the Arcont scene candidate first')
    # Complete texture detection and mipmap import before the editor's bake toolbar is opened.
    from configure_shooter_imports import configure
    import_log=project/'.arcont/lightmap-import.log';import_log.parent.mkdir(exist_ok=True)
    with import_log.open('w') as output:
        for pass_ in range(2):
            imported=subprocess.run([str(args.engine.resolve()),'--headless','--path',str(project),'--editor','--import'],stdout=output,stderr=subprocess.STDOUT,timeout=240)
            if imported.returncode:raise RuntimeError('stage import failed: '+str(import_log))
            if pass_==0:configure(project)
    if any(value in import_log.read_text() for value in ('SCRIPT ERROR','Parse Error','ERROR:')):
        raise RuntimeError('stage import reported errors: '+str(import_log))
    plugin.mkdir(parents=True)
    (plugin/'plugin.cfg').write_text('[plugin]\nname="Nexo staged native lightmap bake"\ndescription="Owned stage only"\nauthor="Closeseal"\nversion="1"\nscript="plugin.gd"\n')
    shutil.copy(source,plugin/'plugin.gd')
    settings.write_text(original.decode()+'\n[editor_plugins]\nenabled=PackedStringArray("res://addons/nexo_lightmap_bake/plugin.cfg")\n')
    env=os.environ.copy();env['NEXO_BAKE_SCENE']=scene
    log=project/'.arcont/lightmap-bake.log';log.parent.mkdir(exist_ok=True)
    try:
        warmup=project/'.arcont/lightmap-warmup.log'
        warm_env=dict(env);warm_env['NEXO_BAKE_WARMUP']='1'
        with warmup.open('w') as output:
            warmed=subprocess.run([str(args.engine.resolve()),'--display-driver','x11','--rendering-method','mobile',
                '--path',str(project),'--editor','--audio-driver','Dummy'],env=warm_env,stdout=output,stderr=subprocess.STDOUT,timeout=240)
        if warmed.returncode or 'SCRIPT ERROR' in warmup.read_text():
            raise RuntimeError('native scene warmup failed: '+str(warmup))
        with log.open('w') as output:
            run=subprocess.run([str(args.engine.resolve()),'--display-driver','x11','--rendering-method','mobile',
                '--path',str(project),'--editor','--audio-driver','Dummy'],env=env,stdout=output,stderr=subprocess.STDOUT,timeout=900)
        text=log.read_text()
        if run.returncode or 'SCRIPT ERROR' in text or 'NEXO_LIGHTMAP_EDITOR_DONE' not in text:
            raise RuntimeError('native bake failed; inspect '+str(log))
        receipt=project/'assets/shooter/sector07/sector_bake-bake.json'
        result=json.loads(receipt.read_text())
        if result['properties']['textures']<1 or result['properties']['mesh_binding_fields']<1:
            raise RuntimeError('native bake returned empty output')
        print(json.dumps({'ok':True,'receipt':str(receipt),'engine':result['engine'],'properties':result['properties']}))
    finally:
        settings.write_bytes(original);shutil.rmtree(plugin)


if __name__=='__main__':main()
