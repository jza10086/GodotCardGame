# UNO-style prototype verification

Engine: Godot 4.7.2 stable (`ed1daf0bf`). Tested 2026-10-08.

## Configurable deal and remaining-point ranking update

Default seven cards; 1..floor(107 / player count), leaving a starter for all 2–8 player counts. Deal finishes before exactly one starter is flipped. Every starter keeps player 1 and forward direction; both wild types require player 1 to choose a color, without +4 debt or challenge. Scoring is number face value, colored action 10, Wild 20, Wild Draw Four 40. Rank by each hand’s remaining sum ascending; ties share competition rank, including zero-point cards versus an empty hand. No 500-point match or winner accumulation. Final penalties precede rankings, including stack loops and challenges. Exhausted stalemates still rank by points.

Independent `test_uno_scoring_review.gd` adds 336 complete rounds across 2–8 players, all 16 switch combinations and starting hands 1/7/maximum. It checks every point value independently, invalid restart atomicity, conservation, all starter kinds, tie rankings, terminal penalty timing, and real UI menu signals, unsubmitted SpinBox text, player-count clamping, unapplied settings, result navigation and next-round preservation.

New visual fixtures: `tests/qa_uno_scoring_gui.gd -- --qa-menu`, `--qa-starter`, or `--qa-result`.

## Final serial automated run

`tools/test_all.sh` completed successfully with writable XDG data/config/cache directories:

| Suite | Assertions | Failures |
| --- | ---: | ---: |
| Existing template core | 702 | 0 |
| Existing animations | 299 | 0 |
| Existing views | 168 | 0 |
| Existing Escape menu | 42 | 0 |
| Reusable rules presenter | 42 | 0 |
| UNO rules | 42,777 | 0 |
| Independent integration | 130,108 | 0 |
| Optional-rule combinations | 323,238 | 0 |
| Optional controller integration | 19,612 | 0 |
| Configurable deal / ranking independent review | 83,656 | 0 |
| Total | 600,644 | 0 |

Clean editor import, 180-frame game smoke, 120-frame original-template smoke, and `git diff --check` passed. No script/parse/runtime errors in final logs. Logs are generated locally in ignored `tests/results/`, not repository artifacts.

Rules tests include 140 completed seeded 2–8 player rounds / 12,345 commands; independent integration adds 280 randomized rules rounds and seven complete controller/presenter rounds. These are complementary assertions, not 600,644 separate test scenarios.

The optional suites additionally complete 768 deterministic rules rounds across all 16 switch combinations and 32 full mixed human/bot controller rounds at 2 and 8 players. Tests explicitly exercise request versions, invalid-action immutability, exact/self/out-of-turn jump ordering, cancellation of only the latest action effect, accumulated penalties, cyclic final-card winner selection, usable UNO windows, compulsory wild-color selection, and independent per-game settings.

## Coverage

- All four optional switches default off; settings are copied per round, discarded on Continue, applied on Restart, and retained for Next Round while each new round has independent scores.
- No fixed jump expiry. Local serial rules commands act as host authority, reject stale versions, and distinguish true actual play/draw from invalid requests. On-turn exact cards default to normal play/stacking; the explicit one-action jump checkbox instead replaces the previous effect, then resets. This is not a network transport implementation.
- Continuous draws stop at first match or physical exhaustion. Wild color choice cannot be canceled; voluntary draw with an existing legal move stays single-card.
- +2 / +4 stacking pays accumulated debt; +4 cannot be followed by +2; stacked-debt recipients invalidate empty-hand winner candidates correctly.
- Last-wild forced draw occurs once per transition; even exhausted supply never permits a final wild win, and empty draw/pass reaches bounded stalemate.
- Classic 108 unique IDs conserved across hands/draw/discards, correct deck composition; starter effects suppressed, first player chooses both wild starter colors.
- Color/value/symbol legality, voluntary draw, only-drawn-card rule, no stacking, two-player Reverse/Skip.
- +4 bluffs, pre-play color legality, successful/failed challenges, final-card penalties before scoring, immutable invalid commands.
- UNO commit/window boundaries, late declaration, catch penalties, recycling with top retained, exhausted-deck stalemate.
- Same physical card node flying between zones; unlimited hand count, centered discard, hidden unused pile nodes/colliders.
- Fixed player identity and opponent material masking across first-person / third-person / top views.
- 30-card hand retains pickable strips for all cards; hover/rest pose checked at 1440×960, 1280×720, 1024×768.
- Repeated draw accepts only one; color modal cancel leaves state unchanged; pause blocks gameplay and debug-cheating shortcuts.
- Human challenge evidence modal shows the pre-play snapshot, blocks underlying actions, and dismisses normally.
- Restart during flight removes stale presentation effects; result/menu/continue restores the same independent point ranking without mutation. Actual pressed-signal modal rebuilding and Escape navigation are covered, including safe deferred destruction.

## Manual GUI verification

Latest deal/ranking GUI review passed in a real window: the complete menu is unclipped; eight players at thirteen cards can switch to two players and enter 53 without Return, then Restart deals exactly 53 each with one draw card and player 1 first. Eight-player results clearly show tied ranks 1 and 5 and the requested card values. Result → menu → Escape restores rankings; Next Round retains eight players, thirteen cards and all four enabled options. A blue Reverse starter kept forward direction and player 1 first. A +4 starter required color choice, ignored Escape, then choosing red kept player 1’s normal turn and exactly five cards for every player, with no penalty.

Earlier regression GUI checks (superseded scoring behavior is historical only):

Verified in a real GUI before publication: legal human card play and bot response, true 3D hover lift, opponent backs, +4 color chooser and Escape cancel, accepted +4, restart into eight-player mode, center-focused top view, and eight-player roster/action layout at a smaller window. Final challenge-evidence and result-dialog review uses the reproducible fixtures below. GUI review identified and corrected low-contrast wild-card center text and a modal-rebuild reentrancy bug (freeing a button inside its pressed signal). Modal controls now detach immediately and defer destruction; the actual pressed-signal → menu → Escape path has dedicated regression assertions. Real GUI retest confirmed result → menu → Escape returns cleanly, Next Round starts round 2 (the former cumulative score behavior is superseded below), and successful +4 challenge proof dismisses normally. Automatic tests alone do not establish OS cursor capture or every visual condition.

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

F12 captures to ignored `captures/`; headless runs cannot validate screenshot pixels. Rounds now rank remaining points independently; no cumulative score or persistence. No network play, hidden-information server enforcement, or commercial-strength AI is claimed.
