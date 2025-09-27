extends CharacterBody2D

# Signals
signal died
signal took_damage(amount: int, health: int)
signal health_changed(current_health: int, max_health: int)

# Movement and gameplay configuration
@export var move_speed: float = 120.0
@export var acceleration: float = 800.0
@export var friction: float = 900.0
@export var gravity: float = 1400.0
@export var max_fall_speed: float = 1400.0

# Jump
@export var jump_force: float = 400.0
@export var input_jump: StringName = &"ui_accept" # Space (default Godot Input Map)

# Roll
@export var roll_speed: float = 220.0
@export var roll_duration: float = 0.35
@export var roll_cooldown: float = 0.50
@export var invincible_during_roll: bool = true

# Health
@export var max_health: int = 3

# Input actions (configure in Project Settings > Input Map)
@export var input_left: StringName = &"ui_left"
@export var input_right: StringName = &"ui_right"
@export var input_roll: StringName = &"roll" # Add an Input Map action named "roll"
@export var input_attack: StringName = &"attack" # Add an Input Map action named "attack"
# Timings
@export var hit_stun_duration: float = 0.20
@export var attack_cooldown: float = 0.25

# Nodes
@onready var sprite: AnimatedSprite2D = get_node_or_null("Agentanimator/AnimatedSprite2D")
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
@onready var hurtbox: Area2D = get_node_or_null("Hurtbox")
@onready var hurtbox_shape: CollisionShape2D = get_node_or_null("Hurtbox/HurtboxShape")
@onready var attack_hitbox: Area2D = get_node_or_null("AttackHitbox")
@onready var attack_hitbox_shape: CollisionShape2D = get_node_or_null("AttackHitbox/AttackHitboxShape")
@onready var attach_anchor: Node = get_node_or_null("Agentanimator")
@onready var camera: Camera2D = get_node_or_null("Camera2D")
@onready var player_ui_health_bar: Control = get_node_or_null("PlayerUI/HealthBar")
@onready var player_ui_wave_label: Label = get_node_or_null("PlayerUI/WaveLabel")
@onready var player_ui_soul_label: Label = get_node_or_null("PlayerUI/SoulLabel")

# Weapon
@export var weapon_scene: PackedScene = preload("res://scenes/weapon.tscn")
var weapon: PlayerWeapon = null

# State
var health: int
var _state: String = "idle" # idle, run, roll, hit, dead
var _facing: int = 1 # 1 right, -1 left
var _roll_time_left: float = 0.0
var _roll_cooldown_left: float = 0.0
var _roll_direction: int = 1
var _hit_stun_time: float = 0.0
var _dead: bool = false
var roll_anim_name: StringName = &"roll"
var _health_bonus: int = 0
var _attack_cooldown_left: float = 0.0

func _ready() -> void:
	health = max_health
	emit_signal("health_changed", health, max_health)
	
	# Add player to player group for enemy targeting
	add_to_group("player")
	
	# Update player's own UI health bar
	if player_ui_health_bar and player_ui_health_bar.has_method("set_health"):
		player_ui_health_bar.set_health(health, max_health)

	# Resolve roll animation name (handles a possible typo "roill")
	if sprite and sprite.sprite_frames:
		if sprite.sprite_frames.has_animation("roll"):
			roll_anim_name = &"roll"
		elif sprite.sprite_frames.has_animation("roill"):
			roll_anim_name = &"roill"
		else:
			roll_anim_name = &"idle"

	# Hurtbox wiring (enemies can damage player)
	if hurtbox:
		if hurtbox.has_signal("area_entered"):
			hurtbox.area_entered.connect(_on_hurtbox_area_entered)
		if hurtbox.has_signal("body_entered"):
			hurtbox.body_entered.connect(_on_hurtbox_body_entered)
	
	# Attack hitbox wiring (player can damage enemies)
	if attack_hitbox:
		attack_hitbox.monitoring = false  # Only enable during attacks
		if attack_hitbox.has_signal("area_entered"):
			attack_hitbox.area_entered.connect(_on_attack_hitbox_area_entered)
		if attack_hitbox.has_signal("body_entered"):
			attack_hitbox.body_entered.connect(_on_attack_hitbox_body_entered)

	_play_anim(&"idle")

	# Ensure weapon exists under animator so it flips together
	_ensure_weapon()
	
	# Start with a random weapon
	equip_weapon_random()

func _physics_process(delta: float) -> void:
	if _dead:
		# Apply gravity only, let death animation play
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.y = min(velocity.y + gravity * delta, max_fall_speed)
		move_and_slide()
		return

	if _hit_stun_time > 0.0:
		_hit_stun_time -= delta
	if _attack_cooldown_left > 0.0:
		_attack_cooldown_left = max(0.0, _attack_cooldown_left - delta)

	if _state == "roll":
		_process_roll(delta)
	else:
		_process_ground_movement(delta)
		_maybe_start_roll(delta)
		# Attack input (ground or air)
		if Input.is_action_just_pressed(input_attack):
			attack()

	_update_animation()

