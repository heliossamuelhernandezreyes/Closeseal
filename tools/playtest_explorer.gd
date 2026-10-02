extends CharacterBody3D
## Input-driven test actor. Gameplay production controllers remain game-owned.
signal playtest_tick(snapshot: Dictionary)

@export var speed: float = 4.0
@export var step_height: float = 0.25
@export var interaction_target: NodePath = NodePath("../../Navigation/Workshop/Terminal")
const ACTIONS = ["arcont_left", "arcont_right", "arcont_back", "arcont_forward", "arcont_interact"]
var _created_actions: Array[String] = []
var _ticks: int = 0
var _interactions: int = 0
var _steps: int = 0
var _enabled: bool = false

func _ready() -> void:
    for action in ACTIONS:
        if not InputMap.has_action(action):
            InputMap.add_action(action)
            _created_actions.append(action)
    floor_snap_length = 0.35
    collision_mask = 5
    collision_layer = 2
    set_physics_process(false)

func _exit_tree() -> void:
    for action in _created_actions:
        Input.action_release(action)
        InputMap.erase_action(action)

func begin_playtest() -> void:
    _ticks = 0
    _interactions = 0
    _steps = 0
    _enabled = true

func end_playtest() -> void:
    _enabled = false
    set_physics_process(false)

func _input(event: InputEvent) -> void:
    if not _enabled or not event.is_action_pressed("arcont_interact"): return
    var terminal: Node3D = get_node_or_null(interaction_target)
    if terminal != null and global_position.distance_to(terminal.global_position) <= 2.0:
        _interactions += 1
        terminal.set_meta("activated", true)

func _physics_process(delta: float) -> void:
    var input := Input.get_vector("arcont_left", "arcont_right", "arcont_back", "arcont_forward")
    velocity.x = input.x * speed
    velocity.z = input.y * speed
    velocity.y = -1.0 if is_on_floor() else velocity.y - 12.0 * delta
    var motion := Vector3(velocity.x, 0, velocity.z) * delta
    floor_snap_length = 0.35
    if is_on_floor() and motion.length_squared() > 0:
        if _step_up(motion): floor_snap_length = 0
    move_and_slide()
    _ticks += 1
    playtest_tick.emit(playtest_snapshot())

func _step_up(motion: Vector3) -> bool:
    var contact := PhysicsTestMotionResult3D.new()
    if not test_move(global_transform, motion, contact) or absf(contact.get_collision_normal().y) > 0.2: return false
    var raised := global_transform
    raised.origin.y += step_height
    if test_move(global_transform, Vector3.UP * step_height) or test_move(raised, motion): return false
    var destination := global_position + motion + motion.normalized() * 0.38
    var query := PhysicsRayQueryParameters3D.create(destination + Vector3.UP * step_height, destination - Vector3.UP * 0.05, collision_mask)
    var support := get_world_3d().direct_space_state.intersect_ray(query)
    if support.is_empty(): return false
    var rise: float = support["position"].y - global_position.y
    if rise <= 0.02 or rise > step_height or support["normal"].dot(Vector3.UP) < 0.7: return false
    # Physical step-up only after swept capsule clearance and a support query.
    global_position.y = support["position"].y + 0.005
    velocity.y = 0
    _steps += 1
    return true

func playtest_snapshot() -> Dictionary:
    var contacts: Array = []
    var world: Node = get_parent().get_parent()
    for index in range(get_slide_collision_count()):
        var contact := get_slide_collision(index)
        var collider: Node = contact.get_collider()
        var identity: Node = collider
        while identity != null and not identity.has_meta("source_id"):
            identity = identity.get_parent()
        contacts.append({"path": String(world.get_path_to(collider)),
                         "source_id": identity.get_meta("source_id", "") if identity != null else "",
                         "normal": [contact.get_normal().x, contact.get_normal().y, contact.get_normal().z]})
    var terminal: Node = get_node_or_null(interaction_target)
    return {"tick": _ticks, "position": [global_position.x, global_position.y, global_position.z],
            "velocity": [velocity.x, velocity.y, velocity.z], "on_floor": is_on_floor(),
            "contacts": contacts, "interactions": _interactions, "physical_step_ups": _steps,
            "terminal_active": terminal.get_meta("activated", false) if terminal != null else false}
