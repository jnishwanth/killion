# killion

A personal helper for playing Krillion (krillion.io) Puffer Party lobbies.
It tells you, fast, the best answers to the question currently on the table —
using only answers the game itself has verified.

## Setup

Requirements: `bash`, `jq`, `fzf`, `node`, `python3` (macOS `pbcopy` for the clipboard).

```sh
git clone git@github.com:jnishwanth/killion.git
cd killion
python3 download_full.py   # fetch the full answer dataset (full_dives.json)
```

`full_dives.json` and `official_latest.json` are generated and gitignored —
re-run `python3 download_full.py` whenever a new daily dive lands.

## Use

```sh
killion                      # interactive: fuzzy-search questions, Enter shows
                             # verified answers rarest-first, Enter on an answer
                             # copies it to the clipboard; Esc goes back/quits
killion "Name a fruit"       # one-shot: best verified answers, display-capped
killion "Name a fruit" --all # one-shot: full sheet, uncapped
killion "Name a fruit" --json  # one-shot: raw JSON (pipe to jq)
killion watch ROOMCODE       # watch a Puffer Party room live (invisible, takes
                             # no seat): verified answers minus what players have
                             # already said; records every accepted answer
killion --selftest           # validate the dataset against the official reveal
```

- `party_answers.json` grows from `killion watch`'s recordings, so party-only
  categories gain real answers as you play.
- If there is no verified data for a question, it says so — it never guesses.
- Offline test suite: `tests/run.sh` (skips dataset-dependent cases on a
  machine without the dataset).
