extends Node
## Every frame contributes to distributions; only raw recent detail is a ring.
var arena: Node3D
var enabled := false
var frames_ms: Array[float] = []
var samples: Array[Dictionary] = []
var windows: Array[Dictionary] = []
var histogram := {}
var window_histogram := {}
var raw_cursor := 0
var total_frames := 0
var window_frames := 0
var window_start := 0.0
var window_sum := 0.0
var window_max := 0.0
var timer := 0.0
var seconds := 0.0
var fps := 0.0
var memory_mib := 0.0
var last_saved := ""
var last_frame_us := 0
const MAX_FRAMES := 10800
const MAX_SAMPLES := 3600

func reset_session() -> void:
	frames_ms.clear(); samples.clear(); windows.clear()
	histogram.clear(); window_histogram.clear()
	raw_cursor = 0; total_frames = 0; window_frames = 0
	window_start = 0; window_sum = 0; window_max = 0; timer = 0; seconds = 0
	last_frame_us = 0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		enabled = not enabled

static func percentile(bins: Dictionary, count: int, fraction: float) -> float:
	if count == 0: return 0.0
	var keys := bins.keys()
	keys.sort()
	var cumulative := 0
	for key in keys:
		cumulative += bins[key]
		if cumulative >= ceili(count * fraction): return (float(key)+0.5) / 4.0
	return 0.0

func window_record() -> Dictionary:
	return {"start_s":window_start,"end_s":seconds,"frames":window_frames,
		"mean_ms":window_sum/maxi(window_frames,1),"max_ms":window_max,
		"p50_ms":percentile(window_histogram,window_frames,0.5),
		"p95_ms":percentile(window_histogram,window_frames,0.95),
		"p99_ms":percentile(window_histogram,window_frames,0.99)}

func record_frame(delta: float) -> void:
	if delta <= 0 or not is_finite(delta): return
	var ms := delta * 1000.0
	var bin := int(ms * 4.0)
	histogram[bin] = histogram.get(bin,0)+1
	window_histogram[bin] = window_histogram.get(bin,0)+1
	total_frames += 1; window_frames += 1
	window_sum += ms; window_max = maxf(window_max,ms)
	seconds += delta
	if frames_ms.size() < MAX_FRAMES: frames_ms.append(ms)
	else:
		frames_ms[raw_cursor] = ms
		raw_cursor = (raw_cursor+1) % MAX_FRAMES
	if seconds-window_start >= 60.0:
		windows.append(window_record())
		if windows.size() > 60: windows.pop_front()
		window_start = seconds; window_frames = 0; window_sum = 0; window_max = 0
		window_histogram.clear()

func _process(delta: float) -> void:
	if not is_instance_valid(arena) or not arena.playing:
		last_frame_us=0
		return
	var now := Time.get_ticks_usec()
	var interval := float(now-last_frame_us)/1000000.0 if last_frame_us>0 else delta
	last_frame_us=now
	record_frame(interval)
	timer += interval
	if timer >= 1.0:
		timer = 0
		fps = Engine.get_frames_per_second()
		memory_mib = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
		samples.append({"second":seconds,"fps":fps,"static_memory_mib":memory_mib,
			"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"render_objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)})
		if samples.size() > MAX_SAMPLES: samples.pop_front()

func report(include_raw := true) -> Dictionary:
	var records := windows.duplicate(true)
	if window_frames > 0: records.append(window_record())
	var result := {"version":2,"scope":"android-device" if OS.get_name()=="Android" else "desktop-runtime",
		"os":OS.get_name(),"device":OS.get_model_name(),"engine":Engine.get_version_info(),
		"renderer":RenderingServer.get_video_adapter_name(),"renderer_vendor":RenderingServer.get_video_adapter_vendor(),
		"resolution":[get_viewport().get_visible_rect().size.x,get_viewport().get_visible_rect().size.y],
		"seconds":seconds,"frames_recorded":total_frames,"retained_frames":frames_ms.size(),
		"p50_ms":percentile(histogram,total_frames,0.5),"p95_ms":percentile(histogram,total_frames,0.95),
		"p99_ms":percentile(histogram,total_frames,0.99),"windows":records,"mission":arena.mission_mode,
		"limits":["All frames counted; distributions quantized to 0.25 ms. Raw frames retain recent detail only.",
			"Wall-frame intervals, not CPU/GPU timings. Static memory is not process/GPU memory.",
			"Active-play windows exclude pauses. No direct thermal, display-refresh or touch-latency measurement."]}
	if include_raw:
		result["frame_ms"] = frames_ms.slice(raw_cursor)+frames_ms.slice(0,raw_cursor) if frames_ms.size()==MAX_FRAMES else frames_ms.duplicate()
		result["samples"] = samples.duplicate(true)
	return result

func save_session() -> Dictionary:
	var result := report()
	last_saved = "user://nexo-performance-latest.json"
	var file := FileAccess.open(last_saved,FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(result)); file.close()
	return result

func copy_summary() -> void:
	save_session()
	DisplayServer.clipboard_set(JSON.stringify(report(false)))
