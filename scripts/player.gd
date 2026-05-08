extends CharacterBody2D

# Reference to the parent Game node (used for end_game() callbacks).
@onready var game: Node2D = $".."

# Per-player controls and color — set these in the Inspector for each Player instance.
@export var left_key: Key = KEY_LEFT
@export var right_key: Key = KEY_RIGHT
@export var jump_key: Key = KEY_SPACE
@export var down_key: Key = KEY_NONE     # Optional. Used as the "down" attack direction.
@export var attack_key: Key = KEY_SHIFT
@export var player_color: Color = Color(1, 0.35, 0.35, 1)

# Movement tuning
const SPEED := 120.0
const JUMP_VELOCITY := -250.0
const MAX_JUMPS := 2               # 1 ground jump + 1 air jump (Smash-style double jump)

# Combat tuning
const ATTACK_DURATION := 0.15      # seconds the hitbox is active during a swing
const ATTACK_COOLDOWN := 0.4       # seconds before you can attack again
const KNOCKBACK_LOCKOUT := 0.3     # seconds the victim can't act after being hit
const KNOCKBACK_MULTIPLIER := 0.1  # damage-based knockback scaling factor (#6)
const RESPAWNS := 1                # number of respawns before elimination

# Charge tuning (#19 — charged attacks)
const MAX_CHARGE_TIME := 1.5                   # seconds for full charge
const BASE_DAMAGE := 5.0                       # damage % on a tap (no charge)
const MAX_CHARGE_DAMAGE := 22.0                # damage % at full charge
const BASE_KNOCKBACK_SPEED := 200.0            # knockback magnitude on a tap
const MAX_CHARGE_KNOCKBACK_SPEED := 480.0      # knockback magnitude at full charge

# Hitbox flash (visual feedback when attacking)
const FLASH_BASE_DURATION := 0.15              # seconds the flash lasts on a tap
const FLASH_MAX_DURATION := 0.5                # seconds the flash lasts at full charge
const FLASH_BASE_ALPHA := 0.35                 # opacity at start of a tap flash
const FLASH_MAX_ALPHA := 0.95                  # opacity at start of full-charge flash

# State
var damage: float = 0.0            # Smash-style "%" — increases on hit
var facing: int = 1                # 1 = right, -1 = left

var _attack_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _knockback_timer: float = 0.0

var _charging: bool = false
var _charge_time: float = 0.0

# Cached values for the active swing — set at release, used when a hit lands.
var _current_attack_dir: Vector2 = Vector2.RIGHT
var _current_attack_damage: float = 0.0
var _current_attack_knockback: float = 0.0

var _hit_targets_this_swing: Array = []
var _was_jump_held := false
var _was_attack_held := false
var _jumps_used: int = 0

# Flash state
var _flash_timer: float = 0.0
var _flash_total_duration: float = 0.0
var _flash_max_alpha: float = 0.0

var spawn_position: Vector2
var respawns := RESPAWNS

@onready var _color_rect: ColorRect = $ColorRect
@onready var _hitbox: Area2D = $Hitbox
@onready var _hitbox_shape: CollisionShape2D = $Hitbox/CollisionShape2D
@onready var _hitbox_flash: ColorRect = $Hitbox/HitboxFlash
@onready var _damage_label: Label = $DamageLabel


func _ready() -> void:
	_color_rect.color = player_color
	_hitbox.monitoring = false
	_hitbox_shape.disabled = true
	_hitbox_flash.visible = false
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
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_hitbox_flash.visible = false
		else:
			# Fade alpha linearly from max → 0 over the flash duration.
			var t: float = _flash_timer / _flash_total_duration
			_hitbox_flash.color = Color(1, 1, 1, _flash_max_alpha * t)

	# Reset jump counter when grounded (also enables hold-to-jump-on-land below).
	if is_on_floor():
		_jumps_used = 0

	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Jump — supports double jump and hold-to-jump-on-land. Blocked during knockback.
	var jump_held: bool = Input.is_physical_key_pressed(jump_key)
	var jump_just_pressed: bool = jump_held and not _was_jump_held
	_was_jump_held = jump_held

	if _knockback_timer <= 0.0:
		if is_on_floor():
			# Holding the key OR a fresh press both jump from the ground.
			# This lets you bunny-hop / auto-jump on landing without precise timing.
			if jump_held or jump_just_pressed:
				velocity.y = JUMP_VELOCITY
				_jumps_used += 1
		elif jump_just_pressed and _jumps_used < MAX_JUMPS:
			# Air jump: only on a fresh press, and only if we have a jump left.
			# Holding the key in the air does NOT auto-double-jump — you must release
			# and re-press, otherwise hold-to-jump would burn the second jump immediately.
			velocity.y = JUMP_VELOCITY
			_jumps_used += 1

	# Attack input — charge model (#19)
	var attack_held: bool = Input.is_physical_key_pressed(attack_key)
	var attack_just_pressed: bool = attack_held and not _was_attack_held
	var attack_just_released: bool = not attack_held and _was_attack_held
	_was_attack_held = attack_held

	if attack_just_pressed and _cooldown_timer <= 0.0 and _knockback_timer <= 0.0 and not _charging:
		_start_charge()

	if _charging:
		_charge_time += delta
		_update_charge_visual()
		# Auto-release at max OR on key release
		if attack_just_released or _charge_time >= MAX_CHARGE_TIME:
			_release_attack()

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


