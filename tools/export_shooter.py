#!/usr/bin/env python3
"""Generate reproducible Godot export presets in the isolated shooter staging project."""
import argparse
import json
import os
import subprocess
from pathlib import Path


def presets(template_dir: Path):
    definitions = [
        ("Linux", "Linux", "linux_release.x86_64", 'binary_format/architecture="x86_64"\nbinary_format/embed_pck=true'),
        ("Windows", "Windows Desktop", "windows_release_x86_64.exe", 'binary_format/architecture="x86_64"\nbinary_format/embed_pck=true'),
        ("Android", "Android", "android_debug.apk", '''architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
gradle_build/use_gradle_build=false
package/unique_name="org.closeseal.nexo.preview080"
package/name="Nexo 0.8 — Sector 07"
version/code=9
version/name="0.8.0"
screen/immersive_mode=true
permissions/internet=false'''),
        ("Web", "Web", "web_nothreads_release.zip", 'variant/thread_support=false\nprogressive_web_app/enabled=true\nhtml/canvas_resize_policy=2'),
    ]
    output = []
    for index, (name, platform, filename, options) in enumerate(definitions):
        file = (template_dir / filename).as_posix()
        quoted_file = json.dumps(file, ensure_ascii=False)
        output.append(f'''[preset.{index}]
name="{name}"
platform="{platform}"
runnable=true
export_filter="all_resources"
include_filter="maps/nexo_combat_01.json,assets/shooter/audio/banks/bank.json"
exclude_filter="tools/*,authoring/*,assets/production_candidates/*,assets/urban/sources.lock.json,assets/shooter/sources.lock.json,assets/shooter/animation_sources/*,assets/shooter/serious/factory_building.glb,assets/shooter/sector07/sector_bake.tscn,assets/shooter/sector07/*.json"
export_path=""

[preset.{index}.options]
custom_template/debug={quoted_file}
custom_template/release={quoted_file}
{options}
''')
    return "\n".join(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--templates", type=Path, required=True)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--platform", choices=["Linux", "Windows", "Android", "Web"], required=True)
    args = parser.parse_args()
    (args.stage / "export_presets.cfg").write_text(presets(args.templates.resolve()))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    mode = "--export-debug" if args.platform == "Android" else "--export-release"
    result = subprocess.run([str(args.engine), "--headless", "--path", str(args.stage), mode, args.platform, str(args.output.resolve())])
    if result.returncode: raise SystemExit(result.returncode)
    if not args.output.exists(): raise SystemExit("export did not produce a build")
    print(json.dumps({"ok": True, "platform": args.platform, "file": str(args.output), "bytes": args.output.stat().st_size}))


if __name__ == "__main__": main()
