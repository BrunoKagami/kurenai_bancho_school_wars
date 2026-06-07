extends CharacterBody2D

signal stats_changed(health: float, stamina: float)

enum PlayerState {
	IDLE,
	WALK,
	JUMP_PREPARE,
	JUMP_RISE,
	JUMP_LAND,
	JAB,
	FLYING_KICK,
	FLYING_KICK_FALL,
	FLYING_KICK_LAND,
}

const SPRITE_GROUND_OFFSET := 97.28
const JUMP_SPRITE_GROUND_OFFSET := 127.68
const JAB_HITBOX_SIZE := Vector2(75.0, 20.0)
const FLYING_KICK_HITBOX_SIZE := Vector2(75.0, 24.0)
const GROUND_ALIGNMENT_TOLERANCE := 18.0
const ARENA_LEFT := 75.0
const ARENA_RIGHT := 1460.0
const ARENA_TOP := 415.0
const ARENA_BOTTOM := 495.0
const LEFT_WALL_END := 230.0
const RIGHT_WALL_START := 1285.0
const SIDE_TOP_LIMIT := 478.0

@export var move_speed := 230.0
@export var jump_speed := 800.0
@export var gravity := 2200.0
@export var jump_hold_force := 80.0
@export var jump_hold_duration := 0.18
@export var jump_cut_multiplier := 0.45
@export var jump_prepare_duration := 0.16
@export var jump_up_frame_duration := 0.055
@export var jump_visual_height_scale := 0.32
@export var max_health := 100.0
@export var max_stamina := 100.0
@export var jab_stamina_cost := 12.0
@export var stamina_recovery := 24.0
@export var jab_hit_time := 0.12
@export var jab_duration := 0.25
@export var flying_kick_pose_duration := 0.38
@export var flying_kick_hit_time := 0.08
@export var flying_kick_active_duration := 0.22
@export var flying_kick_recovery_duration := 0.42
@export var jump_recovery_duration := 0.12
@export var post_recovery_action_lock := 0.12

var state: PlayerState = PlayerState.IDLE
var state_time := 0.0
var facing := 1.0
var air_facing := 1.0
var jump_height := 0.0
var vertical_speed := 0.0
var jump_hold_timer := 0.0
var jump_cut_applied := false
var jump_visual_timer := 0.0
var action_locked_until_release := false
var action_lock_timer := 0.0
var attack_hit_checked := false
var health := 100.0
var stamina := 100.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_area: Area2D = $AttackArea
@onready var attack_shape: CollisionShape2D = $AttackArea/CollisionShape2D


func _ready() -> void:
	health = max_health
	stamina = max_stamina
	attack_area.monitoring = false
	_change_state(PlayerState.IDLE)
	stats_changed.emit(health, stamina)
	queue_redraw()


