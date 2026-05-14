extends CharacterBody2D

# Reference to the parent Game node (used for end_game() callbacks).
@onready var game: Node2D = $".."

# Per-player controls and tint — set these in the Inspector for each Player instance.
@export var left_key: Key = KEY_LEFT
@export var right_key: Key = KEY_RIGHT
@export var jump_key: Key = KEY_SPACE
@export var down_key: Key = KEY_NONE     # Optional. Used as the "down" attack direction.
@export var attack_key: Key = KEY_SHIFT
@export var ranged_attack_key: Key = KEY_C
@export var shield_key: Key = KEY_S
@export var character_id: int = 1        # 1 = guy1 sprites, 2 = guy2 sprites
@export var player_color: Color = Color(1, 1, 1, 1)  # Modulate (white = no tint).

# Movement tuning
const GRAVITY_SCALE := 0.7
const SPEED := 110.0
const JUMP_VELOCITY := -200.0
const FAST_FALL_SPEED := 250
const MAX_JUMPS := 2
const WALL_SLIDE_SPEED := 20            

# Combat tuning
const ATTACK_DURATION := 0.15      # seconds the hitbox is active during a swing
const ATTACK_COOLDOWN := 0.4       # seconds before you can attack again
const RANGED_ATTACK_COOLDOWN := 0.8   #seconds before you can ranged attack again
const KNOCKBACK_LOCKOUT := 0.3     # seconds the victim can't act after being hit
const KNOCKBACK_MULTIPLIER := 0.1  # damage-based knockback scaling factor (#6)
const RESPAWNS := 2                # number of respawns before elimination

# Charge tuning (#19 — charged attacks)
const MAX_CHARGE_TIME := 2.5
const BASE_DAMAGE := 5.0
const MAX_CHARGE_DAMAGE := 30.0
const BASE_KNOCKBACK_SPEED := 140.0
const MAX_CHARGE_KNOCKBACK_SPEED := 350.0

# Hitbox flash (visual feedback when attacking)
const FLASH_BASE_DURATION := 0.15
const FLASH_MAX_DURATION := 0.5
const FLASH_BASE_ALPHA := 0.35
const FLASH_MAX_ALPHA := 0.95

# Shield tunig
const MAX_SHIELD := 50.0
const SHIELD_DRAIN := 20.0
const SHIELD_REGEN := 10.0

# State
var damage: float = 0.0
var facing: int = 1                # 1 = right, -1 = left

var _attack_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _knockback_timer: float = 0.0

var _charging: bool = false
var _charge_time: float = 0.0

var ranged_attack_released

var is_shielding: bool = false
var shield_health: float = MAX_SHIELD

# Cached values for the active swing — set at release, used when a hit lands.
var _current_attack_dir: Vector2 = Vector2.RIGHT
var _current_attack_damage: float = 0.0
var _current_attack_knockback: float = 0.0

var _hit_targets_this_swing: Array = []
var _was_jump_held := false
var _was_attack_held := false
var _jumps_used: int = 0
var _was_on_ground: bool = false

# Flash state
var _flash_timer: float = 0.0
var _flash_total_duration: float = 0.0
var _flash_max_alpha: float = 0.0

var spawn_position: Vector2
var respawns := RESPAWNS

# Loaded textures for the chosen character.
var _tex_idle: Texture2D
var _tex_jump: Texture2D
var _tex_punch_right: Texture2D
var _tex_punch_up: Texture2D
var _tex_punch_upright: Texture2D
var _tex_punch_down: Texture2D
var _tex_wall_slide: Texture2D

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _hitbox: Area2D = $Hitbox
@onready var _hitbox_shape: CollisionShape2D = $Hitbox/CollisionShape2D
@onready var _hitbox_flash: ColorRect = $Hitbox/HitboxFlash
@onready var _damage_label: Label = $DamageLabel
@onready var shield_rect: ColorRect = $ShieldRect
const PROJECTILE = preload("res://scenes/projectile.tscn")

func _ready() -> void:
	_load_textures()
	_sprite.texture = _tex_idle
	_sprite.modulate = player_color
	_hitbox.monitoring = false
	_hitbox_shape.disabled = true
	_hitbox_flash.visible = false
	_hitbox.body_entered.connect(_on_hitbox_body_entered)
	_update_label()
	spawn_position = global_position


