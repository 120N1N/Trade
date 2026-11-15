"""
core/timemachine.py — Monte Carlo simulation and historical replay adapted from timemachine.py.

Simulates 10,000 runs of the rest of the day from entry using ratio-based bar sampling
from 60 days of historical 5-minute bars. Also replays the rule across past full sessions.
"""
import datetime
import logging
import random
import statistics
from typing import Dict, Any, List, Optional, Tuple

import pandas as pd
import pytz

from core.yahoo import get_60d_bars

logger = logging.getLogger(__name__)

ET = pytz.timezone("America/New_York")
INTERVAL_SECONDS = 300
SESSION_BARS = 78  # 9:30 to 16:00 ET in 5-minute bars (78 bars)
OPEN_MIN = 9 * 60 + 30
CLOSE_MIN = 16 * 60
MIN_SESSIONS = 10  # allow at least 10 full sessions
SAMPLE_PATHS_COUNT = 50
BAND_PATHS_COUNT = 1000
BAND_Q = (0.05, 0.25, 0.5, 0.75, 0.95)


def _split_into_sessions(df: pd.DataFrame) -> Tuple[List[Tuple[str, List[Dict]]], List[Dict]]:
    """
    Split 60d DataFrame into full 78-bar sessions.
    Returns (full_sessions, short_sessions).
    """
    if df.empty:
        return [], []

    idx = df.index
    if idx.tz is None:
        idx = idx.tz_localize("UTC").tz_convert(ET)
    else:
        idx = idx.tz_convert(ET)

    days: Dict[str, Dict[int, Dict]] = {}

    for i, ts in enumerate(idx):
        if ts.second != 0 or ts.minute % 5 != 0:
            continue
        mins = ts.hour * 60 + ts.minute - OPEN_MIN
        if mins < 0 or mins >= SESSION_BARS * 5:
            continue
        slot = mins // 5

        row = df.iloc[i]
        c = float(row["Close"]) if not pd.isna(row["Close"]) else None
        o = float(row["Open"]) if not pd.isna(row["Open"]) else c
        h = float(row["High"]) if not pd.isna(row["High"]) else c
        l = float(row["Low"]) if not pd.isna(row["Low"]) else c
        if None in (c, o, h, l):
            continue

        d_str = ts.date().isoformat()
        if d_str not in days:
            days[d_str] = {}
        days[d_str][slot] = {
            "slot": slot,
            "start": ts.strftime("%H:%M"),
            "o": o, "h": h, "l": l, "c": c,
            "v": int(row["Volume"]) if not pd.isna(row["Volume"]) else 0,
        }

    full, short = [], []
    for d in sorted(days.keys()):
        s = days[d]
        if len(s) == SESSION_BARS:
            full.append((d, [s[i] for i in range(SESSION_BARS)]))
        else:
            short.append({"date": d, "bars": len(s)})

    return full, short


def _build_pool(sessions: List[Tuple[str, List[Dict]]]) -> List[List[Tuple[float, float, float, float]]]:
    """
    pool[i] = list of (o/pc, h/pc, l/pc, c/pc) for bar slot i from all past sessions.
    """
    pool = [[] for _ in range(SESSION_BARS)]
    for _, s_bars in sessions:
        for i in range(1, SESSION_BARS):
            pc = s_bars[i - 1]["c"]
            if pc > 0:
                pool[i].append((
                    s_bars[i]["o"] / pc,
                    s_bars[i]["h"] / pc,
                    s_bars[i]["l"] / pc,
                    s_bars[i]["c"] / pc,
                ))
    return pool


def _pct(a: List[float], q: float) -> float:
    return a[min(len(a) - 1, int(q * len(a)))]


