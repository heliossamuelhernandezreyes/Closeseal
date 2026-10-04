# Nexo production preparation 0.2

Nexo consumes Arcont at authoring time. `arcont-production.lock.json` and the shooter workflow pin its exact revision; the shipped game has no Arcont runtime dependency. Shared validators and contracts stay in Arcont. This repository owns the native Godot adapter and production profiles.

## Reproduce

Use the pinned Arcont checkout and Godot 4.7.2-stable. Create an isolated shooter staging directory with `tools/prepare_shooter.py`; the production profiles and native probe are copied into it.

```bash
python /path/Arcont/tools/production_toolchain.py doctor
python tools/prepare_shooter.py --stage /tmp/nexo-shooter
GODOT_BIN=/path/Godot_v4.7.2-stable_linux.x86_64 xvfb-run -a -s '-screen 0 1280x720x24' python tools/shooter_production_smoke.py --arcont /path/Arcont --project /tmp/nexo-shooter
```

On a Linux desktop with a display, omit `xvfb-run`. CI also runs the existing bake, gameplay, mobility and two real production-player input replays.

## Accepted work

| Profile | Native acceptance |
| --- | --- |
| `authoring/production/assets.json` | Soldier, AKM and industrial barrel: manifest hashes, complete glTF external dependencies, triangle/material budgets, candidate import, dimensions and soldier skeleton. |
| `authoring/production/animation.json` | Explicit 62-bone map, 21 clips, 94,122 keys; saved/reopened library, preserved timing, identity pose tolerance, renamed bones/rest corrections and a missing-map negative control. |
| `authoring/production/sector.json` | Authored 24 × 32 m review yard, three covers, three declared routes, baked navigation, capsule sweeps and cover collision rays. |

Assets are copied into content-addressed `assets/production_candidates/` without modifying their sources. Imported model roots are flattened when packing native review snapshots, avoiding inherited scene duplication. The animation source library and canonical combat map are checked for preservation.

The sector is a separate editable review scene. To adopt it into the mission, author a revision through the map control contract, rerun physical-world validation and test the production player there. This acceptance does not insert the yard into the mission.

## Review evidence

Successful scenes, recipes, native resources, logs and writer manifests live under `.arcont/runs/`. `.arcont/production-evidence/` contains `acceptance.json`, three PNG captures and raw frame records. The acceptance records project-relative run directories, source/candidate dependency hashes and recipe revisions. CI preserves both locations plus candidate source dependencies as an artifact.

Review scenes reference project resources and their run-local outputs; reopen them in the same staged project, or restore those project-relative paths from the artifact. They are authoring outputs, not an independently packaged game.

Frame records specify warmup, resolution, engine, renderer, device and scenario. Arcont reports mean/p50/p95/p99/max and rejects incompatible comparisons. Linux GL compatibility observations, often through a software renderer, do not establish Android FPS, thermals, GPU memory or touch latency. No Android-device acceptance is included in this release.

Retargeting requires an explicit one-to-one bone map and matching parent topology. Different body proportions still require contact and visual acceptance. External mesh simplification, automatic LOD creation, FBX conversion and texture recompression are not exercised by this integration.

The 0.2 release adds controlled native TPS finish records through `production_toolchain.py finish`. Nexo owns `shooter_finish_acceptance.gd`, runtime clips and captures; Arcont owns the reusable validator/profile. See [SHOOTER_NEXO.md](SHOOTER_NEXO.md) for handset and visual limits.

The 0.3 release adds hash-checked native scene bundles for portable mesh/material/lightmap inputs. Sector presentation authoring and the tested native editor bake adapter stay in Closeseal; see [SECTOR_PRESENTATION.md](SECTOR_PRESENTATION.md). Bake outputs keep a separate post-bake hash record.
