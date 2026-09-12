# ADR-0001 — Separate combat simulation from presentation

Status: ACCEPTED FOR VERTICAL SLICE

## Requirement
Close Seal must support a mobile Hero RTS battle where logical combat scale can grow without forcing every entity to carry an expensive presentation/runtime object model.

## Decision
The authoritative combat simulation and the visual presentation are separate subsystems.

Simulation owns identity, state, orders, cooldowns, targeting, combat resolution and victory state. Presentation consumes simulation state and renders/interpolates it using the cheapest representation that preserves readability.

A logical unit is not required to map 1:1 to a Godot Node, CharacterBody3D, AnimationTree, NavigationAgent3D or physics body.

## Why
ARCONT already has scoped evidence that per-frame processing cost can grow sharply with many processed SceneTree nodes in Godot 4.7.2, while inactive membership alone is much cheaper. This observation is not universal Android proof, but it is strong enough to reject a design that assumes one heavy processing scene object per soldier without measurement.

## Alternatives rejected for baseline
### One full scene tree character per unit
Simple to prototype but risks coupling gameplay scale directly to node, script, navigation, animation and physics overhead.

### Pure visual swarm with no individual logical units
Potentially cheap, but insufficient for the intended RTS combat where members need health, targeting and tactical outcomes.

## Validation
The vertical-slice scale campaign will compare representations at 50, 100, 200, 300 and 500 active units. ARCONT/Runtime Lab evidence will decide the concrete storage, ticking, rendering, navigation and animation implementation.

## Rollback trigger
Revisit this ADR only if reproducible profiling shows the separation adds material complexity without measurable scale or maintainability benefit at Close Seal's validated production target.
