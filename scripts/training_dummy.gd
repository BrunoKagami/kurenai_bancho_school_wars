extends StaticBody2D

const SHADOW_ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")

@export var hits_per_shadow_wave := 5
@export var shadow_spawn_center := Vector2(760.0, 465.0)
@export var shadow_spawn_spacing := 86.0
@export var shadow_spawn_y_step := 18.0

var reacting_to_hit := false
var hit_count := 0
var shadow_wave_size := 1

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func take_hit(
	_damage: float,
	direction: float,
	_knocks_down: bool = false,
	_knockback_distance: float = 0.0
) -> void:
	if reacting_to_hit:
		return
	hit_count += 1
	if hit_count >= hits_per_shadow_wave:
		hit_count = 0
		_spawn_shadow_wave(shadow_wave_size)
		shadow_wave_size += 1
	reacting_to_hit = true
	animated_sprite.flip_h = direction < 0.0
	animated_sprite.play("hit")
	await animated_sprite.animation_finished
	animated_sprite.play("idle")
	reacting_to_hit = false


func _spawn_shadow_wave(amount: int) -> void:
	var parent_node: Node = get_parent()
	if parent_node == null:
		return

	for index in range(amount):
		var enemy: Node2D = _get_inactive_shadow_enemy()
		if enemy == null:
			enemy = SHADOW_ENEMY_SCENE.instantiate() as Node2D
			parent_node.add_child(enemy)

		enemy.global_position = _shadow_spawn_position(index, amount)
		if enemy.has_method("activate"):
			enemy.activate()


func _get_inactive_shadow_enemy() -> Node2D:
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy is Node2D and not enemy.visible and enemy.has_method("activate"):
			return enemy as Node2D
	return null


func _shadow_spawn_position(index: int, amount: int) -> Vector2:
	var centered_index: float = float(index) - (float(amount) - 1.0) * 0.5
	var y_offset: float = shadow_spawn_y_step if index % 2 == 0 else -shadow_spawn_y_step
	return shadow_spawn_center + Vector2(centered_index * shadow_spawn_spacing, y_offset)


func _draw() -> void:
	_draw_shadow_ellipse(Vector2(0.0, -18.0), Vector2(55.0, 20.0), Color(0.05, 0.06, 0.09, 0.3))


func _draw_shadow_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 24:
		var angle := TAU * float(index) / 24.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)
