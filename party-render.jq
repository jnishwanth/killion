# renders a party-verified question (input: party_answers.json, --arg q)
def tn: {"krillion":"One in a Krillion","deepcut":"Deep Cut","rare":"Rare","schooler":"Schooler","tooclever":"Too Clever","plankton":"Plankton"};
def ti: {"krillion":"◆","deepcut":"◆","rare":"●","schooler":"●","tooclever":"○","plankton":"○"};
["krillion","deepcut","rare","schooler","tooclever","plankton"] as $order
| .[$q] // []
| (length) as $total
| select($total > 0)
| [ $q,
    "party-verified · \($total) answers recorded from your games",
    "" ]
+ [ $order[] as $t
  | map(select(.tier == $t)) as $g
  | select(($g|length) > 0)
  | [ "\(ti[$t]) \(tn[$t]) (\($g|length))" ]
  + [ $g[] | "    \(.a)" + (if .seen > 1 then "  (×\(.seen))" else "" end) ]
  + [ "" ]
  | .[] ]
+ [ ( map(select(.tier == null or (.tier | IN("krillion","deepcut","rare","schooler","tooclever","plankton") | not))) ) as $g
  | select(($g|length) > 0)
  | [ "· unscored (\($g|length))" ]
  + [ $g[] | "    \(.a)" ]
  | .[] ]
| .[]
