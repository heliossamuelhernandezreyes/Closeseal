extends CharacterBody3D

const WALK_SPEED := 6.0
const RUN_SPEED := 11.0
var enabled := true
var camera: Camera3D
var pitch := 0.0

func _ready() -> void:
    var collider := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.35
    capsule.height = 1.8
    collider.shape = capsule
    collider.position.y = 0.9
    add_child(collider)
    camera = Camera3D.new()
    camera.position.y = 1.65
    camera.fov = 75
    camera.far = 1500
    add_child(camera)
    camera.make_current()
    floor_snap_length = 0.35
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * 0.0025)
        pitch = clampf(pitch-event.relative.y*0.0025, -1.4, 1.4)
        camera.rotation.x = pitch
    if event is InputEventMouseButton and event.pressed and enabled:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
    if not enabled:
        return
    if not is_on_floor():
        velocity.y -= 20.0*delta
    elif Input.is_physical_key_pressed(KEY_SPACE):
        velocity.y = 7.0
    var movement := Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W))).normalized()
    var direction := global_basis * Vector3(movement.x,0,movement.y)
    var speed := RUN_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else WALK_SPEED
    velocity.x = direction.x*speed
    velocity.z = direction.z*speed
    move_and_slide()

func teleport(point: Vector3) -> void:
    global_position = point + Vector3(0,0.15,0)
    velocity = Vector3.ZERO
