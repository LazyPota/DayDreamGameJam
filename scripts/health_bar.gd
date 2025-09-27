extends Control
class_name HealthBar

@onready var health_fill: TextureProgressBar = $"HealthFill"
@onready var health_label: Label = $"HealthLabel"

var max_health: int = 5
var current_health: int = 5

func _ready() -> void:
	update_display()

func set_health(health: int, max_hp: int) -> void:
	current_health = clamp(health, 0, max_hp)
	max_health = max_hp
	update_display()

func update_display() -> void:
	if health_fill:
		var percentage: float = float(current_health) / float(max_health) * 100.0
		health_fill.value = percentage
	
	if health_label:
		health_label.text = "%d/%d" % [current_health, max_health]

func take_damage(amount: int) -> void:
	set_health(current_health - amount, max_health)

func heal(amount: int) -> void:
	set_health(current_health + amount, max_health)
