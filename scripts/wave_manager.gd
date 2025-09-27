extends Node

# Wave and spawn settings
@export var enemies_base_per_wave: int = 5
@export var enemies_per_skip_increase: int = 5
@export var enemies_total_cap: int = 50
@export var active_enemies_limit: int = 10
@export var spawn_interval: float = 0.6
@export var min_spawn_distance_from_player: float = 150.0
@export var ground_raycast_distance: float = 2000.0
@export var max_spawn_attempts: int = 6

# Economy and win condition
@export var soul_cost_per_wave: int = 5
@export var souls_required_to_win: int = 200

# Enemy scenes
@export var enemy_scenes: Array[PackedScene] = [
	preload("res://scenes/enemy.tscn"),
	preload("res://scenes/enemy1.tscn")
]

# Node paths (will be auto-connected when used in GameManager)
@export var player_path: NodePath = NodePath("../player")
@export var spawns_path: NodePath = NodePath("../SpawnPoints")

# Runtime state
var current_wave: int = 0
var next_wave_extra: int = 0
var stat_multiplier: float = 1.0
var souls: int = 0

var _wave_target: int = 0
var _spawned_in_wave: int = 0
var _alive_enemies: int = 0 # FIXED: Declared the missing variable
var _spawn_points: Array[Node2D] = []
var _spawn_timer: Timer

@onready var player = get_node_or_null(player_path)

func _find_player() -> Node:
	# Try multiple ways to find the player
	if player:
		return player
	
	# Try to find player by group
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
		return player
	
	# Try direct path
	player = get_node_or_null("../player")
	if player:
		return player
	
	# Try searching in parent
	var parent = get_parent()
	if parent:
		player = parent.get_node_or_null("player")
		if player:
			return player
	
	return null
@onready var spawns = get_node_or_null(spawns_path)
@onready var ui_label: Label = get_node_or_null("../UI/WavePrompt/PromptLabel")
@onready var ui_prompt: Control = get_node_or_null("../UI/WavePrompt")
@onready var ui_pay_button: Button = get_node_or_null("../UI/WavePrompt/ButtonContainer/PayButton")
@onready var ui_skip_button: Button = get_node_or_null("../UI/WavePrompt/ButtonContainer/SkipButton")
@onready var wave_counter_label: Label = get_node_or_null("../UI/WaveLabel")
@onready var soul_counter_label: Label = get_node_or_null("../UI/SoulLabel")
@onready var health_bar: Control = get_node_or_null("../UI/HealthBar")
func _ready() -> void:
	print("Wave Manager starting up...")
	
	# Try to find player immediately
	var found_player = _find_player()
	if found_player:
		print("Player found: ", found_player.name)
	else:
		print("Player NOT found during ready!")
		print("Player path: ", player_path)
	
	# Cache spawn points
	if spawns:
		for c in spawns.get_children():
			if c is Node2D:
				_spawn_points.append(c)
	print("Found ", _spawn_points.size(), " spawn points")
	print("Enemy scenes available: ", enemy_scenes.size())
	
	# Create spawn timer
	_spawn_timer = Timer.new()
	_spawn_timer.one_shot = false
	_spawn_timer.wait_time = spawn_interval
	add_child(_spawn_timer)
	_spawn_timer.timeout.connect(_on_spawn_tick)
	
	# Add a longer delay before starting the first wave to let player get ready
	var start_delay = Timer.new()
	start_delay.wait_time = 5.0  # 5 second delay before first wave
	start_delay.one_shot = true
	add_child(start_delay)
	start_delay.timeout.connect(_start_first_wave)
	start_delay.start()
	
	# Show a message to the player
	_show_message("Get ready! First wave starts in 5 seconds...", false)

	# UI prompt system disabled - using automatic wave progression
	
	# Connect player health to health bar
	if player and health_bar:
		if player.has_signal("health_changed"):
			player.health_changed.connect(_on_player_health_changed)
	
	_update_wave_counter_label()
	_update_soul_counter_label()
	# Don't start wave immediately - wait for the delay timer

func _start_next_wave() -> void:
	if souls >= souls_required_to_win:
		_show_message("You have collected %d life souls. You win!" % souls, false)
		return # FIXED: Added return to stop the function on win

	current_wave += 1
	_spawned_in_wave = 0
	_alive_enemies = 0
	_wave_target = min(enemies_total_cap, enemies_base_per_wave + next_wave_extra)
	if ui_prompt:
		ui_prompt.visible = false
	# Give player a new random weapon for the new wave
	if player and player.has_method("equip_weapon_random"):
		player.equip_weapon_random()
	_update_wave_counter_label()
	_spawn_timer.start()

func _start_first_wave() -> void:
	# Start the first wave after delay
	print("Starting first wave!")
	_start_next_wave()

func _on_spawn_tick() -> void:
	# Safety check to prevent runaway spawning
	if _spawned_in_wave > enemies_total_cap * 2:
		print("Error: Excessive spawning detected, stopping timer")
		_spawn_timer.stop()
		return
		
	# Stop spawning if reached target
	if _spawned_in_wave >= _wave_target:
		_spawn_timer.stop()
		# If all spawned enemies are now dead, the wave is cleared
		if _alive_enemies <= 0:
			_on_wave_cleared()
		return
	# Respect active enemies cap
	if _alive_enemies >= active_enemies_limit:
		return

	_spawn_enemy()

