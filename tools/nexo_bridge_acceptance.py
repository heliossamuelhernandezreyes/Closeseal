#!/usr/bin/env python3
"""Fresh-agent acceptance of ARCONT Universal Agent Bridge against Nexo.

The test deliberately learns Nexo through the bridge: capability discovery,
persistent project intent, local asset inventory and authoring catalog/document
reads all happen through the provider-neutral JSON protocol. The final
author/build/playtest plan is then executed through the same bridge, which
delegates to ARCONT's existing bounded execution loop.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def bridge_request(
    arcont: Path,
    project: Path,
    operation: str,
    arguments: dict | None = None,
    *,
    allow_write: bool = False,
    request_id: str | None = None,
    timeout: int = 900,
) -> tuple[int, dict]:
    request = {
        "protocol": "arcont-bridge",
        "version": 1,
        "request_id": request_id or operation.replace(".", "-"),
        "operation": operation,
        "arguments": arguments or {},
    }
    command = [
        sys.executable,
        str(arcont / "tools/arcont_bridge.py"),
        "--project",
        str(project),
        "--request",
        "-",
    ]
    if allow_write:
        command.append("--allow-project-write")
    completed = subprocess.run(
        command,
        input=json.dumps(request),
        text=True,
        capture_output=True,
        timeout=timeout,
        check=False,
    )
    if not completed.stdout.strip():
        raise RuntimeError({
            "operation": operation,
            "returncode": completed.returncode,
            "stderr_tail": completed.stderr[-4000:],
        })
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError({
            "operation": operation,
            "invalid_json": completed.stdout[-4000:],
            "stderr_tail": completed.stderr[-4000:],
        }) from exc
    return completed.returncode, payload


def unwrap_ok(code: int, payload: dict, operation: str) -> dict:
    if code or not payload.get("ok"):
        raise RuntimeError({"bridge_operation_failed": operation, "payload": payload})
    result = payload.get("result")
    if not isinstance(result, dict):
        raise RuntimeError({"bridge_result_missing": operation, "payload": payload})
    return result


def choose_document(catalog: dict, *, kind: str, identity: str) -> dict:
    matches = [
        row for row in catalog.get("documents", [])
        if row.get("kind") == kind and row.get("id") == identity and row.get("parseable") is True
    ]
    if len(matches) != 1:
        raise RuntimeError({
            "authoring_document_selection_failed": {
                "kind": kind,
                "id": identity,
                "matches": matches,
            }
        })
    return matches[0]


def checkpoints(playtest_output: dict) -> dict[str, dict]:
    report = playtest_output["result"]["report"]
    return {item["id"]: item for item in report["checkpoints"]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arcont", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()

    arcont = args.arcont.resolve()
    project = args.project.resolve()
    evidence = args.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)

    # 1. Fresh-agent discovery.
    code, envelope = bridge_request(arcont, project, "discover", request_id="nexo-discover")
    discovery = unwrap_ok(code, envelope, "discover")
    bridge = discovery["bridge"]
    if bridge.get("protocol") != "arcont-bridge" or bridge.get("version") != 1:
        raise RuntimeError({"unexpected_bridge": bridge})
    required_ops = {
        "project.inspect",
        "project.intent.read",
        "assets.inspect",
        "authoring.catalog",
        "authoring.document.read",
        "plan.execute",
    }
    if not required_ops.issubset(set(bridge.get("operations", []))):
        raise RuntimeError({"bridge_missing_operations": sorted(required_ops - set(bridge.get("operations", [])))})
    capability_ids = {
        item.get("id") for item in discovery["agent_control"].get("capabilities", [])
    }
    for required in ("agent.bridge", "godot.authoring.control"):
        if required not in capability_ids:
            raise RuntimeError({"missing_capability": required})

    # 2. Read project-owned intent rather than relying on chat memory.
    code, envelope = bridge_request(arcont, project, "project.intent.read", request_id="nexo-intent")
    intent_report = unwrap_ok(code, envelope, "project.intent.read")
    if not intent_report.get("present"):
        raise RuntimeError("Nexo persistent project intent is missing")
    intent = intent_report["intent"]
    if intent.get("project_id") != "nexo" or intent.get("genre") != "third-person shooter":
        raise RuntimeError({"unexpected_nexo_intent": intent})
    if "movement feel" not in intent.get("priorities", []):
        raise RuntimeError({"intent_missing_movement_priority": intent.get("priorities")})

    # 3. Inspect the external project and its local asset surface.
    code, envelope = bridge_request(
        arcont,
        project,
        "project.inspect",
        {"max_files": 50000},
        request_id="nexo-project-inspect",
    )
    project_report = unwrap_ok(code, envelope, "project.inspect")
    if project_report["project"].get("engine") != "godot":
        raise RuntimeError({"unexpected_engine": project_report["project"].get("engine")})

    code, envelope = bridge_request(
        arcont,
        project,
        "assets.inspect",
        {"max_assets": 10000},
        request_id="nexo-assets",
    )
    asset_report = unwrap_ok(code, envelope, "assets.inspect")
    if asset_report.get("asset_count", 0) < 1:
        raise RuntimeError("Bridge discovered no Nexo assets")

    # 4. Discover recipe/scenario rather than opening known paths directly.
    code, envelope = bridge_request(arcont, project, "authoring.catalog", request_id="nexo-authoring-catalog")
    catalog = unwrap_ok(code, envelope, "authoring.catalog")
    recipe_meta = choose_document(catalog, kind="recipe", identity="shooter_third_person")
    scenario_meta = choose_document(catalog, kind="scenario", identity="third_person_cover_route")

    code, envelope = bridge_request(
        arcont,
        project,
        "authoring.document.read",
        {"path": recipe_meta["path"]},
        request_id="nexo-recipe-read",
    )
    recipe_read = unwrap_ok(code, envelope, "authoring.document.read")
    recipe = recipe_read["document"]

    code, envelope = bridge_request(
        arcont,
        project,
        "authoring.document.read",
        {"path": scenario_meta["path"]},
        request_id="nexo-scenario-read",
    )
    scenario_read = unwrap_ok(code, envelope, "authoring.document.read")
    session = scenario_read["document"]

    # 5. The bridge must not grant itself mutation permission.
    negative_plan = {
        "protocol": "arcont-agent-plan",
        "version": 1,
        "id": "nexo_bridge_write_refusal",
        "goal": "Prove a bridge client cannot mutate Nexo without explicit project-write opt-in.",
        "permissions": {"project_write": True},
        "capability_allowlist": ["godot.authoring.control"],
        "steps": [
            {
                "id": "must_not_author",
                "kind": "invoke",
                "capability": "godot.authoring.control",
                "request": {
                    "protocol_version": 1,
                    "operation": "create",
                    "document_id": recipe["id"],
                    "recipe": recipe,
                    "dry_run": False,
                    "options": {"audio_driver": "Dummy"},
                },
            }
        ],
    }
    negative_code, negative = bridge_request(
        arcont,
        project,
        "plan.execute",
        {"plan": negative_plan},
        allow_write=False,
        request_id="nexo-write-refusal",
    )
    if negative_code == 0 or negative.get("ok") is not False:
        raise RuntimeError({"bridge_write_refusal_failed": negative})
    if (project / "authoring/documents/shooter_third_person.json").exists():
        raise RuntimeError("Bridge write-refusal control unexpectedly authored a document")

    # 6. Execute the real bounded Nexo author/build/playtest route through Bridge.
    plan = {
        "protocol": "arcont-agent-plan",
        "version": 1,
        "id": "nexo_bridge_real_acceptance",
        "goal": "Use persistent intent and discovered authoring documents to build and playtest the real Nexo third-person slice.",
        "permissions": {"project_write": True},
        "capability_allowlist": ["godot.authoring.control"],
        "steps": [
            {
                "id": "inventory",
                "kind": "inspect-project",
                "max_files": 50000,
                "expect": [
                    {"pointer": "/project/engine", "op": "equals", "value": "godot"}
                ],
            },
            {
                "id": "discover_spring_arm",
                "kind": "invoke",
                "capability": "godot.authoring.control",
                "request": {
                    "protocol_version": 1,
                    "operation": "discover",
                    "document_id": recipe["id"],
                    "options": {"class": "SpringArm3D"},
                },
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
                "expect": [
                    {"pointer": "/result/revision", "op": "exists"}
                ],
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
                "expect": [
                    {"pointer": "/result/revision", "op": "exists"},
                    {"pointer": "/result/last_build/directory", "op": "exists"},
                ],
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
                "expect": [
                    {"pointer": "/result/passed", "op": "equals", "value": True},
                    {"pointer": "/result/report/input_released", "op": "equals", "value": True},
                ],
            },
        ],
    }

    code, bridge_envelope = bridge_request(
        arcont,
        project,
        "plan.execute",
        {"plan": plan},
        allow_write=True,
        request_id="nexo-build-playtest",
        timeout=900,
    )
    execution = unwrap_ok(code, bridge_envelope, "plan.execute")
    playtest_step = next(item for item in execution["steps"] if item["id"] == "playtest")
    playtest = playtest_step["output"]
    states = checkpoints(playtest)

    cover = states["cover_settle"]["state"]
    vault = states["vault_midpoint"]["state"]
    land = states["land"]["state"]
    assertions = {
        "fresh_agent_discovered_bridge": bridge.get("protocol") == "arcont-bridge",
        "persistent_intent_loaded": intent_report.get("present") is True,
        "local_assets_discovered": asset_report.get("asset_count", 0) > 0,
        "recipe_discovered_through_bridge": recipe.get("id") == "shooter_third_person",
        "scenario_discovered_through_bridge": session.get("id") == "third_person_cover_route",
        "bridge_refused_unapproved_write": negative_code != 0 and negative.get("ok") is False,
        "cover_state_preserved": cover.get("movement_state") == "cover" and cover.get("crouched") is True,
        "vault_state_reached": vault.get("movement_state") == "vault" and vault.get("position", [0, 0, 0])[1] >= 1.0,
        "vault_lands_without_abort": land.get("movement_state") == "free" and land.get("vault_aborted") is False,
        "input_released": playtest["result"]["report"].get("input_released") is True,
        "third_person_visible": all(
            states[name]["state"].get("perspective") == "third_person"
            and states[name]["state"].get("body_visible") is True
            for name in ("cover_settle", "vault_midpoint", "land")
        ),
    }
    if not all(assertions.values()):
        raise RuntimeError({"bridge_acceptance_assertions": assertions})

    summary = {
        "ok": True,
        "arcont_head": subprocess.check_output(
            ["git", "-C", str(arcont), "rev-parse", "HEAD"], text=True
        ).strip(),
        "bridge": {
            "protocol": bridge["protocol"],
            "version": bridge["version"],
            "operations": bridge["operations"],
        },
        "intent": {
            "sha256": intent_report["sha256"],
            "project_id": intent["project_id"],
            "genre": intent["genre"],
            "targets": intent.get("targets", []),
            "priorities": intent.get("priorities", []),
        },
        "assets": {
            "count": asset_report["asset_count"],
            "counts": asset_report["counts"],
            "truncated": asset_report["truncated"],
        },
        "authoring": {
            "catalog_count": catalog["document_count"],
            "recipe_path": recipe_meta["path"],
            "recipe_sha256": recipe_read["sha256"],
            "scenario_path": scenario_meta["path"],
            "scenario_sha256": scenario_read["sha256"],
        },
        "execution": {
            "plan_sha256": execution["plan_sha256"],
            "registry_sha256": execution["registry_sha256"],
            "steps_completed": execution["steps_completed"],
            "write_steps": execution["write_steps"],
            "revision": next(
                item for item in execution["steps"] if item["id"] == "inspect_authored"
            )["output"]["result"]["revision"],
        },
        "playtest": {
            "passed": playtest["result"]["passed"],
            "physics_frames": playtest["result"]["report"]["physics_frames"],
            "final_state": playtest["result"]["report"]["final_state"],
        },
        "assertions": assertions,
        "limits": [
            "Scripted fresh-agent acceptance proves the provider-neutral bridge contract; it does not invoke a separate vendor LLM inside GitHub Actions.",
            "Linux/Xvfb evidence does not establish Android handset FPS, thermals or subjective AAA presentation.",
            "Public asset network discovery is intentionally outside Bridge v1."
        ],
    }

    (evidence / "discover.json").write_text(json.dumps(discovery, indent=2), encoding="utf-8")
    (evidence / "intent.json").write_text(json.dumps(intent_report, indent=2), encoding="utf-8")
    (evidence / "assets.json").write_text(json.dumps(asset_report, indent=2), encoding="utf-8")
    (evidence / "authoring-catalog.json").write_text(json.dumps(catalog, indent=2), encoding="utf-8")
    (evidence / "write-refusal.json").write_text(json.dumps(negative, indent=2), encoding="utf-8")
    (evidence / "execution.json").write_text(json.dumps(execution, indent=2), encoding="utf-8")
    (evidence / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
