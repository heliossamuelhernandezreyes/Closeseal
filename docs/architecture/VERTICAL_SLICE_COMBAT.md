# Close Seal — First Combat Vertical Slice

Status: ARCHITECTURE BASELINE

## Goal
Build the smallest real battle that proves Close Seal is fun, readable on mobile, and technically scalable before expanding to four races, campaign, ranked multiplayer, or live-service systems.

## Product shape already locked
- Genre: mobile-first Hero RTS.
- Presentation: 2.5D visual language over a real 3D world.
- Primary platform: Android.
- Engine: Godot 4.7.2-stable.
- Long-term vision: four asymmetric races, controllable hero, troop squads, defensive towers, creeps, campaign and multiplayer.

## Vertical slice scope
The first playable combat contains only:
- 1 controllable hero.
- 1 provisional faction.
- 3 troop archetypes: frontline, ranged, support.
- 2 defensive tower archetypes.
- 1 creep lane/flow.
- 1 compact 3D battlefield.
- 1 enemy AI opponent.
- 1 clear win condition and 1 clear loss condition.

No progression economy, cosmetics, account system, matchmaking, ranked mode, clans, battle pass, four-faction balance, or production backend belongs in this slice.

## Core architecture principle
Simulation and presentation are separate.

### Simulation layer
Owns authoritative combat state:
- entity identity
- team/faction
- health/resources
- cooldowns
- target selection
- orders
- movement intent
- combat resolution
- tower/creep rules
- win/loss state

The simulation must not require a high-cost Godot scene node per logical combat entity.

### Presentation layer
Owns what the player sees and hears:
- meshes
- animations
- VFX
- health bars/selections
- audio
- interpolation
- camera feedback

Presentation may use pooling, LOD, instancing or grouped rendering without changing authoritative combat rules.

## Unit command model
The player commands squads, not dozens of individual soldiers one by one.

Each squad has:
- one command identity
- one formation target
- one tactical state
- N visual/combat members

Individual members may separate locally for spacing/combat, but high-level orders are issued to the squad.

Initial orders:
- move
- attack target
- attack-move
- hold
- retreat/follow hero

## Hero model
The hero is directly controllable and is the player's physical anchor on the battlefield.

Initial hero actions:
- movement
- basic attack
- 2 active abilities
- contextual command interaction with nearby/selected squads

The hero must not be required for every troop order; strategic control must remain possible while the hero is elsewhere.

## Mobile interaction baseline
Initial control experiment:
- left thumb: hero movement
- right side: hero abilities / primary combat actions
- tap squad or group card: select squad
- tap terrain: move selected squad
- tap enemy: attack selected target
- drag/gesture experiments are allowed only after the tap model is proven readable

The exact HUD is not final. One-handed and tablet layouts remain future accessibility variants.

## Camera baseline
- perspective or orthographic-like 3D tactical camera, evaluated experimentally
- fixed tactical tilt range
- constrained zoom range
- limited rotation or no rotation for the first slice
- battlefield readability is more important than cinematic freedom

## Performance contract
Target experience: 60 FPS on Android where feasible, with a graceful 30 FPS fallback on weaker supported hardware.

No fixed final entity budget is invented yet. We will determine it with ARCONT evidence.

The first scale campaign must test at least:
- 50 active combat units
- 100
- 200
- 300
- 500

For each scale, measure CPU frame cost, GPU frame cost where available, memory, frame-time percentiles, thermal behavior when tested on a real device, and visual/readability limits.

## ARCONT questions opened by this architecture
1. What is the cheapest authoritative representation for 50–500 active combat units in Godot 4.7.2?
2. At what scale does one Node/process callback per unit become unacceptable on Android-class hardware?
3. What representation should be used for troop visuals: per-unit scene, pooled scene, MultiMesh, or hybrid?
4. What navigation architecture best supports squads and local avoidance without N expensive full navigation agents?
5. What animation strategy gives acceptable visual quality for hundreds of visible units?
6. What tick rate should combat simulation use independently from render FPS?
7. Which camera/render configuration gives the best mobile readability/performance tradeoff?

Each material answer should become an evidence-backed ADR rather than an undocumented implementation shortcut.

## First playable success criteria
The slice is successful only if:
- moving the hero feels immediate on touch
- selecting and commanding a squad is understandable without a tutorial paragraph
- one battle has a meaningful tactical decision within the first minute
- hero, troops, creeps and towers interact in the same simulation
- win/loss can be reached cleanly
- profiling instrumentation is active
- the architecture can increase unit count without rewriting the game core

## Explicit non-goals
This document does not decide:
- final lore
- final four races
- monetization
- final multiplayer topology
- server backend
- exact art style
- final minimum device
- final maximum unit count

Those decisions stay open until product or ARCONT evidence justifies them.
