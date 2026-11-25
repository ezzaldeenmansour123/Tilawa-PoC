#!/usr/bin/env python3
"""Score PoC session logs (JSONL) against a ground-truth manifest.

Inputs:
  --log   session .jsonl file (events written by lib/event_log.dart)
  --truth ground-truth JSON for that session (see test_data/ for the format)

Definitions (see docs/MEASUREMENT_PLAN.md for the full rationale):
  - A predicted error = a `checker` event with state == "confirmed".
    `suspected` / `uncertain` / `resolved` are NEVER counted as errors.
  - True positive  = confirmed error whose (class, location) exactly matches
    a planted error in the ground truth.
  - False positive = confirmed error with no matching planted error
    (a false warning).
  - False negative = planted error with no matching confirmed error (missed).
  - precision = TP / (TP + FP); recall = TP / (TP + FN).
  - False warnings per 5 min = FP / (session audio minutes / 5).
    Session audio duration = max audioMs in the log (engine audio clock).
  - Highlight latency (ms), per `position` event:
        wallMs - (sessionStartedWallMs + audioMs)
    i.e. engine + bridge delivery delay. Median and P90 are reported.
    (The meta line must carry sessionStartedWallMs; otherwise latency is
    reported as null and the criterion is marked UNMEASURED, not passed.)
  - Confirm delay (ms), per confirmed checker id:
        confirmed.wallMs - first-suspected.wallMs for the same id.
    This is the engine's own confirm-policy delay. The phone protocol
    measures the full "spoken error -> confirmed" time with a stopwatch
    (the tester notes when they utter the planted error); this log-derived
    number is supporting evidence, not the whole measurement.
  - Verse found within 5 s (free-recitation sessions only): the first
    `position` event with confidence >= 0.6 and state == "locked" must
    have audioMs <= 5000 and its observed ayah must equal
    truth["expected_ayah"].

Exit code: 0 always (scoring never "passes" a session by itself — the
human-readable verdict table is printed, and the GO/NO-GO decision is made
in the results report against docs/MEASUREMENT_PLAN.md thresholds).

Usage:
  python3 tools/score_sessions.py --log session.jsonl --truth truth.json
  python3 tools/score_sessions.py --log session.jsonl --truth truth.json --json
"""

import argparse
import json
import statistics
import sys
from pathlib import Path


def load_events(path: Path):
    events = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line:
            events.append(json.loads(line))
    return events


def loc_key(loc) -> str:
    return f"{loc['surah']}:{loc['ayah']}:{loc['word']}"


def err_key(cls, loc) -> str:
    return f"{cls}@{loc_key(loc)}"


def percentile(values, p):
    if not values:
        return None
    s = sorted(values)
    idx = round((p / 100) * (len(s) - 1))
    return s[max(0, min(idx, len(s) - 1))]


