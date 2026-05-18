extends Node2D


@onready var player: CharacterBody2D = $player
@onready var player_2: CharacterBody2D = $player2
@onready var game_label: Label = $game_label
@onready var end_game_timer: Timer = $end_game_timer

var winner: String

func end_game():
	if player.respawns == 0:
		winner = "Edgar"
	elif player_2.respawns == 0:
		winner = "Fredrik"
	game_label.text = "%s won the game" % winner
	end_game_timer.start()

func _on_end_game_timer_timeout() -> void:
	get_tree().reload_current_scene()
