# selftest.jq — validate the dataset against the latest official reveal, one pass.
# input: full_dives.json · --slurpfile o official_latest.json
# output: one TSV line per official prompt:  P \t text \t n_official \t n_tool (-1 if absent)
#         then one gem line:                 G \t text \t gem_official \t gem_tool
. as $dives | ($o[0].prompts) as $op
| (reduce ($dives[] | .prompts[]) as $pr ({};
     if .[$pr.q] == null then .[$pr.q] = ($pr.answers | length) else . end)) as $cnt
| ([$op[0].answers[] | select(.tier == "krillion") | .answer] | join(",")) as $go
| ([ $dives[] | .prompts[] | select(.q == $op[0].text) | .answers[]
     | select(.tier == "krillion") | .a ] | join(",")) as $gm
| [ $op[] | ["P", .text, (.answers | length), ($cnt[.text] // -1)] | @tsv ]
  + [["G", $op[0].text, $go, $gm] | @tsv] | .[]