def _simulate(
    pool: List[List[Tuple[float, float, float, float]]],
    entry: float,
    stop: float,
    target: float,
    entry_bar: int,
    last_bar: int,
    replays: int = 10000,
    seed: int = 19,
    window: int = 2,
    side: str = "buy",
) -> Dict[str, Any]:
    """
    Run Monte Carlo simulation matching original timemachine.py.
    """
    long = side == "buy"
    risk = (entry - stop) if long else (stop - entry)
    r_target = round(((target - entry) if long else (entry - target)) / risk, 4)

    def get_slot(rng, i):
        if window == 0:
            return i
        return min(SESSION_BARS - 1, max(1, i + rng.randint(-window, window)))

    rng = random.Random(seed)
    choice = rng.choice
    outcomes, closes, sample_paths = [], [], []

    for n in range(replays):
        p = entry
        outcome = None
        keep = n < SAMPLE_PATHS_COUNT
        path = [round(entry, 2)]

        for i in range(entry_bar + 1, last_bar + 1):
            bar_pool = pool[get_slot(rng, i)]
            if not bar_pool:
                continue
            o, h, l, c = choice(bar_pool)
            hi, lo, cl = p * h, p * l, p * c

            if outcome is None:
                if long:
                    # Conservative: stop is checked before target
                    if lo <= stop:
                        outcome = "stop"
                    elif hi >= target:
                        outcome = "target"
                else:
                    if hi >= stop:
                        outcome = "stop"
                    elif lo <= target:
                        outcome = "target"

            p = cl
            if keep:
                path.append(round(p, 2))

        outcomes.append(outcome or "close")
        closes.append(p)
        if keep:
            sample_paths.append(path)

    cnt = {x: outcomes.count(x) for x in ("target", "stop", "close")}
    green = sum(1 for o, p in zip(outcomes, closes)
                if o == "target" or (o == "close" and (p > entry if long else p < entry)))

    Rs = [
        r_target if o == "target" else -1.0 if o == "stop" else ((p - entry) if long else (entry - p)) / risk
        for o, p in zip(outcomes, closes)
    ]
    srt = sorted(closes)

    # Fan chart percentile bands
    rng_band = random.Random(seed)
    choice_band = rng_band.choice
    allp = []
    for _ in range(BAND_PATHS_COUNT):
        p = entry
        path = [entry]
        for i in range(entry_bar + 1, last_bar + 1):
            bar_pool = pool[get_slot(rng_band, i)]
            if bar_pool:
                o, h, l, c = choice_band(bar_pool)
                p = p * c
            path.append(p)
        allp.append(path)

    bands = []
    num_steps = last_bar - entry_bar + 1
    for j in range(num_steps):
        col = sorted(pp[j] for pp in allp if len(pp) > j)
        if col:
            bands.append([round(_pct(col, q), 2) for q in BAND_Q])

    p_target = cnt["target"] / replays
    p_stop = cnt["stop"] / replays
    p_close = cnt["close"] / replays

    return {
        "replays": replays,
        "seed": seed,
        "bars_left": last_bar - entry_bar,
        "p_target": round(p_target, 4),
        "p_stop": round(p_stop, 4),
        "p_neither": round(p_close, 4),
        "p_green": round(green / replays, 4),
        "win_rate": round(p_target * 100, 1),
        "stop_rate": round(p_stop * 100, 1),
        "flat_rate": round(p_close * 100, 1),
        "median_close": round(_pct(srt, 0.5), 2),
        "p5_close": round(_pct(srt, 0.05), 2),
        "p95_close": round(_pct(srt, 0.95), 2),
        "avg_r": round(statistics.mean(Rs), 3) if Rs else 0.0,
        "sample_paths": sample_paths,
        "bands": bands,
    }


def _history_replay(
    sessions: List[Tuple[str, List[Dict]]],
    or_minutes: int,
    target_r: float,
    stop_rule: str,
    stop_pct: float,
    last_bar: int,
) -> Dict[str, Any]:
    """Replay the ORB rule on each past session."""
    n = or_minutes // 5
    trades = []

    for d, s_bars in sessions:
        if len(s_bars) <= n:
            continue
        oh = max(b["h"] for b in s_bars[:n])
        ol = min(b["l"] for b in s_bars[:n])

        # Find first close above range high
        kk = next((i for i in range(n, last_bar + 1) if s_bars[i]["c"] > oh), None)
        if kk is None:
            continue

        e = round(s_bars[kk]["c"], 2)
        if stop_rule == "or_mid":
            s = round((oh + ol) / 2, 2)
        elif stop_rule == "or_low":
            s = round(ol, 2)
        else:
            s = round(e * (1 - stop_pct / 100.0), 2)

        risk = e - s
        if risk <= 0:
            continue

        t = round(e + target_r * risk, 2)
        outcome = None

        for b in s_bars[kk + 1:last_bar + 1]:
            if b["l"] <= s:
                outcome = "stop"
                break
            if b["h"] >= t:
                outcome = "target"
                break

        cl = s_bars[last_bar]["c"]
        R = target_r if outcome == "target" else -1.0 if outcome == "stop" else (cl - e) / risk

        trades.append({
            "date": d,
            "entry": e,
            "stop": s,
            "target": t,
            "outcome": outcome or "close",
            "pnl_r": round(R, 2),
        })

    return {
        "total_sessions": len(sessions),
        "triggered": len(trades),
        "target_hits": sum(1 for x in trades if x["outcome"] == "target"),
        "stop_hits": sum(1 for x in trades if x["outcome"] == "stop"),
        "close_hits": sum(1 for x in trades if x["outcome"] == "close"),
        "trades": trades[:20],  # return recent 20 for display
    }


