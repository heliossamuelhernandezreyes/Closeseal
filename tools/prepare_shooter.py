#!/usr/bin/env python3
"""Stage the separate shooter build without changing the original RTS entry scene."""
import argparse
import hashlib
import json
import math
import random
import shutil
import struct
import tempfile
import wave
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OWNER = {"owner": "closeseal-nexo-shooter", "schema": 1}
MARKER = ".nexo-shooter-stage.json"


def audio():
    directory = ROOT / "assets/shooter/audio"
    directory.mkdir(parents=True, exist_ok=True)
    for name, duration in [("shot", 0.14), ("hit", 0.09), ("reload", 0.24), ("secure", 0.5)]:
        rng = random.Random(12)
        samples = []
        for i in range(int(duration * 22050)):
            t = i / 22050
            envelope = (1 - t / duration) ** 2
            if name == "shot": value = (rng.uniform(-1, 1) * 0.65 + math.sin(t * 350) * 0.35) * envelope
            elif name == "hit": value = math.sin(t * 5200) * envelope * 0.45
            elif name == "reload": value = rng.uniform(-1, 1) * envelope * (1 if int(t * 35) % 3 == 0 else 0.08) * 0.5
            else: value = math.sin(t * math.tau * (523 if t < 0.2 else 784)) * envelope * 0.35
            samples.append(struct.pack("<h", int(value * 24000)))
        with wave.open(str(directory / (name + ".wav")), "wb") as output:
            output.setnchannels(1); output.setsampwidth(2); output.setframerate(22050)
            output.writeframes(b"".join(samples))


def _populate(target):
    from verify_shooter_sector import verify
    report = verify(ROOT)
    if not report["ok"]:
        raise ValueError("invalid derived sector: " + str(report["errors"]))
    target.mkdir(parents=True, exist_ok=True)
    for path in ["assets/shooter", "src/shooter", "src/map", "src/prototype"]:
        shutil.copytree(ROOT / path, target / path, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns("*.import", "*.uid", "kenney", "sources.lock.json","AnimationLibrary_Godot_Standard.gltf","AnimationLibrary_Godot_Standard.bin"))
    source=target / "assets/shooter/animation_sources/quaternius"
    provenance=json.loads((source / "source.json").read_text())
    archive=source / provenance["archive"]["file"]
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=provenance["archive"]["sha256"]:
        raise ValueError("animation source archive changed")
    with zipfile.ZipFile(archive) as packed:
        names={"AnimationLibrary_Godot_Standard.gltf","AnimationLibrary_Godot_Standard.bin"}
        if set(packed.namelist())!=names:raise ValueError("unexpected animation source member")
        for name in names:
            if packed.getinfo(name).file_size>16*1024*1024:raise ValueError("animation source member exceeds bound")
            data=packed.read(name)
            if hashlib.sha256(data).hexdigest()!=provenance["files"][name]:raise ValueError("animation source member changed")
            (source / name).write_bytes(data)
    # Native lightmap atlases use a layered importer, not the default 2D EXR importer.
    for metadata in (ROOT / "assets/shooter/sector07").glob("*.exr.import"):
        shutil.copy(metadata, target / "assets/shooter/sector07" / metadata.name)
    (target / "maps").mkdir(exist_ok=True)
    shutil.copy(ROOT / "maps/nexo_combat_01.json", target / "maps/nexo_combat_01.json")
    (target / "tools").mkdir(exist_ok=True)
    for script in ROOT.glob("tools/shooter_*.gd"):
        shutil.copy(script, target / "tools" / script.name)
    for name in ["godot_authoring_adapter.py", "godot_authoring_worker.gd", "godot_playtest_runner.gd"]:
        shutil.copy(ROOT / "tools" / name, target / "tools" / name)
    shutil.copy(ROOT / "tools/build_shooter_audio.py",target / "tools/build_shooter_audio.py")
    shutil.copy(ROOT / "godot-authoring.json", target / "godot-authoring.json")
    for folder in ["recipes", "scenarios"]:
        (target / "authoring" / folder).mkdir(parents=True, exist_ok=True)
        shutil.copy(ROOT / "authoring" / folder / "shooter_third_person.json", target / "authoring" / folder / "shooter_third_person.json")
    shutil.copy(ROOT / "authoring/recipes/sector07_presentation.json", target / "authoring/recipes/sector07_presentation.json")
    shutil.copy(ROOT / "authoring/recipes/nexo_motion_source.json",target / "authoring/recipes/nexo_motion_source.json")
    shutil.copytree(ROOT / "authoring/production", target / "authoring/production")
    (target / "project.godot").write_text('''config_version=5
[application]
config/name="Closeseal — Nexo"
run/main_scene="res://src/shooter/shooter_arena.tscn"
config/icon="res://assets/shooter/nexo_icon.svg"
config/features=PackedStringArray("4.7", "GL Compatibility")
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/handheld/orientation=0
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/vram_compression/import_etc2_astc=true
textures/default_filters/use_nearest_mipmap_filter=false
anti_aliasing/quality/msaa_3d=1
lights_and_shadows/directional_shadow/size=2048
[input_devices]
pointing/emulate_mouse_from_touch=false
''')
    (target / MARKER).write_text(json.dumps(OWNER) + "\n")


def stage(target):
    target = Path(target).absolute()
    root = ROOT.resolve()
    if target.is_symlink() or target.resolve() == root or target.resolve() in root.parents:
        raise ValueError("stage must be an independent directory, not the project or its ancestor")
    if target.exists():
        if not target.is_dir():
            raise ValueError("stage destination is not a directory")
        if any(target.iterdir()):
            try:
                owned = json.loads((target / MARKER).read_text()) == OWNER
            except (OSError, ValueError):
                owned = False
            if not owned:
                raise ValueError("refusing to replace an unmanaged directory")
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=".nexo-stage-", dir=target.parent))
    backup = None
    try:
        _populate(temporary)
        if target.exists():
            backup = Path(tempfile.mkdtemp(prefix=".nexo-backup-", dir=target.parent))
            backup.rmdir()
            target.rename(backup)
        try:
            temporary.rename(target)
        except BaseException:
            if backup is not None:
                backup.rename(target)
                backup = None
            raise
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
        if backup is not None and backup.exists():
            shutil.rmtree(backup)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path)
    parser.add_argument("--audio", action="store_true")
    args = parser.parse_args()
    if args.audio: audio()
    if args.stage: stage(args.stage)
    print(json.dumps({"ok": True, "stage": str(args.stage) if args.stage else None}))


if __name__ == "__main__": main()
