extends Node

# Wave and spawn settings
@export var enemies_base_per_wave: int = 5
@export var enemies_per_skip_increase: int = 5
@export var enemies_total_cap: int = 50
@export var active_enemies_limit: int = 10
@export var spawn_interval: float = 0.6
@export var min_spawn_distance_from_player: float = 96.0
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
@onready var spawns = get_node_or_null(spawns_path)
@onready var ui_label: Label = get_node_or_null("../UI/WavePrompt/PromptLabel")
@onready var ui_prompt: Control = get_node_or_null("../UI/WavePrompt")
@onready var ui_pay_button: Button = get_node_or_null("../UI/WavePrompt/ButtonContainer/PayButton")
@onready var ui_skip_button: Button = get_node_or_null("../UI/WavePrompt/ButtonContainer/SkipButton")
@onready var wave_counter_label: Label = get_node_or_null("../UI/WaveLabel")
@onready var soul_counter_label: Label = get_node_or_null("../UI/SoulLabel")
@onready var health_bar: Control = get_node_or_null("../UI/HealthBar")

func _ready() -> void:
	# Cache spawn points
	if spawns:
		for c in spawns.get_children():
			if c is Node2D:
				_spawn_points.append(c)
	# Spawn timer
	_spawn_timer = Timer.new()
	_spawn_timer.one_shot = false
	_spawn_timer.wait_time = spawn_interval
	add_child(_spawn_timer)
	_spawn_timer.timeout.connect(_on_spawn_tick)

	# FIXED: Corrected indentation and added a null check
	# UI wiring
	if ui_prompt:
		ui_prompt.visible = false
		if ui_pay_button and not ui_pay_button.pressed.is_connected(_on_pay_pressed):
			ui_pay_button.pressed.connect(_on_pay_pressed)
		if ui_skip_button and not ui_skip_button.pressed.is_connected(_on_skip_pressed):
			ui_skip_button.pressed.connect(_on_skip_pressed)
	
	# Connect player health to health bar
	if player and health_bar:
		if player.has_signal("health_changed"):
			player.health_changed.connect(_on_player_health_changed)
	
	_update_wave_counter_label()
	_update_soul_counter_label()
	_start_next_wave()

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
	# Pick a spawn far enough from the player and project to ground
	var spawn_node := _pick_spawn_position()
	if spawn_node == null:
		return
	var spawn_pos: Vector2 = _compute_grounded_position(spawn_node)
	
	# Randomly choose enemy type
	var enemy_scene: PackedScene = null
	if enemy_scenes.size() > 0:
		enemy_scene = enemy_scenes[randi() % enemy_scenes.size()]
	else:
		print("No enemy scenes available!")
		return
	
	var enemy := enemy_scene.instantiate()
	if enemy == null:
		print("Failed to instantiate enemy scene")
		return
	get_tree().current_scene.add_child(enemy)
	enemy.global_position = spawn_pos
	# Apply stat multiplier
	if enemy.has_method("set_stat_multiplier"):
		enemy.set_stat_multiplier(stat_multiplier)
	elif enemy.has_method("apply_stat_multiplier"):
		enemy.apply_stat_multiplier(stat_multiplier)
	# Connect death signal
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died)
	_alive_enemies += 1
	_spawned_in_wave += 1

func _on_wave_cleared() -> void:
	if souls >= souls_required_to_win:
		_show_message("You have collected %d life souls. You win!" % souls, false)
		return
	_show_prompt()
	_update_wave_counter_label()

func _show_prompt() -> void:
	if not ui_prompt:
		# No UI, auto decision: prefer pay if can, else skip
		if souls >= soul_cost_per_wave:
			_consume_souls_and_continue()
		else:
			_apply_skip_consequence()
		return
	if ui_label:
		ui_label.text = "Wave %d cleared! Souls: %d\nPay %d life souls to keep difficulty?" % [current_wave, souls, soul_cost_per_wave]
	ui_prompt.visible = true

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
		
		# Check distance to existing enemies
		var enemies = get_tree().get_nodes_in_group("enemy")
		for enemy in enemies:
			if enemy.global_position.distance_to(spawn_pos) < 64.0:  # 64 pixels minimum distance
				too_close = true
				break
		
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

func _on_pay_pressed() -> void:
	if souls >= soul_cost_per_wave:
		_consume_souls_and_continue()
	else:
		_apply_skip_consequence()

func _on_skip_pressed() -> void:
	_apply_skip_consequence()

func _consume_souls_and_continue() -> void:
	souls -= soul_cost_per_wave
	# No extra enemies added
	_start_next_wave()

func _apply_skip_consequence() -> void:
	# Add +5 enemies next wave, cap at total cap
	next_wave_extra = min(enemies_total_cap - enemies_base_per_wave, next_wave_extra + enemies_per_skip_increase)
	# If already at cap and couldn't/didn't pay, increase enemy stats
	if enemies_base_per_wave + next_wave_extra >= enemies_total_cap:
		stat_multiplier *= 2.0
	_start_next_wave()

func _show_message(text: String, auto_hide: bool = true) -> void:
	print("Wave Manager: ", text)
	if auto_hide:
		# Could add a timer here to hide after some seconds
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
