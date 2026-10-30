# render.jq — query match + answer list, single pass over the dataset.
# input: full_dives.json · --arg q <raw query> · --arg m <text|full|json|exact>
#       · --slurpfile p party_answers.json · --slurpfile T tiers.json
# modes (the three decisions are bound once, as $fuzzy/$json/$cap, below):
#   text  fuzzy (exact, else case-insensitive substring) + text lines, capped
#         per tier (+N more) — one-shot terminal display
#   full  fuzzy + all text lines, uncapped — fzf's answer list and --all
#   json  fuzzy + one compact JSON object: {question, source, dive, date, answers}
#   exact exact-match only + JSON object — a fuzzy hit on a server-supplied
#         question could be another question entirely (watch.mjs uses this)
# json/exact are always complete (machine output). Ambiguous query (fuzzy
# modes): each candidate, prefixed with \u0001 · no match: nothing
# tier table (shared with watch.mjs + download_full.py via tiers.json);
# every text section is built by one sec() below: header + capped rows
# (row suffix by $kind: "quip" → "  — quip", "seen" → "  (×N)", "" → none)
# + a "+N more" line when capped + a blank line; an empty group yields []
def capped($capf; $caps; $g):
  (if $capf and $caps != null
   then [ $g[0:$caps], ($g | length) - $caps ]
   else [ $g, 0 ] end);
def sec($capf; $caps; $g; $head; $kind):
  (if ($g | length) == 0 then []
   else (capped($capf; $caps; $g) as [$sh, $more]
         | [ $head ]
         + [ $sh[] | "    \(.a)"
                + (if $kind == "quip" and .quip then "  — \(.quip)"
                   elif $kind == "seen" and .seen > 1 then "  (×\(.seen))"
                   else "" end) ]
         + (if $more > 0 then ["    … +\($more) more (use --all for the full list)"] else [] end)
         + [""])
   end);
($T[0].order) as $order
| ($T[0].tiers | map_values(.name)) as $tn
| ($T[0].tiers | map_values(.icon)) as $ti
| ($T[0].tiers | map_values(.pts)) as $pt
| ($T[0].tiers | map_values(.cap)) as $tc
| ($p[0] // {}) as $party
| . as $dives
# the mode decisions, bound once: substring fallback, JSON output, display
# cap (adding a mode = decide all three, right here)
| ($m != "exact")                 as $fuzzy
| ($m != "text" and $m != "full") as $json
| ($m == "text")                  as $cap
# match: exact, else case-insensitive substring (ASCII case fold, like grep -Fi)
| ([ $dives[] | .prompts[].q ] + ($party | keys)) | unique as $list
| (if ($list | index($q)) != null then [$q]
   elif $fuzzy
   then ($q | ascii_downcase) as $qlow
        | [ $list[] | select((. | ascii_downcase) | index($qlow) != null) ]
   else []
   end) as $hits
| if ($hits | length) == 0 then empty
  elif ($hits | length) > 1 then ($hits[] | "\u0001\(.)")
  else
    $hits[0] as $x
    | ([ $dives[] as $d | $d.prompts[] | select(.q == $x) | {dive: $d.n, date: $d.date, answers: .answers} ] | .[0]) as $daily
    | ($party[$x] // []) as $pans
    | if ($daily == null) and (($pans | length) == 0) then empty
      else
        (if $daily != null then [$daily.answers[] | .a | ascii_downcase] else [] end) as $dlow
        | [ $pans[] | . as $e | select(($dlow | index($e.a | ascii_downcase)) == null)
              | $e + {pts: ($pt[$e.tier // ""] // 0), quip: null} ] as $extra
        | if $json
          then { question: $x,
                 # daily+party means there ARE extra party answers, not just party data
                 source: (if $daily != null then (if (($extra | length) > 0) then "daily+party" else "daily" end) else "party" end),
                 dive: $daily.dive, date: $daily.date,
                 answers: ([ ($daily.answers // [])[] ] + $extra) } | tojson
          else
            (if $daily != null
             then ([ "\($x)",
                     "dive #\($daily.dive) · \($daily.date) · \($daily.answers | length) game-verified answers",
                     "" ]
              + [ $order[] as $t
                 | ($daily.answers | map(select(.tier == $t))) as $g
                 | select(($g | length) > 0)
                 | sec($cap; $tc[$t]; $g; "\($ti[$t]) \($g[0].pts) · \($tn[$t]) (\($g | length))"; "quip")
                 | .[] ])
             else ([ "\($x)",
                     "party-verified · \($pans | length) answers recorded from your games",
                     "" ]
              + [ $order[] as $t
                 | ($pans | map(select(.tier == $t))) as $g
                 | select(($g | length) > 0)
                 | sec($cap; $tc[$t]; $g; "\($ti[$t]) \($tn[$t]) (\($g | length))"; "seen")
                 | .[] ])
             end)
            + (if $daily != null and (($extra | length) > 0)
               then sec(false; null; $extra;
                        "+ party-verified extras (\($extra | length))"; "seen")
               else [] end)
            + (if $daily == null
               then ($pans | map(select(.tier as $t | $t == null or ($order | index($t)) == null))) as $g
               | sec($cap; $tc.plankton; $g; "· unscored (\($g | length))"; "")
               else [] end)
            | .[]
          end
      end
  end