func _process_ground_movement(delta: float) -> void:
	var input_dir := 0
	if Input.is_action_pressed(input_left):
		input_dir -= 1
	if Input.is_action_pressed(input_right):
		input_dir += 1

	if input_dir != 0:
		_facing = input_dir
		velocity.x = move_toward(velocity.x, move_speed * input_dir, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

	# Gravity
	if not is_on_floor():
		velocity.y = min(velocity.y + gravity * delta, max_fall_speed)
	else:
		velocity.y = 0.0

	# Jump
	if is_on_floor() and Input.is_action_just_pressed(input_jump):
		velocity.y = -jump_force

	move_and_slide()

func _maybe_start_roll(delta: float) -> void:
	if _roll_cooldown_left > 0.0:
		_roll_cooldown_left = max(0.0, _roll_cooldown_left - delta)
		return
	if _hit_stun_time > 0.0:
		return
	if Input.is_action_just_pressed(input_roll):
		_state = "roll"
		_roll_time_left = roll_duration
		_roll_cooldown_left = roll_cooldown + roll_duration
		_roll_direction = _facing
		if invincible_during_roll and hurtbox_shape:
			hurtbox_shape.set_deferred("disabled", true) # Disable only the Hurtbox, not physics
		_play_anim(roll_anim_name)

func _process_roll(delta: float) -> void:
	_roll_time_left -= delta
	velocity.x = roll_speed * _roll_direction
	if not is_on_floor():
		velocity.y = min(velocity.y + gravity * delta * 0.8, max_fall_speed)
	else:
		velocity.y = 0.0
	move_and_slide()
	if _roll_time_left <= 0.0:
		_state = "idle"
		if invincible_during_roll and hurtbox_shape:
			hurtbox_shape.set_deferred("disabled", false)
func _update_animation() -> void:
	if _dead:
		_play_anim(&"death")
		return

	if _state == "roll":
		_play_anim(roll_anim_name)
	elif _state == "hit":
		_play_anim(&"hit")
		if _hit_stun_time <= 0.0:
			_state = "idle"
	elif abs(velocity.x) > 2.0 and is_on_floor():
		_play_anim(&"run")
	elif is_on_floor():
		_play_anim(&"idle")
	else:
		_play_anim(&"idle")

	# Flip sprite based on facing
	if sprite:
		sprite.flip_h = (_facing < 0)
	
	# Update weapon direction and position
	if weapon:
		if weapon.has_method("set_facing_dir"):
			weapon.set_facing_dir(_facing)
		# Adjust weapon position based on facing direction
		if _facing < 0:
			weapon.position = Vector2(-8, -4)  # Left side
		else:
			weapon.position = Vector2(8, -4)   # Right side
	
	# Update attack hitbox position based on facing direction
	if attack_hitbox_shape:
		if _facing < 0:
			attack_hitbox_shape.position = Vector2(-8, 2)  # Left side
		else:
			attack_hitbox_shape.position = Vector2(8, 2)   # Right side

func _play_anim(name: StringName) -> void:
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(name):
		if sprite.animation != name:
			sprite.play(name)

# Weapon management
func _ensure_weapon() -> void:
	if weapon == null:
		# Try find existing instance
		var found := get_node_or_null("Agentanimator/Weapon") as PlayerWeapon
		if found:
			weapon = found
		elif weapon_scene and attach_anchor:
			var inst := weapon_scene.instantiate() as PlayerWeapon
			if inst:
				weapon = inst
				attach_anchor.add_child(weapon)
				weapon.position = Vector2(8, -4)

func equip_weapon_random() -> void:
	_ensure_weapon()
	if weapon == null:
		return
	# Remove previous effects
	if weapon.has_method("remove_from_player"):
		weapon.remove_from_player(self)
	# Randomly choose among 3
	var choice := randi() % 3
	match choice:
		0:
			weapon.set_weapon_type(PlayerWeapon.WeaponType.SWORD)
		1:
			weapon.set_weapon_type(PlayerWeapon.WeaponType.SHIELD)
		2:
			weapon.set_weapon_type(PlayerWeapon.WeaponType.STAFF)
	# Apply weapon effects to player
	if weapon.has_method("apply_to_player"):
		weapon.apply_to_player(self)

	# Damage and death handling
func take_damage(amount: int = 1) -> void:
	if _dead:
		return
	# Invulnerable during roll (if configured)
	if invincible_during_roll and _state == "roll":
		return
	# Apply weapon defense bonus
	var defense = 0
	if weapon and weapon.has_method("get_defense_bonus"):
		defense = weapon.get_defense_bonus()
	
	var final_damage = max(0, amount - defense)
	health -= final_damage
	emit_signal("took_damage", final_damage, health)
	emit_signal("health_changed", health, max_health)
	
	# Update player's own UI health bar
	if player_ui_health_bar and player_ui_health_bar.has_method("set_health"):
		player_ui_health_bar.set_health(health, max_health)
	
	_hit_stun_time = hit_stun_duration
	if health <= 0:
		_die()
	else:
		_state = "hit"
		_play_anim(&"hit")

func heal(amount: int = 1) -> void:
	if _dead:
		return
	health = clamp(health + max(0, amount), 0, max_health)
	emit_signal("health_changed", health, max_health)

func attack() -> void:
	# Player attack: enable hitbox briefly to damage enemies
	if _dead:
		return
	if _attack_cooldown_left > 0.0:
		return
	_attack_cooldown_left = attack_cooldown
	
	# Temporarily disable player's hurtbox during attack to prevent self-damage
	var hurtbox_was_monitoring = false
	if hurtbox:
		hurtbox_was_monitoring = hurtbox.monitoring
		hurtbox.monitoring = false
	
	# Enable attack hitbox briefly
	if attack_hitbox:
		attack_hitbox.monitoring = true
		# Create timer to disable hitbox after short duration
		var timer = Timer.new()
		timer.wait_time = 0.15  # Brief attack window
		timer.one_shot = true
		add_child(timer)
		timer.timeout.connect(_disable_attack_hitbox.bind(timer, hurtbox_was_monitoring))
		timer.start()
	
	# Also use weapon system if available
	if weapon and weapon.has_method("perform_attack"):
		weapon.perform_attack()
	
	# Play attack animation if available
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(&"attack"):
		_play_anim(&"attack")

func apply_health_bonus(amount: int) -> void:
	_health_bonus += amount
	max_health += amount
	health += amount

func remove_health_bonus(amount: int) -> void:
	var to_remove: int = min(amount, _health_bonus)
	_health_bonus -= to_remove
	max_health = max(1, max_health - to_remove)
	health = clamp(health, 0, max_health)

func _die() -> void:
	_dead = true
	velocity = Vector2.ZERO
	_play_anim(&"death")
	if hurtbox_shape:
		hurtbox_shape.set_deferred("disabled", true)
	if collision_shape:
		collision_shape.set_deferred("disabled", false) # Keep physics so body can settle if needed
	if sprite and not sprite.animation_finished.is_connected(_on_sprite_anim_finished):
		sprite.animation_finished.connect(_on_sprite_anim_finished)

func _on_sprite_anim_finished() -> void:
	if _dead and sprite and sprite.animation == "death":
		emit_signal("died")
		queue_free()

# Hurtbox callbacks - enemies can damage player on contact
func _on_hurtbox_area_entered(area: Area2D) -> void:
	# Check if this is an enemy's attack area
	var parent = area.get_parent()
	if parent and parent.is_in_group("enemy"):
		var dmg := 1
		if area.has_meta("damage"):
			dmg = int(area.get_meta("damage"))
		elif parent.has_method("get_damage"):
			dmg = int(parent.get_damage())
		take_damage(dmg)

func _on_hurtbox_body_entered(body: Node) -> void:
	# Enemy body touching player hurtbox damages player
	if body and body.is_in_group("enemy"):
		var dmg := 1
		if body.has_method("get_damage"):
			dmg = int(body.get_damage())
		elif body.has_meta("damage"):
			dmg = int(body.get_meta("damage"))
		take_damage(dmg)

# Attack hitbox callbacks - player can damage enemies
func _on_attack_hitbox_area_entered(area: Area2D) -> void:
	var parent = area.get_parent()
	# Make sure we don't damage ourselves or other players
	if parent and parent.is_in_group("enemy") and parent != self:
		if parent.has_method("take_damage"):
			var damage_amount = 1
			if weapon and weapon.has_property("damage"):
				damage_amount = weapon.damage
			parent.take_damage(damage_amount)

func _on_attack_hitbox_body_entered(body: Node) -> void:
	# Make sure we don't damage ourselves or other players
	if body and body.is_in_group("enemy") and body != self:
		if body.has_method("take_damage"):
			var damage_amount = 1
			if weapon and weapon.has_property("damage"):
				damage_amount = weapon.damage
			body.take_damage(damage_amount)

func _disable_attack_hitbox(timer: Timer, restore_hurtbox_monitoring: bool = true) -> void:
	if attack_hitbox:
		attack_hitbox.monitoring = false
	
	# Re-enable hurtbox after attack
	if hurtbox and restore_hurtbox_monitoring:
		hurtbox.monitoring = true
	
	if timer:
		timer.queue_free()

# Functions for external systems to update player UI
func update_wave_display(wave_number: int) -> void:
	if player_ui_wave_label:
		player_ui_wave_label.text = "Wave %d" % wave_number

func update_soul_display(soul_count: int) -> void:
	if player_ui_soul_label:
		player_ui_soul_label.text = "Souls: %d" % soul_count
