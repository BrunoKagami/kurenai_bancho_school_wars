extends CharacterBody2D

signal stats_changed(health: float, stamina: float)

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
@export var jump_speed := 720.0
@export var gravity := 1750.0
@export var jump_hold_force := 1050.0
@export var jump_hold_duration := 0.18
@export var jump_cut_multiplier := 0.45
@export var max_health := 100.0
@export var max_stamina := 100.0
@export var jab_stamina_cost := 12.0
@export var stamina_recovery := 24.0
@export var flying_kick_pose_duration := 0.38
@export var flying_kick_recovery_duration := 0.42

var facing := 1.0
var air_facing := 1.0
var jump_height := 0.0
var vertical_speed := 0.0
var jump_hold_timer := 0.0
var jump_cut_applied := false
var attacking := false
var aerial_kick := false
var aerial_kick_falling := false
var aerial_kick_recovering := false
var flying_kick_pose_timer := 0.0
var flying_kick_recovery_timer := 0.0
var attack_connected := false
var health := 100.0
var stamina := 100.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_area: Area2D = $AttackArea
@onready var attack_shape: CollisionShape2D = $AttackArea/CollisionShape2D


func _ready() -> void:
	health = max_health
	stamina = max_stamina
	attack_area.monitoring = false
	animated_sprite.play("idle")
	stats_changed.emit(health, stamina)
	queue_redraw()


func _physics_process(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if aerial_kick_recovering:
		velocity = Vector2.ZERO
	elif not attacking:
		velocity = input_vector * move_speed
	else:
		velocity = input_vector * move_speed * 0.35

	if input_vector.x != 0.0 and jump_height <= 0.0 and not aerial_kick_recovering:
		facing = sign(input_vector.x)

	move_and_slide()
	global_position.x = clampf(global_position.x, ARENA_LEFT, ARENA_RIGHT)
	global_position.y = clampf(global_position.y, _arena_top_at_x(global_position.x), ARENA_BOTTOM)

	if Input.is_action_just_pressed("jump") and jump_height <= 0.0 and not attacking:
		air_facing = facing
		vertical_speed = jump_speed
		jump_hold_timer = jump_hold_duration
		jump_cut_applied = false
		animated_sprite.play("jump")

	if jump_height > 0.0 or vertical_speed > 0.0:
		if aerial_kick:
			flying_kick_pose_timer = maxf(flying_kick_pose_timer - delta, 0.0)
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
			attack_area.monitoring = false
			if aerial_kick:
				_start_flying_kick_recovery()

	if aerial_kick_recovering:
		flying_kick_recovery_timer -= delta
		if flying_kick_recovery_timer <= 0.0:
			aerial_kick_recovering = false
			aerial_kick = false
			aerial_kick_falling = false
			attacking = false

	if Input.is_action_just_pressed("punch") and not attacking:
		if stamina >= jab_stamina_cost:
			stamina -= jab_stamina_cost
			stats_changed.emit(health, stamina)
			if jump_height > 0.0:
				_start_flying_kick()
			else:
				_start_punch()

	if not attacking and stamina < max_stamina:
		stamina = minf(stamina + stamina_recovery * delta, max_stamina)
		stats_changed.emit(health, stamina)

	_update_animation(input_vector)
	queue_redraw()


func _start_punch() -> void:
	attacking = true
	attack_connected = false
	_set_attack_hitbox(JAB_HITBOX_SIZE)
	attack_area.position.x = 75.0 * facing
	attack_area.monitoring = true
	animated_sprite.play("jab")

	await get_tree().create_timer(0.12).timeout
	for area in attack_area.get_overlapping_areas():
		if _try_hit_area(area, facing):
			attack_connected = true
	attack_area.monitoring = false

	await get_tree().create_timer(0.13).timeout
	attacking = false


func _start_flying_kick() -> void:
	attacking = true
	aerial_kick = true
	aerial_kick_falling = false
	aerial_kick_recovering = false
	flying_kick_pose_timer = flying_kick_pose_duration
	attack_connected = false
	_set_attack_hitbox(FLYING_KICK_HITBOX_SIZE)
	attack_area.position.x = 100.0 * air_facing
	attack_area.monitoring = true
	animated_sprite.play("flying_kick")

	await get_tree().create_timer(0.08).timeout
	for area in attack_area.get_overlapping_areas():
		if _try_hit_area(area, air_facing):
			attack_connected = true

	await get_tree().create_timer(0.14).timeout
	attack_area.monitoring = false


func _start_flying_kick_recovery() -> void:
	aerial_kick_recovering = true
	flying_kick_recovery_timer = flying_kick_recovery_duration
	velocity = Vector2.ZERO
	animated_sprite.play("flying_kick_recover")


func _set_attack_hitbox(hitbox_size: Vector2) -> void:
	var rectangle := attack_shape.shape as RectangleShape2D
	rectangle.size = hitbox_size


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


func _update_animation(input_vector: Vector2) -> void:
	animated_sprite.flip_h = (air_facing if jump_height > 0.0 or aerial_kick_recovering else facing) < 0.0

	if jump_height > 0.0:
		animated_sprite.position = Vector2(0.0, -JUMP_SPRITE_GROUND_OFFSET)
		if aerial_kick:
			if vertical_speed <= 0.0 and flying_kick_pose_timer <= 0.0 and not aerial_kick_falling:
				aerial_kick_falling = true
				animated_sprite.play("flying_kick_fall")
			elif not aerial_kick_falling and animated_sprite.animation != &"flying_kick":
				animated_sprite.play("flying_kick")
		elif animated_sprite.animation != &"jump":
			animated_sprite.play("jump")
		return

	if aerial_kick_recovering:
		animated_sprite.position = Vector2(0.0, -JUMP_SPRITE_GROUND_OFFSET)
		if animated_sprite.animation != &"flying_kick_recover":
			animated_sprite.play("flying_kick_recover")
		return

	animated_sprite.position = Vector2(0.0, -SPRITE_GROUND_OFFSET)

	if attacking:
		return

	if input_vector.length_squared() > 0.01:
		if animated_sprite.animation != &"walk":
			animated_sprite.play("walk")
	elif animated_sprite.animation != &"idle":
		animated_sprite.play("idle")


func _draw() -> void:
	_draw_shadow_ellipse(Vector2(0.0, -7.0), Vector2(60.0, 14.0), Color(0.05, 0.06, 0.09, 0.3))


func _draw_shadow_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 24:
		var angle := TAU * float(index) / 24.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)
