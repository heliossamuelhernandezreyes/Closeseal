#!/usr/bin/env python3
"""Controlled Nexo fault -> diagnosis -> ARCONT repair -> replay acceptance.

The checkout is never intentionally left broken. A disposable staged Nexo copy is
used for every mutation. ARCONT performs the map edits and revisioned Godot
authoring; this harness only supplies a deterministic diagnosis policy so the
closed loop can be tested in CI without an LLM.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
from pathlib import Path


FAULT_OBJECT_ID = "hero_cover_body_0"
FAULT_HEIGHT = 1.70
FAULT_CENTER_Y = 0.85
CANONICAL_HEIGHT = 1.14
CANONICAL_CENTER_Y = 0.57


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command: list[str], *, cwd: Path | None = None, log: Path | None = None, timeout: int = 600) -> subprocess.CompletedProcess:
    completed = subprocess.run(command, cwd=cwd, text=True, capture_output=True, timeout=timeout, check=False)
    if log is not None:
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text(completed.stdout + completed.stderr, encoding="utf-8")
    if completed.returncode:
        raise RuntimeError({
            "command": command,
            "returncode": completed.returncode,
            "stdout_tail": completed.stdout[-3000:],
            "stderr_tail": completed.stderr[-3000:],
        })
    return completed


def run_agent(arcont: Path, project: Path, plan: dict, evidence: Path, name: str) -> dict:
    command = [
        sys.executable,
        str(arcont / "tools/arcont_agent.py"),
        "run-plan",
        "--project",
        str(project),
        "--plan",
        "-",
        "--allow-project-write",
    ]
    completed = subprocess.run(
        command,
        input=json.dumps(plan),
        text=True,
        capture_output=True,
        timeout=900,
        check=False,
    )
    (evidence / f"{name}.stdout.json").write_text(completed.stdout, encoding="utf-8")
    (evidence / f"{name}.stderr.log").write_text(completed.stderr, encoding="utf-8")
    try:
        report = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError({"invalid_agent_json": name, "stderr": completed.stderr[-3000:]}) from exc
    if completed.returncode or not report.get("ok"):
        raise RuntimeError({"agent_plan_failed": name, "report": report})
    return report


def step_output(report: dict, step_id: str) -> dict:
    for step in report.get("steps", []):
        if step.get("id") == step_id:
            return step["output"]
    raise KeyError(step_id)


def checkpoint_states(playtest_output: dict) -> dict[str, dict]:
    report = playtest_output["result"]["report"]
    return {item["id"]: item for item in report["checkpoints"]}


def find_object(data: dict, identity: str) -> dict:
    for item in data.get("authoring", {}).get("objects", []):
        if item.get("id") == identity:
            return item
    raise KeyError(identity)


def nearest_collision_box(data: dict, position: list[float]) -> dict:
    px, _, pz = map(float, position)
    candidates = []
    for item in data.get("authoring", {}).get("objects", []):
        if item.get("type") != "box" or item.get("collision") is not True:
            continue
        center = item.get("position")
        size = item.get("size")
        if not (isinstance(center, list) and len(center) >= 3 and isinstance(size, list) and len(size) >= 3):
            continue
        horizontal = math.hypot(float(center[0]) - px, float(center[2]) - pz)
        candidates.append((horizontal, -float(size[0]) * float(size[2]), item))
    if not candidates:
        raise RuntimeError("no collidable box candidates near failed cover checkpoint")
    candidates.sort(key=lambda value: (value[0], value[1]))
    return candidates[0][2]


def runtime_recipe(project: Path) -> dict:
    recipe = json.loads((project / "authoring/recipes/shooter_third_person.json").read_text(encoding="utf-8"))
    dependencies = {}
    for relative in recipe.get("dependencies", {}):
        path = project / relative
        if path.is_file():
            dependencies[relative] = sha256(path)
    recipe["dependencies"] = dependencies
    return recipe


def map_fault_plan(original: dict) -> dict:
    return {
        "protocol": "arcont-agent-plan",
        "version": 1,
        "id": "nexo_inject_low_cover_fault",
        "goal": "Inject a bounded physical low-cover height fault by stable map object ID.",
        "permissions": {"project_write": True},
        "capability_allowlist": ["map-forge.editor.control"],
        "steps": [
            {
                "id": "inspect_map",
                "kind": "invoke",
                "capability": "map-forge.editor.control",
                "request": {"protocol_version": 1, "operation": "inspect", "map_id": "nexo_combat_01"},
            },
            {
                "id": "fault_cover",
                "kind": "invoke",
                "capability": "map-forge.editor.control",
                "request": {
                    "protocol_version": 1,
                    "operation": "patch",
                    "map_id": "nexo_combat_01",
                    "if_revision": {"$from": "inspect_map", "pointer": "/result/revision"},
                    "dry_run": False,
                    "patch": [
                        {
                            "op": "test",
                            "path": f"/map/authoring/objects/@{FAULT_OBJECT_ID}/size/1",
                            "value": original["size"][1],
                        },
                        {
                            "op": "test",
                            "path": f"/map/authoring/objects/@{FAULT_OBJECT_ID}/position/1",
                            "value": original["position"][1],
                        },
                        {
                            "op": "replace",
                            "path": f"/map/authoring/objects/@{FAULT_OBJECT_ID}/size/1",
                            "value": FAULT_HEIGHT,
                        },
                        {
                            "op": "replace",
                            "path": f"/map/authoring/objects/@{FAULT_OBJECT_ID}/position/1",
                            "value": FAULT_CENTER_Y,
                        },
                    ],
                },
                "expect": [
                    {"pointer": "/result/committed", "op": "equals", "value": True},
                    {"pointer": "/result/revision", "op": "exists"},
                ],
            },
        ],
    }


def first_playtest_plan(recipe: dict, session: dict) -> dict:
    return {
        "protocol": "arcont-agent-plan",
        "version": 1,
        "id": "nexo_observe_fault",
        "goal": "Build the faulted Nexo slice and observe the real third-person cover/vault route.",
        "permissions": {"project_write": True},
        "capability_allowlist": ["godot.authoring.control"],
        "steps": [
            {
                "id": "inventory",
                "kind": "inspect-project",
                "max_files": 50000,
                "expect": [{"pointer": "/project/engine", "op": "equals", "value": "godot"}],
            },
            {
                "id": "author",
                "kind": "invoke",
                "capability": "godot.authoring.control",
                "timeout_seconds": 300,
                "request": {
                    "protocol_version": 1,
                    "operation": "create",
                    "document_id": recipe["id"],
                    "recipe": recipe,
                    "dry_run": False,
                    "options": {"audio_driver": "Dummy"},
                },
                "expect": [{"pointer": "/result/revision", "op": "exists"}],
            },
            {
                "id": "inspect_authored",
                "kind": "invoke",
                "capability": "godot.authoring.control",
                "request": {
                    "protocol_version": 1,
                    "operation": "inspect",
                    "document_id": recipe["id"],
                },
            },
            {
                "id": "playtest",
                "kind": "invoke",
                "capability": "godot.authoring.control",
                "timeout_seconds": 300,
                "request": {
                    "protocol_version": 1,
                    "operation": "playtest",
                    "document_id": recipe["id"],
                    "if_revision": {"$from": "inspect_authored", "pointer": "/result/revision"},
                    "if_bundle": {"$from": "inspect_authored", "pointer": "/result/last_build/directory"},
                    "scene": "scenes/nexo_third_person.tscn",
                    "session": session,
                    "options": {"audio_driver": "Dummy"},
                },
            },
        ],
    }


def diagnose_fault(project: Path, playtest_output: dict) -> dict:
    states = checkpoint_states(playtest_output)
    cover = states["cover_settle"]["state"]
    vault = states["vault_midpoint"]["state"]
    land = states["land"]["state"]
    data = json.loads((project / "maps/nexo_combat_01.json").read_text(encoding="utf-8"))
    obstacle = nearest_collision_box(data, cover["position"])
    top_y = float(obstacle["position"][1]) + float(obstacle["size"][1]) * 0.5

    signals = {
        "cover_is_not_low": cover.get("cover_low") is not True or cover.get("crouched") is not True,
        "vault_state_not_reached": vault.get("movement_state") != "vault",
        "vault_route_not_completed": land.get("position", [0, 0, 999])[2] > 99.8 or land.get("vault_aborted") is True,
    }
    if not signals["cover_is_not_low"] or not signals["vault_state_not_reached"]:
        raise RuntimeError({"controlled_fault_not_observed": signals, "states": states})
    if obstacle.get("id") != FAULT_OBJECT_ID:
        raise RuntimeError({"unexpected_obstacle_diagnosis": obstacle.get("id"), "expected": FAULT_OBJECT_ID})

    return {
        "ok": True,
        "code": "low_cover_height_out_of_vault_range",
        "signals": signals,
        "object_id": obstacle["id"],
        "observed": {
            "center_y": obstacle["position"][1],
            "height": obstacle["size"][1],
            "top_y": top_y,
            "cover_low": cover.get("cover_low"),
            "cover_crouched": cover.get("crouched"),
            "vault_state": vault.get("movement_state"),
            "land_position": land.get("position"),
        },
        "repair": {
            "position_y": CANONICAL_CENTER_Y,
            "height": CANONICAL_HEIGHT,
            "reason": "restore the known accepted low-cover geometry selected by stable object ID",
        },
    }


def repair_map_plan(diagnosis: dict) -> dict:
    identity = diagnosis["object_id"]
    return {
        "protocol": "arcont-agent-plan",
        "version": 1,
        "id": "nexo_repair_low_cover",
        "goal": "Restore the diagnosed low-cover obstacle using revision-checked stable-ID editing.",
        "permissions": {"project_write": True},
        "capability_allowlist": ["map-forge.editor.control"],
        "steps": [
            {
                "id": "inspect_faulted_map",
                "kind": "invoke",
                "capability": "map-forge.editor.control",
                "request": {"protocol_version": 1, "operation": "inspect", "map_id": "nexo_combat_01"},
            },
            {
                "id": "repair_cover",
                "kind": "invoke",
                "capability": "map-forge.editor.control",
                "request": {
                    "protocol_version": 1,
                    "operation": "patch",
                    "map_id": "nexo_combat_01",
                    "if_revision": {"$from": "inspect_faulted_map", "pointer": "/result/revision"},
                    "dry_run": False,
                    "patch": [
                        {"op": "test", "path": f"/map/authoring/objects/@{identity}/size/1", "value": FAULT_HEIGHT},
                        {"op": "test", "path": f"/map/authoring/objects/@{identity}/position/1", "value": FAULT_CENTER_Y},
                        {"op": "replace", "path": f"/map/authoring/objects/@{identity}/size/1", "value": diagnosis["repair"]["height"]},
                        {"op": "replace", "path": f"/map/authoring/objects/@{identity}/position/1", "value": diagnosis["repair"]["position_y"]},
                    ],
                },
                "expect": [
                    {"pointer": "/result/committed", "op": "equals", "value": True},
                    {"pointer": "/result/revision", "op": "exists"},
                ],
            },
        ],
    }


def recovery_playtest_plan(recipe: dict, session: dict) -> dict:
    return {
        "protocol": "arcont-agent-plan",
        "version": 1,
        "id": "nexo_verify_repair",
        "goal": "Rebuild from the repaired revision and prove the exact cover/vault route recovers.",
        "permissions": {"project_write": True},
        "capability_allowlist": ["godot.authoring.control"],
        "steps": [
            {
                "id": "inspect_old_authoring",
                "kind": "invoke",
                "capability": "godot.authoring.control",
                "request": {
                    "protocol_version": 1,
                    "operation": "inspect",
                    "document_id": recipe["id"],
                },
            },
            {
                "id": "rebuild",
                "kind": "invoke",
                "capability": "godot.authoring.control",
                "timeout_seconds": 300,
                "request": {
                    "protocol_version": 1,
                    "operation": "replace",
                    "document_id": recipe["id"],
                    "if_revision": {"$from": "inspect_old_authoring", "pointer": "/result/revision"},
                    "recipe": recipe,
                    "dry_run": False,
                    "options": {"audio_driver": "Dummy"},
                },
                "expect": [{"pointer": "/result/revision", "op": "exists"}],
            },
            {
                "id": "inspect_repaired_authoring",
                "kind": "invoke",
                "capability": "godot.authoring.control",
                "request": {
                    "protocol_version": 1,
                    "operation": "inspect",
                    "document_id": recipe["id"],
                },
            },
            {
                "id": "playtest",
                "kind": "invoke",
                "capability": "godot.authoring.control",
                "timeout_seconds": 300,
                "request": {
                    "protocol_version": 1,
                    "operation": "playtest",
                    "document_id": recipe["id"],
                    "if_revision": {"$from": "inspect_repaired_authoring", "pointer": "/result/revision"},
                    "if_bundle": {"$from": "inspect_repaired_authoring", "pointer": "/result/last_build/directory"},
                    "scene": "scenes/nexo_third_person.tscn",
                    "session": session,
                    "options": {"audio_driver": "Dummy"},
                },
                "expect": [
                    {"pointer": "/result/passed", "op": "equals", "value": True},
                    {"pointer": "/result/report/input_released", "op": "equals", "value": True},
                ],
            },
        ],
    }


def prepare_stage(source: Path, stage: Path, godot: str, evidence: Path) -> None:
    run([sys.executable, str(source / "tools/prepare_shooter.py"), "--stage", str(stage)], cwd=source, log=evidence / "prepare-stage.log")

    # The staged slice normally consumes a pre-baked sector. This experiment
    # deliberately edits the canonical map, so force the existing dynamic
    # MapVisualKit path instead of allowing stale derived geometry.
    derived = stage / "assets/shooter/sector07/sector_world.tscn"
    derived.unlink(missing_ok=True)

    shutil.copy(source / "map-forge.authoring.json", stage / "map-forge.authoring.json")
    for name in ("map_forge_adapter.py", "validate_maps.py", "validate_environment.py"):
        shutil.copy(source / "tools" / name, stage / "tools" / name)

    run([godot, "--headless", "--path", str(stage), "--editor", "--import"], log=evidence / "import-1.log")
    run([sys.executable, str(source / "tools/configure_shooter_imports.py"), "--stage", str(stage)], cwd=source, log=evidence / "configure-imports.log")
    run([godot, "--headless", "--path", str(stage), "--editor", "--import"], log=evidence / "import-2.log")
    run([godot, "--headless", "--path", str(stage), "--script", "res://tools/shooter_bake.gd"], log=evidence / "bake.log")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arcont", type=Path, required=True)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()

    source = Path(__file__).resolve().parents[1]
    arcont = args.arcont.resolve()
    stage = args.stage.resolve()
    evidence = args.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    godot = os.environ.get("GODOT_BIN", "godot")

    prepare_stage(source, stage, godot, evidence)

    map_path = stage / "maps/nexo_combat_01.json"
    canonical_sha = sha256(map_path)
    canonical_data = json.loads(map_path.read_text(encoding="utf-8"))
    original = find_object(canonical_data, FAULT_OBJECT_ID)
    if original["size"][1] != CANONICAL_HEIGHT or original["position"][1] != CANONICAL_CENTER_Y:
        raise RuntimeError({"unexpected_canonical_cover": original})

    session = json.loads((stage / "authoring/scenarios/shooter_third_person.json").read_text(encoding="utf-8"))

    fault_edit = run_agent(arcont, stage, map_fault_plan(original), evidence, "01-fault-map")
    fault_data = json.loads(map_path.read_text(encoding="utf-8"))
    fault_object = find_object(fault_data, FAULT_OBJECT_ID)
    if fault_object["size"][1] != FAULT_HEIGHT or fault_object["position"][1] != FAULT_CENTER_Y:
        raise RuntimeError({"fault_not_committed": fault_object})

    fault_recipe = runtime_recipe(stage)
    fault_observation = run_agent(arcont, stage, first_playtest_plan(fault_recipe, session), evidence, "02-observe-fault")
    fault_playtest = step_output(fault_observation, "playtest")
    diagnosis = diagnose_fault(stage, fault_playtest)
    (evidence / "03-diagnosis.json").write_text(json.dumps(diagnosis, indent=2), encoding="utf-8")

    repair_edit = run_agent(arcont, stage, repair_map_plan(diagnosis), evidence, "04-repair-map")
    if sha256(map_path) != canonical_sha:
        raise RuntimeError({
            "repair_did_not_restore_canonical_map_bytes": {
                "expected": canonical_sha,
                "actual": sha256(map_path),
            }
        })

    repaired_recipe = runtime_recipe(stage)
    recovery = run_agent(arcont, stage, recovery_playtest_plan(repaired_recipe, session), evidence, "05-verify-repair")
    repaired_playtest = step_output(recovery, "playtest")
    states = checkpoint_states(repaired_playtest)
    cover = states["cover_settle"]["state"]
    vault = states["vault_midpoint"]["state"]
    land = states["land"]["state"]

    assertions = {
        "fault_was_detected": diagnosis["ok"],
        "canonical_map_restored_byte_for_byte": sha256(map_path) == canonical_sha,
        "cover_low_recovered": cover.get("movement_state") == "cover" and cover.get("cover_low") is True and cover.get("crouched") is True,
        "vault_recovered": vault.get("movement_state") == "vault",
        "landing_recovered": land.get("movement_state") == "free" and land.get("vault_aborted") is False,
        "playtest_passed": repaired_playtest["result"].get("passed") is True,
        "input_released": repaired_playtest["result"]["report"].get("input_released") is True,
    }
    if not all(assertions.values()):
        raise RuntimeError({"recovery_assertions": assertions, "states": states})

    summary = {
        "ok": True,
        "arcont_head": subprocess.check_output(["git", "-C", str(arcont), "rev-parse", "HEAD"], text=True).strip(),
        "fault": {
            "object_id": FAULT_OBJECT_ID,
            "canonical_height": CANONICAL_HEIGHT,
            "fault_height": FAULT_HEIGHT,
            "diagnosis": diagnosis,
            "map_plan_sha256": fault_edit["plan_sha256"],
            "observation_plan_sha256": fault_observation["plan_sha256"],
            "playtest_passed": fault_playtest["result"].get("passed"),
        },
        "repair": {
            "map_plan_sha256": repair_edit["plan_sha256"],
            "verification_plan_sha256": recovery["plan_sha256"],
            "canonical_map_sha256": canonical_sha,
            "assertions": assertions,
            "physics_frames": repaired_playtest["result"]["report"]["physics_frames"],
            "final_state": repaired_playtest["result"]["report"]["final_state"],
        },
        "limits": [
            "Controlled disposable-stage repair experiment; production repository content is not committed by the loop.",
            "Diagnosis policy is deterministic CI logic, not an autonomous LLM planner.",
            "Linux/Xvfb evidence does not establish Android handset FPS, thermals, or subjective animation quality.",
        ],
    }
    (evidence / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
