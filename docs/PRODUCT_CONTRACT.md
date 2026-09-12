# Closeseal Product Contract

Status: BOOTSTRAP / UNDECIDED PRODUCT SHAPE

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
| Genre | UNDECIDED | — |
| Primary platform | UNDECIDED | — |
| Secondary platforms | UNDECIDED | — |
| Camera | UNDECIDED | — |
| Single-player / multiplayer | UNDECIDED | — |
| Online topology | UNDECIDED | — |
| Target player count | UNDECIDED | — |
| World/level scale | UNDECIDED | — |
| Peak active entities | UNDECIDED | — |
| Target frame rate | UNDECIDED | — |
| Minimum hardware | UNDECIDED | — |
| Art direction | UNDECIDED | — |
| Input model | UNDECIDED | — |

## Rule

No subsystem may be selected solely because it is familiar. Architecture decisions that materially affect performance, networking, simulation scale, rendering, physics, AI, animation or streaming should either cite mature ARCONT evidence or create a new scoped question for ARCONT/Runtime Lab.
