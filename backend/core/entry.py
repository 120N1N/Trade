"""
core/entry.py — Entry timer logic adapted from the original entry.py.

Checks whether an ORB or level setup has triggered for a given ticker.
"""
import datetime
import logging
from typing import Dict, Any, Optional

import pandas as pd
import pytz

from core.yahoo import get_bars

logger = logging.getLogger(__name__)

ET = pytz.timezone("America/New_York")
BAR_MIN = 5
STEP_SECONDS = {"5m": 300, "1m": 60}


def _session_bars(df: pd.DataFrame, day: datetime.date, interval: str, now_et: datetime.datetime):
    """Return closed, on-grid bars for the session, oldest first."""
    step = STEP_SECONDS.get(interval, 300)
    if df.empty:
        return []

    idx = df.index
    if idx.tz is None:
        idx = idx.tz_localize("UTC").tz_convert(ET)
    else:
        idx = idx.tz_convert(ET)

    open_dt = datetime.datetime.combine(day, datetime.time(9, 30)).replace(tzinfo=ET)
    close_dt = datetime.datetime.combine(day, datetime.time(16, 0)).replace(tzinfo=ET)

    out = {}
    for i, ts in enumerate(idx):
        if ts.date() != day:
            continue
        # Must be on the interval grid (seconds == 0, minute divisible by step/60)
        if ts.second != 0 or (ts.minute * 60) % step != 0:
            continue
        if ts < open_dt or ts >= close_dt:
            continue
        bar_end = ts + datetime.timedelta(seconds=step)
        if bar_end > now_et:
            continue  # bar still in progress

        row = df.iloc[i]
        c = float(row["Close"]) if not pd.isna(row["Close"]) else None
        if c is None:
            continue
        slot = int((ts - open_dt).total_seconds()) // step
        out[slot] = {
            "slot": slot,
            "start": ts.strftime("%H:%M"),
            "end": bar_end.strftime("%H:%M"),
            "o": float(row["Open"]) if not pd.isna(row["Open"]) else c,
            "h": float(row["High"]) if not pd.isna(row["High"]) else c,
            "l": float(row["Low"]) if not pd.isna(row["Low"]) else c,
            "c": c,
            "v": int(row["Volume"]) if not pd.isna(row["Volume"]) else 0,
        }
    return [out[k] for k in sorted(out)]