def score(events, truth):
    planted = {
        err_key(e["class"], e["location"]): e for e in truth.get("planted_errors", [])
    }
    confirmed = []
    suspected_first_wall = {}
    uncertain = resolved = 0
    positions = []
    start_wall = None
    max_audio_ms = 0
    for ev in events:
        if ev["type"] == "meta":
            if ev["payload"].get("sessionStartedWallMs") is not None:
                start_wall = ev["payload"]["sessionStartedWallMs"]
            continue
        audio_ms = ev.get("audioMs")
        if isinstance(audio_ms, (int, float)):
            max_audio_ms = max(max_audio_ms, audio_ms)
        if ev["type"] == "position":
            positions.append(ev)
        elif ev["type"] == "checker":
            p = ev["payload"]
            state = p.get("state")
            if state == "suspected":
                suspected_first_wall.setdefault(p.get("id"), ev["wallMs"])
            elif state == "confirmed":
                confirmed.append(ev)
            elif state == "uncertain":
                uncertain += 1
            elif state == "resolved":
                resolved += 1

    predicted = {
        err_key(ev["payload"]["errorClass"], ev["payload"]["location"]): ev
        for ev in confirmed
    }
    tp_keys = set(planted) & set(predicted)
    fp_keys = set(predicted) - set(planted)
    fn_keys = set(planted) - set(predicted)
    tp, fp, fn = len(tp_keys), len(fp_keys), len(fn_keys)
    precision = tp / (tp + fp) if (tp + fp) else None
    recall = tp / (tp + fn) if (tp + fn) else None

    duration_min = max_audio_ms / 60000 if max_audio_ms else 0
    fp_per_5min = fp / (duration_min / 5) if duration_min > 0 else None

    latencies = []
    if start_wall is not None:
        for ev in positions:
            audio_ms = ev.get("audioMs")
            wall_ms = ev.get("wallMs")
            if audio_ms is None or wall_ms is None:
                continue
            latencies.append(wall_ms - (start_wall + audio_ms))
    highlight = {
        "n": len(latencies),
        "median_ms": statistics.median(latencies) if latencies else None,
        "p90_ms": percentile(latencies, 90),
        "max_ms": max(latencies) if latencies else None,
    }

    confirm_delays = []
    for ev in confirmed:
        first = suspected_first_wall.get(ev["payload"].get("id"))
        if first is not None:
            confirm_delays.append(ev["wallMs"] - first)
    confirm = {
        "n": len(confirm_delays),
        "median_ms": statistics.median(confirm_delays) if confirm_delays else None,
        "max_ms": max(confirm_delays) if confirm_delays else None,
    }

    verse_ok = None
    expected_ayah = truth.get("expected_ayah")
    if expected_ayah:
        for ev in positions:
            p = ev["payload"]
            observed = (p.get("observed") or [{}])[0]
            word = observed.get("word") or {}
            conf = observed.get("confidence")
            if (
                p.get("state") == "locked"
                and isinstance(conf, (int, float))
                and conf >= 0.6
            ):
                audio_ms = ev.get("audioMs") or 0
                verse_ok = (
                    audio_ms <= 5000
                    and word.get("surah") == expected_ayah.get("surah")
                    and word.get("ayah") == expected_ayah.get("ayah")
                )
                break

    return {
        "session_id": truth.get("session_id"),
        "planted": len(planted),
        "predicted_confirmed": len(predicted),
        "true_positives": tp,
        "false_positives": fp,
        "false_negatives": fn,
        "precision": precision,
        "recall": recall,
        "false_warnings_per_5min": fp_per_5min,
        "session_audio_minutes": round(duration_min, 2),
        "highlight_latency_ms": highlight,
        "confirm_delay_ms": confirm,
        "uncertain_events": uncertain,
        "resolved_self_corrections": resolved,
        "verse_found_within_5s": verse_ok,
        "missed_planted": sorted(fn_keys),
        "false_warnings": sorted(fp_keys),
    }


def verdict_line(result):
    def fmt(x, digits=3):
        return "—" if x is None else f"{x:.{digits}f}"

    lines = [
        f"session: {result['session_id']}",
        f"planted={result['planted']} predicted={result['predicted_confirmed']} "
        f"TP={result['true_positives']} FP={result['false_positives']} "
        f"FN={result['false_negatives']}",
        f"precision={fmt(result['precision'])} recall={fmt(result['recall'])}",
        f"false warnings / 5 min: {fmt(result['false_warnings_per_5min'], 2)} "
        f"(audio {result['session_audio_minutes']} min)",
        f"highlight latency: n={result['highlight_latency_ms']['n']} "
        f"median={result['highlight_latency_ms']['median_ms']}ms "
        f"p90={result['highlight_latency_ms']['p90_ms']}ms",
        f"confirm delay (suspected->confirmed): n={result['confirm_delay_ms']['n']} "
        f"median={result['confirm_delay_ms']['median_ms']}ms "
        f"max={result['confirm_delay_ms']['max_ms']}ms",
        f"uncertain={result['uncertain_events']} "
        f"self-corrections={result['resolved_self_corrections']}",
        f"verse found within 5s: {result['verse_found_within_5s']}",
    ]
    if result["missed_planted"]:
        lines.append("missed planted: " + ", ".join(result["missed_planted"]))
    if result["false_warnings"]:
        lines.append("false warnings: " + ", ".join(result["false_warnings"]))
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", required=True)
    ap.add_argument("--truth", required=True)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    events = load_events(Path(args.log))
    truth = json.loads(Path(args.truth).read_text(encoding="utf-8"))
    result = score(events, truth)
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(verdict_line(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
