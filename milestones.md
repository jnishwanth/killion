# killion — milestones

Change log + plan for iterative improvement of killion. Objective: keep all
functionality while improving simplicity, performance, usability/UI without
bloat. One small verifiable step per iteration; entries record what changed
and how it was verified.

## Baseline (iteration 0, 2026-10-30)

Files: `killion` 200 ln · `watch.mjs` 235 · `download_full.py` 170 ·
`render.jq` 18 · `party-render.jq` 23 · `AGENTS.md` 99.

Measured (owner's machine, 35 MB `full_dives.json`):
- one jq pass over the dataset ≈ 0.3 s
- one-shot lookup `killion <q>` ≈ 1.5 s (5 passes: `qlist`×2 for exact +
  case-insensitive grep, `render` + `EXTRAS`)
- `--selftest` ≈ 2.5 s (9 passes: one per prompt + gem checks)

## Log

### Iteration 1 — single-pass render (2026-10-30)

- Merged `party-render.jq` and the bash `EXTRAS` heredoc into `render.jq`:
  one jq program now renders daily answers, party-verified extras, and
  party-only lists (incl. unscored tier) from one pass over the dataset.
- `killion` `render()` is now a single `jq` invocation (was 2–3).
- Deleted `party-render.jq`; dropped the `EXTRAS` heredoc from `killion`.
  Net −14 lines (745 → 731) across the repo.
- Performance: one-shot ≈ 1.5 s → 0.63 s; interactive Enter→answers halved
  (2 passes → 1).
- Verified: `bash -n`; end-to-end output byte-identical to the old code for
  four captured cases (daily-only, daily+party extras, party-only with
  unscored tier, no-match/empty); `--selftest` still PASSED; `--json`
  unchanged; `party_answers.json` left untouched (tested via temp copy).
- Updated the AGENTS.md files table.

### Iteration 2 — single-pass one-shot lookup (2026-10-30)

- `render.jq` is now the whole lookup: it matches the raw query against
  daily + party questions (exact, else case-insensitive substring) and in
  the same pass renders the answer list (m=text) or emits the compact JSON
  object (m=json, via `tojson`). Ambiguous → candidates prefixed with `\u0001`;
  no match → silent.
- `killion`: new `lookup()` = one jq invocation; `one_shot` resolves +
  displays from that single pass (mode = text|json). Deleted the `AS_JSON`
  heredoc and `as_json()` — its dedup/enrichment logic now lives once in
  `render.jq` (shared by text and json modes), removing the last duplicated
  daily-lookup + party-dedup code.
- Performance (measured, 35 MB dataset): one-shot 0.62 s → 0.32 s (3 passes →
  1); no-match 0.62 s → 0.32 s; `--json` 0.62 s → 0.32 s. Interactive
  Enter→answers unchanged (1 pass). This was the plan's 0.3 s target.
- Line counts: `killion` 181 → 164, `render.jq` 46 → 72 (absorbed AS_JSON);
  code files 632 → 641 (+9: protocol plumbing in exchange for the speed and
  the dedup of the AS_JSON/render logic).
- Verified: `bash -n`; 15-case battery (exact daily, daily+party extras,
  case-insensitive unique, party-only + unscored tier, dup-case ambiguous,
  ambiguous, no-match, empty query, `--json` ×5, `--selftest`): 11/15
  byte-identical, 3/15 set-equal with reordered ambiguous-candidate lists
  (locale `sort -u` order → jq `unique` codepoint order — cosmetic), 1/15
  intentional change: `killion ""` now says "no game-verified answers"
  (old `grep -Fx ""` matched every line and dumped all 745 questions as
  "ambiguous"). `--selftest` still PASSED; real `party_answers.json` untouched
  (battery used a temp copy with synthetic daily+party, party-only and
  unscored-tier entries).
- Updated the AGENTS.md files table.

### Iteration 4 — single-pass `--selftest` (2026-10-30)

- New `selftest.jq` (12 ln): one jq pass over the dataset with
  `--slurpfile o official_latest.json`. Builds a `question → answer-count`
  map (first occurrence, matching the old `.[0] // -1` semantics) and emits
  one TSV row per official prompt (`P \t text \t n_official \t n_tool`) plus
  a gem row (`G \t text \t gem_official \t gem_tool`).
- `killion` `selftest()`: the per-prompt jq-in-a-while-loop and the
  separate gem jq calls are gone; one `jq -r -f selftest.jq` feeds the loop,
  which keeps the original `ok`/`MISMATCH`/`gem` formatting and exit codes.
- Performance (measured, 35 MB dataset): `--selftest` 2.54 s → 0.33 s
  (9 dataset passes → 1); plan's step 1 done.
- Line counts: `killion` 164 → 162 (−2); +`selftest.jq` 12 (net +10 in the
  repo — protocol plumbing, per AGENTS.md speed wins over smaller diffs).
- Verified: `bash -n`; baseline output diff (byte-identical, exit 0);
  doctored-official test in a temp copy (count mismatch, absent prompt →
  `tool=-1`, wrong gem, missing official file) — MISMATCH/FALSE output
  byte-identical to the HEAD version, exit 1 in all failure cases; one-shot
  text/`--json`/no-match smoke-tested unchanged.
- Updated the AGENTS.md files table.

### Iteration 5 — shared tier table + null-tier render fix (2026-10-30)

- New `tiers.json` (11 ln): the one source of truth for the tier table —
  `order` (display order) plus per-tier `name`/`icon`/`pts`/`cap`. All four
  duplicated copies are gone: `render.jq`'s `tn`/`ti`/`pt`/`$order` defs,
  `watch.mjs`'s `TIER_NAME`/`TIER_ICON`/`TIER_ORDER`/`SHOW_CAP`, and
  `download_full.py`'s `TIER_PTS`. Plan step 1 done.
- Fixed a latent bug the battery exposed (present since iteration 0): a party
  entry with `tier: null` — written by `watch.mjs` `record()` whenever the
  server omits the tier — crashed `render.jq` with "Cannot index object with
  null" (`pt[null]`), so the whole question silently reported "no
  game-verified answers". Now `$pt[$e.tier // ""] // 0`; the unscored section
  renders those entries as always intended.
- `killion`: `TIERS` var + existence check + `--slurpfile T` in `lookup()`.
- Performance: one-shot 0.369 s → 0.374 s (noise; the ~10-line slurpfile is
  negligible vs the 35 MB dataset).
- Line counts: `killion` 162 → 165, `render.jq` 72 → 74, `watch.mjs` 235 →
  236, `download_full.py` 170 → 173, +`tiers.json` 11 (net +19 in exchange
  for four tier tables becoming one; a tier change now touches one file).
- Verified: `bash -n`, `node --check`, `py_compile`; 12-case battery (temp
  repo copy + synthetic party file with scored/unscored(null)/unknown-tier
  entries and a daily-extra dedup): 10/12 byte-identical to baseline (daily
  text, daily+party extras, --json ×2, partial match, no-match, empty,
  ambiguous, real party daily+party, --selftest, usage), 2/12 the intentional
  null-tier fix (party-only question now renders + exit 0). Node/python checks
  confirm the tables derived from `tiers.json` equal the old hardcoded values
  exactly; missing-`tiers.json` error path tested.
- Updated the AGENTS.md files table.

### Iteration 6 — `watch.mjs` trim: shared `applyEvents` + dead code (2026-10-30)

- Extracted `applyEvents(events)`: the two byte-identical `pass`-event loops in
  the snap/patch handlers are now one helper — the pass-event semantics (mark
  said if new; record *every* sighting, so duplicate events count) live in one
  place. Plan step 1 done.
- Removed dead code found in the review: the `dirty` flag (always true on
  every snap/patch message — `draw()`'s sig check already dedupes, and Node's
  `onmessage` runs serialized), the `leaving` flag (never set to `true`, both
  guards were dead), and the module-level `let ws` (never read; now a `const`
  local in `connect()`).
- Line counts: `watch.mjs` 236 → 231 (−5).
- New verification: an offline harness (`/tmp/kw_harness.mjs` +
  `/tmp/kw_setup.sh`) that stubs `fetch`/`WebSocket` and feeds a scripted 7-
  message snap/patch sequence (duplicate pass event, tierless pass, non-pass
  event, string + object `lastAnswer`, unknown message type, `patch` without a
  `patch` field, no-change patch, new-round patch) to a temp repo copy with
  synthetic data. Ran it against HEAD's `watch.mjs` and the new one: stdout
  byte-identical (4 draws, 1 bell) and `party_answers.json` byte-identical
  (`Go` seen=2 from the duplicate event, null tiers, flush-merge across rounds),
  exit 0 both. Live-room testing avoided on purpose (a test room would leave
  a trace on the server — see AGENTS.md "be a quiet client").
- Smoke: one-shot 0.41 s, `--selftest` PASSED.

### Iteration 7 — durable home for the test scripts (2026-10-30)

- Promoted the two `/tmp` safety nets to a permanent `tests/` dir (plan step
  1 done): `kb_battery.sh` (12-case CLI/render battery), `kw_harness.mjs`
  (offline stubbed-WebSocket `watch.mjs` driver), and a new one-command entry
  point `tests/run.sh` that runs syntax checks + both suites against a temp
  repo copy and compares to `tests/golden.sha` (13 lines: sha256 of
  stdout+stderr and the exit code per case). `tests/run.sh --regen`
  re-records the golden after an intentional output change; on failure the
  temp workdir is left behind for inspection.
- Golden strategy: hashes, not content — the battery's raw outputs total
  ~700 KB (daily answer sheets + ambiguous-candidate list), which would have
  bloated the repo. The harness's `party_answers.json` carries today's date
  (not byte-stable), so its record semantics are asserted as five semantic
  `jq -e` facts instead (dup-event seen=2, null tier, patch event, tierless
  player answer, new-round flush).
- The harness now normalizes the random player key in its printed ws URL
  (`key=<key32>`) so its own stdout is byte-stable; the old `/tmp` scripts
  (incl. `kw_setup.sh`, now inlined into `run.sh`) were deleted.
- Verified: PASS path (13/13 golden cases, 5/5 facts, timing 0.37 s < the
  2.0 s guard, exit 0, workdir cleaned). Three negative paths, all correctly
  failing with exit 1 + the right diagnosis: doctored `tiers.json` → golden
  diff listing exactly the affected cases; doctored `watch.mjs` record() (no
  dup counting) → the dup-event fact fails; doctored `download_full.py`
  syntax error → syntax FAIL. Real `party_answers.json` untouched; no
  network, no live room.
- Line counts: +`tests/` 257 (run.sh 121, battery 54, harness 69, golden 13),
  +1 `.gitignore` line — the cost of durability; every future iteration keeps
  both safety nets with one command instead of reconstructing them in `/tmp`.
- Updated the AGENTS.md files table.

### Iteration 8 — interactive copy fix + stubbed-pty test (2026-10-30)

- Fixed a usability bug in the interactive path (the only part no test could
  reach): pressing Enter copied *the whole selected line* — daily answers
  came with their `  — quip` decoration, party answers with `  (×N)`, and
  even 2-space-indented tier rows (`● 60 · Rare (2)`) were "copied". Pasting
  any of those into the game submits a wrong answer. `answer_view` now only
  treats exactly-4-space-indented lines as answers and strips the quip / ×N
  decorations before `pbcopy`; headers and tier rows copy nothing.
- New durable test for that path (closes plan step 2 without fzf flakiness):
  `tests/run.sh` now runs the real `killion` on a pty (`script -q`) with a
  stubbed `fzf` (call-count state file scripts: question hit → scripted
  answer line → Esc) and a stubbed `pbcopy` (writes stdin to a file), and
  asserts the clipboard for 4 cases: quip stripped, ×N stripped, plain,
  tier row not copied. Four new golden cases (17 total).
- Verified: `bash -n`; full suite 3× green (17/17 golden, 5/5 facts,
  0.37 s one-shot); the new test run against the old buggy `answer_view`
  fails on exactly the 3 buggy cases (quip, ×N, tier row) and passes plain —
  i.e. it pins the fix. Golden diff is exactly +4 lines; all 13 pre-existing
  hashes unchanged (one-shot/selftest/usage untouched by the fix).
- Line counts: `killion` 165 → 169 (+4), `tests/run.sh` 121 → 170 (+49, the
  stubs + driver), `tests/golden.sha` 13 → 17. Net +57 — coverage of a path
  that had none, in exchange for the bug fix it found.

### Iteration 9 — offline parser test for `download_full.py` + cleanups (2026-10-30)

- `download_full.py` had no behavior test at all (only a syntax check), so
  plan step 1's cleanups were unverifiable. New `tests/kd_parse.py` pins
  `parse_cards` against the site's real format: it feeds the actual archived
  dive page for 2026-08-31 (dive #47, stored in `tests/fixtures/` — page +
  5 answer-roster JSONs, 164 KB) through `parse_cards` with `get()` stubbed
  to the local files, and asserts deep equality with the `full_dives.json`
  entry recorded from that same page. The fixture covers both card branches
  (roster-src and inline chips) with quips in both (roster 4-element rows,
  chip quip spans, HTML entities), plus the cardless/wrong-count error paths.
  Wired into `tests/run.sh` as a semantic (not byte-hashed) check.
- `download_full.py` cleanups (all behavior-neutral, all now test-pinned):
  dropped the dead `day` parameter of `parse_cards`; removed the redundant
  `marks.sort()` (`re.finditer` already yields in document order — now noted
  in a comment); the inline tier-group count is incremented per chip instead
  of re-scanning the whole `answers` list twice on the error path (the rescan
  also counted earlier groups, a latent false-fail if a card repeated a
  tier); `problems` now stores just the dive number (only `p[0]` was ever
  read); dropped an unused `as e`.
- Line counts: `download_full.py` 173 → 175 (+2: clarity over line count),
  +`tests/kd_parse.py` 63, `tests/run.sh` 170 → 183, +164 KB fixtures.
- Verified: full suite green (17/17 golden, 5/5 facts, 2/2 parse checks,
  0.37 s one-shot). The new test was proven to have teeth with a 6-case
  doctored-copy battery (each against a fresh temp repo copy): baseline
  passes (7 prompts, 1256 answers == dataset); broken quip regex → prompt
  mismatch; corrupted first inline chip → tier-count ValueError; mangled
  roster answer → prompt mismatch; old 2-arg `parse_cards` signature →
  TypeError; broken chip counter → fail. All five breaks caught.
- Fixture choice lesson: the first candidate fixture (dive #17) had zero
  quips in its whole page, so it silently left the quip branch unpinned —
  switched to dive #47 after checking per-branch marker counts in both the
  fixture and the dataset.

### Iteration 10 — `watch.mjs` survives disconnects and network failures (2026-10-30)

- Fixed a real bug found on review (present since the initial commit): after
  any non-fatal disconnect the watcher printed "connection lost, retrying…" and
  then **silently exited 0**. The retry timer was `.unref()`'d, the socket's
  handle was already gone, and signal handlers don't keep the event loop alive
  — so nothing ref'd remained and Node exited ~1.5 s before the retry could
  fire. The user was left with a frozen screen and a dead process. Fix: the
  retry timer is ref'd (it *is* the keep-alive while reconnecting).
- Fixed the same area's crash-on-network-failure: `j()` only caught
  `r.json()`, so a fetch failure rejected — a raw unhandled-rejection stack
  trace at startup, and inside `onclose` (4401 token refresh) too. Now `j()`
  catches everything and yields `{}`; a missing startup token exits 1 with a
  clean one-line error, a failed 4401 refresh keeps the old token and retries.
- `tests/kw_harness.mjs`: after the scripted sequence the harness now fires a
  non-fatal close and asserts a second WebSocket is constructed before
  SIGTERMing. The stub WebSocket emulates a *live* socket's ref'd handle
  (a `setInterval` cleared when the socket dies) and the watchdog is unref'd —
  without both, the harness itself would mask the bug. New `KSTUB_NETFAIL=1`
  mode makes fetch reject (clean token-failure path).
- `tests/run.sh`: two new semantic checks — "reconnects after disconnect"
  (grep the harness's builds line) and "clean exit on token-fetch failure"
  (exit 1 + the error line). `golden.sha`: exactly one line changed (the
  harness stdout hash, from the new builds line); all 16 other cases
  byte-identical.
- Verified: teeth first — the new harness against HEAD's `watch.mjs` fails
  exactly as designed (no builds line, silent exit, final flush never ran so
  the party file lacks the last round's entry; netfail prints a raw stack
  trace). Against the fix: reconnects (builds=2), final flush runs, drawn.txt
  byte-identical, netfail clean. Full suite 4× green (17/17 golden, 5/5 facts,
  2/2 new checks, 2/2 parse, 0.37 s one-shot), `--selftest` PASSED.
- Line counts: `watch.mjs` 231 → 242 (+11: the fix + comments explaining why
  the timer must be ref'd), `tests/kw_harness.mjs` 69 → 92, `tests/run.sh`
  183 → 199 — a live watcher's reconnection behavior is exactly what a test
  should pin.

### Iteration 11 — `--help`/`-h` flag (2026-10-30)

- `killion --help`/`-h` used to fall through to the one-shot lookup as the
  query "--help" — a futile 0.35 s dataset pass ending in "no game-verified
  answers". It now prints a readable multi-line usage and exits 0, handled
  *before* the dep/data checks so it works on a bare machine with no fzf and
  no dataset (and without creating `party_answers.json`). Closes standing
  plan candidate 1.
- The usage string now lives in one place: a `usage()` function. The
  no-args-non-tty path (exit 2, unchanged) and `-h/--help` (exit 0) share it —
  the old cramped one-line usage is gone. `killion watch --help` also prints
  the usage (previously "--help" was handed to the watcher as a room code).
- `tests/kb_battery.sh`: two new golden cases (`17_help`, `18_h`; stdout,
  exit 0); `tests/run.sh` KB_CASES +2 (19 total). Golden diff on re-record:
  exactly one line changed (`kb/12_usage` — the new multi-line text, still
  exit 2) plus the two added lines; all three usage emitters carry one hash,
  proving the text is byte-identical on every path.
- Verified: `bash -n` ×3; 3 consecutive full-suite greens (19/19 golden,
  5/5 facts, 2/2 watch checks, 2/2 parse, 0.37 s one-shot); bare-dir test
  (only `killion` copied) → help exits 0, no `party_answers.json` created;
  one-shot/`--selftest`/interactive battery all unchanged.
- Line counts: `killion` 169 → 191 (+22: the usage text + the early scan),
  `kb_battery.sh` 54 → 56, `run.sh` 199 → 200, `golden.sha` 17 → 19.

### Iteration 12 — dead-branch removal, side-effect ordering, two unpinned branches pinned (2026-10-30)

- `watch.mjs`: removed the unreachable `'  looking up verified answers…'`
  branch in `draw()`. `lookupIfNeeded()` runs *synchronously* (spawnSync) at
  the top of `draw()`, so by the time the inner branch executes, `lookupResult`
  is always already set (object or null) and `lookupFor === cat.text` — the
  "in progress" state can never be observed. Replaced with a comment saying
  why null means "no verified answers exist".
- `killion`: the `party_answers.json` creation moved *after* the fzf/jq/DATA/
  TIERS prerequisite checks (it ran before them) — a failed prerequisite no
  longer leaves a stray file in the repo, extending the zero-side-effect
  convention established for `--help`. Verified both directions on a temp
  copy: no dataset → no file created (old code created it); full copy → file
  still created on first normal run.
- `tests/kb_battery.sh`: two more previously-untested branches pinned —
  `19_json_ambiguous` (`--json` + ambiguous query: candidates on stderr, exit
  1; its hash equals case 07's, as expected — the ambiguity path is
  mode-independent, so text and json emit byte-identical streams) and
  `20_selftest_fail` (doctored `official_latest.json` — one answer appended to
  prompt 0 — must yield `MISMATCH … official=3529 tool=3528`, `SELFTEST
  FAILED`, exit 1; the first golden pin of the selftest failure path, which
  until now was only manually A/B'd in iteration 4). Golden 19 → 21 cases.
- Verified: `bash -n` ×3, `node --check`; 3 consecutive full-suite greens
  (21/21 golden, 5/5 facts, 2/2 watch, 2/2 parse, 0.36 s one-shot). Golden
  diff on re-record is exactly +2 lines; all 19 prior hashes unchanged —
  including `kw/harness`, proving the dead-branch removal is behavior-proof
  (the harness never printed that line, and now it cannot). Teeth: doctored
  killion that always prints `SELFTEST PASSED` flips exactly case 20;
  doctored killion missing the `ambiguous — re-run` hint flips exactly case
  19; cases 01/07/11 stay put under both tampers.
- Line counts: `killion` 191 → 192 (+1 comment), `watch.mjs` 242 (net 0: the
  dead branch out, two why-comments in), `kb_battery.sh` 56 → 62,
  `golden.sha` 19 → 21.

### Iteration 13 — watcher lookup is now the CLI's own `render.jq` (exact mode) (2026-10-30)

- The last duplicated lookup logic is gone: `watch.mjs`'s inline jq program +
  JS daily/party dedup (which had already drifted from `render.jq`'s json mode
  in the `source` label) is replaced by one `spawnSync` of `render.jq` in the
  new `m=exact` mode. Exact-only on purpose: a fuzzy match on a
  server-supplied question could silently show *another* question's answers
  (AGENTS.md: a wrong suggestion mid-round is worse than silence).
  Missing party file degrades via `--slurpfile p /dev/null` (→ empty party),
  so `node watch.mjs` straight from a fresh checkout still works.
- `render.jq` `source` semantics fixed: `daily+party` now means there ARE
  extra party answers, not merely party data (was: any party entry, even when
  every one dedupes against daily). The battery's synthetic entries (Go,
  Rithmomachia) both exist in the real daily list for that question, so case
  03 was emitting a false `daily+party` all along — it now says `daily`.
- Tests: `kw_harness.mjs` now runs three rounds against a pre-seeded party
  file (Go pre-seeded so the dup dedupes and seen merges 1+2=3; Shogi as a
  genuine extra rendered into the tier list; a party-only question; and a
  final round whose text is a *case-variant* of the daily question — exact
  mode must not match it, so a fuzzy fallback would be caught). `kb_battery.sh`
  gained case 21 (`--json` on a question whose party entries all dup daily
  answers → `source` must stay `daily`).
- Verified: golden diff on re-record is exactly 3 lines — `kb/03_json_daily`
  (the intentional source fix), `kb/21_json_dedup_all` (new), `kw/harness`
  (extended scenario); all 18 other hashes byte-identical. Teeth: tampering
  exact mode back to fuzzy flips exactly `kw/harness` (round 3 leaks the
  daily list); reverting `source` to pans-based flips exactly cases 03+21,
  and 03's flipped hash equals its pre-iteration hash (the tamper provably
  is the old code). Suite 3× green: 22/22 golden, 6/6 facts, 2/2 watch,
  2/2 parse, 0.37 s one-shot.
- Line counts: `watch.mjs` 242 → 238, `render.jq` 74 → 80, `run.sh` 200 →
  217, `kb_battery.sh` 62 → 70, `kw_harness.mjs` 92 → 96, `golden.sha`
  21 → 22. Code files net +2; the watcher's daily-lookup + party-dedup rules
  now exist in exactly one program.
- Updated the AGENTS.md files table (watch.mjs + render.jq rows).

### Iteration 14 — golden manifest pins stream discipline (2026-10-30)

- The golden manifest hashed `cat out err` as ONE stream, so a pure
  stdout↔stderr swap changed no hash. That was a real gap, not a pedantry:
  the documented `--json` contract is "print to stdout, pipe to jq" — a
  regression moving the JSON to stderr would silently break
  `killion q --json | jq .a` while every test passed (all 22 golden cases
  are single-stream, so the combined bytes are identical under a swap). Proven
  before fixing: swapped case 03's streams in a temp battery run — combined
  hash identical, separate hashes different.
- `tests/run.sh` `manifest()` now hashes the two streams separately: the
  golden is 4 columns (name, sha of stdout, sha of stderr, exit) and a new
  `sha()` helper replaced the two `cat | shasum` pipelines. Closing standing
  candidate 3 ("if output-stream discipline ever matters for a case").
- Verified: suite green (22/22) before the change; after the change the
  plain run FAILs on the golden diff as designed, and the `--regen` diff
  preserves all 22 names + exit codes exactly (only the hash columns changed
  shape). 17/17 battery cases independently re-verified (fresh battery run →
  per-stream sha256 vs. the new golden columns; the 4 pty cases + the harness
  line are verified by the suite itself). Teeth: the simulated --json→stderr
  swap now FAILS the new manifest (pre-swap line matches, post-swap mismatches)
  while leaving the old combined hash untouched. Full suite 5× green, 0.37 s
  one-shot.
- Line counts: `run.sh` 217 → 223 (+6: helper, per-stream hashes, comment),
  `golden.sha` 22 → 22 lines (now 4 columns).

### Iteration 15 — `render.jq`'s mode decisions bound in one place (2026-10-30)

- The mode logic was scattered string comparisons with a documented trap: a
  new `--arg m` mode had to be added to *both* the match branch and the render
  branch (it bit exactly once — the first `m=exact` attempt in iteration 13 fell
  through to text rendering). Now the two mode decisions are bound once near
  the top — `($m != "exact") as $fuzzy` (substring fallback) and
  `($m != "text") as $json` (JSON-object output) — and the match/render
  branches reference the flags; the header carries the mode table. Adding a
  mode = deciding both values in one spot.
- The first attempt collapsed this to ONE predicate (non-text ⇒ exact+json).
  A/B caught a real regression before the suite did: `killion "Name a" --json`
  lost its candidate list. The mode space is 2-dimensional (match: fuzzy vs
  exact × output: text vs json) with the three modes forming an L-shape — the
  CLI's `--json` is fuzzy by contract (golden case 19's hash equals case 07's,
  pinning the mode-independent ambiguity path), only `exact` is exact-only.
  The 2-flag design preserves behavior exactly.
- Verified: zero golden diff (22/22 — battery, pty copy, and the watch.mjs
  exact-mode harness all byte-identical, suite run 2× green) plus A/B on the
  real repo across 8 branches (text, `--json`, partial, no-match, empty,
  ambiguous text, ambiguous `--json`, `--selftest`): stdout + stderr + exit
  codes all identical.
- Line counts: `render.jq` 80 → 82 (+2: the two named bindings; one match-
  comment line out).

### Iteration 16 — one-shot text output is display-capped, + `--all` (2026-10-30)

- Fixed the biggest remaining usability gap: the one-shot text mode printed
  the ENTIRE answer sheet — up to 32,273 lines (the strategy-board-game
  sheet is 8,049 answers; 657 of the 745 questions have >33) — burying the
  rarest-first "best verified answers" the mode exists for. `text` mode now
  caps each tier group with the `tiers.json` `cap` field (the same caps
  watch's view already used) and appends `… +N more (use --all for the
  full list)` per truncated group, including the party-only unscored section
  (capped at plankton's cap). The 8,049-answer sheet now prints 42 lines.
- New `--all` flag: the full uncapped sheet (the old one-shot behavior,
  now opt-in) — no capability lost. `render.jq` gained a `full` mode
  (fuzzy + uncapped text) which the fzf answer view and `--all` share, so
  interactive search still sees every answer; `json`/`exact` are untouched
  (machine output stays complete). The cap is the third named mode binding,
  `$cap` — adding a mode still means deciding the flags in one spot.
- `watch.mjs`: the `… +N more — ./killion "<q>"` pointer now says `--all`
  (plain one-shot is capped now, so the pointer had to move with it).
- Tests: new battery case `22_all` (the full sheet, byte-pinned); the stub
  fzf now counts its stdin and run.sh asserts the fzf list is the full
  uncapped sheet (8,061 lines for the 8,049-answer question, expected value
  computed from the dataset) — a fzf list that got capped fails the fact;
  the harness dataset gained 4 plankton answers (cap 3) so the drawn
  `--all` pointer line is golden-pinned.
- Verified: A/B — `--all` output byte-identical to the pre-change text
  output (the new `kb/22_all` hash equals the old `kb/02` hash), `--json`
  byte-identical, party-only capped == full when every group is under its
  cap, capped party-only edge (7 rare / 4 plankton / 5 unscored) renders
  correctly; golden diff on re-record = exactly 8 changed lines (01/02/04/
  10 capped, 12/17/18 usage, kw/harness pointer) + 1 added (22_all), all 13
  other cases byte-identical — including the 4 pty copy cases (fzf path
  unchanged) and 19==07 (ambiguity stays mode-independent). Teeth: answer
  view tampered to capped mode fails the new fact (got 42, want 8061); the
  watch pointer reverted flips kw/harness. Suite 3× green; one-shot 0.35 s.
- Line counts: `killion` 192 → 200, `render.jq` 82 → 99, `watch.mjs` 238
  (net 0), `kb_battery.sh` 70 → 73, `run.sh` 223 → 248, `golden.sha`
  22 → 23.

### Iteration 17 — `full_answers.csv` opt-in (`--csv`), `main()` pinned offline (2026-10-30)

- Closed the last standing plan candidate: `download_full.py` no longer
  writes the 44 MB `full_answers.csv` (516,633 rows) on every refresh —
  nothing in the repo consumes it, it was not in the AGENTS.md files table,
  and a full refresh (≈1,100 requests, SLEEP 0.25) was paying a 44 MB write
  + an O(answers) CSV loop for it. New `--csv` flag restores the exact same
  file; `main(with_csv: bool = False)` keeps the function pure, and the
  `__main__` guard parses the flag. The default refresh now writes only
  `full_dives.json` + `official_latest.json`.
- `main()` had **no test at all** (only `parse_cards` was pinned by
  `kd_parse.py`), so the change would have been unverifiable. New
  `tests/kd_main.py` (114 ln) runs `main()` fully offline in a scratch dir:
  stubs `get()` (the 2026-08-31 fixture page + its rosters, and an official
  reveal built from the `full_dives.json` entry of the same page), stubs
  `date.today()` to the day after the fixture (a `datetime.date` subclass;
  the discovery loop finds the fixture on its second step, and the 46
  preceding dive days 404 into the `problems` list), sets `SLEEP = 0`, and
  asserts: `full_dives.json` deep-equals the dataset entry, no CSV without
  the flag, `--csv` writes header + exactly N_ANS rows, `official_latest.json`
  is the raw reveal, and a doctor-ed reveal (one count off) prints MISMATCH —
  pinning the validation section that produces the `--selftest` target.
- Wired into `tests/run.sh` (syntax check + a semantic ok/FAIL block beside
  the parser test); zero golden impact (no CLI/watch output changes — all
  23 golden cases matched without re-recording).
- Verified: standalone run 0.34 s (3/3 asserts); full suite 3× green
  (23/23 golden, 6/6 facts, 2/2 watch, 2/2 parse, 3/3 main, 0.36 s one-shot);
  teeth — three doctored copies each failed exactly as intended: gate
  reverted (CSV always written) → caught, MISMATCH reporting removed →
  caught, CSV points column dropped → caught. Real `full_answers.csv`
  untouched (mtime unchanged), no scratch dirs leaked.
- Line counts: `download_full.py` 175 → 177 (+2), `tests/run.sh` 248 → 260
  (+12), +`tests/kd_main.py` 114. AGENTS.md files table rows for
  `download_full.py` + `tests/` updated.

### Iteration 18 — one shared text-section builder in `render.jq` (2026-10-30)

- De-duplicated the four copies of the "capped slice + rows + `… +N more` +
  blank line" text rendering (daily tier groups, party tier groups, the
  uncapped extras list, the party-only unscored section) into one `sec()` jq
  def + a `capped()` helper: the cap/slice/more-line/blank rules and the two
  row-suffix forms ("quip" → `  — quip`, "seen" → `  (×N)`) now live in
  exactly one place, and a null/missing cap is explicitly "uncapped" (the old
  inline code would have crashed on `length - null` in that unreachable
  region).
- Behavior: byte-identical. A/B battery (HEAD's render.jq vs the new one,
  all 22 cases, fresh temp copies) is byte-identical at the killion level;
  the raw jq stream differs by exactly one trailing blank line in party-only
  mode, which command substitution strips in every consumer (`render()` and
  `one_shot()` both capture via `$(...)`). Golden re-record diff vs the
  pre-iteration golden = exactly 2 lines: `kb/01_text_daily` changed +
  `kb/23_party_overcap` added (why below); all 22 other lines byte-identical.
- The refactor exposed two previously unpinned branches, now pinned:
  - new case `23_party_overcap`: a party-only question over BOTH caps (4
    plankton vs cap 3, 4 unscored vs cap 3) — pins the capped slice, the
    `+N more` line, and the no-×N-suffix on unscored rows;
  - case 01's synthetic party file gained 7 genuine extras on the hair
    question (7 > rare cap 6): the `+ party-verified extras` TEXT section was
    rendered by no battery case at all before — case 02's two entries and
    case 10's entry all dedupe against the daily list, so extras was always
    empty (JSON-mode extras are pinned by the harness's Shogi, but not the
    text section). Now all 7 render uncapped, pinning that too.
- Line counts: `render.jq` 99 → 99 (net zero — a ~20-line builder + 4 short
  call sites replace ~30 lines of triplicated block; the logic is now
  single-sourced), `kb_battery.sh` 73 → 98 (+25: the new pins),
  `run.sh` 260 → 261, `golden.sha` 23 → 24.
- Verified: teeth — a doctored off-by-one slice (`$g[0:($caps+1)]`) and a
  suppressed more-line each flip exactly cases 01/02/23; a final compression
  pass (inlining `moreline` into `sec`, one-line call sites) was proven
  behavior-identical by the suite passing WITHOUT re-recording the golden.
  Suite 4× green (24/24 golden, 6/6 facts, 2/2 watch, 2/2 parse, 3/3 main,
  0.36 s one-shot). Note: the owner's live `killion watch` session recorded
  real answers into the repo's `party_answers.json` mid-iteration (8
  questions, 57 entries dated today) — expected per AGENTS.md ("the dataset
  grows with play"); it never affects the suite (everything runs on temp
  copies) and was left in place.

### Iteration 19 — cached fzf question list: interactive startup 0.35 s → 0.04 s (2026-10-30)

- `killion qlist()` now serves the dataset half of the fzf question list
  from a cache (`questions.txt`, gitignored): regenerated when missing or
  when `full_dives.json` is newer than the cache (refresh or hand-edit),
  written temp+mv so a partial write never sticks. Party-only questions
  still come straight from `party_answers.json` keys every time (small file,
  no cache). This closes the last standing plan candidate — the "derived
  cache risks going stale" objection is answered by the mtime check: every
  way the dataset can change (refresh via `download_full.py`, hand edit,
  file restore) makes it newer than the list, and a deleted/absent list
  self-heals on the next interactive run.
- Cost: the 0.35 s startup pass is paid exactly once per dataset change
  (first interactive run after a refresh), then ~20 ms cache read +
  `sort -u`. Measured: interactive startup (real `killion` on a pty with a
  stub fzf that exits) 0.345–0.352 s before → 0.043–0.045 s warm after;
  742-line list file.
- Output-neutral by design: one-shot mode never reads the cache (it
  searches the dataset directly), so `--json`/`--all`/selftest/watch are
  untouched. Proof: `tests/run.sh` passed WITHOUT re-recording the golden —
  all 24 golden cases byte-identical, including the 4 pty copy cases.
- Tests (`tests/run.sh`, 3 new semantic checks; the stub fzf now captures
  the question list it is fed on the first search):
  - `qcache: fresh copy self-heals` — case 13 runs on the pristine temp
    copy (no `questions.txt`); the captured list must equal
    dataset-questions ∪ party-keys computed fresh;
  - `qcache: fresh cached list is used` — plant a `ZZZ qcache probe` line
    in a just-written (hence newer) list: it survives in the captured list
    only if the cache was used, not regenerated;
  - `qcache: stale list regenerated` — same probe list, but its mtime
    backdated with `touch -t` so the dataset is newer: the probe must
    vanish and the list must equal the fresh computation.
- Teeth: doctored guards each flip exactly the right check —
  `if [[ ! -f $QLIST ]]` (no mtime check) → "stale list not regenerated"
  FAIL; `if true` (always regenerate) → "fresh cached list ignored" FAIL.
- Line counts: `killion` 200 → 205 (+5 net: QLIST var, cache guard,
  comments), `run.sh` 261 → 298 (+37 net: stub capture + 3 checks),
  `.gitignore` +2, `golden.sha` unchanged (24 lines — the output-neutrality
  proof).
- Docs: AGENTS.md (killion bullet, files table + `questions.txt` row,
  performance note), plan (qlist candidate removed).
- Verified: suite 3× green (25 ok: 24/24 golden, 6/6 facts, 2/2 watch,
  2/2 parse, 3/3 main, 4/4 copy, 3/3 qcache, fzf sheet, timing 0.36 s),
  both teeth tamper runs fail exactly once each.

### Iteration 20 — no-trace hygiene: `-f` jq invocation everywhere, suite stops littering (2026-10-30)

- `killion` `lookup()` was the last jq consumer that passed the program as a
  `RENDER=$(cat render.jq)` string; it now uses `jq -r -f render.jq` — the
  pattern `selftest()` already used, so both CLI jq paths invoke identically
  (and the `jq -f` rule of thumb now covers every program-file call in the
  repo). The startup `cat` and the `RENDER` variable are gone (−2 lines).
- `watch.mjs` `lookup()` did `readFileSync(RENDER_FILE, 'utf8')` into a
  program string on every category change; it now passes `-f RENDER_FILE`
  (net 0 lines: one read call out, one flag in).
- The test suite itself had a working-tree side effect: `kd_parse.py` /
  `kd_main.py` do `sys.path.insert(0, ROOT)` + `import download_full`, so
  every `tests/run.sh` run regenerated `__pycache__/download_full.cpython-315.pyc`
  in the repo dir (gitignored, but litter the tool shouldn't leave). Both
  now set `sys.dont_write_bytecode = True` before the import (+1 line each);
  the stale `__pycache__/` was deleted. (Iteration 7's in-memory `compile()`
  trick only fixed the *syntax-check* path — the real import still wrote a
  pyc.)
- Verified: A/B vs the pre-change code — one-shot text / `--json` / ambiguous
  / `--selftest` / `--help` all byte-identical; suite 3× green WITHOUT
  re-recording the golden (all 24 kb cases + `kw/harness` — the harness's
  exact-mode lookup now runs through the `-f` path, so that change is
  pinned by the golden, not just A/B); `__pycache__` absent after three
  consecutive runs; one-shot 0.349 s (unchanged); `bash -n` + `node --check`
  clean.
- Line counts: `killion` 205 → 203, `watch.mjs` 238 → 238 (net 0),
  `kd_parse.py` 63 → 64, `kd_main.py` 114 → 115 (net 0 across the repo).

### Iteration 21 — locale-proof writes in `download_full.py`, pinned by a POSIX/C-locale suite run (2026-10-30)

- Promoted the last standing plan candidate (it was the only actionable one
  left): the three `download_full.py` write sites had no explicit
  `encoding="utf-8"`. On Python ≥ 3.15 (PEP 686, UTF-8 default) that is
  invisible, but on older Python under a POSIX/C locale the default text
  encoding is ASCII and `json.dump(..., ensure_ascii=False)` — the dataset
  has 16,200 non-ASCII answers/quips — crashes **mid-dump of
  `full_dives.json`**, leaving killion's dataset half-written after a
  failed refresh. Proven, not hypothetical: `PYTHONUTF8=0
  PYTHONCOERCECLOCALE=0 LC_ALL=C` reproduces a US-ASCII Python on this
  machine, and the pre-fix code died there with a `UnicodeEncodeError`
  (line 138, mid-dump).
- All three write sites now pass `encoding="utf-8"`; the bare
  `open("official_latest.json", "w").write(...)` also became a `with` block
  (explicit close, consistent with the other two). `tests/kd_main.py`'s own
  CSV read got the same keyword (the harness must not be locale-dependent
  itself), and its three prints lost an em dash (US-ASCII stdout is strict —
  the test's own output crashed the hostile-locale run before the fix).
- New `tests/run.sh` check: re-runs the offline `kd_main.py` under
  `PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 LC_ALL=C` and requires exit 0 — a
  write site that loses its keyword now fails the suite, not just an older
  Python in the wild. The fixture's "Yaoundé" answer gives both the
  `full_dives.json` and CSV writes teeth; the `official_latest.json` write is
  pinned by content equality (the fixture's prompt texts are all ASCII, but
  real official reveals can carry non-ASCII question text).
- Verified: teeth — reverting either teeth-bearing encoding in a temp copy
  makes the hostile run die with the exact `UnicodeEncodeError` (both caught);
  full suite 3× green including the new check; the 24 golden cases match
  WITHOUT re-recording (the change touches no CLI/watch output — the
  manifest itself proves output neutrality); `--selftest` PASSED, one-shot
  0.34 s, no stray `__pycache__`.
- Line counts: `download_full.py` 177 → 181 (+4: 3 comment lines + the `with`
  block), `kd_main.py` 115 (net 0), `run.sh` 298 → 310 (+12).
- Docs: AGENTS.md tests row mentions the POSIX/C-locale run; the encoding
  standing candidate is removed from the plan.

### Iteration 22 — single source for mode documentation: `usage()` (2026-10-30)

- The `killion` file header (lines 3–21) duplicated the `usage()` text at
  ~80%: both enumerated every mode and flag. It was a live trap — both
  iteration 11 (`-h/--help`) and iteration 16 (`--all`) had to update both
  places when adding a flag. The header now says 3 lines (what the tool is,
  "modes: killion --help", data files) and `usage()` is the single source.
- Nothing was lost: the header's unique operational details moved into
  `usage()`'s interactive line (Enter on question → answers, Enter on answer
  → copy, Esc in answers → back with query kept, Esc in search → quit) and
  the watch line ("minus what's already been said"), which `usage()` lacked;
  the data-regeneration note stays in the header (maintainer info, not user
  usage). The "party categories accumulate over time" why-clause lives in
  AGENTS.md and was not duplicated.
- `killion` 203 → 191 lines (−12).
- Verified: `bash -n`; the pre-regen suite run drifted on EXACTLY the 3 usage
  golden lines (12/17/18) with all other 21 cases byte-identical, and the
  post-regen diff vs the old golden is those 3 lines only, names + exit-code
  columns byte-identical (12 → exit 2, 17/18 → exit 0). The three emitters
  still share one hash (12's stderr == 17's stdout == 18's stdout), proving
  one `usage()` renders byte-identically on every path. Suite 3× green after
  re-recording; bare-machine check: `--help` still exits 0 in a dir with no
  dataset/fzf and creates no files.

### Iteration 23 — interactive answer-view cache: re-Enter on the same question is instant (2026-10-30)

- Landed the plan's named "first win" for the conditional index step:
  interactive mode re-ran the ~0.3 s full-mode dataset pass on every Enter,
  including Esc-back-and-re-Enter on the *same* question. `view_ready()` now
  keeps the rendered sheet per question in a main-shell `declare -A VIEW`
  (old `render()` deleted; `answer_view` pipes the cached text itself — see
  the subshell note below), so re-Enter is instant.
- Staleness: a concurrent `killion watch` records accepted answers into
  `party_answers.json` *between rounds* — the realistic case where a cached
  view of the current question goes stale mid-session. `VIEW_EPOCH` (a
  `mktemp` marker file created in `interactive()`, removed by a function-local
  `RETURN` trap) invalidates the whole cache when `full_dives.json` or
  `party_answers.json` is newer than it; the marker is touched after each
  fresh lookup. The marker file + `[[ -nt ]]` is used on purpose: bash
  compares mtimes at full precision, while an mtime *string* (stat) is
  second-granular and a same-second flush would slip through.
- Tests (`tests/run.sh`): the pty section gained a `jq` stub that logs every
  invocation to `KSTUB_JQLOG` and `exec`s the real jq (resolved in run.sh's
  PATH, where `$B/bin` is absent — the stub must not resolve itself), and the
  fzf stub gained an answers-view visit counter (`KSTUB_ANS`; 2nd visit = Esc
  130), a `KSTUB_REPEAT` scenario (hit → answer → esc-answers → hit → answer →
  esc) and an optional `KSTUB_TOUCH_PARTY` (touches the party file during the
  first answer view, simulating the watcher's between-rounds flush). Two new
  semantic checks (not golden lines — the clipboard bytes equal case 15's):
  `viewcache: second Enter … (1 lookup)` and `viewcache: party rewrite
  invalidates … (2 lookups)`.
- Teeth, both directions: the new flow run against HEAD's `killion` (no
  cache) fails exactly `viewcache: second Enter` (2 lookups, want 1); the new
  `killion` with the invalidation disabled fails exactly `viewcache: party
  rewrite` (1 lookup, want 2). Wall clock on the same Enter-twice pty flow
  (alternated to cancel cold-cache bias): old 0.81–1.17 s vs new 0.52–0.87 s —
  consistently ≈0.3 s (one dataset pass), matching the count assertion.
- Verified: full suite 3× green; all 24 golden cases match WITHOUT
  re-recording (the change touches no user-facing bytes — the manifest itself
  proves output neutrality); `bash -n` clean; one-shot 0.36 s unchanged.
- Line counts: `killion` 191 → 209 (+18: cache + epoch + comments),
  `tests/run.sh` 310 → 349 (+39: stubs + checks), `golden.sha` unchanged (24).
- Docs: AGENTS.md killion bullet + performance note mention the view cache.

## Known issues (accepted as-is; follow-ups)

- `watch.mjs` reconnect double-counts `seen` (accepted as-is, 2026-10-30).
  Sequence: mid-round disconnect → the reconnect's snap re-delivers the
  current round's event log + players → `applyEvents()` and the snap
  handler's `addSaidFromPlayer()` re-record the same accepted answers (the
  in-memory `recorded` map survives the disconnect) → the next flush writes
  an inflated `seen` count: each 1.5 s blip adds +1 per accepted answer (a
  round with 3 accepted answers and one blip records seen=2 for each). The
  answers themselves stay game-verified (only the decorative `seen` / `(×N)`
  count drifts up), so suggestion accuracy is unaffected. Proposed minimal
  fix: a per-round counted-answer set, cleared on the new-round patch.

## Plan (next steps, roughly in order)

1. If the mirror site changes its format, `kd_parse.py` fails first:
   re-fetch the fixture page + rosters for the affected date and re-record.
   If a genuinely new card branch appears, extend the fixture choice.
   (`kd_main.py` reuses the same fixture, so both suites stay in sync.)
2. Only if jq ever stops being fast enough: precomputed index (per AGENTS.md
   — don't add a runtime). The per-question interactive view cache landed in
   iteration 23 (re-Enter is instant); the remaining costs are the first view
   of a question, the one-shot lookup, and `--selftest` — all single dataset
   passes that an index would serve.

Standing candidates (not yet worth an iteration on their own):
- Mode/flag documentation for `killion` lives in exactly one place, `usage()`
  (the header comment only points at it): add a mode or flag → edit `usage()`
  only, then re-record the 3 usage golden lines (12/17/18 share one hash —
  an emitter that drifts from the others flips the shared-hash consistency).
- Mined in iteration 22, judged not worth an iteration: `watch.mjs` computes
  the alive-player count in both `sig()` and `draw()` (one line each); the
  44 MB `full_answers.csv` in the working tree is untracked/gitignored, so
  deleting it frees only local disk (owner preference, not repo bloat).
- `render.jq`'s mode decisions are the three named bindings (`$fuzzy`, `$json`,
  `$cap`) near the top: adding a mode = decide all three there + add a header
  row. Unknown `m` values get fuzzy+JSON (the safe default for non-interactive
  callers); no caller passes anything but text/full/json/exact. Caps are a
  display-surface decision: text (capped) is for terminals, full/json/exact
  stay complete. All four text sections (daily tier, party tier, extras,
  unscored) render through the one `sec()` def — a display change to caps,
  row suffixes or the more-line belongs in `sec`, not at the call sites.

## Rules of thumb learned

- bash `$(...)` strips trailing newlines: when comparing jq output captured
  raw vs. through command substitution, normalize both sides or outputs will
  appear to differ by one blank line.
- In jq, `($arr | index(.field))` rebinds `.` to the array — capture the
  field first (`.field as $t | ($arr | index($t))`).
- Before refactoring a renderer: capture end-to-end baseline output for
  every branch (daily, daily+party, party-only, no-match, empty party file)
  and diff after; that is the whole safety net here.
- jq `index("")` is `null` (no empty substring), but `grep -Fx ""` matches
  every line — empty-query behavior diverges between the two matchers.
- jq `unique` sorts by codepoint; macOS `sort -u` uses locale collation —
  different order for case-variant duplicates (cosmetic for a candidate list).
- `A | unique as $x | B` gives B the input of `unique` (the pre-unique
  value), not $x — capture the data file first (`. as $dives`) and use it
  explicitly in B.
- Bash variables cannot hold NUL bytes — use `\x01` for out-of-band markers
  in command-substituted output.
- `tojson` and `jq -c` produce byte-identical serialization, so a jq program
  can emit a JSON object as a single string through one `jq -r` invocation.
- A jq program ending in an *array of strings* prints the whole JSON array
  even under `jq -r` (−r only unwraps top-level strings) — finish with
  `| .[]` to get one line per element.
- `jq -r -f prog.jq` reads the program straight from a file — no shell
  variable or `$(cat)` needed for a per-invocation program.
- jq `a // b` falls back only on null/false — a legitimate 0 count survives
  `($map[$k] // -1)`.
- jq object indexing with `null` is a hard error ("Cannot index object with
  null"), unlike an unknown string key which yields null — guard
  null-valued keys with `$x // ""` before indexing.
- jq `def` cannot capture runtime variables (no closures), so data-driven
  lookups from a slurpfile must be plain `as` variables referenced in the
  body, not `def`s.
- Reusable 12-case battery (temp repo copy + synthetic party file, capture
  stdout/stderr/exit per branch) is the standard render safety net — baseline
  first, `diff -r` after; it caught the null-tier crash that four iterations
  of byte-identical refactors had left latent.
- As of 2026-10-29, question texts are unique across the whole dataset
  (0 duplicates), so first-occurrence lookups and multi-day lookups agree;
  the selftest keeps first-occurrence semantics anyway, matching the old
  `.[0] // -1`.
- watch.mjs record semantics differ by source and must be preserved: `pass`
  events are recorded *unconditionally* (duplicate events in the log count
  multiple times in `seen`), while a player's `lastAnswer` is recorded only
  when the answer is new to the round.
- Node gotcha: `process.kill(self, SIGTERM/SIGINT)` dispatches the registered
  handler only if a ref'd handle keeps the event loop alive; otherwise the
  process exits 0 silently without running it — add a keepalive `setTimeout`
  when self-signaling in a test harness.
- Offline `watch.mjs` testing pattern: stub `globalThis.fetch` and
  `WebSocket` (class whose constructor captures the instance), feed scripted
  `onmessage` payloads, capture stdout via a `process.stdout.write` override,
  and SIGTERM at the end to trigger `flush()`; diff stdout + the party file
  between base and new versions for behavior-proof equivalence.
- `[[ $VAR ]]` tests string truthiness: `[[ 0 ]]` is TRUE (non-empty) — use
  `[[ $VAR -eq 1 ]]` for numeric flags. This bug let a plain (non-`--regen`)
  `tests/run.sh` run re-record the golden until caught by re-running.
- A pipeline's exit status is its last command's: `if diff … | sed …; then`
  always took the `then` branch — capture diff to a file and test its exit
  code, never a piped exit status.
- Python 3.15: `PYCACHEPREFIX` did NOT redirect `py_compile` output for an
  explicit source file (the pyc still landed in the source dir's
  `__pycache__/`) — use an in-memory `compile(open(f).read(), f, "exec")` for
  a zero-artifact syntax check.
- Golden-file workflow for output-stable tools: per-case sha256 + exit in one
  small manifest file (`tests/golden.sha`), `--regen` to re-record after
  intentional changes, leave the workdir on failure for inspection. Content
  goldens would have cost ~700 KB of repo bloat; the harness party file is
  asserted semantically because it embeds today's date.
- A stub fzf in tests must drain stdin (`cat >/dev/null`) before exiting:
  real fzf always reads all input, but a stub that exits early makes the
  producer (render → jq) SIGPIPE, and with `pipefail` the command-substitution
  rc becomes 141 — the copy branch never ran on first harness runs for
  exactly this reason.
- `script -q <file> bash -c '…'` (BSD/macOS) gives the child a real pty
  (both `-t 0` and `-t 1` true), so the fzf-gated interactive path runs
  headless; combined with a stubbed fzf (scripted selections via a call-count
  state file) and a stubbed pbcopy (`cat > file`) the whole interactive loop
  is testable deterministically, with no keystroke driving and no real fzf
  flakiness.
- macOS `script` transcripts start with a `^D` (0x04) byte glued to the first
  output line — extract what you assert with `grep -o` instead of raw lines,
  or the golden hashes pty noise.
- macOS `sed` (BSD) silently ignores the GNU `0,/re/` address form — a
  doctored-file tamper applied nothing and the "negative" test passed; use
  Python for reliable file tampering in test scripts.
- When choosing a test fixture, verify it actually exercises every branch
  you claim it pins (count branch markers in the fixture, not just the
  parser's success): a page with zero quips left the whole quip branch
  unpinned despite a byte-exact round-trip.
- A parse test that asserts deep equality against a dataset entry generated
  from the same source page is self-validating: the first green run
  simultaneously proves the fixture is intact and pins the parser.
- `re.finditer` yields matches in document order, so an explicit
  `sort(key=start)` over `finditer` results is redundant.
- A stubbed WebSocket in a test harness must hold a ref'd handle while "live"
  (and lose it on close), mirroring a real socket: without that, the harness
  process's own loop stays alive and silently masks "process exits early" bugs
  (and a ref'd watchdog lets a buggy unref'd retry timer still fire).
- `setTimeout(...).unref()` means "don't keep the process alive for me" — for
  the *only* remaining handle after a disconnect (a retry timer) that kills the
  process before the timer fires. Ref'd-ness is part of a timer's behavior, not
  an implementation detail.
- A test that asserts "the process is still alive at time T" needs its own
  watchdog unref'd, so only the code under test can keep the loop alive; the
  assertion is then the watchdog firing at all.
- Node signal handlers (`process.on('SIGINT'/'SIGTERM')`) do NOT keep the
  event loop alive (verified directly on Node 26) — so after the last
  ref'd handle (a socket) dies, only ref'd timers keep the process running;
  this is also why a self-sent SIGTERM needs a ref'd handle to be dispatched.
- Hash stdout and stderr *separately* in the golden manifest (one sha per
  stream, not `cat out err`): the stream is part of the contract (--json must
  land on stdout for `| jq`), and a pure swap is byte-identical when combined
  — every golden case here is single-stream, so a combined hash is blind to
  stream discipline in all of them.
- Python `str.replace` is a silent no-op when the pattern is absent — stack
  tampers on a fresh clean copy, or `assert pattern in s` first; a second
  tamper written against the pre-first-tamper text matches nothing. And when
  the replacement text carries a `# comment`, it must not sit before more
  code on the same line — a tamper written as `… )   # TAMPER` where the line
  continued with `then` commented out the `then`, jq failed to parse, and the
  whole battery flipped (looking like a massive behavior change instead of a
  syntax error); use a unique pattern that ends the code segment, or assert
  `s.count(pat) == 1` and keep the line self-contained.
- A synchronous lookup (spawnSync) makes any "looking up…" UI state
  unreachable — the branch was dead the moment the lookup stopped being
  async; prove unreachability from the harness transcript before deleting,
  and re-check after any change that makes the lookup async.
- When a tamper meant to restore legacy behavior flips a case's hash *back to
  the pre-change hash*, the tamper is provably the old code — a strong
  equivalence check for behavior-preserving refactors.
- `render.jq`'s mode space is 2-dimensional (match: fuzzy vs exact × output:
  text vs json); the three modes are an L-shaped subset (text=fuzzy+text,
  json=fuzzy+json, exact=exact+json). Collapsing it to one predicate silently
  turned `--json` from fuzzy to exact-only — the golden (case 19's hash ==
  case 07's) pins that `--json` stays fuzzy, and the A/B branch set catches it
  earlier with a clearer diagnosis.
- `--slurpfile p /dev/null` is a clean "empty JSON array" source in jq (empty
  file → no values → `$p[0]` undefined) — the cheap way for a caller to pass
  "no data" for a required slurpfile without temp files.
- A jq program with no input file reads STDIN: an expected-value jq call in a
  test runner that forgets the data-file argument silently yields an empty
  string (and `set -u` does not catch an assigned-but-empty variable) — the
  failure looked like "got 42, want " until the missing argument was spotted.
- Command substitution strips ALL trailing newlines: a text renderer whose
  output ends in a blank line loses exactly that line when captured with
  `$(...)` and re-emitted via `printf '%s\n'` — expected line counts for the
  captured stream must subtract one.
- When a display cap lands on one surface, audit the other surfaces' pointers
  in the same pass: watch's `more — ./killion "<q>"` line pointed at the
  one-shot that had just become capped, and silently pointed at the wrong
  (capped) view until it moved to `--all`.
- Offline-testing a `main()` that does date-walking network loops: monkeypatch
  the module's `get`, `SLEEP` (→ 0), and `date` (a `datetime.date` subclass
  whose `today()` returns a fixed date one step before the fixture), run it in
  a `tempfile.mkdtemp` scratch dir (it writes outputs with relative paths,
  so `chdir` first and restore in `finally`), and build the official-reveal
  stub from the dataset entry the fixture was recorded from — the whole
  1,100-request refresh then runs in ~0.3 s with zero network.
- An opt-in flag for a side-effecting output (44 MB CSV) is the
  keep-functionality form of "drop it": the default path loses the write, the
  flag preserves byte-identical behavior, and the gate is exactly what the
  main() test asserts (no file without the flag, full file with it).
- jq user-defined function ARGS are evaluated EAGERLY in the caller's context
  — unlike builtin `map` (which takes a closure), you cannot pass a row
  formatter as a function arg to a user def (`f(xs; .a)` evaluates `.a` once
  against the caller's input). Pass data (a kind string) and branch inside
  the def instead.
- jq `def` syntax is `def name(args): body;` — the definition is terminated
  by a SEMICOLON, not `end` (that token belongs to `if/elif/else`). `def f:
  … end;` is a parse error ("unexpected end"); nothing in this repo had used
  a def before, so there was no local example to copy.
- Because jq function args are eager, a header built from `$g[0].pts` crashes
  on an empty group BEFORE the def's internal empty-check runs — keep the
  caller-side `select(($g|length)>0)` guard; the def's own check is a belt.
- `A + (X | .[])` with X an array is a runtime error ("array and string
  cannot be added"): the flattened stream is only valid inside a `[ … ]`
  construction; in a `+`-concatenation context the callee must return the
  array.
- `kb_battery.sh` A/B reuse gotcha: the battery docters `official_latest.json`
  at the end (case 20) and never restores it — a second run in the same dir
  sees the tampered file (case 11 MISMATCHes, case 20's count increments per
  run). Restore the file between A/B runs, as run.sh's fresh-copy design does.
- Probe-line pattern for cache tests: plant a line in the cached file that
  the canonical computation could never emit (a `ZZZ …` probe). Run the
  consumer and grep the captured input: probe present ⇒ cache used, probe
  gone ⇒ regenerated. One grep discriminates the two paths, and the
  regenerated content is separately diffed against the fresh computation.
- To simulate a stale file deterministically: `touch -t 202601010000.00`
  (explicit past mtime) — no `sleep`, no dependence on filesystem mtime
  granularity (a same-second write+touch would make `-nt` see "not newer"
  on a coarse-grained fs).
- `sys.dont_write_bytecode = True` set *before* a `sys.path.insert` +
  `import` is the zero-artifact import guard: unlike the in-memory
  `compile()` trick (which syntax-checks without importing), it lets the
  test run the real import machinery while keeping the repo litter-free.
- Output-neutrality of an internal change is proven by the manifest itself:
  if a change touches no user-facing output, `tests/run.sh` passes without
  `--regen` — all 24 golden hashes stay identical (no re-record needed,
  which would have papered over an accidental output drift).
- Reproducing a locale-hostile Python on PEP 686 (3.15) macOS needs BOTH
  `PYTHONUTF8=0` (3.15's UTF-8 mode is default-on) and `PYTHONCOERCECLOCALE=0`
  (PEP 538 would otherwise auto-coerce the C locale to C.UTF-8) plus
  `LC_ALL=C`: only then is the default text encoding US-ASCII and an
  un-encoded `open(…, "w")` of non-ASCII data crashes with
  `UnicodeEncodeError` — a deterministic teeth-check for explicit-encoding
  write sites, without needing an older interpreter.
- An offline test of a locale-sensitive function must be locale-proof in its
  OWN output too: `kd_main.py` crashed the hostile-locale run on an em dash in
  its `print` (US-ASCII stdout is strict) even after the code under test was
  fixed — harness prints must be ASCII (or explicitly encoded), and the
  fixture must actually contain the non-ASCII byte your check claims to pin
  ("Yaoundé" does; the fixture's prompt texts are all ASCII, which is why the
  `official_latest.json` write is pinned by content equality instead).
- A pipeline component runs in a SUBSHELL: a cache helper called as
  `helper | fzf` loses every global write it makes (`declare -A` cache,
  epoch touch — all silently dropped when the subshell exits). Keep the
  cache update in the main shell (a helper called *before* the pipe, with the
  caller piping the cached variable) — the first render-cache attempt "passed"
  the invalidation test while the hit test caught it.
- The word `false` inside `[[ ]]` is a NON-EMPTY STRING (true), not the
  command `false`: "disabling" a tamper condition via
  `str.replace(pat, "false")` left it enabled (xtrace showed `[[ -n false ]]
  → VIEW=()` on every call). Use a reliably-false expression such as
  `[[ false == true ]]`, or delete the block; a `bash -x` trace of the
  suspect function is the fastest way to see what a tamper really did.
- bash's `-nt` compares file mtimes at FULL precision (stat(2)), while an
  mtime string (stat/glob) is second-granular — for sub-second cache
  invalidation (a watcher flush between two user Enters), use a marker file
  + `[[ file -nt marker ]]` + `touch marker`, not a stored timestamp string.
- A stub binary that must count its own invocations without changing
  behavior: log `"$*"` to an env-gated file, then `exec` the real binary by
  ABSOLUTE path resolved at stub-creation time (the stub's own dir is first
  in PATH, so `command -v` inside it would find itself).
