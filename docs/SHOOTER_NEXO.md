# Nexo Industrial 0.7.0 — presentation and camera milestone

0.7 keeps the playable 0.6 combat and traversal while improving camera continuity,
action transitions and Sector 07 presentation. A 22 cm sphere clears the shoulder
offset, including swaps. Camera obstruction retracts immediately and returns with
damping. Native per-pixel distance fade affects nearby character surfaces while the
rig remains present. Sub-centimetre locomotion sway is reduced further in ADS.
Bounded Hermite position offsets and quaternion offsets bridge action changes before
combat/contact IK; these are authored-clip transitions, not motion capture.

The industrial palette combines a readable sky, cool fill and warm practical lights.
Maintenance panels, restrained safety paint, conduits and machine feet add 39
decorative meshes without adding collision. Arcont authors and relocates the derived
scene with explicit input/output hashes. A native RenderingDevice editor bake produces
UV2 lightmaps and actor probes; the shipped renderer remains Compatibility.
The canonical map and its navigation ownership stay unchanged.

Use the separate [presentation authoring guide](SECTOR_PRESENTATION.md) to rebuild
the scene. This is an improvement milestone, not a claim that the prototype matches
the art, animation, audio or content of a finished AAA shooter. Android frame pacing,
thermal behaviour and touch comfort must be tested on the handset after export.

## Previous 0.6 finish milestone

This finish milestone follows the October 4 audit. It adds shared metre-based gait/cadence definitions, world-space foot contacts, a crouched run clip, asymmetrical cover stance and bounded acceleration/turn lean. Cover directions are selected in rig space, including bent firing. Eight controlled native motion cases validate signed cadence within 1.5%, foot-anchor drift within 3 cm and three-stance weapon grips within 4 cm. These are project targets, not an industry AAA certification.

Combat now uses bounded reusable effect and voice pools, distinct metal/concrete/flesh impact feedback, spatial contact-timed footsteps, mild horizontal recoil, actual posed-head damage checks and separate tactical/empty reload durations. The reticle projects the same accuracy cone used by the shot ray. All enemies use the hostile skin and lower their actual collision capsule while taking cover.

The menu includes saved look/ADS sensitivity, opacity, button size and dragged HUD positions. Invalid overlaps and out-of-screen edits preserve the usable layout; the display safe area is respected. Two local native reflection volumes, authored through Arcont recipes, supplement the sky lighting. They are not baked GI.