# ---- charge / attack flow ------------------------------------------------

func _start_charge() -> void:
	_charging = true
	_charge_time = 0.0


func _update_charge_visual() -> void:
	var ratio: float = clampf(_charge_time / MAX_CHARGE_TIME, 0.0, 1.0)
	# Tint toward white as charge builds — visual feedback.
	_color_rect.color = player_color.lerp(Color.WHITE, ratio * 0.6)


func _release_attack() -> void:
	var ratio: float = clampf(_charge_time / MAX_CHARGE_TIME, 0.0, 1.0)
	var dmg: float = lerpf(BASE_DAMAGE, MAX_CHARGE_DAMAGE, ratio)
	var kb: float = lerpf(BASE_KNOCKBACK_SPEED, MAX_CHARGE_KNOCKBACK_SPEED, ratio)

	# Compute attack direction from currently held keys (#18 — multi-direction).
	# Up uses jump_key (which also makes you jump if grounded — fine for now).
	# Down uses optional down_key, only if configured in the Inspector.
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(left_key):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(right_key):
		dir.x += 1.0
	if Input.is_physical_key_pressed(jump_key):
		dir.y -= 1.0
	if down_key != KEY_NONE and Input.is_physical_key_pressed(down_key):
		dir.y += 1.0

	if dir == Vector2.ZERO:
		# Neutral: attack in facing direction.
		dir = Vector2(float(facing), 0.0)
	dir = dir.normalized()

	_current_attack_dir = dir
	_current_attack_damage = dmg
	_current_attack_knockback = kb

	# Reset charge state and visual.
	_charging = false
	_charge_time = 0.0
	_color_rect.color = player_color

	# Schedule hitbox active period and cooldown.
	_attack_timer = ATTACK_DURATION
	_cooldown_timer = ATTACK_COOLDOWN
	_hit_targets_this_swing.clear()

	# Place hitbox in attack direction.
	_hitbox.position = dir * 16.0
	_hitbox.monitoring = true
	_hitbox_shape.disabled = false

	# Trigger hitbox flash — brighter and longer-lived for stronger charges.
	_flash_total_duration = lerpf(FLASH_BASE_DURATION, FLASH_MAX_DURATION, ratio)
	_flash_max_alpha = lerpf(FLASH_BASE_ALPHA, FLASH_MAX_ALPHA, ratio)
	_flash_timer = _flash_total_duration
	_hitbox_flash.color = Color(1, 1, 1, _flash_max_alpha)
	_hitbox_flash.visible = true


func _end_attack() -> void:
	_hitbox.monitoring = false
	_hitbox_shape.disabled = true


# ---- hit detection -------------------------------------------------------

func _on_hitbox_body_entered(body: Node) -> void:
	if body == self:
		return
	if body in _hit_targets_this_swing:
		return
	if body.has_method("take_hit"):
		_hit_targets_this_swing.append(body)
		body.take_hit(_current_attack_dir, _current_attack_damage, _current_attack_knockback)


func take_hit(attack_dir: Vector2, damage_amount: float, knockback_speed: float) -> void:
	damage += damage_amount
	# Combine our directional knockback (#18) with damage-based scaling (#6).
	var scaled_kb: float = knockback_speed + damage * damage * KNOCKBACK_MULTIPLIER
	velocity = attack_dir * scaled_kb
	# For purely horizontal attacks, give a slight upward bias so the victim launches.
	if absf(attack_dir.y) < 0.1:
		velocity.y = -scaled_kb * 0.4
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
