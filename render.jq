def tn: {"krillion":"One in a Krillion","deepcut":"Deep Cut","rare":"Rare","schooler":"Schooler","tooclever":"Too Clever","plankton":"Plankton"};
def ti: {"krillion":"◆","deepcut":"◆","rare":"●","schooler":"●","tooclever":"○","plankton":"○"};
["krillion","deepcut","rare","schooler","tooclever","plankton"] as $order
| .[] as $d
| $d.prompts[]
| select(.q == $q)
| ( .answers | length ) as $total
| [ "\(.q)",
    "dive #\($d.n) · \($d.date) · \($total) game-verified answers",
    "" ]
+ [ $order[] as $t
  | ( .answers | map(select(.tier == $t)) ) as $g
  | select(($g|length) > 0)
  | [ "\(ti[$t]) \($g[0].pts) · \(tn[$t]) (\($g|length))" ]
  + [ $g[] | "    \(.a)" + (if .quip then "  — \(.quip)" else "" end) ]
  + [ "" ]
  | .[] ]
| .[]
