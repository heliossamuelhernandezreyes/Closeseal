# Close Seal — Tactical Command & Mobile HUD

Status: DESIGN PILLAR / vertical-slice target

## Core fantasy
Close Seal is a Hero RTS: the player directly pilots a powerful hero while commanding an army through high-level tactical intent rather than per-soldier micromanagement.

**Hero = direct control.**
**Squad = tactical unit.**
**Soldier = local executor.**
**Formation = squad constraint/behavior.**
**Order = player intent.**

This separation is a product rule and should remain compatible with the simulation/presentation split in ADR-0001.

## Mobile HUD spatial contract

### Lower left — hero movement
- Virtual joystick dedicated to direct hero locomotion.
- Must remain reachable without covering the central combat field.
- Movement input must not select troops or pan the tactical camera while the joystick owns the pointer.

### Upper left — army command
- Persistent formation controls for the currently selected squad(s).
- Squad cards/selectors adjacent to formation controls.
- A squad-division control exposes fast army partition presets.

### Lower center — tactical minimap
- Always-readable compact battlefield map.
- Tap minimap: reposition tactical camera to the tapped world location.
- Drag on minimap: continuously scrub/pan camera across the battlefield.
- Long-press/command modifier is reserved for later testing as a possible squad-order shortcut; it is not canonical yet.

### Lower right — hero actions
- Basic attack.
- Dash/mobility action.
- Hero abilities.
- Troop summon/reinforcement action where the hero design supports it.
- Army formation buttons must not be mixed into the hero ability cluster.

### Main viewport — right-thumb camera
- Drag on unoccupied terrain: pan tactical camera.
- Tap enemy/unit: targeting or selection has priority over camera movement.
- Tap interactive battlefield object: contextual interaction has priority.
- Gestures must use explicit pointer ownership so hero controls, selection and camera do not fight each other.

## Delegated tactical actions
The player issues intent to squads. Soldiers solve local positions, spacing and obstacle avoidance while respecting the squad order and formation constraints.

Initial order vocabulary:
- Move
- Attack target
- Attack-move
- Hold
- Retreat
- Follow hero

An order should be representable independently from presentation so it can later be serialized for multiplayer/replay.

## Formation system
Formation names may reference historical structures, but Close Seal implements their tactical principle rather than pretending to reproduce a historical army exactly. Each formation must have gameplay tradeoffs and measurable simulation parameters.

### Line
Purpose: maximize frontage and ranged firing opportunity.
- wide frontage
- low depth
- strong firing coverage
- weaker local concentration/cohesion

### Column
Purpose: traversal and rapid movement through narrow space.
- narrow frontage
- high depth
- good pathing through corridors
- vulnerable if engaged frontally before redeployment

### Phalanx / shield wall
Purpose: cohesive frontal defense.
- dense front
- high cohesion
- reduced turn/reorientation speed
- strong frontal protection/anti-push behavior
- vulnerable to flank/rear pressure

### Wedge / arrowhead
Purpose: concentrate force at a breakthrough point.
- strong leading point
- aggressive forward pressure
- reduced lateral coverage
- exposed flanks if breakthrough fails

### Crescent / horseshoe
Purpose: envelop, channel or threaten flanks.
- center held farther back
- wings advanced
- requires space and sufficient squad width
- weaker if compressed into a corridor

### Square / all-around defense
Purpose: resist pressure from several directions.
- reduced directional vulnerability
- lower mobility and offensive frontage
- useful against fast encirclement threats

### Dispersed
Purpose: reduce vulnerability to area attacks and projectile saturation.
- increased spacing
- reduced AoE density
- lower cohesion and mutual protection

## Formation simulation contract
A formation is not a cosmetic pose. Candidate parameters include:
- slot geometry
- preferred member spacing
- cohesion radius
- reformation tolerance
- turn rate / reorientation cost
- movement-speed modifier
- frontal/rear/flank exposure
- push resistance
- ranged firing clearance
- local avoidance freedom
- maximum useful squad size

Bonuses must emerge from explicit mechanics where possible rather than arbitrary percentage buffs. Example: a shield wall gains frontal resilience because shields overlap, spacing is constrained and facing is maintained—not merely because `defense += 20%`.

## Squad division
The player can rapidly partition selected troops without individually selecting soldiers.

Initial presets:
1. **Balanced** — divide available roles proportionally between 2–4 squads.
2. **By role** — create role-focused squads such as frontline/tanks, ranged, and support/regular troops when composition permits.
3. **Custom** — future/manual allocation surface after the fast presets are proven usable.

The division control should expose a fast 1/2/3/4 squad choice. Three squads is the initial UX reference because it allows meaningful flanking without overwhelming a phone screen; the final supported count requires playtesting.

Each resulting squad gets a persistent selectable card and stable squad identity until merged/disbanded.

## Command execution model
1. Player selects one or more squads.
2. Player selects a formation or keeps the current formation.
3. Player issues a world-space order.
4. Squad computes an anchor, orientation and formation slots.
5. Members receive local targets/intent derived from squad slots.
6. Members solve short-range separation/avoidance without destroying formation intent.
7. Squad detects excessive deformation and reforms according to tolerance/urgency.

Formation transitions should be visible and take time. Instant teleport/reordering is forbidden in normal combat.

## Input arbitration
Every touch pointer has one owner at a time:
- hero joystick
- hero action
- army-command UI
- minimap
- world selection/targeting
- camera gesture

UI hit-testing occurs before world camera handling. Camera drag begins only after movement exceeds a small threshold, allowing a short tap to remain a selection/targeting gesture. Multi-touch must allow left-thumb hero movement while the right thumb uses hero actions or camera where technically feasible.

## Vertical-slice implementation order
1. HUD safe zones and pointer ownership.
2. Hero joystick + right-thumb camera pan.
3. Tactical minimap tap/drag camera navigation.
4. Squad selection cards.
5. Line and phalanx formations.
6. Move/attack-move order execution at squad level.
7. Wedge and dispersed formations.
8. Fast 1/2/3 squad division with Balanced and By-role presets.
9. Crescent, column and square after pathing/readability tests.
10. Multiplayer serialization only after deterministic command semantics are stable enough to measure.

## Required Arcont experiments
Before hard-coding final budgets, Arcont/Runtime Lab should measure:
- formation slot solving cost at 50/100/200/300/500 combat units
- local avoidance cost under dense phalanx and dispersed layouts
- reformation cost after obstacles/collisions
- navigation/path corridor behavior for wide formations
- mobile touch conflict/error rate for simultaneous hero + camera/ability input
- minimap targeting precision at representative phone sizes
- readability of formation state at tactical camera distances

## Non-goals for first implementation
- exact historical simulation
- per-soldier manual micro as the primary control model
- arbitrary stat buffs used as substitutes for formation mechanics
- unrestricted camera rotation
- desktop-first HUD
- final four-faction visual language

## Design test
A successful Close Seal encounter should allow the player to do something like:

> Move the hero directly, order Squad A into a phalanx to hold the center, split ranged troops into Squad B, send them to a flank in line formation, then personally dash the hero into the breakthrough—all with a small number of thumb actions.

If that sequence requires selecting individual soldiers or opening nested menus, the command UX has failed.