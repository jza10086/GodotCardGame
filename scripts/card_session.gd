extends Node
## In-memory session survives navigation. Process exit intentionally clears it.
var blackjack: RefCounted
func get_blackjack() -> RefCounted:
	if blackjack == null: blackjack = load("res://scripts/blackjack_rules.gd").new()
	return blackjack

var blackjack_ring: RefCounted
func get_blackjack_ring() -> RefCounted:
	if blackjack_ring == null: blackjack_ring = load("res://scripts/blackjack_ring_rules.gd").new()
	return blackjack_ring

var bluff: RefCounted
func get_bluff() -> RefCounted:
	if bluff == null: bluff = load("res://scripts/bluff_rules.gd").new()
	return bluff
