#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
mkdir -p tests/results
"$GODOT" --headless --path . --editor --import --quit > tests/results/import.log 2>&1
for test in test_cards test_animations test_views test_menu test_rules_table test_uno_rules test_uno_options test_uno_integration test_uno_options_integration test_uno_scoring_review; do
  "$GODOT" --headless --max-fps 60 --path . --script "res://tests/$test.gd" > "tests/results/$test.log" 2>&1
  tail -1 "tests/results/$test.log"
done
"$GODOT" --headless --max-fps 60 --path . --quit-after 180 > tests/results/uno-smoke.log 2>&1
"$GODOT" --headless --max-fps 60 --path . res://scenes/table_demo.tscn --quit-after 120 > tests/results/template-smoke.log 2>&1
if grep -E '(SCRIPT ERROR|Parse Error|ERROR:)' tests/results/{import,test_cards,test_animations,test_views,test_menu,test_rules_table,test_uno_rules,test_uno_options,test_uno_integration,test_uno_options_integration,test_uno_scoring_review,uno-smoke,template-smoke}.log; then
  echo 'Godot reported errors; inspect tests/results.' >&2
  exit 1
fi
echo 'All serial tests and both scene smoke tests passed.'
