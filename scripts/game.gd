extends Node2D

# "Blast zone" — when a player's position leaves this rectangle (world coords),
# they're eliminated. Tweak these to taste.
const BOUND_LEFT := -200.0
const BOUND_RIGHT := 200.0
const BOUND_TOP := -200.0
const BOUND_BOTTOM := 250.0

var _game_over: bool = false


func _ready() -> void:
	$UI/ResultLabel.visible = false
	$UI/SubLabel.visible = false


func _process(_delta: float) -> void:
	if _game_over:
		return

	for player in [$Player, $Player2]:
		if not is_instance_valid(player):
			continue
		var p: Vector2 = player.position
		if p.x < BOUND_LEFT or p.x > BOUND_RIGHT \
				or p.y < BOUND_TOP or p.y > BOUND_BOTTOM:
			_eliminate(player)
			return


func _eliminate(loser: Node) -> void:
	_game_over = true
	var winner_name: String = "Player 1" if loser.name == "Player2" else "Player 2"
	$UI/ResultLabel.text = "%s wins!" % winner_name
	$UI/ResultLabel.visible = true
	$UI/SubLabel.visible = true
	get_tree().paused = true


func _unhandled_input(event: InputEvent) -> void:
	if not _game_over:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k == KEY_R or k == KEY_ENTER or k == KEY_KP_ENTER:
			get_tree().paused = false
			get_tree().reload_current_scene()
