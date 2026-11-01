#!/usr/bin/env bash
# killion CLI/render test battery: run in a temp copy of the repo with a
# synthetic party_answers.json, capture stdout/stderr/exit for every branch.
# Normal entry point is tests/run.sh; this also works standalone for
# A/B runs:  kb_battery.sh <repo-copy-dir> <output-dir>
set -u
R="$1"; OUT="$2"
rm -rf "$OUT"; mkdir -p "$OUT"
cd "$R"

# synthetic party file: daily+extras (one entry dups a daily answer, must be
# deduped), a daily question whose party entries ALL dup daily answers
# (21_json_dedup_all: source must stay "daily"), and a party-only question
# with scored / unscored(null) / unknown tier
cat > party_answers.json <<'EOF'
{
 "Name a hair type, texture, or natural color": [
  {"a":"Zzzquiff one","tier":"rare","seen":2,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"},
  {"a":"Zzzquiff two","tier":"rare","seen":1,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"},
  {"a":"Zzzquiff three","tier":"rare","seen":1,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"},
  {"a":"Zzzquiff four","tier":"rare","seen":1,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"},
  {"a":"Zzzquiff five","tier":"rare","seen":1,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"},
  {"a":"Zzzquiff six","tier":"rare","seen":1,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"},
  {"a":"Zzzquiff seven","tier":"rare","seen":1,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"}
 ],
 "Name a strategy board game": [
  {"a":"Go","tier":"rare","seen":2,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"},
  {"a":"Rithmomachia","tier":"schooler","seen":1,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"}
 ],
 "Name a place people keep or store cash": [
  {"a":"Air conditioner","tier":"deepcut","seen":1,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"}
 ],
 "A party-only question nobody asked daily": [
  {"a":"Sardine","tier":"plankton","seen":1,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"},
  {"a":"Unscored thing","tier":null,"seen":3,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"},
  {"a":"Odd tier","tier":"legendarypeel","seen":1,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"}
 ],
 "A party-only question that overflows the caps": [
  {"a":"P1","tier":"plankton","seen":1,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"},
  {"a":"P2","tier":"plankton","seen":2,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"},
  {"a":"P3","tier":"plankton","seen":1,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"},
  {"a":"P4","tier":"plankton","seen":1,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"},
  {"a":"U1","tier":null,"seen":1,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"},
  {"a":"U2","tier":null,"seen":3,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"},
  {"a":"U3","tier":null,"seen":1,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"},
  {"a":"U4","tier":"legendarypeel","seen":1,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"}
 ]
}
EOF

run() {
  local name="$1"; shift
  ./killion "$@" > "$OUT/$name.out" 2> "$OUT/$name.err"
  echo "$?" > "$OUT/$name.code"
}

# fzf-less variant of run(): the PATH sees only bin_nofzf plus /usr/bin:
# /bin (stock macOS has no fzf, no jq, no node there). bin_nofzf supplies
# symlinks to the real jq and the modern bash the shebang needs (the system
# /bin/bash 3.2 chokes on the top-level declare -A) and a stub node that
# records its argv (KSTUB_NODELOG) and exits 0 — the watch case is tested
# without touching the network (audit M4: only interactive mode needs fzf)
mkdir -p bin_nofzf
ln -sf "$(command -v jq)" bin_nofzf/jq
ln -sf "$(command -v bash)" bin_nofzf/bash
cat > bin_nofzf/node <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${KSTUB_NODELOG:?}"
exit 0
EOF
chmod +x bin_nofzf/node
nofzf_run() {
  local name="$1"; shift
  PATH="$R/bin_nofzf:/usr/bin:/bin" KSTUB_NODELOG="$OUT/node_$name.log" \
    ./killion "$@" > "$OUT/$name.out" 2> "$OUT/$name.err"
  echo "$?" > "$OUT/$name.code"
}

# the hair question's party entries are all genuine extras (7 > rare cap 6):
# pins the uncapped "+ party-verified extras" section in the shared builder
run 01_text_daily        "Name a hair type, texture, or natural color"
run 02_text_daily_extras "Name a strategy board game"
run 03_json_daily        "Name a strategy board game" --json
run 04_text_partial      "name a country where another religion"
run 05_text_no_match     "zzz definitely not a question"
run 06_text_empty        ""
run 07_text_ambiguous    "Name a"
run 08_text_party_only   "A party-only question nobody asked daily"
run 09_json_party_only   "A party-only question nobody asked daily" --json
run 10_text_cash         "Name a place people keep or store cash"
run 11_selftest          --selftest
run 12_usage             </dev/null
run 17_help              --help
run 18_h                 -h
# fzf-less PATH: one-shot + selftest must work without fzf, byte-identical
# to the with-fzf runs (02's question, 11's mode); watch dispatches to
# node (the stub records the exec). Must run before the official-file
# corruption below (cases 20/24)
nofzf_run 28_nofzf_oneshot   "Name a strategy board game"
nofzf_run 29_nofzf_selftest  --selftest
nofzf_run 30_nofzf_watch     watch ABCD
# check-party on the pristine synthetic party file: pins the 4 known
# false-positive baseline (Sardine, P1, P2, U2 — daily-verified for other
# questions) and, by byte-exact output, that the other 17 entries — incl.
# Go/Rithmomachia under their own daily question — are NOT flagged; exit 0
# even with flags (review list, not a gate)
run 31_check_party --check-party
run 19_json_ambiguous    "Name a" --json
# all party entries dup daily answers: source must be "daily" (no extras exist),
# pinning the extras-based source semantics
run 21_json_dedup_all    "Name a place people keep or store cash" --json
# --all: the full uncapped sheet (8049 answers) — pins full mode byte-for-byte;
# case 02 pins the capped text mode for the same question
run 22_all               "Name a strategy board game" --all
# party-only question over both caps (plankton tier cap 3, unscored cap 3):
# pins the capped-slice + "+N more" + no-×N-suffix-on-unscored edges in the
# shared section builder (case 08 stays under the caps)
run 23_party_overcap     "A party-only question that overflows the caps"
# selftest failure path: doctored official file must report MISMATCH, exit 1
# (after 11_selftest, which still sees the untouched file)
jq '.prompts[0].answers += [{"answer":"Doctored","tier":"plankton"}]' \
  official_latest.json > .off.tmp && mv .off.tmp official_latest.json
run 20_selftest_fail     --selftest
# selftest must fail closed on a malformed official file (invalid JSON):
# Bad-JSON diagnostic + malformed error on stderr, exit 1 — never a
# vacuous PASSED (case 20 pins the valid-but-wrong-data path)
printf '{ this is not valid json' > official_latest.json
run 24_selftest_malformed --selftest
# jq's error embeds the absolute file path (fresh temp dir per run):
# normalize it for a stable golden hash
sed "s|$R|<repo>|g" "$OUT/24_selftest_malformed.err" > .err.tmp \
  && mv .err.tmp "$OUT/24_selftest_malformed.err"

# check-party true-positive direction: an answer daily-verified for a
# different question (Go — verified under 11 daily questions, none of them
# this party-only one) must be flagged (case 31 pins the untouched file)
jq '.["A party-only question nobody asked daily"] +=
  [{"a":"Go","tier":"rare","seen":1,"firstSeen":"2026-10-29","lastSeen":"2026-10-29"}]' \
  party_answers.json > .party.tmp && mv .party.tmp party_answers.json
run 32_check_party_doctored --check-party

# timing: min of 3 text lookups, seconds
best=99
for i in 1 2 3; do
  s=$( { time ./killion "Name a strategy board game" >/dev/null; } 2>&1 \
        | awk '/real/{split($2,a,/[ms]/); print a[1]*60+a[2]}')
  awk -v b="$best" -v x="$s" 'BEGIN{exit !(x+0<b+0)}' && best=$s
done
echo "$best" > "$OUT/timing_s"
echo "battery done: $OUT"
