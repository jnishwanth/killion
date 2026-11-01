# killion

A personal helper for playing Krillion (krillion.io) Puffer Party lobbies.
It tells you, fast, the best answers to the question currently on the
table — using only answers the game itself has verified.

This document describes what the tool *is for*, not how it must be built.
Today's implementation is a starting point: change any part of it — the
language, the tools, the architecture — whenever that gives an objective
improvement (faster, simpler, more robust, less detectable, more data).

## Main objectives (the only hard requirements)

1. **Invisible.** The tool must leave no trace in the game: it never appears
   in the lobby UI, player list, or chat; it never joins, never holds a seat,
   never submits, never acts. Read-only, from the outside. If a future change
   increases detectability in any way, it's wrong no matter what else it
   improves.

2. **Only game-verified answers.** Everything shown must have been accepted
   and scored by the game itself (daily reveal data, or recorded from a live
   room). No LLM guesses, no "probably valid", no fabricated entries. When
   there is no verified data for a question, say so plainly and stop. A wrong
   suggestion during a live round is worse than silence.

3. **Fast.** It is used mid-round while a puffer timer runs. Lookup should be
   near-instant on the owner's machine. If a change is objectively faster, it
   wins, even over smaller diffs.

4. **Simple and maintainable.** One person (plus their agents) maintains this.
   Small files, obvious code, no surprise dependencies, nothing that needs a
   build step or a service. Prefer the design that the next maintainer will
   understand in one sitting.

Everything else — file layout, tooling, data formats — is current opinion,
open to change.

## What it does today

- `killion` (bash + fzf + jq): fuzzy-search the known questions, show the
  best verified answers rarest-first, Enter copies an answer to the
  clipboard. The interactive question list is a self-regenerating cache
  (`questions.txt`, gitignored) so startup skips the dataset pass, and the
  answer view is cached per question (re-Enter on the same question is
  instant; the cache invalidates when a data file is rewritten). One-shot
  mode for scripts; its text output is display-capped per tier (like
  watch's view), `--all` lifts the caps, `--json` is always complete.
  `-h/--help` prints usage (works even without fzf or the dataset).
  `--selftest` validates the dataset against the official API.
- `killion watch <CODE>` (node ≥ 22, stdlib): watches a lobby's live
  question and shows the best verified answers, minus what players have
  already said this round. It reads the room's live stream anonymously —
  the stream is not gated on membership, so no join is needed and nothing
  is visible.
- **Recording:** every accepted answer seen in a room arrives pre-scored by
  the server; watch records it into `party_answers.json`. The dataset grows
  with play, so party-only categories accumulate real answers over time.

## Files

| file | job |
|---|---|
| `killion` | CLI entry: fzf interactive, one-shot lookup, `watch` dispatch, `--selftest`, `--check-party` |
| `watch.mjs` | live room watcher + recorder (answer lookup is the CLI's `render.jq` in exact mode) |
| `render.jq` | query match (exact, else case-insensitive substring; exact-only for watch) + answer-list rendering — capped text for one-shot, full text for fzf/--all, JSON for --json/watch (single jq pass, shared by CLI and watcher) |
| `selftest.jq` | dataset validation for `--selftest` (single jq pass) |
| `check_party.jq` | party-dataset review list for `--check-party`: entries daily-verified for another question (single jq pass) |
| `tiers.json` | shared tier table (order, names, icons, points, display caps) used by `render.jq`, `watch.mjs`, `download_full.py` |
| `party_answers.json` | earned record of game-verified party answers (append-only by design) |
| `full_dives.json` | daily-dive dataset: all dives since launch, every accepted answer + tier |
| `questions.txt` | fzf question list cache (gitignored; killion regenerates it when missing or stale vs `full_dives.json`) |
| `download_full.py` | refreshes `full_dives.json` from public data (the only Python; stdlib only; writes land next to the script — CWD-independent, atomic tmp+rename; `--csv` opt-in also writes `full_answers.csv`) |
| `official_latest.json` | latest official API reveal; target of `--selftest` |
| `tests/` | offline test suite: `tests/run.sh` runs the CLI/render battery + a stubbed-WebSocket `watch.mjs` driver against `tests/golden.sha`, plus offline `download_full.py` parser (`tests/kd_parse.py`) and main (`tests/kd_main.py`, stubbed archive + `date.today` + `df.HERE`; pins CWD-independent atomic writes; also re-run under a POSIX/C locale to pin the explicit utf-8 writes) tests vs a real archived dive page in `tests/fixtures/` — no network, no live room |

## Protocol facts (as observed; re-verify if something breaks)

The server can change any of this. Treat it as measured knowledge, not
spec.

- `GET krillion.io/api/party/token` → anonymous guest token (no account).
- `GET krillion.io/api/reveal?date=YYYY-MM-DD` → full answer sheet, but only
  for the latest completed daily dive.
- Party service `party.krillion.io`: `POST /rooms` (create),
  `POST /rooms/{code}/join`, `POST /rooms/{code}/act`, and the live room
  stream `wss://party.krillion.io/rooms/{code}/ws?key=<playerKey>&token=<guestToken>`.
- **The room stream is not gated on membership** — any guest token plus any
  key receives the full room state (players, phase, category, events). This
  is why the watcher is invisible. If the server ever starts rejecting
  anonymous streams, the fallback is joining with auto-join disabled
  (spectator state: `0 lives`, never in a game) — visible in the UI, so only
  as a last resort.
- One connection per playerKey; a second connection with the same key closes
  both (`4403`). Never mirror the owner's browser session.
- `act` must carry the actor's own guest token. `holderId` is a playerId, not
  a playerKey. Full rooms (6/6) refuse joins.
- Accepted answers surface as `players[].lastAnswer = {text, tier}` and as
  events `{kind:"pass", answer, tier}`; submit responses echo
  `{accepted, answer, tier}`. These are the recording inputs.
- Tiers: krillion 100 · deepcut 85 · rare 60 · schooler 30 · tooclever 15 ·
  plankton 10.

## Notes for future work

- The dataset currently covers the daily-dive questions in `full_dives.json`
  (refreshed and reported on by `download_full.py`) plus whatever has been
  recorded from lobbies. Party-only categories will be "no verified
  data" until recorded — that gap is expected and closes with use.
- Performance today: jq over the 35 MB dataset is ~0.3 s cold for a lookup;
  interactive startup no longer pays it (the fzf question list is cached in
  `questions.txt`), and neither does a re-Enter on the same question
  (per-question answer-view cache, invalidated on data-file rewrite).
  If one-shot speed ever stops being good enough, precompute an index —
  don't add a runtime for it.
- Keep request volume to the party service modest and idle (one room stream,
  low patch frequency). It's a hobby game server; be a quiet client.
