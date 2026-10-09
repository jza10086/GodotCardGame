extends Node
## In-memory session survives navigation. Process exit intentionally clears it.
var blackjack: RefCounted
func get_blackjack() -> RefCounted:
	if blackjack == null: blackjack = load("res://scripts/blackjack_rules.gd").new()
	return blackjack
