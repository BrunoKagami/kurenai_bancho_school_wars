extends CharacterBody2D

enum EnemyState {
	IDLE,
	CHASE,
	ATTACK,
	HURT,
	BRACE,
	REPOSITION,
	DEFEATED,
}

const SPRITE_GROUND_OFFSET := 97.28
const DEFEATED_SPRITE_GROUND_OFFSET := 127.68
const ATTACK_HITBOX_SIZE := Vector2(64.0, 20.0)
const GROUND_ALIGNMENT_TOLERANCE := 18.0
const ARENA_LEFT := 75.0
const ARENA_RIGHT := 1460.0
const ARENA_TOP := 415.0
const ARENA_BOTTOM := 495.0
const LEFT_WALL_END := 230.0
const RIGHT_WALL_START := 1285.0
const SIDE_TOP_LIMIT := 478.0
const DEFAULT_COLLISION_LAYER := 4
const DEFAULT_COLLISION_MASK := 1
const CORNER_ESCAPE_MARGIN := 120.0

@export var move_speed := 120.0
@export var attack_range := 74.0
@export var attack_slot_tolerance := 12.0
@export var personal_space_x := 58.0
@export var personal_space_y := 22.0
@export var separation_speed := 135.0
@export var separation_position_step := 1.2
@export var contact_reposition_delay := 0.32
@export var reposition_distance_x := 96.0
@export var reposition_distance_y := 34.0
@export var reposition_tolerance := 10.0
@export var reposition_duration := 0.6
@export var reposition_speed := 190.0
@export var brace_duration := 0.22
@export var max_external_push_distance := 2.0
@export var max_health := 40.0
@export var attack_damage := 8.0
@export var attack_hit_time := 0.16
@export var attack_duration := 0.42
@export var attack_cooldown := 0.7
@export var hurt_duration := 0.22
@export var active_on_start := true
@export var defeated_disappear_delay := 2.5

var state: EnemyState = EnemyState.IDLE
var state_time: float = 0.0
var facing: float = -1.0
var health: float = 40.0
var attack_hit_checked: bool = false
var cooldown_timer: float = 0.0
var contact_timer: float = 0.0
var reposition_target := Vector2.ZERO
var previous_position: Vector2 = Vector2.ZERO
var target: Node2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var hurt_shape: CollisionShape2D = $Hurtbox/CollisionShape2D
@onready var attack_area: Area2D = $AttackArea
@onready var attack_shape: CollisionShape2D = $AttackArea/CollisionShape2D


func _ready() -> void:
	health = max_health
	target = get_tree().get_first_node_in_group("player")
	previous_position = global_position
	attack_area.monitoring = false
	if not active_on_start:
		_deactivate()
		return
	_change_state(EnemyState.IDLE)
	queue_redraw()


func _physics_process(delta: float) -> void:
	state_time += delta
	cooldown_timer = maxf(cooldown_timer - delta, 0.0)

	if not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player")

	_update_state()
	_update_contact_timer(delta)
	_apply_personal_space()
	previous_position = global_position
	move_and_slide()
	_limit_external_push()
	global_position.x = clampf(global_position.x, ARENA_LEFT, ARENA_RIGHT)
	global_position.y = clampf(global_position.y, _arena_top_at_x(global_position.x), ARENA_BOTTOM)
	_update_animation()
	queue_redraw()


func take_hit(direction: float) -> void:
	if not visible:
		return
	if state == EnemyState.DEFEATED:
		return
	health -= 15.0
	if direction != 0.0:
		facing = -1.0 if direction > 0.0 else 1.0
	if health <= 0.0:
		_change_state(EnemyState.DEFEATED)
	else:
		_change_state(EnemyState.HURT)


func activate() -> void:
	if visible:
		return
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	set_physics_process(true)
	health = max_health
	previous_position = global_position
	_restore_body_collision()
	hurt_shape.disabled = false
	_change_state(EnemyState.IDLE)
	queue_redraw()


func _deactivate() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	body_shape.disabled = true
	hurt_shape.disabled = true
	attack_area.monitoring = false


