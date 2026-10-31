#!/usr/bin/env bash
# killion offline test runner — both safety nets in one command.
# No network, no live room; runs against a temp copy, so the real
# party_answers.json is never touched.
#
#   tests/run.sh          run everything, compare against tests/golden.sha
#   tests/run.sh --regen  re-record the golden from current behavior — only
#                         after an intentional output change, and review the
#                         golden.sha diff together with that change
#
# The generated dataset files (full_dives.json, official_latest.json —
# gitignored, ~35 MB) are a precondition for the dataset-dependent checks:
# on a dataset-less checkout the runner still runs the dataset-independent
# watch.mjs harness (comparing its kw/harness golden line), skips the rest,
# exits 0, and prints the remedy; --regen refuses without the dataset.
#
# The golden covers the CLI/render battery (24 cases: sha of stdout and
# stderr SEPARATELY + exit code), the interactive copy path (4 cases, real
# killion on a pty with stubbed fzf/pbcopy) and the offline watch.mjs driver
# (drawn stdout + harness stdout + exit). Hashing the streams separately
# pins stream discipline too: --json must land on stdout (pipe to jq), so a
# stdout<->stderr swap fails the golden (a combined hash would be blind).
# More checks are semantic (not byte-hashed): the harness's party file
# carries today's date, and the download_full.py parser + main tests compare
# against full_dives.json. On failure the temp workdir is left behind for inspection.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
REGEN=0
[[ "${1:-}" == --regen ]] && REGEN=1
GOLDEN="$HERE/golden.sha"
WORK="$(mktemp -d)"
fails=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails+1)); }
cleanup() {
  if [[ $fails -eq 0 && $REGEN -eq 0 ]]; then rm -rf "$WORK";
  else echo "workdir left for inspection: $WORK"; fi
}
trap cleanup EXIT

# --- syntax checks ---------------------------------------------------------
for f in killion tests/kb_battery.sh tests/run.sh; do
  bash -n "$ROOT/$f" || bad "syntax: $f"
done
node --check "$ROOT/watch.mjs"            || bad "syntax: watch.mjs"
node --check "$ROOT/tests/kw_harness.mjs" || bad "syntax: kw_harness.mjs"
for f in download_full.py tests/kd_parse.py tests/kd_main.py; do
  python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
    "$ROOT/$f" 2>/dev/null || bad "syntax: $f"
done
if [[ $fails -gt 0 ]]; then echo "RESULT: FAIL (syntax)"; exit 1; fi

