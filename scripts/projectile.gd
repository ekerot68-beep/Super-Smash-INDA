extends Area2D

@export var speed := 700.0
@export var damage := 5
@export var lifetime := 1.0
@export var knockback := 140

var direction := Vector2.RIGHT
var shooter: CharacterBody2D

func _ready() -> void:
	await get_tree().create_timer(lifetime).timeout
	queue_free()
	
func _physics_process(delta: float) -> void:
	position += direction * speed * delta

func _on_body_entered(body: CharacterBody2D) -> void:
	if body == shooter:
		return
	body.take_hit(direction, damage, knockback)
