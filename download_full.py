#!/usr/bin/env python3
"""Download the FULL Krillion answer sheets (all dives, every accepted answer).

Source: krilliongame.net mirror of the official public reveal data.
Each /archive/YYYY-MM-DD/ page has 7 prompt cards (id="p1".."p7"):
  - big answer sets: card carries data-answer-src="/answer-rosters/<hash>.json"
    -> fetch that JSON: {text, answers: [[answer, tier, points, quip?], ...]}
  - small answer sets: answers are inlined as chips in the card HTML
    (<button class="chip" data-copy="..."> with optional <span class="quip">),
    grouped by tier-group data-tier.

Outputs (in this directory):
  full_dives.json  - one object per dive: {n, date, prompts: [{q, answers: [{a, tier, pts, quip}]}]}
  official_latest.json - raw latest official reveal (for validation)
With --csv (opt-in; nothing in the repo consumes the CSV):
  full_answers.csv - one row per answer: dive, date, prompt, answer, tier, points
"""
import csv
import html as htmlmod
import json
import os
import re
import sys
import time
import urllib.request
from datetime import date, timedelta

BASE = "https://krilliongame.net"
START = date(2026, 7, 16)          # Dive #1
SLEEP = 0.25
UA = {"User-Agent": "Mozilla/5.0 (killion-tool research)"}

# tier table shared with render.jq + watch.mjs (next to this script)
HERE = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(HERE, "tiers.json"), encoding="utf-8") as _f:
    TIER_PTS = {k: v["pts"] for k, v in json.load(_f)["tiers"].items()}

CARD_RE = re.compile(r'id="p([1-7])"')


def get(url: str, retries: int = 3) -> bytes:
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.read()
        except Exception as e:
            if i == retries - 1:
                raise
            print(f"    retry {i+1} after error: {e}")
            time.sleep(2 * (i + 1))


def parse_cards(html: str) -> list[dict]:
    """Parse all 7 prompt cards out of a dive page."""
    # split html into card segments by id="pN" (finditer is in document order,
    # so the marks are already position-sorted)
    marks = [(int(m.group(1)), m.start()) for m in CARD_RE.finditer(html)]
    if not marks:
        raise ValueError("no prompt cards found")
    prompts = []
    for idx, (num, start) in enumerate(marks):
        end = marks[idx + 1][1] if idx + 1 < len(marks) else start + 60000
        seg = html[start:end]

        text = re.search(r'data-answer-text="([^"]*)"', seg)
        count = re.search(r'data-answer-count="(\d+)"', seg)
        src = re.search(r'data-answer-src="(/answer-rosters/[a-f0-9]+\.json)"', seg)
        if not (text and count):
            raise ValueError(f"card p{num} missing text/count")
        expected = int(count.group(1))
        q = htmlmod.unescape(text.group(1))

        if src:
            data = json.loads(get(BASE + src.group(1)))
            answers = [{"a": a[0], "tier": a[1], "pts": a[2],
                        "quip": a[3] if len(a) > 3 and a[3] else None}
                       for a in data["answers"]]
        else:
            answers = []
            for tg in re.finditer(
                    r'data-tier="(\w+)" data-roster-count="(\d+)"(.*?)(?=</details>)',
                    seg, re.S):
                tier, tcount, body = tg.group(1), int(tg.group(2)), tg.group(3)
                pts = TIER_PTS.get(tier)
                got = 0
                for chip in re.finditer(r'data-copy="([^"]*)"', body):
                    a = htmlmod.unescape(chip.group(1))
                    quip = None
                    tail = body[chip.end(): chip.end() + 300]
                    mq = re.search(r'<span class="quip">([^<]*)</span>', tail)
                    if mq:
                        quip = htmlmod.unescape(mq.group(1)) or None
                    answers.append({"a": a, "tier": tier, "pts": pts, "quip": quip})
                    got += 1
                if got != tcount:
                    raise ValueError(f"p{num} tier {tier}: got {got}, expected {tcount}")
        if len(answers) != expected:
            raise ValueError(f"p{num} '{q[:40]}': got {len(answers)}, expected {expected}")
        prompts.append({"q": q, "answers": answers})
    return prompts


def main(with_csv: bool = False):
    latest = None
    d = date.today()
    for _ in range(20):
        try:
            get(f"{BASE}/archive/{d.isoformat()}/")
            latest = d
            break
        except Exception:
            pass
        d -= timedelta(days=1)
        time.sleep(SLEEP)
    if latest is None:
        sys.exit("could not find any archive page")
    print(f"latest archived dive date: {latest}")

    dives, problems = [], []
    for i in range((latest - START).days + 1):
        day = START + timedelta(days=i)
        n = i + 1
        try:
            page = get(f"{BASE}/archive/{day.isoformat()}/").decode("utf-8", "replace")
            prompts = parse_cards(page)
        except Exception as e:
            problems.append(n)
            print(f"  ! dive #{n} {day}: {e}")
            time.sleep(SLEEP)
            continue
        total = sum(len(p["answers"]) for p in prompts)
        dives.append({"n": n, "date": day.isoformat(), "prompts": prompts})
        print(f"  dive #{n} {day}: {len(prompts)} prompts, {total} answers")
        time.sleep(SLEEP)

    # explicit utf-8 on every write: under a POSIX/C locale the default
    # encoding is ASCII, and a crash mid-dump would leave the dataset
    # half-written
    with open("full_dives.json", "w", encoding="utf-8") as f:
        json.dump(dives, f, ensure_ascii=False)
    if with_csv:    # opt-in: 44 MB, and nothing in the repo consumes it
        with open("full_answers.csv", "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["dive", "date", "prompt", "answer", "tier", "points"])
            for dv in dives:
                for p in dv["prompts"]:
                    for a in p["answers"]:
                        w.writerow([dv["n"], dv["date"], p["q"], a["a"], a["tier"], a["pts"]])

    # cross-check the latest complete dive against the official public API
    for dv in reversed(dives):
        try:
            off = json.loads(get(f"https://krillion.io/api/reveal?date={dv['date']}"))
        except Exception:
            continue
        with open("official_latest.json", "w", encoding="utf-8") as f:
            f.write(json.dumps(off, ensure_ascii=False))
        print(f"\nvalidation vs official API (dive #{dv['n']} {dv['date']}):")
        off_by_q = {p["text"]: len(p["answers"]) for p in off["prompts"]}
        allok = True
        for p in dv["prompts"]:
            o = off_by_q.get(p["q"])
            ok = o == len(p["answers"])
            allok &= ok
            if not ok:
                print(f"  MISMATCH {p['q'][:60]!r}: official={o} mirror={len(p['answers'])}")
        if allok:
            print(f"  all {len(dv['prompts'])} prompts match official counts "
                  f"({sum(len(p['answers']) for p in dv['prompts'])} answers)")
        break

    n_ans = sum(len(p["answers"]) for dv in dives for p in dv["prompts"])
    complete = sum(1 for dv in dives if len(dv["prompts"]) == 7)
    print(f"\ndone: {len(dives)} dives ({complete} complete), {n_ans} answers")
    if problems:
        print(f"{len(problems)} dives had problems: {problems}")


if __name__ == "__main__":
    main("--csv" in sys.argv[1:])
