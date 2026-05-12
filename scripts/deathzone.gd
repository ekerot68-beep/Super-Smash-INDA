extends Area2D

# Copy of the body that just left the play area, used for delayed respawn.
var last_body: CharacterBody2D


# Called when a CharacterBody2D leaves the play-area rectangle. Starts a short
# timer before triggering respawn so death feels less abrupt.
func _on_body_exited(body: CharacterBody2D) -> void:
	respawn(body)

func respawn(body: CharacterBody2D):
	await get_tree().create_timer(1.0).timeout
	body.respawn()
