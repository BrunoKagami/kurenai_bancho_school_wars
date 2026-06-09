extends CanvasLayer

const ENEMY_HUD_VISIBLE_DURATION := 3.0
const ENEMY_HEALTH_DELAY := 0.06
const ENEMY_HEALTH_FALL_DURATION := 0.16
const ENEMY_DAMAGE_DELAY := 0.45
const ENEMY_DAMAGE_FALL_SPEED := 48.0

@onready var player = $"../World/Player"
@onready var health_bar: TextureProgressBar = $PlayerHUD/HealthBar
@onready var stamina_bar: TextureProgressBar = $PlayerHUD/StaminaBar
@onready var enemy_hud: Control = $EnemyHUD
@onready var enemy_name_label: Label = $EnemyHUD/Box/Name
@onready var enemy_damage_bar: TextureProgressBar = $EnemyHUD/Box/DamageBar
@onready var enemy_health_bar: TextureProgressBar = $EnemyHUD/Box/HealthBar
@onready var controls_panel: PanelContainer = $Controls
@onready var toggle_button: Button = $ToggleControls

var current_enemy: Node
var enemy_hud_timer := 0.0
var enemy_health_tween: Tween
var enemy_damage_tween: Tween


func _ready() -> void:
	toggle_button.pressed.connect(_toggle_controls)
	player.stats_changed.connect(_update_player_stats)
	get_tree().node_added.connect(_on_node_added)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		_connect_enemy(enemy)
	health_bar.max_value = player.max_health
	stamina_bar.max_value = player.max_stamina
	_update_player_stats(player.health, player.stamina)
	enemy_hud.hide()
	if _should_show_mobile_controls():
		controls_panel.hide()
		toggle_button.hide()


func _process(delta: float) -> void:
	if current_enemy != null and not is_instance_valid(current_enemy):
		current_enemy = null
		enemy_hud.hide()
		return

	if not enemy_hud.visible:
		return

	enemy_hud_timer = maxf(enemy_hud_timer - delta, 0.0)
	if enemy_hud_timer <= 0.0:
		enemy_hud.hide()


func _update_player_stats(health: float, stamina: float) -> void:
	health_bar.value = health
	stamina_bar.value = stamina


func _on_node_added(node: Node) -> void:
	if node.is_in_group("enemy"):
		_connect_enemy(node)


func _connect_enemy(enemy: Node) -> void:
	if not enemy.has_signal("target_status_changed"):
		return
	var callback := Callable(self, "_update_enemy_status")
	if not enemy.is_connected("target_status_changed", callback):
		enemy.connect("target_status_changed", callback)


func _update_enemy_status(
	enemy: Node,
	enemy_name: String,
	health: float,
	max_health: float,
	previous_health: float
) -> void:
	var changed_target: bool = current_enemy != enemy
	current_enemy = enemy
	enemy_name_label.text = enemy_name
	enemy_health_bar.max_value = max_health
	enemy_damage_bar.max_value = max_health
	_stop_enemy_bar_tweens()
	if changed_target or not enemy_hud.visible:
		enemy_health_bar.value = previous_health
		enemy_damage_bar.value = previous_health
	else:
		enemy_damage_bar.value = maxf(enemy_damage_bar.value, enemy_health_bar.value)
	enemy_damage_bar.show()
	enemy_hud_timer = ENEMY_HUD_VISIBLE_DURATION
	enemy_hud.show()
	_animate_enemy_bars(health)


func _animate_enemy_bars(target_health: float) -> void:
	enemy_health_tween = create_tween()
	enemy_health_tween.tween_interval(ENEMY_HEALTH_DELAY)
	enemy_health_tween.tween_property(
		enemy_health_bar,
		"value",
		target_health,
		ENEMY_HEALTH_FALL_DURATION
	)

	var damage_distance: float = maxf(enemy_damage_bar.value - target_health, 0.0)
	var damage_duration: float = maxf(damage_distance / ENEMY_DAMAGE_FALL_SPEED, 0.12)
	enemy_damage_tween = create_tween()
	enemy_damage_tween.tween_interval(ENEMY_DAMAGE_DELAY)
	enemy_damage_tween.tween_property(
		enemy_damage_bar,
		"value",
		target_health,
		damage_duration
	)
	enemy_damage_tween.tween_callback(enemy_damage_bar.hide)


func _stop_enemy_bar_tweens() -> void:
	if enemy_health_tween != null and enemy_health_tween.is_valid():
		enemy_health_tween.kill()
	if enemy_damage_tween != null and enemy_damage_tween.is_valid():
		enemy_damage_tween.kill()


func _toggle_controls() -> void:
	controls_panel.visible = not controls_panel.visible
	toggle_button.text = "Ocultar dicas" if controls_panel.visible else "Mostrar dicas"


func _should_show_mobile_controls() -> bool:
	if DisplayServer.is_touchscreen_available():
		return true
	return OS.has_feature("web") and DisplayServer.window_get_size().x <= 980
