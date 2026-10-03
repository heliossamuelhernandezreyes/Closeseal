#!/usr/bin/env python3
"""Exercise consolidated ARCONT tools against delivered Nexo assets and Godot."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arcont",type=Path,required=True)
    parser.add_argument("--project",type=Path,default=ROOT)
    args=parser.parse_args()
    arcont=args.arcont.resolve(); project=args.project.resolve()
    sys.path.insert(0,str(arcont))
    from tools.production_assets import digest, stage
    from tools.production_recipes import animation_profile, sector
    from tools.production_evidence import summarize
    from tools.production_toolchain import doctor
    release=doctor(arcont)
    if not release["ok"]: raise RuntimeError(release)
    profiles=project/"authoring/production"
    assets=json.loads((profiles/"assets.json").read_text())
    animation=animation_profile(json.loads((profiles/"animation.json").read_text()))
    layout=json.loads((profiles/"sector.json").read_text()); sector(layout)
    original_map=(project/"maps/nexo_combat_01.json").read_bytes()
    original_motion=digest(project/"assets/shooter/serious/combat_motion.res")
    bundle=stage(project,assets,"assets/production_candidates")
    repeated=stage(project,assets,"assets/production_candidates")
    if bundle!=repeated: raise RuntimeError("asset staging is not idempotent")
    # Import the visible staged dependencies before the bridge loads them.
    engine=os.environ.get("GODOT_BIN","godot")
    imported=subprocess.run([engine,"--headless","--path",str(project),"--editor","--import"],capture_output=True,text=True,timeout=180)
    log=imported.stdout+imported.stderr
    evidence=project/".arcont/production-evidence"; evidence.mkdir(parents=True,exist_ok=True)
    (evidence/"candidate-import.log").write_text(log)
    if imported.returncode or any(x in log for x in ("SCRIPT ERROR","Parse Error","Failed to load script","ERROR:")):
        raise RuntimeError("candidate import failed: "+log[-4000:])
    control=[sys.executable,str(arcont/"tools/godot_authoring_control.py"),"--project",str(project)]
    def call(operation, **values):
        request={"protocol_version":1,"operation":operation,**values}
        run=subprocess.run(control,input=json.dumps(request),text=True,capture_output=True,timeout=300)
        result=json.loads(run.stdout)
        if run.returncode or not result.get("ok"): raise RuntimeError(result)
        return result
    call("discover",options={"class":"Skeleton3D"})
    source_paths=["tools/shooter_production_probe.gd","assets/shooter/serious/combat_motion.res",
                  "authoring/production/assets.json","authoring/production/animation.json","authoring/production/sector.json"]
    source_paths+=[assets["provenance_manifest"]]+list(bundle["files"])
    for name in ("asphalt", "concrete"):
        material="assets/shooter/serious/materials/"+name+".tres"
        source_paths.append(material)
        source_paths+=re.findall(r'path="res://([^\"]+)"', (project/material).read_text())
    candidate_paths=[bundle["bundle_directory"]+"/"+p for p in bundle["files"]]
    dependencies={p:digest(project/p) for p in source_paths+candidate_paths}
    dependencies[bundle["bundle_directory"]+"/bundle.json"]=digest(project/bundle["bundle_directory"]/"bundle.json")
    records={}
    for operation, arguments in [
        ("assets",{"operation":"assets","bundle":"res://"+bundle["bundle_directory"]+"/bundle.json"}),
        ("animation",{"operation":"animation","profile":animation}),
        ("sector",{"operation":"sector","recipe":layout})]:
        identity="nexo_production_"+operation
        recipe={"version":1,"id":identity,"dependencies":dependencies,"steps":[
            {"op":"new","id":"review_root","class":"Node3D"},
            {"op":"attach","target":"review_root"},
            {"op":"script","id":"review","path":"res://tools/shooter_production_probe.gd","args":arguments},
            {"op":"save","target":"production_world","path":"review.tscn"},
            {"op":"wait","frames":30},
            {"op":"profile","id":"measurement","frames":120},
            {"op":"capture","camera":"production_camera","path":operation+".png","width":1280,"height":720}
        ]}
        document=project/"authoring/documents"/(identity+".json")
        if document.exists():
            before=call("inspect",document_id=identity)
            result=call("replace",document_id=identity,if_revision=before["revision"],recipe=recipe,dry_run=False,options={"render":True,"audio_driver":"Dummy"})
        else:
            result=call("create",document_id=identity,recipe=recipe,dry_run=False,options={"render":True,"audio_driver":"Dummy"})
        accepted=call("inspect",document_id=identity)
        directory=project/accepted["last_build"]["directory"]
        report=json.loads((directory/(operation[:-1]+"-review.json" if operation=="assets" else operation+"-review.json")).read_text())
        # Reopen saved source through the same writer and require its native tree.
        reopened={"version":1,"id":identity+"_reopen","dependencies":dependencies,"steps":[
            {"op":"load","id":"reopened","path":str(directory/"review.tscn"),"instantiate":True},
            {"op":"attach","target":"reopened"},
            {"op":"inspect","target":"reopened"},
            {"op":"wait","frames":2},
            {"op":"remove","target":"reopened"},
            {"op":"wait","frames":2}
        ]}
        call("create",document_id=reopened["id"],recipe=reopened,dry_run=True,options={"render":True,"audio_driver":"Dummy"})
        response=json.loads((directory/"engine-response.json").read_text())
        measurement=next(x["value"] for x in response["steps"] if x["id"]=="measurement")
        record={"scope":"linux-rendered","device":report["device"]+" / "+platform.node(),
            "engine":response["engine"]["string"],"renderer":"gl_compatibility","resolution":[1280,720],
            "build":"editor-runner","scenario":identity,"warmup_frames":30,**measurement}
        record["scope"]="linux-rendered"
        summary=summarize(record)
        (evidence/(operation+"-performance.json")).write_text(json.dumps(record,indent=2))
        shutil.copyfile(directory/(operation+".png"),evidence/(operation+".png"))
        records[operation]={"report":report,"summary":summary,"directory":str(directory.relative_to(project)),
            "saved_scene_reopened":True,"recipe_revision":accepted["revision"]}
    if (project/"maps/nexo_combat_01.json").read_bytes()!=original_map or digest(project/"assets/shooter/serious/combat_motion.res")!=original_motion:
        raise RuntimeError("production review mutated accepted map or animation")
    report={"ok":True,"toolchain":release,"dependency_hashes":dependencies,
        "asset_bundle":bundle["bundle_sha256"],"asset_count":len(bundle["assets"]),"dependency_files":len(bundle["files"]),
        "reviews":records,"canonical_map_preserved":True,"source_motion_preserved":True,
        "limits":["Linux GL compatibility observations; Android device unmeasured",
                  "explicit topology retarget; different body proportions need additional contact acceptance"]}
    (evidence/"acceptance.json").write_text(json.dumps(report,indent=2))
    print(json.dumps({"ok":True,"assets":report["asset_count"],"clips":records["animation"]["report"]["clips"],
        "routes":len(records["sector"]["report"]["routes"]),"evidence":str(evidence)}))


if __name__=="__main__": main()
