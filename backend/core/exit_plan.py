"""
core/exit_plan.py — Stop and target exit planner adapted from original exit.py.

Sets the stop and target before entering a long trade:
  - Stops: or-mid, or-low, price:X, pct:X, atr:K
  - Targets: 1R, 1.5R, 2R, ..., price:X
  - Longs only: stop < entry < target
"""
import datetime
import json
import logging
import math
import os
import re
from decimal import Decimal, InvalidOperation, ROUND_FLOOR, ROUND_HALF_UP
from typing import Dict, Any, Optional, Tuple, List

import pytz

from config import PLAN_PATH, CONFIG_PATH, DEFAULT_CONFIG
from core.yahoo import get_bars

logger = logging.getLogger(__name__)

ET = pytz.timezone("America/New_York")
CENT = Decimal("0.01")
MIN_RISK_PCT = Decimal("0.05")  # risk under 0.05% of price is inside spread noise
NOTE = "A stop is a plan, not a guarantee: a gap or a fast market can fill past it."


class PlanError(Exception):
    pass


def _D(x, what: str = "a number") -> Decimal:
    try:
        if isinstance(x, float):
            return Decimal(repr(x))
        return Decimal(str(x).strip().lstrip("$").replace(",", ""))
    except (InvalidOperation, ValueError):
        raise PlanError(f"{what} is not a valid number: {x!r}")


def _cents(x) -> Decimal:
    """Round half up to the cent."""
    return _D(x).quantize(CENT, rounding=ROUND_HALF_UP)


def _floor_cents(x) -> Decimal:
    """A long's stop rounds DOWN away from the entry."""
    return _D(x).quantize(CENT, rounding=ROUND_FLOOR)


def _parse_stop(text: str) -> Tuple[str, Optional[Decimal]]:
    t = str(text).strip().lower()
    if t in ("or-mid", "or_mid", "mid", "or-midpoint"):
        return "or_mid", None
    if t in ("or-low", "or_low", "low"):
        return "or_low", None
    m = re.match(r"^(price|pct|atr):\s*\$?([0-9][0-9,]*\.?[0-9]*)$", t)
    if not m:
        raise PlanError(f"stop must be or-mid, or-low, price:X, pct:X, or atr:K (got {text!r})")
    kind, val = m.group(1), _D(m.group(2), "stop")
    if val <= 0:
        raise PlanError(f"stop {kind} needs a number above 0")
    if kind == "pct" and val >= 100:
        raise PlanError("stop pct:X needs X under 100")
    return kind, val


def _parse_target(text: str) -> Tuple[str, Decimal]:
    t = str(text).strip()
    m = re.match(r"^([0-9]*\.?[0-9]+)\s*[Rr]$", t)
    if m:
        r = _D(m.group(1), "target")
        if r <= 0:
            raise PlanError("target needs an R multiple above 0, e.g. 1R, 2R")
        return "r", r
    m = re.match(r"^price:\s*\$?([0-9][0-9,]*\.?[0-9]*)$", t.lower())
    if m:
        return "price", _D(m.group(1), "target")
    raise PlanError(f"target must be 1R, 1.5R, 2R... or price:X (got {text!r})")


def compute_atr(symbol: str, interval: str = "5m", n: int = 14) -> Optional[float]:
    """Compute ATR over the last n bars from yfinance intraday data."""
    try:
        df = get_bars(symbol, period="5d", interval=interval)
        if df.empty or len(df) < 3:
            return None
        high = df["High"].values
        low = df["Low"].values
        close = df["Close"].values
        trs = []
        for i in range(1, len(df)):
            tr = max(high[i] - low[i], abs(high[i] - close[i - 1]), abs(low[i] - close[i - 1]))
            trs.append(tr)
        if not trs:
            return None
        use = trs[-n:]
        return sum(use) / len(use)
    except Exception as exc:
        logger.warning("compute_atr failed for %s: %s", symbol, exc)
        return None


