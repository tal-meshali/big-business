class_name CoinView
extends Control
## A single coin drawn in code, used for the coins that fly between seats
## and Market shares. Square; `size` sets the diameter.

var gold: bool = false


func _init(p_gold: bool = false, diameter: float = 24.0) -> void:
	gold = p_gold
	size = Vector2(diameter, diameter)
	custom_minimum_size = size
	pivot_offset = size / 2.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	Glyphs.coin(self, size / 2.0, size.x / 2.0, gold)
