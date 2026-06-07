extends StaticBody2D

var reacting_to_hit := false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func take_hit(direction: float) -> void:
	if reacting_to_hit:
		return
	reacting_to_hit = true
	animated_sprite.flip_h = direction < 0.0
	animated_sprite.play("hit")
	await animated_sprite.animation_finished
	animated_sprite.play("idle")
	reacting_to_hit = false


func _draw() -> void:
	_draw_shadow_ellipse(Vector2(0.0, -18.0), Vector2(55.0, 20.0), Color(0.05, 0.06, 0.09, 0.3))


func _draw_shadow_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 24:
		var angle := TAU * float(index) / 24.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)