def compute_plan(
    symbol: str,
    entry: float,
    or_high: Optional[float] = None,
    or_low: Optional[float] = None,
    stop_type: str = "or-mid",
    target_type: str = "2R",
    flat_by: str = "15:55",
    setup: str = "orb",
    or_minutes: int = 15,
) -> Dict[str, Any]:
    """
    Computes an exit plan for a long trade.
    """
    sym = symbol.upper()
    e = _cents(entry)
    if e <= 0:
        raise PlanError("Entry price must be positive")

    stop_rule, stop_param = _parse_stop(stop_type)
    target_rule, target_param = _parse_target(target_type)

    detail = ""
    if stop_rule in ("or_mid", "or_low"):
        if or_high is None or or_low is None:
            raise PlanError(f"Stop {stop_type} requires or_high and or_low")
        oh, ol = _cents(or_high), _cents(or_low)
        if oh <= ol:
            raise PlanError(f"Opening range high (${oh}) must be above low (${ol})")
        if stop_rule == "or_mid":
            raw = (oh + ol) / 2
            label = "opening-range midpoint"
            detail = f"(${oh} + ${ol}) / 2 = ${raw:.2f}"
        else:
            raw, label = ol, "opening-range low"
    elif stop_rule == "price":
        raw, label = stop_param, "custom price"
    elif stop_rule == "pct":
        raw = e * (1 - stop_param / 100)
        label = f"{stop_param}% under entry"
        detail = f"${e} x (1 - {stop_param}%) = ${raw:.2f}"
    elif stop_rule == "atr":
        atr_val = compute_atr(sym)
        if atr_val is None:
            raise PlanError("Could not calculate ATR from market data")
        raw = e - stop_param * _D(round(atr_val, 4))
        label = f"{stop_param}x ATR(14) under entry"
        detail = f"ATR = ${atr_val:.4f}"
    else:
        raise PlanError(f"Unknown stop rule: {stop_rule}")

    stop = _floor_cents(raw)
    if stop >= e:
        raise PlanError(f"Stop (${stop}) is at or above entry (${e}): a long stop must be below entry")
    if stop <= 0:
        raise PlanError(f"Stop (${stop}) must be above $0")

    risk = e - stop
    floor_risk = e * MIN_RISK_PCT / 100
    if risk < floor_risk:
        raise PlanError(
            f"Risk (${risk:.2f}) is under 0.05% of price (${e:.2f}): too tight to survive spread"
        )

    if target_rule == "r":
        target = _cents(e + target_param * risk)
        t_label = f"{target_param}R target"
        rr = target_param
    else:
        target = _cents(target_param)
        t_label = f"custom target ${target}"
        rr = ((target - e) / risk).quantize(CENT, rounding=ROUND_HALF_UP)

    if target <= e:
        raise PlanError(f"Target (${target}) is at or below entry (${e}): target must be above entry")

    now_et = datetime.datetime.now(ET)
    orr = None
    if or_high is not None and or_low is not None:
        orr = {"high": float(_cents(or_high)), "low": float(_cents(or_low)), "minutes": or_minutes}

    plan_doc = {
        "created_by": "trader-exit",
        "symbol": sym,
        "side": "buy",
        "date": now_et.date().isoformat(),
        "setup": setup,
        "entry": float(e),
        "stop": float(stop),
        "stop_rule": stop_rule,
        "stop_label": label,
        "stop_detail": detail,
        "target": float(target),
        "target_r": float(rr),
        "target_label": t_label,
        "risk_per_share": float(risk),
        "reward_risk": float(rr),
        "flat_by": flat_by,
        "opening_range": orr,
        "created_at": now_et.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "note": NOTE,
    }
    return plan_doc


def save_plan(plan: Dict[str, Any], path=PLAN_PATH) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(plan, f, indent=2)


def get_current_plan(path=PLAN_PATH) -> Optional[Dict[str, Any]]:
    if not os.path.exists(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as exc:
        logger.warning("Could not read plan from %s: %s", path, exc)
        return None
