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
| Optional-rule combinations | 329,010 | 0 |
| Optional controller integration | 13,852 | 0 |
| Total | 513,121 | 0 |

Clean editor import, 180-frame game smoke, 120-frame original-template smoke, and `git diff --check` passed. No script/parse/runtime errors in final logs. Logs are generated locally in ignored `tests/results/`, not repository artifacts.

Rules tests include 140 completed seeded 2–8 player rounds / 12,860 commands; independent integration adds 280 randomized rules rounds and seven complete controller/presenter rounds. These are complementary assertions, not 513,121 separate test scenarios.

The optional suites additionally complete 768 deterministic rules rounds across all 16 switch combinations and 32 full mixed human/bot controller rounds at 2 and 8 players. Tests explicitly exercise request versions, invalid-action immutability, exact/self/out-of-turn jump ordering, cancellation of only the latest action effect, accumulated penalties, cyclic final-card winner selection, usable UNO windows, compulsory wild-color selection, and independent per-game settings.

## Coverage

- All four optional switches default off; settings are copied per round, discarded on Continue, applied on Restart, and retained for Next Round without resetting match scores.
- No fixed jump expiry. Local serial rules commands act as host authority, reject stale versions, and distinguish true actual play/draw from invalid requests. On-turn exact cards default to normal play/stacking; the explicit one-action jump checkbox instead replaces the previous effect, then resets. This is not a network transport implementation.
- Continuous draws stop at first match or physical exhaustion. Wild color choice cannot be canceled; voluntary draw with an existing legal move stays single-card.
- +2 / +4 stacking pays accumulated debt; +4 cannot be followed by +2; stacked-debt recipients invalidate empty-hand winner candidates correctly.
- Last-wild forced draw occurs once per transition; even exhausted supply never permits a final wild win, and empty draw/pass reaches bounded stalemate.
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

Optional-rule GUI review also passed in a real 1178-pixel-wide window: all four switches initially off; toggling then Continue leaves the live round unchanged; enabling all and restarting updates the active summary. The out-of-turn red-7 fixture reduced the human hand 3→2 and changed the next bot seat. Continuous drawing increased a two-card hand to five, required the drawn Wild's color, ignored Escape, then committed the Wild (five→four cards) and advanced the turn after choosing red. A misleading +4 hint on ordinary Wild was corrected to display card-specific instructions; the corresponding automated regression covers it. The combined stacking/jump fixture also passed both branches: default same-color +2 increased debt 2→4; selecting 本次抢牌 instead left debt at 2 and replaced the preceding effect. Explicit GUI fixtures freeze bot timing only for inspection and are never normal startup code.

## Reproduce

```sh
GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 tools/test_all.sh
# Deterministic ordinary deal:
$GODOT --path . -- --uno-seed=42 --uno-players=4
# Manual challenge and result fixtures (not part of normal startup):
$GODOT --path . --script res://tests/qa_uno_gui.gd -- --qa-challenge
$GODOT --path . --script res://tests/qa_uno_gui.gd -- --qa-result
# Optional-rule visual fixtures: bots deliberately frozen, normal startup unaffected.
$GODOT --path . --script res://tests/qa_uno_options_gui.gd -- --qa-jump
$GODOT --path . --script res://tests/qa_uno_options_gui.gd -- --qa-forced-wild
$GODOT --path . --script res://tests/qa_uno_options_gui.gd -- --qa-stack-jump
```

F12 captures to ignored `captures/`; headless runs cannot validate screenshot pixels. Runtime cumulative scores are not persisted. No network play, hidden-information server enforcement, or commercial-strength AI is claimed.
