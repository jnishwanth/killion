#!/usr/bin/env python3
"""Offline test for download_full.parse_cards (no network).

Feeds the real archived dive page stored in fixtures/ through parse_cards
with get() stubbed to the local roster files, and asserts the result equals
the full_dives.json entry it was recorded from. This pins the parser against
the site's actual format: a regex regression or a site format change fails
here, at test time, instead of silently during the next real download.

usage: kd_parse.py <repo-root>
"""
import json
import os
import sys

ROOT = os.path.abspath(sys.argv[1])
# 2026-08-31 (dive #47): covers both card branches — roster-src cards and
# inline-chip cards — with quips in both (roster 4-element rows, chip quip
# spans, HTML entities)
DATE = "2026-08-31"
FX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", DATE)

sys.dont_write_bytecode = True   # the suite must not litter the repo with __pycache__
sys.path.insert(0, ROOT)
import download_full


def local_get(url, retries=3):
    with open(os.path.join(FX, url.rsplit("/", 1)[-1]), "rb") as f:
        return f.read()


def main():
    download_full.get = local_get
    with open(os.path.join(FX, "index.html"), encoding="utf-8") as f:
        html = f.read()
    prompts = download_full.parse_cards(html)

    with open(os.path.join(ROOT, "full_dives.json"), encoding="utf-8") as f:
        data = json.load(f)
    want = next(d for d in data if d["date"] == DATE)
    assert len(prompts) == len(want["prompts"]), \
        f"prompt count: got {len(prompts)}, want {len(want['prompts'])}"
    for got, w in zip(prompts, want["prompts"]):
        assert got == w, f"prompt mismatch: {w['q'][:60]!r}"
    n = sum(len(p["answers"]) for p in prompts)
    print(f"parse: {DATE} — {len(prompts)} prompts, {n} answers == full_dives.json")

    # error paths: a cardless page and a card claiming the wrong answer count
    for label, bad_html in (
        ("cardless page", "<html>no cards</html>"),
        ("wrong count", html.replace('data-answer-count="', 'data-answer-count="9999', 1)),
    ):
        try:
            download_full.parse_cards(bad_html)
        except ValueError:
            pass
        else:
            sys.exit(f"FAIL parse: expected ValueError ({label})")
    print("parse: error paths (cardless page, wrong count) raise ValueError")


if __name__ == "__main__":
    main()
