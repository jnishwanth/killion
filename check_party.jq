# check_party.jq — review list for party_answers.json (killion --check-party).
# Flags an entry whose answer (case-folded) is daily-verified for at least
# one question OTHER than its own — the strict variant of the audit's
# heuristic: an answer never daily-verified anywhere is a party-only answer,
# not a flag (the looser variant flags those too; they are legit). A
# party-only question legitimately overlaps other questions' daily answers,
# so this is a review list, not a verdict: killion always exits 0 on a
# successful run. The own-question match is exact (server text and daily
# text agree for the same question).
# input: full_dives.json · --slurpfile p party_answers.json
# output: one TSV line per flagged entry:
#         F \t firstSeen \t question \t answer \t tier \t nOther \t q1,q2,…
#         then one summary line:
#         S \t totalEntries \t flagged
([ .[] | .prompts[] | .q as $q | .answers[] | {a: (.a | ascii_downcase), q: $q} ]
  | group_by(.a)
  | map({key: .[0].a, value: ([.[].q] | unique)})
  | from_entries) as $daily
| [ $p[0] | to_entries[]
    | .key as $q | .value[]
    | (.a | ascii_downcase) as $al
    | ($daily[$al] // []) as $qs
    | select(($qs | length) > 0 and ($qs | index($q)) == null)
    | ["F", (.firstSeen // "?"), $q, .a, (.tier // "unscored"),
       ($qs | length | tostring), ($qs | join(","))]
  ] as $flags
| ([ $p[0] | to_entries[].value[] ] | length) as $total
| ( $flags | map(@tsv) )
  + ( [ ["S", ($total | tostring), ($flags | length | tostring)] ] | map(@tsv) )
| .[]
