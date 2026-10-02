# Nexo: zona de combate — playable shooter prototype

The user explicitly requested a shooter using Arcont's 3D assets, animated
characters and a medium-large combat map on 2026-10-02. This adds a separate
first-person shooter scene and export target. The original RTS entry scene,
its design contract and existing canonical maps retain their identities.

## Play

Open `src/shooter/shooter_arena.tscn` in Godot **4.7.2-stable**
(`ed1daf0bf001b61586d9930840f2f1394092c079`) and run the current scene.
For a standalone build, use `tools/prepare_shooter.py --stage <directory>`;
that project's main scene is the shooter. Android uses landscape orientation,
an arm64 native build, an offline mission and touch controls.

Secure A, B and C by interacting within 3.8 metres and remaining there for
three seconds. Return to the marked extraction point and interact to win.
There are 16 enemies, five health/ammo crates, a 24-round rifle, automatic
fire, aiming, a 1.6-second reload, jumping and sprinting. Health recovers
after five seconds without damage. Death opens the retry menu.

| Action | Desktop | Touch |
| --- | --- | --- |
| Move / look | WASD / mouse | Left stick / drag right side |
| Shoot / aim | Left / right mouse | FUEGO / MIRA, hold |
| Reload / jump | R / Space | CARGAR / SALTO |
| Interact | E | USAR |
| Sprint | Shift | Double-tap movement stick |
| Pause | Escape | II |

## Authored world and actual assets

`maps/nexo_combat_01.json` is the source of truth for the **256 × 256 m**
arena: industrial, commercial and residential blocks; a maintenance hangar;
street cover; and a command post four metres above ground with a ramp.
`tools/author_shooter_map.py` creates or replaces that map through Arcont's
revision-guarded Map Forge writer. It records explicit geometry rather than
changing the existing 512-metre urban map.

59 imported urban models retain their original CC0 files and the provenance
in `assets/urban/sources.lock.json`. The new Kenney survivors and blasters
were selected from Arcont's catalog, downloaded from their official source
archives and bound to hashes in `assets/shooter/sources.lock.json`.
Catalog entries alone are not runtime assets. License files accompany both
new packs. The pavement SVG, procedural audio and combat animation layer
are authored within this project; no paid asset or generation service is used.

## Animation and combat

The character uses the source FBX skeleton and its real idle, run and jump
tracks. The run clip blends over 0.16 seconds and scales with movement speed.
The FBX faces +Z, so the model is corrected to the game's -Z convention.
`combat_pose.gd` runs as a SkeletonModifier3D after the source clips and
solves the two arms against the rifle's grip positions. Recoil and reload
move the weapon and supporting hand together. Death lowers and rotates the
hips through a timed fall and disables the enemy's combat collider.

Enemies use a baked world navigation mesh and physical CharacterBody3D
movement. They patrol, detect line of sight, pursue, fire with distance-based
spread, reload and die. Wall collisions, navigation paths and weapon rays are
separate systems. Player shots first resolve the camera aim, then cast from
the physical muzzle, preventing fire through nearby cover.

## Validation and limits

`tools/shooter_bake.gd` bakes the actual authored static colliders.
`tools/shooter_acceptance.gd` checks objective paths, physical ramp ascent,
map boundaries, jumping, active enemy movement and damage, cover-blocked
shots and perception, player damage and ammo conservation, skeletal leg
motion, weapon grip alignment, touch release, victory and defeat. It emits
an engine-version-bound JSON report and captures. The dedicated GitHub
workflow imports and re-bakes the isolated shooter before running acceptance.

The locally exported Linux executable starts successfully. The Android APK
is arm64 and its APK v2/v3 signatures verify. This is a playable single-player
prototype; it has no multiplayer, controller support, Xbox package or device
performance claim. Installation, graphics and frame rate on the user's Poco
X7 Pro still need an actual handset playtest.

## Build

```sh
python tools/prepare_shooter.py --stage /tmp/nexo-shooter
godot --headless --path /tmp/nexo-shooter --editor --import
godot --headless --path /tmp/nexo-shooter --script res://tools/shooter_bake.gd
godot --path /tmp/nexo-shooter --script res://tools/shooter_acceptance.gd -- --captures=/tmp/nexo-evidence
python tools/export_shooter.py --stage /tmp/nexo-shooter --templates /path/to/4.7.2-stable/templates --engine /path/to/godot --output /tmp/Nexo.apk --platform Android
```

Android export requires Java and Android SDK tools configured in Godot's
editor settings. The prebuilt native template is used without a Gradle build.
Debug signing is appropriate to this downloadable prototype; store publishing
and release credentials are outside this change.