func _load_textures() -> void:
	# Pick guy1 or guy2 sprite set based on the character_id exported on this instance.
	var prefix: String = "res://assets/sprites/guy%d" % character_id
	_tex_idle = load("%s.png" % prefix)
	_tex_jump = load("%s_jump_right.png" % prefix)
	_tex_punch_right = load("%s_punch_right.png" % prefix)
	_tex_punch_up = load("%s_punch_up.png" % prefix)
	_tex_punch_upright = load("%s_punch_upright.png" % prefix)
	_tex_punch_down = load("%s_punch_down.png" % prefix)
	_tex_wall_slide = load("%s_hang_ledge.png" % prefix)

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
	var on_ground: bool = is_on_floor() or is_on_wall() # are we touching ground or wall last frame?
	if on_ground and not _was_on_ground:
		_jumps_used = 0
	_was_on_ground = on_ground

	# Gravity & Wall Slide
	if not is_on_floor():
		velocity += get_gravity() * GRAVITY_SCALE * delta
		
		if is_on_wall() and velocity.y > 0:
				velocity.y = WALL_SLIDE_SPEED
		
		if down_key != KEY_NONE and Input.is_physical_key_pressed(down_key) and velocity.y < FAST_FALL_SPEED:
			velocity.y = FAST_FALL_SPEED

	# Jump — supports double jump and hold-to-jump-on-land. Blocked during knockback.
	var jump_held: bool = Input.is_physical_key_pressed(jump_key)
	var jump_just_pressed: bool = jump_held and not _was_jump_held
	_was_jump_held = jump_held

	if _knockback_timer <= 0.0:
		if is_on_floor():
			if jump_held or jump_just_pressed:
				velocity.y = JUMP_VELOCITY
				_jumps_used += 1
		elif jump_just_pressed and _jumps_used < MAX_JUMPS:
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
		if attack_just_released or _charge_time >= MAX_CHARGE_TIME:
			_release_attack()
			
	# Ranged Attack
	var ranged_attack_pressed = Input.is_key_pressed(ranged_attack_key)
	if ranged_attack_pressed and ranged_attack_released and _cooldown_timer <= 0.0 and _knockback_timer <= 0.0:
		shoot()
	ranged_attack_released = not ranged_attack_pressed
	
	# Shielding
	shielding(delta)

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
	_update_sprite()


# ---- charge / attack flow ------------------------------------------------

func _start_charge() -> void:
	_charging = true
	_charge_time = 0.0

func _update_charge_visual() -> void:
	# Brighten the sprite as charge builds — works on the pixel art without tinting.
	var ratio: float = clampf(_charge_time / MAX_CHARGE_TIME, 0.0, 1.0)
	var brightness: float = 1.0 + ratio * 0.6
	_sprite.modulate = Color(brightness, brightness, brightness, 1.0) * player_color


func _release_attack() -> void:
	var ratio: float = clampf(_charge_time / MAX_CHARGE_TIME, 0.0, 1.0)
	var dmg: float = lerpf(BASE_DAMAGE, MAX_CHARGE_DAMAGE, ratio)
	var kb: float = lerpf(BASE_KNOCKBACK_SPEED, MAX_CHARGE_KNOCKBACK_SPEED, ratio)

	# Compute attack direction from currently held keys (#18 — multi-direction).
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
		dir = Vector2(float(facing), 0.0)
	dir = dir.normalized()

	_current_attack_dir = dir
	_current_attack_damage = dmg
	_current_attack_knockback = kb

	# Reset charge state and visual.
	_charging = false
	_charge_time = 0.0
	_sprite.modulate = player_color

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

func shoot():
	var p = PROJECTILE.instantiate()
	p.shooter = self
	p.global_position = global_position
	p.direction =  Vector2.RIGHT if facing == 1 else Vector2.LEFT
	get_tree().current_scene.add_child(p)
	_cooldown_timer = RANGED_ATTACK_COOLDOWN
	
func shielding(delta):
	var shield_pressed = Input.is_physical_key_pressed(shield_key)
	
	is_shielding = shield_pressed and shield_health > 0.0
	
	if is_shielding:
		shield_health -= SHIELD_DRAIN * delta
	else:
		shield_health += SHIELD_REGEN * delta
		
	shield_health = clamp(shield_health, 0.0, MAX_SHIELD)
		
	shield_rect.visible = is_shielding
	shield_rect.modulate.a = shield_health / MAX_SHIELD

# ---- sprite state -------------------------------------------------------

func _update_sprite() -> void:
	# During an active swing, show the punch pose matching the attack direction.
	if _attack_timer > 0.0:
		var d: Vector2 = _current_attack_dir
		if d.x == 0.0 and d.y < 0.0:
			# Pure up
			_sprite.texture = _tex_punch_up
			_sprite.flip_h = false
		elif d.x == 0.0 and d.y > 0.0:
			# Pure down
			_sprite.texture = _tex_punch_down
			_sprite.flip_h = false
		elif d.y < 0.0:
			# Diagonal up-right or up-left
			_sprite.texture = _tex_punch_upright
			_sprite.flip_h = d.x < 0.0
		elif d.y > 0.0:
			# Diagonal down-right / down-left (no dedicated diagonal-down sprite,
			# fall back to the side punch).
			_sprite.texture = _tex_punch_right
			_sprite.flip_h = d.x < 0.0
		else:
			# Pure horizontal
			_sprite.texture = _tex_punch_right
			_sprite.flip_h = d.x < 0.0
		return
		
	if not is_on_floor() and is_on_wall() and velocity.y > 0:
		_sprite.texture = _tex_wall_slide
		_sprite.flip_h = facing < 0
		return

	# In the air: show the jump pose.
	if not is_on_floor():
		_sprite.texture = _tex_jump
		_sprite.flip_h = facing < 0
		return

	# Default: idle pose, flipped to face movement direction.
	_sprite.texture = _tex_idle
	_sprite.flip_h = facing < 0


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
	if is_shielding:
		shield_health -= damage_amount
		return

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
	shield_health = MAX_SHIELD
	_update_label()
