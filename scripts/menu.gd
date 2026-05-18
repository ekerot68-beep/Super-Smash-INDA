extends Control

@onready var start_button: TextureButton = $TextureButton
var base_y: float

func _ready() -> void:
	base_y = start_button.position.y

func _process(delta: float) -> void:
	start_button.position.y = base_y + sin(Time.get_ticks_msec() / 300.0) * 10.0 # later button is bob height for button, denominator is speed of bob

func _on_texture_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