The reusable TPS mobile quality policy and validator live in [Arcont PR21](https://github.com/heliossamuelhernandezreyes/Arcont/pull/21). Native measurements, rendered runtime sequences and remaining visual limitations are preserved in [0.6 evidence](evidence/nexo-industrial-060.json).

## Previous 0.5.1 fixes

0.5.1 fixes the reported mobility and facade defects. Intentional unaimed
movement into a nearby low obstacle automatically invokes the same collision
sweep and clear-landing gate as Space. Low-cover aim/fire keeps a 1.50m capsule,
a bent pose and directional strafe; its raised muzzle and exposed target remain
physical. Flat-ground foot adaptation leaves every animated leg transform
unchanged; slope corrections preserve the existing knee bend and boot basis.
Lateral crouch strides keep the feet separated. The delivered CC0 facade is
reassembled into four outward-facing walls, preserving the original source GLB.

Regression evidence samples 248 poses through complete gait/action cycles and
casts 84 rays against all repaired facade modules. Mobility acceptance also
checks automatic traversal, blocked landings, ADS exclusion and firing while
moving in a bent low-cover posture. [Real engine captures and results](evidence/nexo-industrial-051.json) accompany the reports.

The authoring pipeline now includes [production preparation 0.1](PRODUCTION_TOOLCHAIN.md): versioned Arcont tools, immutable asset candidates, explicit animation profiles, an editable tactical-sector review and rendered evidence.

Nexo now uses a complete animated character and an over-the-shoulder camera.
Run `src/shooter/shooter_arena.tscn` in Godot **4.7.2-stable**
(`ed1daf0bf001b61586d9930840f2f1394092c079`). The isolated staging project's
main scene is the shooter; the existing RTS and urban scene keep their entries.

The default menu starts **Sector 07 / Maintenance**: secure supplies A, the
upper workshop relay B and access control C in order, holding each within 3.8m
for three seconds, then return to extraction. Six enemies defend the approach,
workshop and upper landing, with two health/ammo pickups. The intended duration
is 3–5 minutes; human playtesting still needs to confirm pacing and difficulty.
**MAPA COMPLETO** keeps the original sixteen-enemy, three-objective operation.
Both modes have a 30-round rifle, automatic fire, aiming, reload, jumping,
sprinting and health regeneration.

| Action | Desktop | Touch |
| --- | --- | --- |
| Move / orbit | WASD / mouse | Left stick / drag right side |
| Shoot / aim | Left / right mouse, hold | FUEGO / MIRA, hold |
| Reload / jump or vault | R / Space | CARGAR / SALTO or PASAR |
| Enter / leave / transfer cover | C | CUBRIR / SALIR / CAMBIAR |
| Crouch / slide while running | Ctrl | AGACHAR / DESLIZAR |
| Interact | E | USAR |
| Sprint | Shift | Extend the stick forward |
| Swap shoulder | Q | HOMBRO |
| Pause | Escape | II |
| Show performance | F3 / menu | MOSTRAR FPS in menu |

## Camera, animation and combat

A sphere-swept SpringArm3D excludes the player collider and retracts before
world/enemy geometry. The lateral shoulder offset also checks walls, including
while changing shoulders. Orbit preserves idle body heading. Movement turns
the body into the travel direction; aiming and firing face the reticle.

Twenty-one authored skeletal clips provide idle, directional gait, run, death,
cover entry/idle/strafe/high cover, bent peek/peek-strafe, crouch, slide, vault, jump and landing. A 2D AnimationTree blends gait direction and adjusts cadence to
travel speed. The native compressed AnimationLibrary remains editable in Godot;
`tools/shooter_bake_animations.gd` rebuilds it. These are authored clips, not
motion capture. A SkeletonModifier3D solves hands to weapon grips, with recoil,
magazine removal and reload motion. Enemy movement uses the same directional rig. A second skeleton modifier
samples the floor beneath each foot and applies bounded (±18cm), smoothed
height correction on slopes, preserving authored gait. Jump, vault, slide and
death disable it. This is height adaptation, not full foot locking or arbitrary
body-proportion retargeting. Skin roughness now samples its delivered texture.

Shots resolve camera aim, check the barrel from its mount to its tip, then cast
from the physical muzzle to the reticle. This prevents a protruding barrel from
firing through close cover even when the camera sees over it. The visible weapon
also aligns to that target. Enemy navigation, perception, damage, cover behavior
and mission state continue to use real physics and the baked navigation mesh.

## Tactical mobility and HUD

`mobility.gd` owns explicit free/cover/corner/transfer/slide/vault states. Normal speed is 5.4m/s,
sprint 8.8m/s, aimed movement 3.25m/s; acceleration, braking, diagonal limits,
air control, 100ms coyote time and 130ms jump buffering keep inputs responsive.
Ctrl while running starts a 620ms decelerating slide with a shorter real capsule.
Standing up requires actual overhead clearance. Slide and vault suppress firing.

C detects supported wall faces within 1.25m and attaches at 0.43m clearance.
Low cover lowers the capsule; aim/fire partially rises above it while keeping
the knees flexed and exposing the upper body.
High-cover edge peeking shifts the visible body and real capsule together, with
clearance checks; enemy targeting follows that exposed position. Strafe follows
the face; moving away, sprinting, toggling C or removing the collider releases it.
Space accepts 0.45–1.35m obstacles only with a standing-height landing and complete
swept path clearance. The 680ms traversal keeps collision active and aborts on a
new obstruction. Strafing without aiming at a supported convex corner wraps onto the adjacent
face of the same collider at 2.6m/s. Aiming retains edge peeking. When a clear,
parallel neighboring cover face is found along the movement direction, C or
CAMBIAR starts a 6.8m/s transfer. Both transitions validate floor and capsule
clearance and retain collision; a new obstruction or removed destination aborts
them. Firing is suppressed during transitions. Concave corners, arbitrary
nonparallel transfers and high-wall climbing are outside this pass.

The HUD combines the mission, targets and clock into a compact ribbon, uses
movement-aware reticle spacing, directional damage feedback, reload progress
and context labels for cover/corner/transfer/slide/vault. A red confirmation
marks a kill. The sector ribbon names the next objective; world labels use a
smaller scale. Sector flankers seek reachable lateral positions while injured
enemies retain their existing cover behavior. Touch controls use independent finger
ownership for stick/look/fire/aim, with forward stick extension enabling sprint.
ADS touch sensitivity is reduced. A uniform reference layout keeps targets
inside landscape layouts without overlaps; button sizes scale with the viewport.
The Linux checks do not measure handset touch comfort, cutouts or frame rate.

## Authored industrial sector

`maps/nexo_combat_01.json` remains the **256 × 256m** canonical world. The south
approach now includes asymmetric, enterable service buildings, a structural pipe
bridge, gutters, yard surfaces, lighting and catalog props. It contains 625 native
objects, 82 imported asset instances and two indexed physical ramps. The workshop
now has a 3.1m mezzanine, a 12m ramp, physical guardrails, benches, lighting and
crate props. New pairs of low cover and high crates support the mobility paths.
Navigation is baked from the actual world collision. Both operations preserve
reachable objectives and clear enemy spawns.

`tools/author_shooter_map.py` reads the industrial canonical map and revision-
checks its explicit edits through Arcont. It replaces its own `hero_*` entries
idempotently and preserves other sectors; it no longer restores the obsolete
Kenney generator. ARCONT materialization independently produces baked navigation
polygons from the actual authored world colliders.

## Asset integration

The edition uses Irondust's Sci-fi Soldier, LonesomeDucky's weathered AKM and Poly
Haven environment models/materials/HDR sky. The manifest records licenses,
conversion details and **98 delivered file hashes**. The industrial build
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
checks the scene build, reopens it twice and verifies walking, attaching to low cover, vaulting,
interaction, input release and matching positions within 1mm. Each replay
completes 233 measured actor ticks and preserves the canonical map and accepted
scene document. Audio voices are stopped and retired before teardown.

The build pins Arcont commit `6d6d567a419be52424e6939b7360e28a631e7369`, production preparation 0.2 with TPS finish review:
[Arcont PR21](https://github.com/heliossamuelhernandezreyes/Arcont/pull/21).
Kernel-backed locks prevent interrupted jobs from stranding the editor. A real
SIGKILL recovery regression and concurrent-writer rejection pass on POSIX.
The Windows byte-lock implementation still needs Windows CI.

Local verification: 42 gameplay checks, 44 mobility/HUD checks, 24 sector checks and 4 visual
regression checks plus 31 controlled motion/mobile/recorder checks in Godot,
21 game Python tests,
6 canonical map validations, one physical profile, Map Forge control smoke,
98 asset hashes and two reopened production-player replays. Rendered checkpoints
were inspected; acceptance renders evidence checkpoints and is not an FPS test.
GitHub's shooter workflow repeats import, mipmap configuration, physics/navigation
baking, rendered gameplay/mobility/sector/visual acceptance and production-player
Arcont replay, then asset/animation/sector production reviews.

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
godot --path /tmp/nexo-shooter --audio-driver Dummy --script res://tools/shooter_mobility_acceptance.gd -- --captures=/tmp/nexo-evidence
godot --path /tmp/nexo-shooter --audio-driver Dummy --script res://tools/shooter_slice_acceptance.gd -- --captures=/tmp/nexo-evidence
godot --path /tmp/nexo-shooter --audio-driver Dummy --script res://tools/shooter_visual_acceptance.gd -- --captures=/tmp/nexo-evidence
godot --headless --path /tmp/nexo-shooter --script res://tools/shooter_finish_acceptance.gd -- --captures=/tmp/nexo-evidence
python /path/to/arcont/tools/production_toolchain.py finish /tmp/nexo-evidence/finish-record.json
GODOT_BIN=godot python tools/shooter_authoring_smoke.py --arcont /path/to/arcont --project /tmp/nexo-shooter
python tools/export_shooter.py --stage /tmp/nexo-shooter --templates /path/to/4.7.2-stable/templates --engine /path/to/godot --output /tmp/Nexo.apk --platform Android
```

Android export uses the arm64 native template with landscape touch controls,
offline permissions and debug signing; Java and Android SDK tools must be
configured in Godot. Staging rejects unmanaged destinations and preserves the
old build if preparation fails. A signed arm64 debug APK was exported locally
with Godot 4.7.2, JDK 17 and Android build tools 35.0.0. Signature/ZIP alignment
checks validate packaging; installation and frame rate on a Poco remain untested.
The preview APK package is `org.closeseal.nexo.preview`, version 0.6.0 / code 7.
It uses a new debug certificate and installs alongside previous Nexo packages;
there is no need to remove the older build.

F3 or the pause menu toggles an FPS/static-memory overlay. Every active-play
frame contributes to a 0.25 ms quantized distribution and 60-second p50/p95/p99
windows. Actual wall-clock intervals are read from the monotonic clock rather
than simulated delta. The most recent 10,800 raw intervals are a ring; up to
60 completed minute windows and 3,600 one-second summaries are retained.
Pause excludes inactive time; a new operation resets the session. Pause or
mission completion saves `user://nexo-performance-latest.json`; COPIAR INFORME
copies the compact session/device summary for handset feedback.

The 20-minute slowdown regression injects 54,000 synthetic intervals. It verifies
recorder retention and warm-tail detection, not a 20-minute Android benchmark.
Static memory is not total process or GPU memory. No direct thermal, touch-latency
or display refresh measurement is available. Test 15+ active minutes on the Poco
X7 Pro, compare cold/warm windows and report control comfort separately.

Rendered review still identifies limits: tight obstructions can abruptly hide
the body through the existing camera safety rule; material/sky cohesion, pose
weight and reload polish remain below the reference AAA finish. The reflection
volumes need handset cost measurement, and impact surfaces currently use collider
name heuristics rather than explicit authored physical material tags.

This remains a single-player prototype. AAA art quality, handset frame rate,
multiplayer, controller support and console packaging are not established by
these checks. Character detail, animation polish and broader level composition
need further art work and actual target-device review.
