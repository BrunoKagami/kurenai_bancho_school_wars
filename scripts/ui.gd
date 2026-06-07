extends CanvasLayer

@onready var player = $"../World/Player"
@onready var health_bar: TextureProgressBar = $PlayerHUD/HealthBar
@onready var stamina_bar: TextureProgressBar = $PlayerHUD/StaminaBar
@onready var controls_panel: PanelContainer = $Controls
@onready var toggle_button: Button = $ToggleControls


func _ready() -> void:
	toggle_button.pressed.connect(_toggle_controls)
	player.stats_changed.connect(_update_player_stats)
	health_bar.max_value = player.max_health
	stamina_bar.max_value = player.max_stamina
	_update_player_stats(player.health, player.stamina)
	if DisplayServer.is_touchscreen_available():
		controls_panel.hide()
		toggle_button.hide()


func _update_player_stats(health: float, stamina: float) -> void:
	health_bar.value = health
	stamina_bar.value = stamina


func _toggle_controls() -> void:
	controls_panel.visible = not controls_panel.visible
	toggle_button.text = "Ocultar dicas" if controls_panel.visible else "Mostrar dicas"
