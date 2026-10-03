# Nexo Industrial 0.3 — third-person playable prototype

Nexo now uses a complete animated character and an over-the-shoulder camera.
Run `src/shooter/shooter_arena.tscn` in Godot **4.7.2-stable**
(`ed1daf0bf001b61586d9930840f2f1394092c079`). The isolated staging project's
main scene is the shooter; the existing RTS and urban scene keep their entries.

Secure A, B and C within 3.8m for three seconds each, then return to extraction.
The mission contains 16 enemies, five health/ammo pickups, a 30-round rifle,
automatic fire, aiming, reload, jumping, sprinting and health regeneration.

| Action | Desktop | Touch |
| --- | --- | --- |
| Move / orbit | WASD / mouse | Left stick / drag right side |
| Shoot / aim | Left / right mouse, hold | FUEGO / MIRA, hold |
| Reload / jump | R / Space | CARGAR / SALTO |
| Interact | E | USAR |
| Sprint | Shift | Double-tap movement stick |
| Swap shoulder | Q | HOMBRO |
| Pause | Escape | II |

## Camera, animation and combat

A sphere-swept SpringArm3D excludes the player collider and retracts before
world/enemy geometry. The lateral shoulder offset also checks walls, including
while changing shoulders. Orbit preserves idle body heading. Movement turns
the body into the travel direction; aiming and firing face the reticle.

Seven authored skeletal clips provide idle, forward/backward/sideways walking,
run and death. A 2D AnimationTree blends gait direction and adjusts cadence to
travel speed. The native compressed AnimationLibrary remains editable in Godot;
`tools/shooter_bake_animations.gd` rebuilds it. These are authored clips, not
motion capture. A SkeletonModifier3D solves hands to weapon grips, with recoil,
magazine removal and reload motion. Enemy movement uses the same directional rig.

Shots resolve camera aim, check the barrel from its mount to its tip, then cast
from the physical muzzle to the reticle. This prevents a protruding barrel from
firing through close cover even when the camera sees over it. The visible weapon
also aligns to that target. Enemy navigation, perception, damage, cover behavior
and mission state continue to use real physics and the baked navigation mesh.

## Authored industrial sector

`maps/nexo_combat_01.json` remains the **256 × 256m** canonical world. The south
approach now includes asymmetric, enterable service buildings, a structural pipe
bridge, gutters, yard surfaces, lighting and catalog props. It contains 531 native
objects, 78 imported asset instances and one physical ramp. The three objectives
and all sixteen enemy spawns remain reachable and free of collider overlaps.

`tools/author_shooter_map.py` reads the industrial canonical map and revision-
checks its explicit edits through Arcont. It replaces its own `hero_*` entries
idempotently and preserves other sectors; it no longer restores the obsolete
Kenney generator. ARCONT materialization independently produces 1,107 navigation
polygons from the actual authored world colliders.

## Asset integration

The edition uses Irondust's Sci-fi Soldier, LonesomeDucky's weathered AKM and Poly
Haven environment models/materials/HDR sky. The manifest records licenses,
conversion details and **97 delivered file hashes**. The industrial build
excludes the earlier Kenney packs. Models, textures and sky are CC0; the gunshot
uses the downloaded archive's CC BY 3.0 attribution, included in credits and
`assets/shooter/serious/LICENSES.txt`. No source archive or Blender is needed to
compile the delivered assets.

A clean Godot import had left extracted facade textures without mipmaps.
`tools/configure_shooter_imports.py` now configures the staged 3D texture imports,
including images extracted from GLB files. Reimport after configuration. Native
acceptance checks the loaded facade image actually has a mip chain.

## Arcont control and evidence

`authoring/recipes/shooter_third_person.json` saves the production scene with
pinned source dependencies. `authoring/scenarios/shooter_third_person.json`
replays actual InputEvents against the production player's lifecycle interface.
`tools/shooter_authoring_smoke.py` discovers the native camera API, revision-
checks the scene build, reopens it twice and verifies walking, jumping,
interaction, input release and matching positions within 1mm. Each replay
completes 189 measured actor ticks and preserves the canonical map and accepted
scene document. Audio voices are stopped and retired before teardown.

The build pins Arcont commit `678d907e742d4ecd66934c9f1d1b83858e7b9e2c`:
[recoverable authoring locks, PR19](https://github.com/heliossamuelhernandezreyes/Arcont/pull/19).
Kernel-backed locks prevent interrupted jobs from stranding the editor. A real
SIGKILL recovery regression and concurrent-writer rejection pass on POSIX.
The Windows byte-lock implementation still needs Windows CI.

Local verification: 42 real-engine gameplay checks, 21 game Python tests,
6 canonical map validations, one physical profile, Map Forge control smoke,
97 asset hashes and two reopened production-player replays. Rendered checkpoints
were inspected; acceptance renders evidence checkpoints and is not an FPS test.
GitHub's shooter workflow repeats import, mipmap configuration, physics/navigation
baking, rendered gameplay acceptance and production-player Arcont replay.

## Build

```sh
python tools/verify_shooter_assets.py
python -m unittest discover -s tests -p 'test_shooter_build.py'
python tools/prepare_shooter.py --stage /tmp/nexo-shooter
godot --headless --path /tmp/nexo-shooter --editor --import
python tools/configure_shooter_imports.py --stage /tmp/nexo-shooter
godot --headless --path /tmp/nexo-shooter --editor --import
godot --headless --path /tmp/nexo-shooter --script res://tools/shooter_bake.gd
godot --path /tmp/nexo-shooter --audio-driver Dummy --script res://tools/shooter_acceptance.gd -- --captures=/tmp/nexo-evidence
GODOT_BIN=godot python tools/shooter_authoring_smoke.py --arcont /path/to/arcont --project /tmp/nexo-shooter
python tools/export_shooter.py --stage /tmp/nexo-shooter --templates /path/to/4.7.2-stable/templates --engine /path/to/godot --output /tmp/Nexo.apk --platform Android
```

Android export uses the arm64 native template with landscape touch controls,
offline permissions and debug signing; Java and Android SDK tools must be
configured in Godot. Staging rejects unmanaged destinations and preserves the
old build if preparation fails. No current-edition APK/device test is claimed
by this source change.

This remains a single-player prototype. AAA art quality, handset frame rate,
multiplayer, controller support and console packaging are not established by
these checks. Character detail, animation polish and broader level composition
need further art work and actual target-device review.