func _update_state() -> void:
	match state:
		EnemyState.IDLE:
			velocity = Vector2.ZERO
			if _has_target():
				_change_state(EnemyState.CHASE)

		EnemyState.CHASE:
			if not _has_target():
				_change_state(EnemyState.IDLE)
				return
			_face_target()
			if _can_attack_target():
				_change_state(EnemyState.ATTACK)
				return
			velocity = _movement_toward_target()

		EnemyState.ATTACK:
			velocity = Vector2.ZERO
			if state_time >= attack_hit_time and not attack_hit_checked:
				_check_attack_hits()
			if state_time >= attack_duration:
				attack_area.monitoring = false
				cooldown_timer = attack_cooldown
				_change_state(EnemyState.CHASE)

		EnemyState.HURT:
			velocity = Vector2.ZERO
			if state_time >= hurt_duration:
				_change_state(EnemyState.CHASE)

		EnemyState.BRACE:
			velocity = Vector2.ZERO
			if _can_attack_target():
				_change_state(EnemyState.ATTACK)
				return
			if state_time >= brace_duration:
				_start_reposition()

		EnemyState.REPOSITION:
			if not _has_target():
				_change_state(EnemyState.IDLE)
				return
			velocity = _movement_toward_reposition_target()
			if global_position.distance_to(reposition_target) <= reposition_tolerance or state_time >= reposition_duration:
				_change_state(EnemyState.CHASE)

		EnemyState.DEFEATED:
			velocity = Vector2.ZERO
			if state_time >= defeated_disappear_delay:
				queue_free()


func _change_state(next_state: EnemyState) -> void:
	if state == next_state and state_time > 0.0:
		return

	state = next_state
	state_time = 0.0
	attack_hit_checked = false

	match state:
		EnemyState.IDLE:
			_restore_body_collision()
			attack_area.monitoring = false
			animated_sprite.play("idle")

		EnemyState.CHASE:
			_restore_body_collision()
			attack_area.monitoring = false
			animated_sprite.play("walk")

		EnemyState.ATTACK:
			_restore_body_collision()
			_set_attack_hitbox(ATTACK_HITBOX_SIZE)
			attack_area.position.x = 66.0 * facing
			attack_area.monitoring = true
			animated_sprite.play("jab")

		EnemyState.HURT:
			_restore_body_collision()
			attack_area.monitoring = false
			animated_sprite.play("jab")

		EnemyState.BRACE:
			_restore_body_collision()
			attack_area.monitoring = false
			animated_sprite.play("idle")

		EnemyState.REPOSITION:
			attack_area.monitoring = false
			_disable_body_collision()
			animated_sprite.play("walk")

		EnemyState.DEFEATED:
			attack_area.monitoring = false
			collision_layer = 0
			collision_mask = 0
			body_shape.disabled = true
			hurt_shape.disabled = true
			animated_sprite.play("jump_recover")


func _has_target() -> bool:
	return is_instance_valid(target)


func _face_target() -> void:
	var delta_x: float = target.global_position.x - global_position.x
	if absf(delta_x) > 1.0:
		facing = 1.0 if delta_x > 0.0 else -1.0


func _can_attack_target() -> bool:
	if cooldown_timer > 0.0:
		return false
	var delta_to_target: Vector2 = target.global_position - global_position
	return absf(global_position.x - _target_attack_x()) <= attack_slot_tolerance and absf(delta_to_target.y) <= GROUND_ALIGNMENT_TOLERANCE


func _movement_toward_target() -> Vector2:
	var delta_to_target: Vector2 = target.global_position - global_position
	var target_attack_x: float = _target_attack_x()
	var direction: Vector2 = Vector2.ZERO
	if absf(target_attack_x - global_position.x) > attack_slot_tolerance:
		direction.x = 1.0 if target_attack_x > global_position.x else -1.0
	if absf(delta_to_target.y) > GROUND_ALIGNMENT_TOLERANCE * 0.55:
		direction.y = 1.0 if delta_to_target.y > 0.0 else -1.0
	return direction.normalized() * move_speed


func _update_contact_timer(delta: float) -> void:
	if state == EnemyState.DEFEATED or state == EnemyState.REPOSITION or state == EnemyState.BRACE or not _has_target():
		contact_timer = 0.0
		return

	if _is_overlapping_target_space() and not _can_attack_target():
		contact_timer += delta
		if contact_timer >= contact_reposition_delay:
			_change_state(EnemyState.BRACE)
	else:
		contact_timer = 0.0


func _start_reposition() -> void:
	contact_timer = 0.0
	var horizontal_escape: float = _preferred_attack_side()

	var vertical_escape: float = -1.0 if global_position.y > ARENA_TOP + reposition_distance_y else 1.0
	var target_x: float = clampf(
		target.global_position.x + horizontal_escape * reposition_distance_x,
		ARENA_LEFT + reposition_distance_x,
		ARENA_RIGHT - reposition_distance_x
	)
	reposition_target = Vector2(
		target_x,
		clampf(target.global_position.y + vertical_escape * reposition_distance_y, _arena_top_at_x(target_x), ARENA_BOTTOM)
	)
	_change_state(EnemyState.REPOSITION)