# --- watch.mjs harness -----------------------------------------------------
# dataset-independent (synthetic heredoc data below): runs before the dataset
# gate, so a fresh checkout still gets the watch.mjs checks
seed_harness() { # $1 = dir: the synthetic harness dataset + pre-seeded party file
  cat > "$1/full_dives.json" <<'EOF'
[ { "n": 1, "date": "2026-10-29", "prompts": [
  { "q": "Name a strategy board game", "answers": [
    { "a": "Chess", "tier": "deepcut", "pts": 85, "quip": null },
    { "a": "Go", "tier": "rare", "pts": 60, "quip": null },
    { "a": "Rithmomachia", "tier": "schooler", "pts": 30, "quip": null },
    { "a": "Backgammon", "tier": "plankton", "pts": 10, "quip": null },
    { "a": "Checkers", "tier": "plankton", "pts": 10, "quip": null },
    { "a": "Parchisi", "tier": "plankton", "pts": 10, "quip": null },
    { "a": "Halma", "tier": "plankton", "pts": 10, "quip": null } ] } ] } ]
EOF
  # pre-seeded party file: the daily question carries one entry that duplicates
  # a daily answer (Go: must be deduped; seen merges on flush) and one genuine
  # extra (Shogi: must be rendered into the tier list); the party-only question
  # exists only in this file (the harness dataset has no such prompt)
  cat > "$1/party_answers.json" <<'EOF'
{
 "Name a strategy board game": [
  {"a":"Go","tier":"rare","seen":1,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"},
  {"a":"Shogi","tier":"schooler","seen":1,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"}
 ],
 "A party-only question nobody asked daily": [
  {"a":"Sardine","tier":"plankton","seen":1,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"},
  {"a":"Unscored thing","tier":null,"seen":3,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"}
 ]
}
EOF
}
H="$WORK/watch"
mkdir -p "$H"
cp "$ROOT/tiers.json" "$ROOT/watch.mjs" "$ROOT/render.jq" "$H/"
seed_harness "$H"
node "$HERE/kw_harness.mjs" "$H" "$H/drawn.txt" > "$H/stdout.txt" 2>&1
echo $? > "$H/exit"
[[ -f $H/drawn.txt ]] || bad "harness crashed"

# watch.mjs record semantics (semantic: the file carries today's date)
P="$H/party_answers.json"
fact() { jq -e "$2" "$P" >/dev/null 2>&1 && ok "fact: $1" || bad "fact: $1"; }
fact 'duplicate pass events add to the pre-seeded count (Go seen=1+2=3, rare)' \
  '.["Name a strategy board game"] | map(select(.a=="Go"))[0] | .seen==3 and .tier=="rare"'
fact 'flush merge keeps pre-seeded entries untouched (Shogi seen=1, schooler)' \
  '.["Name a strategy board game"] | map(select(.a=="Shogi"))[0] | .seen==1 and .tier=="schooler"'
fact 'tierless pass kept as null tier' \
  '.["Name a strategy board game"] | map(select(.a=="Rithmomachia"))[0] | .tier==null'
fact 'patch pass event recorded' \
  '.["Name a strategy board game"] | map(select(.a=="Gomoku"))[0] | .tier=="schooler" and .seen==1'
fact 'player lastAnswer without tier recorded once' \
  '.["Name a strategy board game"] | map(select(.a=="No tier answer"))[0] | .tier==null and .seen==1'
fact 'new-round answer flushed under its own (party-only) question' \
  '.["A party-only question nobody asked daily"] | map(select(.a=="Fresh answer"))[0] | .seen==1 and .tier=="plankton"'
fact 'snap-stale lastAnswer (no pass event) is not recorded anywhere' \
  '[.[] | .[] | .a] | index("Stale snap") | not'
fact 'stale lastAnswers carried by the new-round patch are not recorded under the new question' \
  '.["A party-only question nobody asked daily"] | [.[].a]
   | (index("Rithmomachia") | not) and (index("No tier answer") | not) and (index("Stale snap") | not)'
fact 'pass event matching a baseline is still recorded (events are unconditional)' \
  '.["A party-only question nobody asked daily"] | map(select(.a=="Go"))[0] | .tier=="rare" and .seen==1'
fact 'lastAnswer change after round start is recorded (state-channel transition)' \
  '.["A party-only question nobody asked daily"] | map(select(.a=="Trick answer"))[0] | .tier=="rare" and .seen==1'

# stale round-start values must not be shown as "already said" either:
# "Stale snap" never appears in the draw at all, and round 2's said line
# is exactly the event-sourced answers plus Dave's round-2 transition
if grep -q 'Stale snap' "$H/drawn.txt"; then
  bad "display: stale round-start lastAnswer shown as said"
else
  ok "display: stale round-start lastAnswers never shown"
fi
grep -q 'said this round: "Fresh answer" (Plankton)  "Go" (Rare)  "Trick answer" (Rare)' "$H/drawn.txt" \
  && ok "display: round-2 said line is only post-round-start answers" \
  || bad "display: round-2 said line wrong (see $H/drawn.txt)"

# the watcher must survive a disconnect: the harness fired a non-fatal close
# above; a second WebSocket must have been constructed (an unref'd retry
# timer lets the process exit silently before it ever reconnects)
grep -q 'harness: ws builds after close' "$H/stdout.txt" \
  && ok "watch: reconnects after disconnect" || bad "watch: no reconnect after close (see $H/stdout.txt)"

# startup with the network down: a clean error + exit 1, not a raw
# rejection crash
KSTUB_NETFAIL=1 node "$HERE/kw_harness.mjs" "$H" "$H/drawn_netfail.txt" > "$H/netfail.txt" 2>&1
if [[ $? -eq 1 ]] && grep -q 'no guest token' "$H/netfail.txt"; then
  ok "watch: clean exit on token-fetch failure"
else
  sed 's/^/    /' "$H/netfail.txt"
  bad "watch: token-fetch failure path"
fi

# fatal-close variant (4404 room-gone; 4403 refused is the same code path):
# the harness appends a pass event AFTER the last new-round boundary, then
# fires the close — watch.mjs must flush the party file on the way out
# (exit 1, existing message). Fresh copy dir so the file after exit is
# exactly preseed + this run's records. Semantic assertions only (like the
# netfail variant): no golden line.
H4404="$WORK/watch4404"
mkdir -p "$H4404"
cp "$H/tiers.json" "$H/watch.mjs" "$H/render.jq" "$H4404/"
seed_harness "$H4404"
KSTUB_CLOSE=4404 node "$HERE/kw_harness.mjs" "$H4404" "$H4404/drawn.txt" > "$H4404/out.txt" 2>&1
if [[ $? -eq 1 ]] && grep -q 'room is gone' "$H4404/out.txt"; then
  ok "watch: fatal close (4404) exits 1 with the existing message"
else
  sed 's/^/    /' "$H4404/out.txt"
  bad "watch: fatal close (4404) exit/message"
fi
# the regression pin: the late answer landed after the last new-round flush
# (in memory only at close time) — the onclose flush must have written it.
# Absent in the pre-fix code, which exited without flushing.
if jq -e '.["name a strategy board game"] | map(select(.a=="Late answer"))[0]
    | .tier=="rare" and .seen==1' "$H4404/party_answers.json" >/dev/null 2>&1; then
  ok "watch: answer after the last round boundary survives the 4404 close"
else
  jq -r '.["name a strategy board game"] // "question missing"' "$H4404/party_answers.json" 2>/dev/null | sed 's/^/    /'
  bad "watch: late answer lost on 4404 close (file above)"
fi
# everything recorded earlier must be there too: the pre-flush rounds merged
# and the pre-seeded counts intact (Go = 1 preseed + 2 snap events = 3)
if jq -e '(.["A party-only question nobody asked daily"] | map(select(.a=="Trick answer"))[0] | .tier=="rare" and .seen==1)
    and (.["Name a strategy board game"] | map(select(.a=="Go"))[0] | .seen==3)' \
    "$H4404/party_answers.json" >/dev/null 2>&1; then
  ok "watch: 4404 close keeps earlier rounds and pre-seeded counts"
else
  jq '.' "$H4404/party_answers.json" 2>/dev/null | head -20 | sed 's/^/    /'
  bad "watch: 4404 close file missing earlier entries (file above)"
fi

# the harness's golden line — part of the full manifest, compared alone when
# the dataset is missing (the harness is the only dataset-independent check)
sha() { shasum -a 256 "$1" | awk '{print $1}'; }
harness_manifest() {
  printf 'kw/harness\t%s\t%s\t%s\n' \
    "$(sha "$H/drawn.txt")" "$(sha "$H/stdout.txt")" \
    "$(cat "$H/exit")"
}

# --- dataset precondition ---------------------------------------------------
# full_dives.json + official_latest.json are generated artifacts (gitignored,
# ~35 MB): a fresh checkout has neither, and every check below reads one of
# them (the dataset-independent watch.mjs harness already ran above). Skip
# loud with the remedy instead of ~20 opaque per-case failures.
missing=""
[[ -f "$ROOT/full_dives.json" ]]      || missing="$missing full_dives.json"
[[ -f "$ROOT/official_latest.json" ]] || missing="$missing official_latest.json"
if [[ -n $missing ]]; then
  if [[ $REGEN -eq 1 ]]; then
    echo
    echo "REFUSE: --regen with generated dataset file(s) missing:$missing"
    echo "remedy: python3 download_full.py   (then re-run tests/run.sh --regen)"
    echo "Without the battery cases a re-record would truncate $GOLDEN to the"
    echo "kw/harness line, so it is refused."
    echo
    echo "RESULT: REFUSE (--regen without dataset)"
    exit 1
  fi
  echo
  echo "SKIP — generated dataset file(s) missing:$missing"
  echo "remedy: python3 download_full.py   (then re-run tests/run.sh)"
  echo
  echo "skipped (all dataset-dependent): download_full.py parser + main tests"
  echo "(incl. the POSIX/C-locale run), the 24-case CLI/render battery, the"
  echo "interactive pty copy / question-list cache / answer-view cache checks,"
  echo "the one-shot timing guard, and the kb/* golden lines (the dataset-"
  echo "independent watch.mjs harness above still ran; the golden compare"
  echo "covers its kw/harness line only)"
  # the battery never ran: the only golden line available is kw/harness
  harness_manifest > "$WORK/actual.manifest"
  if [[ -f $GOLDEN ]]; then
    if diff -u <(grep '^kw/harness' "$GOLDEN") "$WORK/actual.manifest" \
        > "$WORK/golden.diff" 2>&1; then
      ok "golden: kw/harness matches"
    else
      sed 's/^/    /' "$WORK/golden.diff"
      bad "golden: kw/harness drift (diff above)"
    fi
  else
    bad "missing $GOLDEN — run: tests/run.sh --regen"
  fi
  echo
  if [[ $fails -eq 0 ]]; then
    echo "RESULT: SKIP (no dataset — watch.mjs harness only; run python3 download_full.py first)"
  else
    echo "RESULT: FAIL ($fails)"
  fi
  exit $(( fails > 0 ))
fi

# --- download_full.py parser (offline fixture: a real archived dive page) --
# kd_parse.py stubs get() to the local fixture files, runs parse_cards, and
# asserts the result equals the full_dives.json entry recorded from that
# same page — pins the parser against the site's actual format
python3 "$HERE/kd_parse.py" "$ROOT" > "$WORK/parse.txt" 2>&1
if [[ $? -eq 0 ]]; then
  sed 's/^/ok   /' "$WORK/parse.txt"
else
  sed 's/^/    /' "$WORK/parse.txt"
  bad "parse: parse_cards vs archived page"
fi

# --- download_full.py main (offline: get + date.today stubbed) -------------
# kd_main.py runs main() in a scratch dir against the same fixture: pins the
# output files, the --csv opt-in (no CSV by default) and the official-API
# validation section (official_latest.json + MISMATCH reporting)
python3 "$HERE/kd_main.py" "$ROOT" > "$WORK/kdmain.txt" 2>&1
if [[ $? -eq 0 ]]; then
  sed 's/^/ok   /' "$WORK/kdmain.txt"
else
  sed 's/^/    /' "$WORK/kdmain.txt"
  bad "main: download_full.main vs stubbed archive"
fi

# the write sites must be locale-proof: re-run the same offline main() under a
# POSIX/C locale with UTF-8 mode off (default text encoding = US-ASCII) — an
# open() without an explicit encoding='utf-8' crashes mid-dump on the
# fixture's non-ASCII answers and leaves full_dives.json half-written
if PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 LC_ALL=C \
    python3 "$HERE/kd_main.py" "$ROOT" > "$WORK/kdmain_c.txt" 2>&1; then
  ok "main: POSIX/C locale - all write sites use explicit utf-8"
else
  sed 's/^/    /' "$WORK/kdmain_c.txt"
  bad "main: POSIX/C locale (a write site lost its encoding='utf-8')"
fi

# --- CLI/render battery ----------------------------------------------------
B="$WORK/battery"
mkdir -p "$B"
cp "$ROOT/killion" "$ROOT/render.jq" "$ROOT/selftest.jq" "$ROOT/tiers.json" \
   "$ROOT/full_dives.json" "$ROOT/official_latest.json" "$B/"
bash "$HERE/kb_battery.sh" "$B" "$B/out" || bad "battery crashed"

KB_CASES="01_text_daily 02_text_daily_extras 03_json_daily 04_text_partial
05_text_no_match 06_text_empty 07_text_ambiguous 08_text_party_only
09_json_party_only 10_text_cash 11_selftest 12_usage
13_itrm_quip 14_itrm_seen 15_itrm_plain 16_itrm_header
17_help 18_h 19_json_ambiguous 20_selftest_fail 21_json_dedup_all 22_all
23_party_overcap 24_selftest_malformed"

# --- interactive copy path (pty + stubbed fzf/pbcopy) ---------------------
# the fzf-driven flow the one-shot battery can't reach: run the real killion
# on a pty (script) with a stub fzf that scripts the selections and a stub
# pbcopy that writes to a file, then assert what ends up on the clipboard
mkdir -p "$B/bin"
cat > "$B/bin/fzf" <<'EOF'
#!/usr/bin/env bash
# every branch must drain stdin like real fzf (an early exit SIGPIPEs the
# producer; with pipefail the command-substitution rc becomes 141)
n=1
[[ -f ${KSTUB_STATE:?} ]] && n=$(( $(cat "$KSTUB_STATE") + 1 ))
echo "$n" > "$KSTUB_STATE"
if [[ "$*" == *--no-sort* ]]; then            # answers view
  a=1
  [[ -f ${KSTUB_ANS:?} ]] && a=$(( $(cat "$KSTUB_ANS") + 1 ))
  echo "$a" > "$KSTUB_ANS"
  if (( a == 2 )); then                       # 2nd visit (repeat scenario): Esc
    cat > /dev/null; exit 130
  fi
  [[ ${KSTUB_TOUCH_PARTY:-} == 1 ]] && touch "$KSTUB_PARTY"
  wc -l <&0 | tr -d '[:space:]' > "${KSTUB_LINES:?}"   # count the list fed in
  printf '%s\n' "$KSTUB_ANSWER"; exit 0
elif (( n == 1 )) || { [[ ${KSTUB_REPEAT:-} == 1 ]] && (( n == 3 )); }; then
  cat > "${KSTUB_QLIST:-/dev/null}"; printf '%s\n' "$KSTUB_QUESTION"; exit 0
else                                          # question search: Esc
  cat > /dev/null; exit 1
fi
EOF
cat > "$B/bin/pbcopy" <<'EOF'
#!/usr/bin/env bash
cat > "$KSTUB_CLIP"
EOF
# jq stub: log every invocation, then hand it to the real jq (resolved in
# run.sh's PATH, where $B/bin is not present) — lets a test count how many
# dataset passes a flow paid without changing what jq does
REAL_JQ="$(command -v jq)"
cat > "$B/bin/jq" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "\${KSTUB_JQLOG:-/dev/null}"
exec "$REAL_JQ" "\$@"
EOF
chmod +x "$B/bin/fzf" "$B/bin/pbcopy" "$B/bin/jq"

iterm() { # name  answer-line  expected-clip (- = nothing may be copied)
  local name="$1" want="$3" code=0
  rm -f "$B/state" "$B/ans" "$B/clip" "$B/tty" "$B/lines" "$B/jqlog"
  KSTUB_STATE="$B/state" KSTUB_CLIP="$B/clip" KSTUB_ANSWER="$2" \
    KSTUB_QUESTION="Name a strategy board game" KSTUB_LINES="$B/lines" \
    KSTUB_QLIST="$B/qlist_$name" KSTUB_JQLOG="$B/jqlog" \
    KSTUB_PARTY="$B/party_answers.json" KSTUB_ANS="$B/ans" \
    script -q "$B/tty" bash -c "cd '$B' && PATH='$B/bin:'\$PATH ./killion" >/dev/null 2>&1
  if [[ $want == - ]]; then
    [[ ! -f $B/clip ]] && ! grep -aq 'copied:' "$B/tty" || code=1
    printf 'not-copied\n' > "$B/out/$name.out"
  else
    { [[ -f $B/clip && $(cat "$B/clip") == "$want" ]] && grep -aq "copied: $want" "$B/tty" || code=1
      [[ -f $B/clip ]] && cat "$B/clip" || printf 'not-copied\n'; } > "$B/out/$name.out"
  fi
  grep -a -o 'copied: .*' "$B/tty" 2>/dev/null | tr -d '\r' > "$B/out/$name.err" || true
  echo "$code" > "$B/out/$name.code"
  (( code == 0 )) && ok "copy: $name" || bad "copy: $name (want [${want}])"
}
iterm 13_itrm_quip   '    Go  — two moves and the game is lost'  Go
iterm 14_itrm_seen   '    Rithmomachia  (×2)'                    Rithmomachia
iterm 15_itrm_plain  '    Go'                                    Go
iterm 16_itrm_header '  ● 60 · Rare (2)'                         -

# --- fzf question list cache (questions.txt) --------------------------------
# the stub fzf captured the question list fed to it on the first search.
# Case 13 ran on the fresh temp copy (no questions.txt): qlist must
# self-heal — regenerate the cache — and feed fzf exactly dataset questions
# + party keys
exp_qlist="$({ jq -r '[.[] | .prompts[].q] | unique | .[]' "$B/full_dives.json"
  jq -r 'keys[]' "$B/party_answers.json"; } | sort -u)"
if diff -u <(printf '%s\n' "$exp_qlist") "$B/qlist_13_itrm_quip" > "$WORK/qlist.diff" 2>&1; then
  ok "qcache: fresh copy self-heals (list == dataset questions + party keys)"
else
  sed 's/^/    /' "$WORK/qlist.diff"
  bad "qcache: self-healed list wrong (diff above)"
fi

# the fzf answer list must be the FULL uncapped sheet (the display caps are
# for terminal output only): the stub fzf counted its stdin; compare against
# the expected full text length (3 header lines + per non-empty tier:
# header + answers + blank, minus the final blank line that render()'s
# command substitution strips)
exp_full=$(jq -r --slurpfile T "$B/tiers.json" --arg q "Name a strategy board game" '
  . as $d
  | ($d[] | .prompts[] | select(.q == $q) | .answers) as $a
  | (3 + ([ $T[0].order[] as $t
            | ($a | map(select(.tier == $t)))
            | select(length > 0)
            | 2 + length ] | add)) - 1' "$B/full_dives.json")
fzf_lines=$(cat "$B/lines" 2>/dev/null)
if [[ $fzf_lines =~ ^[0-9]+$ ]] && (( fzf_lines == exp_full )); then
  ok "fzf: answer list is the full uncapped sheet ($fzf_lines lines)"
else
  bad "fzf: answer list not the full sheet (got '${fzf_lines:-none}', want $exp_full)"
fi

# a fresh cache (newer than the dataset) must be used AS-IS: a probe line
# planted in it survives only if qlist did not regenerate (a probe the
# canonical dataset computation would never emit)
printf '%s\n' "$exp_qlist" "ZZZ qcache probe" > "$B/questions.txt"
iterm 24_qcache_used '    Go' Go
grep -qx 'ZZZ qcache probe' "$B/qlist_24_qcache_used" \
  && ok "qcache: fresh cached list is used (probe survived)" \
  || bad "qcache: fresh cached list ignored (regenerated instead)"

# a stale cache (dataset newer than the list — refresh or hand-edit) must be
# regenerated: the probe vanishes and the list equals the fresh computation.
# touch -t sets an explicit past mtime: no sleep, no fs-granularity flake
printf '%s\n' "$exp_qlist" "ZZZ qcache probe" > "$B/questions.txt"
touch -t 202601010000.00 "$B/questions.txt"
iterm 25_qcache_stale '    Go' Go
if ! grep -qx 'ZZZ qcache probe' "$B/qlist_25_qcache_stale" \
   && diff -u <(printf '%s\n' "$exp_qlist") "$B/qlist_25_qcache_stale" > /dev/null 2>&1; then
  ok "qcache: stale list regenerated (probe gone, content correct)"
else
  bad "qcache: stale list not regenerated"
fi

# --- interactive render cache (per-question view cache) -----------------------
# a second Enter on the same question must not re-pay the ~0.3 s dataset
# pass: KSTUB_REPEAT scripts hit → answer → Esc-answers → hit → answer → Esc,
# and the jq stub logs every invocation (real jq still does the work)
KSTUB_REPEAT=1 iterm 26_viewcache_hit '    Go' Go
n=$(grep -c 'render\.jq' "$B/jqlog" 2>/dev/null) || n=0
if [[ $n -eq 1 ]]; then
  ok "viewcache: second Enter on the same question is cached (1 lookup)"
else
  bad "viewcache: second Enter re-ran the lookup ($n lookups, want 1)"
fi
# a concurrent `killion watch` records into party_answers.json between rounds:
# the stub fzf rewrites the party file during the first answer view, so the
# second Enter must re-lookup
KSTUB_REPEAT=1 KSTUB_TOUCH_PARTY=1 iterm 27_viewcache_invalidate '    Go' Go
n=$(grep -c 'render\.jq' "$B/jqlog" 2>/dev/null) || n=0
if [[ $n -eq 2 ]]; then
  ok "viewcache: party rewrite invalidates the cache (2 lookups)"
else
  bad "viewcache: party rewrite did not invalidate ($n lookups, want 2)"
fi

# --- one-shot timing guard ---------------------------------------------------
t="$(cat "$B/out/timing_s")"
awk -v t="$t" 'BEGIN{exit !(t+0 < 2.0)}' \
  && ok "timing: ${t}s (< 2.0s)" || bad "timing: ${t}s >= 2.0s"

# --- golden compare ----------------------------------------------------------
# stdout and stderr are hashed separately: the stream is part of the contract
# (--json -> stdout), so a swap must fail even when the bytes are unchanged
manifest() {
  local c
  for c in $KB_CASES; do
    printf 'kb/%s\t%s\t%s\t%s\n' "$c" \
      "$(sha "$B/out/$c.out")" "$(sha "$B/out/$c.err")" \
      "$(cat "$B/out/$c.code")"
  done
  harness_manifest
}
ACT="$WORK/actual.manifest"
manifest > "$ACT"
if [[ $REGEN -eq 1 ]]; then
  cp "$ACT" "$GOLDEN"
  echo "golden re-recorded: $GOLDEN"
else
  if [[ -f $GOLDEN ]]; then
    if diff -u "$GOLDEN" "$ACT" > "$WORK/golden.diff" 2>&1; then
      ok "golden: all $(wc -l < "$GOLDEN" | tr -d ' ') cases match"
    else
      sed 's/^/    /' "$WORK/golden.diff"
      bad "golden: output drift (diff above)"
    fi
  else
    bad "missing $GOLDEN — run: tests/run.sh --regen"
  fi
fi

echo
if [[ $fails -eq 0 ]]; then echo "RESULT: PASS"; else echo "RESULT: FAIL ($fails)"; fi
exit $(( fails > 0 ))
