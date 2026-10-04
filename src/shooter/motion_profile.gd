extends RefCounted
## Metre-based source gait and runtime cadence share one definition.
const SOLE_HEIGHT := 0.095
const COVER_STRIDE := 0.24
const COVER_PERIOD := 0.82
const WALK_STRIDE := 0.42
const RUN_STRIDE := 0.52
static func nominal_speed(clip: String) -> float:
	if clip in ["cover_left", "cover_right", "cover_peek_left", "cover_peek_right"]:
		return 4.0 * COVER_STRIDE / COVER_PERIOD
	if clip == "crouch_run": return 4.0 * 0.40 / 0.64
	if clip == "crouch_walk": return 4.0 * 0.28 / 0.92
	if clip == "run": return 4.0 * RUN_STRIDE / 0.64
	return 4.0 * WALK_STRIDE / 0.92
