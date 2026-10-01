# Close Seal editor work

Use ARCONT as the authoring-time technical toolchain. Production game code and
authored maps stay here; reusable standards and tools stay in ARCONT.

For map creation/editing, read `docs/map_forge/EDITOR_CONTROL.md` and
`map-forge.authoring.json`. Use the ARCONT control CLI to discover capabilities,
inspect state/revision, submit explicit edits, materialize and capture. Decide
the geometry yourself; this project does not provide a generative map service.

Preserve the canonical contract. Inspect actual captures when changing visual
output. Do not claim Android performance from Linux CI. Custom mesh collision
and route navigation are distinct and must be tested for the requested layout.

Run `tools/validate_maps.py`, `tools/validate_physical_world.py` and the control
smoke test for editor changes. Godot import must contain no script errors.
Changes belong on reviewable branches. Do not merge Close Seal PRs without the
user's explicit authorization.

Read `docs/map_forge/ENVIRONMENT_AUTHORING.md` for environment work. Use
`purpose: environment` when competitive topology is not requested. Brushes and
provider pulls are explicit revision-checked editor operations. Inspect captures
and test actual collision/navigation when changing traversal. Preserve authored
JSON; provider region files are generated data.