func _physics_process(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	state_time += delta
	_update_action_lock(delta)
	_update_state(delta, input_vector)
	_recover_stamina(delta)
	_apply_velocity(input_vector)

	move_and_slide()
	global_position.x = clampf(global_position.x, ARENA_LEFT, ARENA_RIGHT)
	global_position.y = clampf(global_position.y, _arena_top_at_x(global_position.x), ARENA_BOTTOM)

	_update_animation(input_vector)
	queue_redraw()


func _update_state(delta: float, input_vector: Vector2) -> void:
	if _can_face_input() and input_vector.x != 0.0:
		facing = sign(input_vector.x)

	if _is_airborne_state():
		_update_jump_physics(delta)

	match state:
		PlayerState.IDLE, PlayerState.WALK:
			if _try_start_jump():
				return
			if _try_start_ground_attack():
				return
			_change_state(PlayerState.WALK if input_vector.length_squared() > 0.01 else PlayerState.IDLE)

		PlayerState.JUMP_PREPARE:
			if state_time >= jump_prepare_duration:
				_change_state(PlayerState.JUMP_RISE)

		PlayerState.JAB:
			if state_time >= jab_hit_time and not attack_hit_checked:
				_check_attack_hits(facing)
			if state_time >= jab_duration:
				attack_area.monitoring = false
				_change_state(PlayerState.WALK if input_vector.length_squared() > 0.01 else PlayerState.IDLE)

		PlayerState.JUMP_RISE:
			if _try_start_aerial_attack():
				return

		PlayerState.JUMP_LAND:
			if state_time >= jump_recovery_duration:
				_finish_recovery_lock()
				_change_state(PlayerState.WALK if input_vector.length_squared() > 0.01 else PlayerState.IDLE)

		PlayerState.FLYING_KICK:
			if state_time >= flying_kick_hit_time and not attack_hit_checked:
				_check_attack_hits(air_facing)
			if state_time >= flying_kick_active_duration:
				attack_area.monitoring = false
			if vertical_speed <= 0.0 and state_time >= flying_kick_pose_duration:
				_change_state(PlayerState.FLYING_KICK_FALL)

		PlayerState.FLYING_KICK_FALL:
			if state_time >= flying_kick_active_duration:
				attack_area.monitoring = false

		PlayerState.FLYING_KICK_LAND:
			if state_time >= flying_kick_recovery_duration:
				_finish_recovery_lock()
				_change_state(PlayerState.WALK if input_vector.length_squared() > 0.01 else PlayerState.IDLE)


func _update_jump_physics(delta: float) -> void:
	if _is_normal_jump_state():
		jump_visual_timer += delta
		if Input.is_action_pressed("jump") and jump_hold_timer > 0.0 and vertical_speed > 0.0:
			vertical_speed += jump_hold_force * delta
			jump_hold_timer -= delta
		elif Input.is_action_just_released("jump") and vertical_speed > 0.0 and not jump_cut_applied:
			vertical_speed *= jump_cut_multiplier
			jump_cut_applied = true
			jump_hold_timer = 0.0

	jump_height += vertical_speed * delta
	vertical_speed -= gravity * delta

	if jump_height <= 0.0:
		jump_height = 0.0
		vertical_speed = 0.0
		jump_hold_timer = 0.0
		jump_cut_applied = false
		jump_visual_timer = 0.0
		attack_area.monitoring = false
		if state == PlayerState.FLYING_KICK or state == PlayerState.FLYING_KICK_FALL:
			_change_state(PlayerState.FLYING_KICK_LAND)
		else:
			_change_state(PlayerState.JUMP_LAND)


func _try_start_jump() -> bool:
	if Input.is_action_just_pressed("jump") and not _is_action_locked():
		_change_state(PlayerState.JUMP_PREPARE)
		return true
	return false


func _try_start_ground_attack() -> bool:
	if Input.is_action_just_pressed("punch") and _can_spend_stamina():
		stamina -= jab_stamina_cost
		stats_changed.emit(health, stamina)
		_change_state(PlayerState.JAB)
		return true
	return false


func _try_start_aerial_attack() -> bool:
	if Input.is_action_just_pressed("punch") and jump_height > 1.0 and vertical_speed != 0.0 and _can_spend_stamina():
		stamina -= jab_stamina_cost
		stats_changed.emit(health, stamina)
		_change_state(PlayerState.FLYING_KICK)
		return true
	return false


func _can_spend_stamina() -> bool:
	return stamina >= jab_stamina_cost and not _is_action_locked()


func _change_state(next_state: PlayerState) -> void:
	if state == next_state and state_time > 0.0:
		return

	state = next_state
	state_time = 0.0
	attack_hit_checked = false

	match state:
		PlayerState.IDLE:
			attack_area.monitoring = false
			animated_sprite.play("idle")

		PlayerState.WALK:
			attack_area.monitoring = false
			animated_sprite.play("walk")

		PlayerState.JAB:
			_set_attack_hitbox(JAB_HITBOX_SIZE)
			attack_area.position.x = 75.0 * facing
			attack_area.monitoring = true
			animated_sprite.play("jab")

		PlayerState.JUMP_PREPARE:
			air_facing = facing
			jump_height = 0.0
			vertical_speed = 0.0
			jump_visual_timer = 0.0
			animated_sprite.play("jump_prepare")

		PlayerState.JUMP_RISE:
			jump_height = 0.0
			vertical_speed = jump_speed
			jump_hold_timer = jump_hold_duration
			jump_cut_applied = false
			jump_visual_timer = 0.0
			_show_jump_up_frame(0)

		PlayerState.JUMP_LAND:
			velocity = Vector2.ZERO
			animated_sprite.play("jump_recover")

		PlayerState.FLYING_KICK:
			air_facing = facing if jump_height <= 0.0 else air_facing
			_set_attack_hitbox(FLYING_KICK_HITBOX_SIZE)
			attack_area.position.x = 100.0 * air_facing
			attack_area.monitoring = true
			animated_sprite.play("flying_kick")

		PlayerState.FLYING_KICK_FALL:
			animated_sprite.play("flying_kick_fall")

		PlayerState.FLYING_KICK_LAND:
			velocity = Vector2.ZERO
			attack_area.monitoring = false
			animated_sprite.play("flying_kick_recover")


func _finish_recovery_lock() -> void:
	action_locked_until_release = Input.is_action_pressed("punch")
	action_lock_timer = post_recovery_action_lock


func _update_action_lock(delta: float) -> void:
	action_lock_timer = maxf(action_lock_timer - delta, 0.0)
	if action_locked_until_release and not Input.is_action_pressed("punch"):
		action_locked_until_release = false


func _is_action_locked() -> bool:
	return action_locked_until_release or action_lock_timer > 0.0


func _recover_stamina(delta: float) -> void:
	if _is_attack_state():
		return
	if stamina < max_stamina:
		stamina = minf(stamina + stamina_recovery * delta, max_stamina)
		stats_changed.emit(health, stamina)


func _apply_velocity(input_vector: Vector2) -> void:
	if state == PlayerState.JUMP_PREPARE or state == PlayerState.JUMP_LAND or state == PlayerState.FLYING_KICK_LAND:
		velocity = Vector2.ZERO
	elif state == PlayerState.JAB or state == PlayerState.FLYING_KICK or state == PlayerState.FLYING_KICK_FALL:
		velocity = input_vector * move_speed * 0.35
	else:
		velocity = input_vector * move_speed


func _can_face_input() -> bool:
	return state == PlayerState.IDLE or state == PlayerState.WALK or state == PlayerState.JAB


func _is_airborne_state() -> bool:
	return state == PlayerState.JUMP_RISE or state == PlayerState.FLYING_KICK or state == PlayerState.FLYING_KICK_FALL


func _is_normal_jump_state() -> bool:
	return state == PlayerState.JUMP_RISE


func _is_attack_state() -> bool:
	return state == PlayerState.JAB or state == PlayerState.FLYING_KICK or state == PlayerState.FLYING_KICK_FALL


func _set_attack_hitbox(hitbox_size: Vector2) -> void:
	var rectangle := attack_shape.shape as RectangleShape2D
	rectangle.size = hitbox_size


func _check_attack_hits(hit_direction: float) -> void:
	attack_hit_checked = true
	for area in attack_area.get_overlapping_areas():
		_try_hit_area(area, hit_direction)


func _try_hit_area(area: Area2D, hit_direction: float) -> bool:
	var target: Node2D
	if area.has_method("take_hit"):
		target = area
	elif area.get_parent() is Node2D and area.get_parent().has_method("take_hit"):
		target = area.get_parent()
	else:
		return false

	# Beat'em up depth is measured at the characters' feet, not at their torsos.
	if absf(global_position.y - target.global_position.y) > GROUND_ALIGNMENT_TOLERANCE:
		return false

	target.call("take_hit", hit_direction)
	return true


func _arena_top_at_x(x_position: float) -> float:
	if x_position < LEFT_WALL_END:
		var side_weight := inverse_lerp(LEFT_WALL_END, ARENA_LEFT, x_position)
		return lerpf(ARENA_TOP, SIDE_TOP_LIMIT, side_weight)
	if x_position > RIGHT_WALL_START:
		var side_weight := inverse_lerp(RIGHT_WALL_START, ARENA_RIGHT, x_position)
		return lerpf(ARENA_TOP, SIDE_TOP_LIMIT, side_weight)
	return ARENA_TOP


func _show_jump_up_frame(frame_index: int) -> void:
	if animated_sprite.animation != &"jump":
		animated_sprite.play("jump")
	animated_sprite.set_frame_and_progress(frame_index, 0.0)
	animated_sprite.pause()


func _update_animation(input_vector: Vector2) -> void:
	animated_sprite.flip_h = (air_facing if _is_airborne_state() or state == PlayerState.JUMP_PREPARE or state == PlayerState.JUMP_LAND or state == PlayerState.FLYING_KICK_LAND else facing) < 0.0

	if _is_airborne_state():
		animated_sprite.position = Vector2(0.0, -JUMP_SPRITE_GROUND_OFFSET - jump_height * jump_visual_height_scale)
	elif state == PlayerState.JUMP_PREPARE:
		animated_sprite.position = Vector2(0.0, -JUMP_SPRITE_GROUND_OFFSET)
	elif state == PlayerState.JUMP_LAND or state == PlayerState.FLYING_KICK_LAND:
		animated_sprite.position = Vector2(0.0, -JUMP_SPRITE_GROUND_OFFSET)
	else:
		animated_sprite.position = Vector2(0.0, -SPRITE_GROUND_OFFSET)

	match state:
		PlayerState.IDLE:
			if animated_sprite.animation != &"idle":
				animated_sprite.play("idle")

		PlayerState.WALK:
			if input_vector.length_squared() > 0.01 and animated_sprite.animation != &"walk":
				animated_sprite.play("walk")
			elif input_vector.length_squared() <= 0.01:
				_change_state(PlayerState.IDLE)

		PlayerState.JUMP_PREPARE:
			if animated_sprite.animation != &"jump_prepare":
				animated_sprite.play("jump_prepare")

		PlayerState.JUMP_RISE:
			var jump_frame_count := animated_sprite.sprite_frames.get_frame_count(&"jump")
			var jump_frame := mini(jump_frame_count - 1, int(jump_visual_timer / jump_up_frame_duration))
			_show_jump_up_frame(jump_frame)

		PlayerState.JUMP_LAND:
			if animated_sprite.animation != &"jump_recover":
				animated_sprite.play("jump_recover")

		PlayerState.JAB:
			if animated_sprite.animation != &"jab":
				animated_sprite.play("jab")

		PlayerState.FLYING_KICK:
			if animated_sprite.animation != &"flying_kick":
				animated_sprite.play("flying_kick")

		PlayerState.FLYING_KICK_FALL:
			if animated_sprite.animation != &"flying_kick_fall":
				animated_sprite.play("flying_kick_fall")

		PlayerState.FLYING_KICK_LAND:
			if animated_sprite.animation != &"flying_kick_recover":
				animated_sprite.play("flying_kick_recover")


func _draw() -> void:
	_draw_shadow_ellipse(Vector2(0.0, -3.0), Vector2(68.0, 9.0), Color(0.05, 0.06, 0.09, 0.3))


func _draw_shadow_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 24:
		var angle := TAU * float(index) / 24.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)
