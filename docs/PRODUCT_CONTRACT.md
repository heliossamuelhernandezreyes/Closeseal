# Closeseal Product Contract

Status: PRODUCT DIRECTION LOCKED / TECHNICAL TARGETS PARTIALLY UNDECIDED

This document is the source of truth for product-level constraints that affect architecture. Unknowns stay explicit until decided; they must not be silently inferred from prototypes.

## Canonical repository boundary

- Closeseal owns production game code, scenes, assets, tests, builds and release automation.
- ARCONT owns reusable technical knowledge, evidence, experiments and decision support.
- ARCONT Runtime Lab owns isolated reproducible experiments; it is not a production game repository.

## Engine pin

- Engine: Godot
- Initial version: 4.7.2-stable
- Canonical upstream commit: `ed1daf0bf001b61586d9930840f2f1394092c079`
- Upgrade policy: deliberate only; record reason, evidence and migration risk before changing.

## Product decisions

| Decision | State | Current value |
|---|---|---|
| Genre | LOCKED | Mobile-first Hero RTS |
| Primary platform | LOCKED | Android |
| Secondary platforms | OPEN | iOS and PC candidates |
| Camera | LOCKED | Constrained isometric/angled 2.5D presentation |
| World dimensionality | LOCKED | Real-time 3D world with 2D UI |
| Core gameplay | LOCKED | Direct hero control plus troops, defensive towers, creeps and objectives |
| Races/factions | VISION LOCKED | Four asymmetric playable races |
| Campaign | VISION LOCKED | Yes |
| Multiplayer | VISION LOCKED | Yes; exact modes pending |
| Online topology | UNDECIDED | — |
| Target player count | UNDECIDED | — |
| World/level scale | UNDECIDED | — |
| Peak active entities | UNDECIDED | — |
| Target frame rate | TARGET | 60 FPS on representative mid-range Android hardware |
| Minimum hardware | UNDECIDED | — |
| Art direction | DIRECTION LOCKED | Stylized readable 3D for mobile RTS viewing |
| Input model | DIRECTION LOCKED | Touch-first hero control plus tactical commands |

## First vertical slice

Before expanding the full vision, prove one complete battle loop with:

- one playable hero;
- one provisional race;
- three troop archetypes;
- two tower archetypes;
- one creep flow;
- one compact 3D battlefield;
- one opposing AI force;
- touch-first controls;
- measurable Android performance.

## Rule

No subsystem may be selected solely because it is familiar. Architecture decisions that materially affect performance, networking, simulation scale, rendering, physics, AI, animation or streaming should either cite mature ARCONT evidence or create a new scoped question for ARCONT/Runtime Lab.
