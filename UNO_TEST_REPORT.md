# UNO-style prototype verification

Engine: Godot 4.7.2 stable (`ed1daf0bf`). Tested 2026-10-08.

## Final serial automated run

`tools/test_all.sh` completed successfully with writable XDG data/config/cache directories:

| Suite | Assertions | Failures |
| --- | ---: | ---: |
| Existing template core | 702 | 0 |
| Existing animations | 299 | 0 |
| Existing views | 168 | 0 |
| Existing Escape menu | 42 | 0 |
| Reusable rules presenter | 42 | 0 |
| UNO rules | 44,282 | 0 |
| Independent integration | 124,724 | 0 |
| Total | 170,259 | 0 |

Clean editor import, 180-frame game smoke, 120-frame original-template smoke, and `git diff --check` passed. No script/parse/runtime errors in final logs. Logs are generated locally in ignored `tests/results/`, not repository artifacts.

Rules tests include 140 completed seeded 2–8 player rounds / 12,860 commands; independent integration adds 280 randomized rules rounds and seven complete controller/presenter rounds. These are complementary assertions, not 170,259 separate test scenarios.

## Coverage

- Classic 108 unique IDs conserved across hands/draw/discards, correct deck composition and opening actions.
- Color/value/symbol legality, voluntary draw, only-drawn-card rule, no stacking, two-player Reverse/Skip.
- +4 bluffs, pre-play color legality, successful/failed challenges, final-card penalties before scoring, immutable invalid commands.
- UNO commit/window boundaries, late declaration, catch penalties, recycling with top retained, exhausted-deck stalemate.
- Same physical card node flying between zones; unlimited hand count, centered discard, hidden unused pile nodes/colliders.
- Fixed player identity and opponent material masking across first-person / third-person / top views.
- 30-card hand retains pickable strips for all cards; hover/rest pose checked at 1440×960, 1280×720, 1024×768.
- Repeated draw accepts only one; color modal cancel leaves state unchanged; pause blocks gameplay and debug-cheating shortcuts.
- Human challenge evidence modal shows the pre-play snapshot, blocks underlying actions, and dismisses normally.
- Restart during flight removes stale presentation effects; result/menu/continue restores result and scores only once. Actual pressed-signal modal rebuilding and Escape navigation are covered, including safe deferred destruction.

## Manual GUI verification

Verified in a real GUI before publication: legal human card play and bot response, true 3D hover lift, opponent backs, +4 color chooser and Escape cancel, accepted +4, restart into eight-player mode, center-focused top view, and eight-player roster/action layout at a smaller window. Final challenge-evidence and result-dialog review uses the reproducible fixtures below. GUI review identified and corrected low-contrast wild-card center text and a modal-rebuild reentrancy bug (freeing a button inside its pressed signal). Modal controls now detach immediately and defer destruction; the actual pressed-signal → menu → Escape path has dedicated regression assertions. Real GUI retest confirmed result → menu → Escape returns cleanly, Next Round preserves the 85-point fixture score and starts round 2, and successful +4 challenge proof dismisses normally. Automatic tests alone do not establish OS cursor capture or every visual condition.

## Reproduce

```sh
GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 tools/test_all.sh
# Deterministic ordinary deal:
$GODOT --path . -- --uno-seed=42 --uno-players=4
# Manual challenge and result fixtures (not part of normal startup):
$GODOT --path . --script res://tests/qa_uno_gui.gd -- --qa-challenge
$GODOT --path . --script res://tests/qa_uno_gui.gd -- --qa-result
```

F12 captures to ignored `captures/`; headless runs cannot validate screenshot pixels. Runtime cumulative scores are not persisted. No network play, hidden-information server enforcement, or commercial-strength AI is claimed.
