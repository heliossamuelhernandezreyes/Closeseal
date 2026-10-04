#!/usr/bin/env python3
"""Rebuild source motion using ARCONT, reopen and compare every delivered native key."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arcont',type=Path,required=True);parser.add_argument('--project',type=Path,required=True)
    args=parser.parse_args();project=args.project.resolve();recipe=json.loads((project/'authoring/recipes/nexo_motion_source.json').read_text())
    control=[sys.executable,str(args.arcont.resolve()/'tools/godot_authoring_control.py'),'--project',str(project)]
    def call(operation,**values):
        request={'protocol_version':1,'operation':operation,'document_id':recipe['id'],**values}
        run=subprocess.run(control,input=json.dumps(request),text=True,capture_output=True,timeout=240)
        result=json.loads(run.stdout)
        if run.returncode or not result.get('ok'):raise RuntimeError(result)
        return result
    document=project/'authoring/documents/nexo_motion_source.json'
    if document.exists():
        state=call('inspect');call('replace',if_revision=state['revision'],recipe=recipe,dry_run=False,options={'audio_driver':'Dummy'})
    else:call('create',recipe=recipe,dry_run=False,options={'audio_driver':'Dummy'})
    state=call('inspect');candidate=state['last_build']['directory']+'/motion.res'
    run=subprocess.run([os.environ['GODOT_BIN'],'--headless','--path',str(project),'--script','res://tools/shooter_motion_repro.gd','--','--candidate=res://'+candidate],capture_output=True,text=True,timeout=60)
    if run.returncode or any(s in run.stdout+run.stderr for s in ('SCRIPT ERROR','ERROR:')):raise RuntimeError(run.stdout+run.stderr)
    print(run.stdout)

if __name__=='__main__':main()
