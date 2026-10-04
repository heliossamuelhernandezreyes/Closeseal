extends Node3D
## Fixed reusable effect/voice pools; no per-shot node/material allocation.
const CAPACITY := 64
var entries: Array[Dictionary] = []
var materials := {}
var local_voices: Array[AudioStreamPlayer] = []
var spatial_voices: Array[AudioStreamPlayer3D] = []
var local_cursor := 0
var spatial_cursor := 0
var effect_cursor := 0
var dropped := 0
var arena: Node3D
var ball: SphereMesh
var line: CylinderMesh
var sound_variants: Dictionary={}
var audio_events: Dictionary={}

func _ready() -> void:
	ball = SphereMesh.new(); ball.radius = 1; ball.height = 2; ball.radial_segments = 8; ball.rings = 4
	line = CylinderMesh.new(); line.top_radius = 1; line.bottom_radius = 1; line.height = 1; line.radial_segments = 6
	for color in ["ffda7d","ff8961","ffc878","a39787","aab6b8","b94c42","252d31"]:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(color)
		materials[color] = material
	for _index in range(CAPACITY):
		var node := MeshInstance3D.new()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visible = false
		add_child(node)
		entries.append({"node":node,"life":0.0,"duration":1.0,"scale":Vector3.ONE,"velocity":Vector3.ZERO,"mark":false})
	for _index in range(8):
		var voice := AudioStreamPlayer.new(); add_child(voice); local_voices.append(voice)
	for _index in range(16):
		var voice := AudioStreamPlayer3D.new()
		voice.max_distance = 70; voice.unit_size = 8
		add_child(voice); spatial_voices.append(voice)

func acquire(duration: float, color: String, size: Vector3, position_value: Vector3, velocity := Vector3.ZERO, mark := false) -> MeshInstance3D:
	var chosen := -1
	for offset in range(CAPACITY):
		var index := (effect_cursor+offset) % CAPACITY
		if entries[index].life <= 0: chosen=index; break
	if chosen < 0:
		# Marks are expendable before active muzzle/impact feedback.
		for offset in range(CAPACITY):
			var index := (effect_cursor+offset) % CAPACITY
			if entries[index].mark: chosen=index; break
	if chosen < 0: dropped+=1; return null
	effect_cursor=(chosen+1)%CAPACITY
	var entry := entries[chosen]
	entry.life=duration; entry.duration=duration; entry.scale=size; entry.velocity=velocity; entry.mark=mark
	var node: MeshInstance3D = entry.node
	node.mesh=ball; node.material_override=materials[color]; node.global_position=position_value
	node.basis=Basis.IDENTITY; node.scale=size; node.visible=true
	return node

func tracer(start: Vector3, end: Vector3, hostile := false) -> void:
	var length := start.distance_to(end)
	if length < 0.01: return
	var node := acquire(0.055,"ff8961" if hostile else "ffda7d",Vector3(0.006,length,0.006),start.lerp(end,0.5))
	if node:
		node.mesh=line; node.basis=Basis(Quaternion(Vector3.UP,(end-start).normalized())).scaled(Vector3(0.006,length,0.006))

func impact(point: Vector3, normal: Vector3, surface: String) -> void:
	var color := "ffc878" if surface=="metal" else "b94c42" if surface=="flesh" else "a39787"
	var tangent := normal.cross(Vector3.UP).normalized()
	if tangent.length()<0.1:tangent=Vector3.RIGHT
	for index in range(3):
		var direction := normal*0.8+tangent*(index-1)*0.6+Vector3.UP*0.25
		acquire(0.16 if surface=="metal" else 0.30,color,Vector3.ONE*(0.018 if surface=="metal" else 0.05),point+normal*0.035,direction*(2.0 if surface=="metal" else 0.55))
	if surface!="flesh":
		var mark := acquire(5.0,"252d31",Vector3(0.026,0.003,0.026),point+normal*0.009,Vector3.ZERO,true)
		if mark:mark.basis=Basis(Quaternion(Vector3.UP,normal)).scaled(Vector3(0.026,0.003,0.026))

func _process(delta: float) -> void:
	var active := 0
	for entry in entries:
		if entry.life<=0:continue
		entry.life=maxf(0,entry.life-delta)
		var node: MeshInstance3D=entry.node
		node.visible=entry.life>0
		if entry.life<=0:continue
		active+=1
		node.global_position+=entry.velocity*delta
		if not entry.mark and node.mesh==ball:
			node.scale=entry.scale*maxf(0.1,entry.life/entry.duration)
	if is_instance_valid(arena):arena.effect_count=active

func sound(name_: String, point := Vector3.INF, volume := -10.0, pitch := 1.0) -> void:
	if not arena.sounds.has(name_):return
	var bank: Variant=arena.sounds[name_]
	var stream: AudioStream
	if bank is Array:
		var variant: int=int(sound_variants.get(name_,0))%bank.size()
		stream=bank[variant]
		sound_variants[name_]=variant+1
	else:stream=bank
	audio_events[name_]=int(audio_events.get(name_,0))+1
	var voice: Node
	if point==Vector3.INF:
		voice=local_voices[local_cursor]; local_cursor=(local_cursor+1)%local_voices.size()
	else:
		voice=spatial_voices[spatial_cursor]; spatial_cursor=(spatial_cursor+1)%spatial_voices.size()
		voice.global_position=point
	voice.stop(); voice.stream=stream; voice.volume_db=volume; voice.pitch_scale=pitch; voice.play()

func stop_audio() -> void:
	for voice in local_voices+spatial_voices:
		voice.stop();voice.stream=null
