extends Area2D

@onready var timer: Timer = $Timer

#Copy of body to use for timeout
var last_body: CharacterBody2D

#Reload scene if player touckes deathzone
func _on_body_entered(body: CharacterBody2D) -> void:
	last_body = body
	timer.start()
	
func _on_timer_timeout() -> void:
	print("hej")
	if last_body:
		last_body.respawn()
