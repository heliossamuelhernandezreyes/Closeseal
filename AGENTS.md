# Close Seal editor work

For arbitrary native Godot and installed provider API authoring, read
docs/map_forge/GODOT_AUTHORING.md and godot-authoring.json. Use ARCONT's
godot_authoring_control.py (or its MCP stdio transport) for discover, inspect,
revision-checked recipe edits and staged engine output. Preserve canonical map
ownership: separate scene recipes do not edit maps/*.json. Use the actual engine
acceptance job before claiming provider workflow support; discovery is not proof.

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