def run_timemachine(
    symbol: str,
    entry: float,
    stop: float,
    target: float,
    entry_time: str = "10:15",
    until: str = "15:55",
    replays: int = 10000,
    seed: int = 19,
    or_minutes: int = 15,
) -> Dict[str, Any]:
    """
    Main entry point for Time Machine run.
    """
    sym = symbol.upper()
    df = get_60d_bars(sym)
    if df.empty:
        raise ValueError(f"No 60-day market data found for {sym}")

    full_sessions, _ = _split_into_sessions(df)
    if len(full_sessions) < MIN_SESSIONS:
        # If fewer full sessions (e.g. recent IPO or holiday period), fall back with warning
        logger.warning(
            "Found %d full sessions for %s (preferred >= %d)",
            len(full_sessions), sym, MIN_SESSIONS
        )
        if len(full_sessions) < 3:
            raise ValueError(f"Too few complete trading days for {sym} ({len(full_sessions)} found)")

    # Compute entry bar index (slot)
    try:
        h, m = map(int, entry_time.replace("AM", "").replace("PM", "").strip().split(":"))
        mins = h * 60 + m - OPEN_MIN
        entry_bar = max(0, min(SESSION_BARS - 2, mins // 5))
    except Exception:
        entry_bar = 9  # default ~ 10:15 AM

    # Compute last bar index (slot)
    try:
        h2, m2 = map(int, until.split(":"))
        mins2 = h2 * 60 + m2 - OPEN_MIN
        last_bar = max(entry_bar + 1, min(SESSION_BARS - 1, mins2 // 5))
    except Exception:
        last_bar = SESSION_BARS - 1

    pool = _build_pool(full_sessions)
    mc = _simulate(
        pool=pool,
        entry=entry,
        stop=stop,
        target=target,
        entry_bar=entry_bar,
        last_bar=last_bar,
        replays=replays,
        seed=seed,
    )

    risk = entry - stop
    target_r = (target - entry) / risk if risk > 0 else 2.0
    history = _history_replay(
        sessions=full_sessions,
        or_minutes=or_minutes,
        target_r=target_r,
        stop_rule="or_mid",
        stop_pct=(risk / entry) * 100,
        last_bar=last_bar,
    )

    # Prepare fan chart data for frontend recharts
    # Format: list of { step, p5, p25, median, p75, p95, ...sample paths }
    fan_data = []
    bands = mc.get("bands", [])
    sample_paths = mc.get("sample_paths", [])

    for step_idx, band_vals in enumerate(bands):
        point: Dict[str, Any] = {
            "step": step_idx,
            "p5": band_vals[0] if len(band_vals) > 0 else None,
            "p25": band_vals[1] if len(band_vals) > 1 else None,
            "median": band_vals[2] if len(band_vals) > 2 else None,
            "p75": band_vals[3] if len(band_vals) > 3 else None,
            "p95": band_vals[4] if len(band_vals) > 4 else None,
        }
        # Add up to 10 sample paths
        for path_i in range(min(10, len(sample_paths))):
            if step_idx < len(sample_paths[path_i]):
                point[f"path_{path_i}"] = sample_paths[path_i][step_idx]
        fan_data.append(point)

    return {
        "symbol": sym,
        "entry": entry,
        "stop": stop,
        "target": target,
        "win_rate": mc["win_rate"],
        "stop_rate": mc["stop_rate"],
        "flat_rate": mc["flat_rate"],
        "avg_r": mc["avg_r"],
        "median_close": mc["median_close"],
        "p5_close": mc["p5_close"],
        "p95_close": mc["p95_close"],
        "replays": replays,
        "sessions_analyzed": len(full_sessions),
        "history": history,
        "fan_data": fan_data,
        "sample_paths": sample_paths[:20],
    }
