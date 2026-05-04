extends CharacterBody2D

# Variable for main scene
@onready var game: Node2D = $".."

# Per-player controls and color — set these in the Inspector for each Player instance.
@export var left_key: Key = KEY_LEFT
@export var right_key: Key = KEY_RIGHT
@export var jump_key: Key = KEY_SPACE
@export var attack_key: Key = KEY_SHIFT
@export var player_color: Color = Color(1, 0.35, 0.35, 1)

# Movement tuning
const SPEED := 120.0
const JUMP_VELOCITY := -250.0

# Combat tuning
const ATTACK_DURATION := 0.15      # seconds the hitbox is active during a swing
const ATTACK_COOLDOWN := 0.4       # seconds before you can attack again
const HIT_DAMAGE := 8.0            # damage % added per hit
const HIT_KNOCKBACK_X := 220.0     # horizontal knockback speed
const HIT_KNOCKBACK_Y := -180.0    # vertical knockback (upward)
const KNOCKBACK_LOCKOUT := 0.3    # seconds the victim can't act
const KNOCKBACK_MULTIPLIER := 0.1 # knockback strength
const RESPAWNS := 1               # amount of respawns

# State
var damage: float = 0.0            # Smash-style "%" — increases on hit
var facing: int = 1                # 1 = right, -1 = left

var _attack_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _knockback_timer: float = 0.0
var _hit_targets_this_swing: Array = []
var _was_jump_held := false
var _was_attack_held := false

var spawn_position: Vector2
var respawns := RESPAWNS

@onready var _color_rect: ColorRect = $ColorRect
@onready var _hitbox: Area2D = $Hitbox
@onready var _hitbox_shape: CollisionShape2D = $Hitbox/CollisionShape2D
@onready var _damage_label: Label = $DamageLabel


func _ready() -> void:
	_color_rect.color = player_color
	_hitbox.monitoring = false
	_hitbox_shape.disabled = true
	_hitbox.body_entered.connect(_on_hitbox_body_entered)
	_update_label()
	spawn_position = global_position


func _physics_process(delta: float) -> void:
	# Tick timers
	if _attack_timer > 0.0:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_end_attack()
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
	if _knockback_timer > 0.0:
		_knockback_timer -= delta

	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Jump (blocked during knockback)
	var jump_held: bool = Input.is_physical_key_pressed(jump_key)
	var jump_just_pressed: bool = jump_held and not _was_jump_held
	_was_jump_held = jump_held
	if jump_just_pressed and is_on_floor() and _knockback_timer <= 0.0:
		velocity.y = JUMP_VELOCITY

	# Attack (blocked during knockback or cooldown)
	var attack_held: bool = Input.is_physical_key_pressed(attack_key)
	var attack_just_pressed: bool = attack_held and not _was_attack_held
	_was_attack_held = attack_held
	if attack_just_pressed and _cooldown_timer <= 0.0 and _knockback_timer <= 0.0:
		_start_attack()

	# Horizontal movement (skip during knockback so you actually fly)
	if _knockback_timer <= 0.0:
		var direction := 0.0
		if Input.is_physical_key_pressed(left_key):
			direction -= 1.0
			facing = -1
		if Input.is_physical_key_pressed(right_key):
			direction += 1.0
			facing = 1

		if direction != 0.0:
			velocity.x = direction * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0.0, SPEED)

	move_and_slide()


func _start_attack() -> void:
	_attack_timer = ATTACK_DURATION
	_cooldown_timer = ATTACK_COOLDOWN
	_hit_targets_this_swing.clear()
	# Move hitbox to the side the player is facing.
	_hitbox.position.x = facing * 14
	_hitbox.monitoring = true
	_hitbox_shape.disabled = false


func _end_attack() -> void:
	_hitbox.monitoring = false
	_hitbox_shape.disabled = true


func _on_hitbox_body_entered(body: Node) -> void:
	# Don't hit yourself, and only hit each target once per swing.
	if body == self:
		return
	if body in _hit_targets_this_swing:
		return
	if body.has_method("take_hit"):
		_hit_targets_this_swing.append(body)
		body.take_hit(facing)


func take_hit(attacker_facing: int) -> void:
	damage += HIT_DAMAGE
	velocity.x = (HIT_KNOCKBACK_X + damage * damage * KNOCKBACK_MULTIPLIER) * attacker_facing
	velocity.y = HIT_KNOCKBACK_Y - damage * damage * KNOCKBACK_MULTIPLIER * 0.8
	_knockback_timer = KNOCKBACK_LOCKOUT
	_update_label()


func _update_label() -> void:
	_damage_label.text = "%d%%" % int(damage)

func respawn():
	if respawns == 0:
		game.end_game()
	respawns -= 1
	global_position = spawn_position
	damage = 0.0
	facing = 1 
	_update_label()
