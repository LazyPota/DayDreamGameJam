extends CharacterBody2D

# Movement config
@export var move_speed: float = 60.0
@export var gravity: float = 1400.0
@export var max_fall_speed: float = 1400.0

# Random movement
@export var change_dir_time: float = 2.0 # setiap berapa detik ganti arah
var _time_left: float = 0.0
var _facing: int = 1 # 1 = kanan, -1 = kiri

# Health
@export var max_health: int = 2
var health: int
var _dead: bool = false

# Drops
@export var soul_drop_chance: float = 0.5

# Signals
signal died(dropped_soul: bool)

# Nodes
@onready var sprite: AnimatedSprite2D = $"Agentanimator/AnimatedSprite2D"
@onready var collision_shape: CollisionShape2D = $"CollisionShape2D"
@onready var attack_area: Area2D = get_node_or_null("AttackArea")

# Attack system
@export var attack_damage: int = 1
@export var attack_cooldown: float = 1.0
var _attack_cooldown_left: float = 0.0

func _ready() -> void:
	health = max_health
	_time_left = change_dir_time
	_play_anim(&"idle")
	add_to_group("enemy")

func _physics_process(delta: float) -> void:
	if _dead:
		velocity.x = move_toward(velocity.x, 0, 100 * delta)
		velocity.y = min(velocity.y + gravity * delta, max_fall_speed)
		move_and_slide()
		return
	
	# Update attack cooldown
	if _attack_cooldown_left > 0.0:
		_attack_cooldown_left = max(0.0, _attack_cooldown_left - delta)

	# Timer untuk ganti arah random
	_time_left -= delta
	if _time_left <= 0.0:
		_time_left = change_dir_time
		if randf() > 0.5:
			_facing = 1
		else:
			_facing = -1  # random kiri/kanan

	# Gerakan horizontal
	velocity.x = _facing * move_speed
	
	# Gravity
	velocity.y = min(velocity.y + gravity * delta, max_fall_speed)
	
	# Check for player to attack
	_check_for_player_attack()
	
	# Move and slide
	move_and_slide()
	
	# Check if stuck against wall and change direction
	if is_on_wall():
		_facing *= -1
		_time_left = change_dir_time  # Reset direction timer
	
	# Check if at edge of platform and change direction
	if is_on_floor():
		var space_state = get_world_2d().direct_space_state
		var query = PhysicsRayQueryParameters2D.create(
			global_position + Vector2(_facing * 20, 10), 
			global_position + Vector2(_facing * 20, 50)
		)
		var result = space_state.intersect_ray(query)
		if not result:  # No ground ahead, turn around
			_facing *= -1
			_time_left = change_dir_time
	_update_animation()

func _update_animation() -> void:
	# FIXED: Added a 'pass' statement to the empty 'if' block.
	if _dead:
		pass
	elif abs(velocity.x) > 1 and is_on_floor():
		_play_anim(&"run")
	elif is_on_floor():
		_play_anim(&"idle")
	else:
		_play_anim(&"fall")

	# Flip sprite sesuai arah
	if sprite:
		sprite.flip_h = (_facing < 0)

func _play_anim(name: StringName) -> void:
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(name):
		if sprite.animation != name:
			sprite.play(name)

func take_damage(amount: int = 1) -> void:
	if _dead:
		return
	health -= max(0, amount)
	if health <= 0:
		_die()

func _die() -> void:
	_dead = true
	velocity = Vector2.ZERO
	_play_anim(&"death")
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if sprite and not sprite.animation_finished.is_connected(_on_sprite_anim_finished):
		sprite.animation_finished.connect(_on_sprite_anim_finished)

	# Roll for soul drop now so listeners can update immediately
	var dropped := randf() < soul_drop_chance
	emit_signal("died", dropped)

func _on_sprite_anim_finished() -> void:
	if _dead and sprite and sprite.animation == "death":
		queue_free()

# Enemy attack function - separate from player collision
func enemy_attack() -> void:
	if _dead or _attack_cooldown_left > 0.0:
		return
	
	_attack_cooldown_left = attack_cooldown
	
	# Check for nearby players to attack
	var players = get_tree().get_nodes_in_group("player")
	for player in players:
		if player and player.has_method("take_damage"):
			var distance = global_position.distance_to(player.global_position)
			if distance < 30.0:  # Reduced attack range - must be very close
				player.take_damage(attack_damage)
				break

# Function to check if player is nearby for automatic attacks
func _check_for_player_attack() -> void:
	if _dead or _attack_cooldown_left > 0.0:
		return
	
	var players = get_tree().get_nodes_in_group("player")
	for player in players:
		if player:
			var distance = global_position.distance_to(player.global_position)
			if distance < 25.0:  # Reduced attack range - enemies must be very close
				enemy_attack()
				break

func apply_stat_multiplier(mult: float) -> void:
	move_speed *= mult
	max_health = int(round(max_health * mult))
	health = max_health

# Return damage amount for player collision
func get_damage() -> int:
	return 1  # Standard enemy damage