func _movement_toward_reposition_target() -> Vector2:
	var direction: Vector2 = reposition_target - global_position
	if direction.length_squared() <= 1.0:
		return Vector2.ZERO
	return direction.normalized() * reposition_speed


func _limit_external_push() -> void:
	if state == EnemyState.DEFEATED or state == EnemyState.REPOSITION:
		return
	if not _has_target() or not _is_overlapping_target_space():
		return

	var displacement: Vector2 = global_position - previous_position
	if displacement.length() <= max_external_push_distance:
		return

	global_position = previous_position + displacement.normalized() * max_external_push_distance
	if state == EnemyState.CHASE:
		_change_state(EnemyState.BRACE)


func _is_overlapping_target_space() -> bool:
	var delta_from_target: Vector2 = global_position - target.global_position
	if absf(global_position.x - _target_attack_x()) <= attack_slot_tolerance and absf(delta_from_target.y) <= GROUND_ALIGNMENT_TOLERANCE:
		return false
	return absf(delta_from_target.x) < personal_space_x and absf(delta_from_target.y) < personal_space_y


func _apply_personal_space() -> void:
	if state == EnemyState.DEFEATED or state == EnemyState.REPOSITION or not _has_target():
		return
	var delta_from_target: Vector2 = global_position - target.global_position
	if absf(delta_from_target.x) >= personal_space_x or absf(delta_from_target.y) >= personal_space_y:
		return

	var push_direction: Vector2 = Vector2.ZERO
	if absf(delta_from_target.x) > 1.0:
		push_direction.x = 1.0 if delta_from_target.x > 0.0 else -1.0
	else:
		push_direction.x = -facing
	if absf(delta_from_target.y) > 1.0:
		push_direction.y = (1.0 if delta_from_target.y > 0.0 else -1.0) * 0.45

	var separation_direction: Vector2 = push_direction.normalized()
	velocity += separation_direction * separation_speed
	global_position += separation_direction * separation_position_step


func _target_attack_x() -> float:
	var side: float = _preferred_attack_side()
	return target.global_position.x + side * attack_range


func _preferred_attack_side() -> float:
	if target.global_position.x <= ARENA_LEFT + CORNER_ESCAPE_MARGIN:
		return 1.0
	if target.global_position.x >= ARENA_RIGHT - CORNER_ESCAPE_MARGIN:
		return -1.0

	if global_position.x > target.global_position.x:
		return 1.0
	if global_position.x < target.global_position.x:
		return -1.0
	return -facing


func _set_attack_hitbox(hitbox_size: Vector2) -> void:
	var rectangle := attack_shape.shape as RectangleShape2D
	rectangle.size = hitbox_size


func _restore_body_collision() -> void:
	if health <= 0.0:
		return
	collision_layer = DEFAULT_COLLISION_LAYER
	collision_mask = DEFAULT_COLLISION_MASK
	body_shape.disabled = false


func _disable_body_collision() -> void:
	collision_layer = 0
	collision_mask = 0
	body_shape.disabled = true


func _check_attack_hits() -> void:
	attack_hit_checked = true
	for area in attack_area.get_overlapping_areas():
		var owner: Node = area.get_parent()
		if owner != null and owner.has_method("take_hit"):
			owner.take_hit(attack_damage, facing)


func _arena_top_at_x(x_position: float) -> float:
	if x_position < LEFT_WALL_END:
		var side_weight: float = inverse_lerp(LEFT_WALL_END, ARENA_LEFT, x_position)
		return lerpf(ARENA_TOP, SIDE_TOP_LIMIT, side_weight)
	if x_position > RIGHT_WALL_START:
		var side_weight: float = inverse_lerp(RIGHT_WALL_START, ARENA_RIGHT, x_position)
		return lerpf(ARENA_TOP, SIDE_TOP_LIMIT, side_weight)
	return ARENA_TOP


func _update_animation() -> void:
	animated_sprite.flip_h = facing < 0.0
	if state == EnemyState.DEFEATED:
		animated_sprite.position = Vector2(0.0, -DEFEATED_SPRITE_GROUND_OFFSET)
	else:
		animated_sprite.position = Vector2(0.0, -SPRITE_GROUND_OFFSET)


func _draw() -> void:
	_draw_shadow_ellipse(Vector2(0.0, -3.0), Vector2(68.0, 9.0), Color(0.05, 0.06, 0.09, 0.3))


func _draw_shadow_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for index in 24:
		var angle: float = TAU * float(index) / 24.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)