func _spawn_enemy() -> void:
	# Spawn enemy 5 feet (150 pixels) away from player
	var current_player = _find_player()
	if not current_player:
		print("Warning: No player found!")
		print("Tried player_path: ", player_path)
		print("Available groups: ", get_tree().get_groups())
		return
	
	print("Spawning enemy 5 feet from player...")
	var player_pos = current_player.global_position
	
	# Spawn 5 feet to the RIGHT of the player (constant position)
	var distance = 150  # 5 feet in pixels
	var spawn_pos = Vector2(
		player_pos.x + distance,  # Always to the right
		player_pos.y  # Same height as player
	)
	
	print("Player position: ", player_pos)
	print("Spawn position: ", spawn_pos)
	
	# Pick random enemy type
	var enemy_scene = enemy_scenes[randi() % enemy_scenes.size()]
	var enemy_inst = enemy_scene.instantiate()
	if enemy_inst == null:
		print("Warning: Failed to instantiate enemy!")
		return
	
	# Apply stat multiplier
	if enemy_inst.has_method("apply_stat_multiplier"):
		enemy_inst.apply_stat_multiplier(stat_multiplier)
	
	# Connect death signal
	if enemy_inst.has_signal("died") and not enemy_inst.died.is_connected(_on_enemy_died):
		enemy_inst.died.connect(_on_enemy_died)
	
	# Add to scene and position
	get_parent().add_child(enemy_inst)
	enemy_inst.global_position = spawn_pos
	print("Enemy spawned! Alive enemies: ", _alive_enemies + 1, " Spawned this wave: ", _spawned_in_wave + 1)
	
	_alive_enemies += 1
	_spawned_in_wave += 1

func _on_wave_cleared() -> void:
	if souls >= souls_required_to_win:
		_show_message("You have collected %d life souls. You win!" % souls, false)
		return
	
	# Automatic wave progression: give 3 souls or add 5 more enemies
	if souls >= 3:
		# Player has enough souls, consume 3 and continue normally
		souls -= 3
		_show_message("Wave cleared! Used 3 souls to keep difficulty normal.", true)
		_update_soul_counter_label()
		_start_next_wave()
	else:
		# Player doesn't have enough souls, add 5 more enemies
		next_wave_extra += 5
		_show_message("Not enough souls! Next wave will have 5 more enemies.", true)
		_start_next_wave()
	
	_update_wave_counter_label()

# Old UI prompt system removed - now using automatic progression

func _on_enemy_died(dropped_soul: bool) -> void:
	if dropped_soul:
		souls += 1
		_update_soul_counter_label()
	_alive_enemies = max(0, _alive_enemies - 1)
	# If the spawn timer is stopped (meaning all enemies for the wave have been spawned)
	# and this was the last enemy, clear the wave.
	if _spawn_timer.is_stopped() and _alive_enemies <= 0:
		_on_wave_cleared()

func _pick_spawn_position() -> Node2D:
	if _spawn_points.is_empty():
		print("Warning: No spawn points available!")
		return null
	
	# Try to find a spawn point that's not too close to existing enemies
	var attempts = 0
	var max_attempts = _spawn_points.size() * 2
	
	while attempts < max_attempts:
		var spawn_point = _spawn_points[randi() % _spawn_points.size()]
		var spawn_pos = spawn_point.global_position
		var too_close = false
		
		# Check distance to existing enemies and player
		var enemies = get_tree().get_nodes_in_group("enemy")
		for enemy in enemies:
			if enemy.global_position.distance_to(spawn_pos) < 64.0:  # 64 pixels minimum distance
				too_close = true
				break
		
		# Also check distance to player
		if not too_close and player:
			var distance_to_player = player.global_position.distance_to(spawn_pos)
			if distance_to_player < min_spawn_distance_from_player:
				too_close = true
		
		if not too_close:
			return spawn_point
		
		attempts += 1
	
	# If we can't find a good spot, just use a random one
	return _spawn_points[randi() % _spawn_points.size()]

func _compute_grounded_position(node: Node2D) -> Vector2:
	var from: Vector2 = node.global_position
	var to: Vector2 = from + Vector2(0, ground_raycast_distance)
	var space: PhysicsDirectSpaceState2D = get_viewport().get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = space.intersect_ray(query)
	if hit.has("position"):
		# Place enemy well above the floor to avoid getting stuck in tiles
		var ground_y: float = hit.position.y
		return Vector2(hit.position.x, ground_y - 16.0) # 16 pixels above ground
	# Fallback to original position if no ground found
	return Vector2(from.x, from.y - 16.0)

# Old UI button functions removed - now using automatic progression

func _show_message(text: String, auto_hide: bool = true) -> void:
	print("Wave Manager: ", text)
	if auto_hide:
		# Could add a timer here to hide after some seconds
		pass

func _hide_message() -> void:
	# Message hiding functionality (currently just prints)
	pass

func _update_wave_counter_label() -> void:
	if wave_counter_label:
		wave_counter_label.text = "Wave %d" % current_wave
	# Also update player's UI if available
	if player and player.has_method("update_wave_display"):
		player.update_wave_display(current_wave)

func _update_soul_counter_label() -> void:
	if soul_counter_label:
		soul_counter_label.text = "Souls: %d" % souls
	# Also update player's UI if available
	if player and player.has_method("update_soul_display"):
		player.update_soul_display(souls)

func _on_player_health_changed(current_health: int, max_health: int) -> void:
	if health_bar and health_bar.has_method("set_health"):
		health_bar.set_health(current_health, max_health)
