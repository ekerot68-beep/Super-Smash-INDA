extends CharacterBody2D

# Per-player controls and color — set these in the Inspector for each Player instance.
@export var left_key: Key = KEY_LEFT
@export var right_key: Key = KEY_RIGHT
@export var jump_key: Key = KEY_SPACE
@export var player_color: Color = Color(1, 0.35, 0.35, 1)

const SPEED := 120.0
const JUMP_VELOCITY := -250.0

var _was_jump_held := false


func _ready() -> void:
	# Tint this player's visible rectangle with its assigned color.
	if has_node("ColorRect"):
		($ColorRect as ColorRect).color = player_color


func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Detect "just pressed" for the jump key without relying on Input Map actions
	# (so each player instance can have its own jump key configured in the Inspector).
	var jump_held: bool = Input.is_physical_key_pressed(jump_key)
	var jump_just_pressed: bool = jump_held and not _was_jump_held
	_was_jump_held = jump_held

	if jump_just_pressed and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Horizontal movement
	var direction := 0.0
	if Input.is_physical_key_pressed(left_key):
		direction -= 1.0
	if Input.is_physical_key_pressed(right_key):
		direction += 1.0

	if direction != 0.0:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)

	move_and_slide()
