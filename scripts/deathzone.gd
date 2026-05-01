extends Area2D


#Reload scene if player touckes deathzone
func _on_body_entered(body: CharacterBody2D) -> void:
	get_tree().reload_current_scene()
