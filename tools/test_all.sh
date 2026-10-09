#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
mkdir -p tests/results
"$GODOT" --headless --path . --editor --import --quit > tests/results/import.log 2>&1
TESTS=(test_cards test_animations test_views test_menu test_rules_table test_uno_rules test_uno_options test_uno_integration test_uno_options_integration test_uno_scoring_review test_blackjack_rules test_blackjack_integration test_blackjack_review test_blackjack_review_integration test_blackjack_ring_rules test_blackjack_dealer_solver test_blackjack_dealer_payoffs test_blackjack_dealer_oracle test_ring_card_table test_blackjack_ring_review test_blackjack_ring_review_integration)
for test in "${TESTS[@]}"; do
  "$GODOT" --headless --max-fps 60 --path . --script "res://tests/$test.gd" > "tests/results/$test.log" 2>&1
  tail -1 "tests/results/$test.log"
done
"$GODOT" --headless --max-fps 60 --path . --quit-after 120 > tests/results/lobby-smoke.log 2>&1
"$GODOT" --headless --max-fps 60 --path . res://scenes/uno_game.tscn --quit-after 180 > tests/results/uno-smoke.log 2>&1
"$GODOT" --headless --max-fps 60 --path . res://scenes/table_demo.tscn --quit-after 120 > tests/results/template-smoke.log 2>&1
"$GODOT" --headless --max-fps 60 --path . res://scenes/blackjack_game.tscn --quit-after 120 > tests/results/blackjack-smoke.log 2>&1
LOGS=(tests/results/import.log tests/results/{lobby,uno,template,blackjack}-smoke.log)
for test in "${TESTS[@]}"; do LOGS+=("tests/results/$test.log"); done
if grep -E '(SCRIPT ERROR|Parse Error|ERROR:)' "${LOGS[@]}"; then
  echo 'Godot reported errors; inspect tests/results.' >&2
  exit 1
fi
echo 'All serial tests and four scene smoke tests passed.'