def check_entry(
    symbol: str,
    setup: str = "orb",
    interval: str = "5m",
    or_minutes: int = 15,
    level: Optional[float] = None,
    cfg: Optional[Dict] = None,
) -> Dict[str, Any]:
    """
    Check whether a setup has triggered for the given symbol today.
    Returns a dict with status, trigger details, and opening range.
    """
    cfg = cfg or {}
    no_before = cfg.get("no_entries_before", "09:45")
    no_after = cfg.get("no_entries_after", "15:30")

    now_et = datetime.datetime.now(ET)
    day = now_et.date()

    result: Dict[str, Any] = {
        "symbol": symbol.upper(),
        "setup": setup,
        "interval": interval,
        "or_minutes": or_minutes,
        "date": day.isoformat(),
        "now": now_et.strftime("%Y-%m-%d %H:%M:%S"),
        "status": "waiting",
        "phase": "",
        "reason": "",
        "opening_range": None,
        "trigger": None,
        "level": level,
    }

    # Check if market is open
    open_dt = datetime.datetime.combine(day, datetime.time(9, 30)).replace(tzinfo=ET)
    close_dt = datetime.datetime.combine(day, datetime.time(16, 0)).replace(tzinfo=ET)

    if now_et < open_dt:
        result.update(phase="pre-open", reason="Market opens at 9:30 ET")
        return result

    if now_et >= close_dt:
        result.update(status="expired", phase="closed", reason="Market is closed")
        return result

    try:
        df = get_bars(symbol.upper(), period="1d", interval=interval)
    except Exception as exc:
        result.update(status="no-data", reason=str(exc))
        return result

    bars = _session_bars(df, day, interval, now_et)
    result["bars_closed"] = len(bars)

    step = STEP_SECONDS.get(interval, 300)
    n_or = (or_minutes * 60) // step
    or_bars = [b for b in bars if b["slot"] < n_or]

    # Compute opening range
    if or_bars:
        oh = max(b["h"] for b in or_bars)
        ol = min(b["l"] for b in or_bars)
        avg_vol = sum(b["v"] for b in or_bars) / len(or_bars) if or_bars else None
        result["opening_range"] = {
            "high": round(oh, 2),
            "low": round(ol, 2),
            "minutes": or_minutes,
            "bars": len(or_bars),
            "of": n_or,
            "complete": len(or_bars) >= n_or,
            "avg_volume": int(round(avg_vol)) if avg_vol else None,
        }

    if setup == "orb":
        # Range still forming?
        or_end = open_dt + datetime.timedelta(minutes=or_minutes)
        if now_et < or_end:
            result.update(
                phase="forming",
                reason=f"{len(or_bars)} of {n_or} range bars closed; range set at {or_end.strftime('%H:%M')}",
            )
            return result

        if not or_bars:
            result.update(status="no-data", phase="open", reason="No bars for the opening range")
            return result

        lvl = max(b["h"] for b in or_bars)
        result["level"] = round(lvl, 2)

    elif setup == "level":
        if level is None:
            result.update(status="error", reason="level setup requires a level price")
            return result
        lvl = float(level)
    else:
        result.update(status="error", reason=f"Unknown setup: {setup}")
        return result

    # Parse time window constraints
    def parse_hm(s):
        h, m = map(int, s.split(":"))
        return datetime.datetime.combine(day, datetime.time(h, m)).replace(tzinfo=ET)

    before_dt = parse_hm(no_before)
    after_dt = parse_hm(no_after)

    # Scan for trigger
    first_slot = n_or if setup == "orb" else 0
    trig = None
    for b in bars:
        if b["slot"] < first_slot:
            continue
        # Check time window
        bar_end_dt = datetime.datetime.combine(day, datetime.time(0, 0)).replace(tzinfo=ET)
        try:
            h2, m2 = map(int, b["end"].split(":"))
            bar_end_dt = datetime.datetime.combine(day, datetime.time(h2, m2)).replace(tzinfo=ET)
        except Exception:
            pass
        if bar_end_dt < before_dt or bar_end_dt > after_dt:
            continue
        if b["c"] > lvl:
            trig = b
            break

    if trig:
        result.update(
            status="triggered",
            phase="open",
            reason=f"The {trig['start']} bar closed above the {'range high' if setup == 'orb' else 'level'}",
        )
        result["trigger"] = {
            "time": trig["end"],
            "bar_start": trig["start"],
            "bar_index": trig["slot"],
            "price": round(trig["c"], 2),
            "volume": trig["v"],
            "pct_over": round((trig["c"] / lvl - 1) * 100, 2),
        }
        return result

    # Not triggered
    if bars:
        last = bars[-1]
        gap = lvl - last["c"]
        result["last"] = {
            "bar_start": last["start"],
            "close": round(last["c"], 2),
            "vs_level_pct": round((last["c"] / lvl - 1) * 100, 2),
        }
        result["reason"] = (
            f"Last close ${last['c']:.2f} ({last['start']} bar), "
            f"${abs(gap):.2f} {'under' if gap >= 0 else 'over'} the level ${lvl:.2f} "
            f"({(last['c'] / lvl - 1) * 100:+.2f}%)"
        )

    # Check expiry
    if now_et >= after_dt:
        result.update(status="expired", phase="after-cutoff",
                      reason=f"No trigger by {no_after}, the last time for a new entry")

    return result


def get_opening_range(symbol: str, or_minutes: int = 15) -> Dict[str, Any]:
    """Return the opening range (high, low) for today's session."""
    now_et = datetime.datetime.now(ET)
    day = now_et.date()

    try:
        df = get_bars(symbol.upper(), period="1d", interval="5m")
    except Exception as exc:
        return {"symbol": symbol.upper(), "error": str(exc)}

    bars = _session_bars(df, day, "5m", now_et)
    n_or = or_minutes // 5
    or_bars = [b for b in bars if b["slot"] < n_or]

    if not or_bars:
        return {
            "symbol": symbol.upper(),
            "or_minutes": or_minutes,
            "complete": False,
            "bars_received": 0,
            "bars_needed": n_or,
        }

    oh = max(b["h"] for b in or_bars)
    ol = min(b["l"] for b in or_bars)
    avg_vol = sum(b["v"] for b in or_bars) / len(or_bars)

    return {
        "symbol": symbol.upper(),
        "or_minutes": or_minutes,
        "high": round(oh, 2),
        "low": round(ol, 2),
        "midpoint": round((oh + ol) / 2, 2),
        "range": round(oh - ol, 2),
        "bars": len(or_bars),
        "of": n_or,
        "complete": len(or_bars) >= n_or,
        "avg_volume": int(round(avg_vol)),
        "date": day.isoformat(),
    }
