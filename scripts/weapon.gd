extends Sprite2D

class_name PlayerWeapon

# Weapon types
enum WeaponType { SWORD, SHIELD, STAFF }

@export var type: WeaponType = WeaponType.SWORD
@export var damage: int = 1
@export var range_scale: float = 1.0
@export var hit_cooldown: float = 0.2

@onready var area: Area2D = get_node_or_null("Area2D")
@onready var hurt_shape: CollisionShape2D = area.get_node_or_null("HurtBox") if area else null

var _last_hit_time: Dictionary = {}

func _ready() -> void:
	_apply_type_defaults()
	if area:
		area.monitoring = true
		area.monitorable = true
		if not area.area_entered.is_connected(_on_area_entered):
			area.area_entered.connect(_on_area_entered)
		if not area.body_entered.is_connected(_on_body_entered):
			area.body_entered.connect(_on_body_entered)

func set_weapon_type(new_type: WeaponType) -> void:
	type = new_type
	_apply_type_defaults()

func set_texture_resource(tex: Texture2D) -> void:
	texture = tex

func _apply_type_defaults() -> void:
	match type:
		WeaponType.SWORD:
			damage = 3  # Highest damage
			range_scale = 1.5  # Highest range
			texture = load("res://assets/sword.tres")
		WeaponType.SHIELD:
			damage = 1  # Lowest damage
			range_scale = 1.0  # Normal range
			texture = load("res://assets/shield.tres")
		WeaponType.STAFF:
			damage = 2  # Medium damage
			range_scale = 1.3  # Medium range
			texture = load("res://assets/staff.tres")
	scale = Vector2(range_scale * 0.6, range_scale * 0.6)  # 70% of player size
	if hurt_shape and hurt_shape.shape is Shape2D:
		hurt_shape.scale = Vector2(range_scale, range_scale)

# Called by player to orient weapon and hitbox
func set_facing_dir(facing: int) -> void:
	# Corrected the ternary operator syntax
	var sign_x: float = -1.0 if (facing < 0) else 1.0
	# Preserve range scaling while flipping and keep small size
	scale = Vector2(range_scale * 0.6 * sign_x, range_scale * 0.6)

func _on_area_entered(a: Area2D) -> void:
	_try_hit(a)

func _on_body_entered(b: Node) -> void:
	_try_hit(b)

func _try_hit(target: Object) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var id: int = -1
	if target and target.has_method("get_instance_id"):
		id = int(target.get_instance_id())
	var last: float = float(_last_hit_time.get(id, -9999.0))
	if now - last < hit_cooldown:
		return
	_last_hit_time[id] = now

	# Call take_damage on enemies
	if target and target.has_method("take_damage"):
		target.take_damage(damage)

func apply_to_player(player: Node) -> void:
	if type == WeaponType.SHIELD and player and player.has_method("apply_health_bonus"):
		player.apply_health_bonus(2)  # Shield gives +2 max health

func remove_from_player(player: Node) -> void:
	if type == WeaponType.SHIELD and player and player.has_method("remove_health_bonus"):
		player.remove_health_bonus(2)  # Remove shield bonus when changing weapons

func get_defense_bonus() -> int:
	match type:
		WeaponType.SHIELD:
			return 1  # Shield reduces incoming damage by 1
		_:
			return 0

# Called by player to perform an attack immediately (checks overlaps)
func perform_attack() -> void:
	# This does not handle cooldown; player_controller enforces its own attack cooldown.
	if not area:
		return
	
	# Temporarily enable monitoring for the attack
	var was_monitoring = area.monitoring
	area.monitoring = true
	
	# Check overlapping bodies and areas and apply damage
	var bodies := area.get_overlapping_bodies()
	for b in bodies:
		_try_hit(b)
	var areas := area.get_overlapping_areas()
	for a in areas:
		_try_hit(a)
	
	# Restore previous monitoring state
	area.monitoring = was_monitoring
