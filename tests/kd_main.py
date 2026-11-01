#!/usr/bin/env python3
"""Offline test for download_full.main (no network, no downloads).

Stubs get() (the 2026-08-31 fixture page + its rosters, and an official
reveal built from the full_dives.json entry recorded from the same page),
date.today() (the day after the fixture) and df.HERE (a scratch dir the
outputs must land in). main() runs from a SEPARATE scratch CWD that must
stay empty: the old CWD-relative writes were masked by a test that
chdir'd into its own output dir. Pins the dive loop + output files (next
to the script, not the CWD), the atomic-write convention (a mid-dump
crash leaves the old file intact), the --csv opt-in (no CSV by default),
and the official-API validation section (official_latest.json + MISMATCH
reporting) — main() previously had no test at all.

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
    # outputs must land next to the script (df.HERE), not where we run
    # from: here/ is the write target, cwd/ is the run-from dir and must
    # stay empty (the pre-M5 code wrote CWD-relative, and a test that
    # chdir'd into its own output dir could not see that)
    here = tempfile.mkdtemp(prefix="kd_main_here_")
    cwd = tempfile.mkdtemp(prefix="kd_main_cwd_")
    saved = df.HERE, os.getcwd()
    df.HERE = here
    os.chdir(cwd)
    try:
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            df.main(with_csv)
        return here, cwd, buf.getvalue()
    finally:
        os.chdir(saved[1])
        df.HERE = saved[0]


def main():
    # default run: dataset + official reveal written next to the script
    # (df.HERE), CWD untouched, NO csv
    here, cwd, out = run_main()
    try:
        with open(os.path.join(here, "full_dives.json"), encoding="utf-8") as f:
            assert json.load(f) == [DIV47], "full_dives.json != the dataset entry"
        with open(os.path.join(here, "official_latest.json"), encoding="utf-8") as f:
            assert json.load(f) == OFFICIAL, "official_latest.json != the reveal"
        assert not os.path.exists(os.path.join(here, "full_answers.csv")), \
            "full_answers.csv written without --csv"
        assert os.listdir(cwd) == [], \
            "outputs written to the CWD: " + repr(sorted(os.listdir(cwd)))
        assert f"done: 1 dives (1 complete), {N_ANS} answers" in out, out
        print(f"main: default run - outputs next to the script, CWD untouched, "
              f"no CSV ({N_ANS} answers)")
    finally:
        shutil.rmtree(here)
        shutil.rmtree(cwd)

    # --csv: the full sheet, one row per answer (in df.HERE, CWD untouched)
    here, cwd, out = run_main(True)
    try:
        with open(os.path.join(here, "full_answers.csv"), newline="", encoding="utf-8") as f:
            rows = list(csv.reader(f))
        assert rows[0] == ["dive", "date", "prompt", "answer", "tier", "points"], rows[0]
        assert len(rows) == 1 + N_ANS, f"csv rows: got {len(rows) - 1}, want {N_ANS}"
        assert os.listdir(cwd) == [], \
            "CSV written to the CWD: " + repr(sorted(os.listdir(cwd)))
        print(f"main: --csv - {len(rows) - 1} rows next to the script, CWD untouched")
    finally:
        shutil.rmtree(here)
        shutil.rmtree(cwd)

    # validation section: an official count off by one must print MISMATCH
    here, cwd, out = run_main(doctor=True)
    try:
        assert "MISMATCH" in out, "official count mismatch not reported: " + out
        print("main: doctored official reveal - MISMATCH reported")
    finally:
        shutil.rmtree(here)
        shutil.rmtree(cwd)

    # atomic write (L13): a crash mid-dump must leave the old file intact —
    # the partial bytes only in the .tmp sibling — and a clean run replaces
    # the target and leaves no .tmp behind (direct helper test, kd_parse
    # style; main()'s three write sites all go through this one path)
    here = tempfile.mkdtemp(prefix="kd_main_atomic_")
    try:
        target = os.path.join(here, "full_dives.json")
        with open(target, "w", encoding="utf-8") as f:
            f.write('["old dataset"]')
        saved = df.HERE
        df.HERE = here
        try:
            try:
                with df.atomic_write("full_dives.json") as f:
                    f.write('{"truncated: ')
                    raise OSError("simulated crash mid-dump")
            except OSError:
                pass
            with open(target, encoding="utf-8") as f:
                data = f.read()
            assert data == '["old dataset"]', \
                "mid-dump crash damaged the old dataset: " + repr(data)
            assert os.path.exists(target + ".tmp"), \
                "partial write should sit in the .tmp sibling"
            with df.atomic_write("full_dives.json") as f:
                f.write('["new dataset"]')
            with open(target, encoding="utf-8") as f:
                data = f.read()
            assert data == '["new dataset"]', "clean write did not replace the target"
            assert not os.path.exists(target + ".tmp"), "clean write left a .tmp behind"
        finally:
            df.HERE = saved
        print("main: atomic write - mid-dump crash leaves old file intact, clean write replaces")
    finally:
        shutil.rmtree(here)


if __name__ == "__main__":
    main()
