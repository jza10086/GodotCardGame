extends Control
const UI = preload("res://scripts/card_ui.gd")
func _open_table_demo() -> void:
	get_tree().change_scene_to_file("res://scenes/table_demo.tscn")

func _open_blackjack_game() -> void:
	get_tree().change_scene_to_file("res://scenes/blackjack_game.tscn")

func _open_uno_game() -> void:
	get_tree().change_scene_to_file("res://scenes/uno_game.tscn")

func _open_bluff_game() -> void:
	get_tree().change_scene_to_file("res://scenes/bluff_game.tscn")
