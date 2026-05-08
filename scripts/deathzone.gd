extends Area2D

@onready var timer: Timer = $Timer

# Copy of the body that just left the play area, used for delayed respawn.
var last_body: CharacterBody2D


# Called when a CharacterBody2D leaves the play-area rectangle. Starts a short
# timer before triggering respawn so death feels less abrupt.
func _on_body_exited(body: CharacterBody2D) -> void:
	last_body = body
	timer.start()


func _on_timer_timeout() -> void:
	if last_body:
		last_body.respawn()
