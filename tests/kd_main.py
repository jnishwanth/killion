#!/usr/bin/env python3
"""Offline test for download_full.main (no network, no downloads).

Stubs get() (the 2026-08-31 fixture page + its rosters, and an official
reveal built from the full_dives.json entry recorded from the same page)
and date.today() (the day after the fixture), and runs main() in a scratch
dir. Pins the dive loop + output files, the --csv opt-in (no CSV by
default), and the official-API validation section (official_latest.json +
MISMATCH reporting) — main() previously had no test at all.

usage: kd_main.py <repo-root>
"""
import contextlib
import csv
import datetime
import io
import json
import os
import shutil
import sys
import tempfile

ROOT = os.path.abspath(sys.argv[1])
DATE = "2026-08-31"
FX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", DATE)
sys.dont_write_bytecode = True   # the suite must not litter the repo with __pycache__
sys.path.insert(0, ROOT)
import download_full as df

with open(os.path.join(ROOT, "full_dives.json"), encoding="utf-8") as f:
    DIV47 = next(d for d in json.load(f) if d["date"] == DATE)
N_ANS = sum(len(p["answers"]) for p in DIV47["prompts"])
# the official reveal the validation section fetches: same prompts and
# counts as the dataset entry this fixture was recorded from
OFFICIAL = {"prompts": [{"text": p["q"], "answers": [0] * len(p["answers"])}
                        for p in DIV47["prompts"]]}


def make_get(doctor=False):
    def get(url, retries=3):
        if url.endswith("/archive/" + DATE + "/"):
            with open(os.path.join(FX, "index.html"), "rb") as f:
                return f.read()
        if "answer-rosters" in url:
            with open(os.path.join(FX, url.rsplit("/", 1)[-1]), "rb") as f:
                return f.read()
        if url.startswith("https://krillion.io/api/reveal"):
            off = json.loads(json.dumps(OFFICIAL))
            if doctor:
                off["prompts"][0]["answers"].append(0)    # one count off
            return json.dumps(off).encode()
        raise AssertionError("unexpected url: " + url)
    return get


class _Today(datetime.date):
    @classmethod
    def today(cls):
        return datetime.date(2026, 9, 1)    # the day after the fixture


def run_main(with_csv=False, doctor=False):
    df.get = make_get(doctor)
    df.date = _Today
    df.SLEEP = 0                              # no sleeping over 46 stubbed 404s
    scratch = tempfile.mkdtemp(prefix="kd_main_")
    cwd = os.getcwd()
    os.chdir(scratch)
    try:
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            df.main(with_csv)
        return scratch, buf.getvalue()
    finally:
        os.chdir(cwd)


def main():
    # default run: dataset + official reveal written, NO csv
    scratch, out = run_main()
    try:
        with open(os.path.join(scratch, "full_dives.json"), encoding="utf-8") as f:
            assert json.load(f) == [DIV47], "full_dives.json != the dataset entry"
        with open(os.path.join(scratch, "official_latest.json"), encoding="utf-8") as f:
            assert json.load(f) == OFFICIAL, "official_latest.json != the reveal"
        assert not os.path.exists(os.path.join(scratch, "full_answers.csv")), \
            "full_answers.csv written without --csv"
        assert f"done: 1 dives (1 complete), {N_ANS} answers" in out, out
        print(f"main: default run - full_dives.json + official_latest.json, "
              f"no CSV ({N_ANS} answers)")
    finally:
        shutil.rmtree(scratch)

    # --csv: the full sheet, one row per answer
    scratch, out = run_main(True)
    try:
        with open(os.path.join(scratch, "full_answers.csv"), newline="", encoding="utf-8") as f:
            rows = list(csv.reader(f))
        assert rows[0] == ["dive", "date", "prompt", "answer", "tier", "points"], rows[0]
        assert len(rows) == 1 + N_ANS, f"csv rows: got {len(rows) - 1}, want {N_ANS}"
        print(f"main: --csv - {len(rows) - 1} rows (dive, date, prompt, answer, tier, points)")
    finally:
        shutil.rmtree(scratch)

    # validation section: an official count off by one must print MISMATCH
    scratch, out = run_main(doctor=True)
    try:
        assert "MISMATCH" in out, "official count mismatch not reported: " + out
        print("main: doctored official reveal - MISMATCH reported")
    finally:
        shutil.rmtree(scratch)


if __name__ == "__main__":
    main()
