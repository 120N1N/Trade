"""
core/check.py — Pre-trade risk checker adapted from original check.py.

Checks orders (or plan) against trading config rules:
  - blocked symbols
  - order size (min/max USD)
  - position cap (% of budget)
  - cash buffer protection
  - max loss per trade
  - min reward:risk ratio
  - max trades per day
  - entry time window (no_entries_before, no_entries_after)
"""
import datetime
import logging
from typing import Dict, Any, List, Optional

import pytz

from config import CONFIG_PATH, ORDERS_PATH, DEFAULT_CONFIG

logger = logging.getLogger(__name__)

ET = pytz.timezone("America/New_York")


def check_orders(
    orders: List[Dict[str, Any]],
    cfg: Optional[Dict[str, Any]] = None,
    now_et: Optional[datetime.datetime] = None,
) -> Dict[str, Any]:
    """
    Check a list of proposed orders against config limits.
    Returns: { "results": [...], "pass": count, "block": count, "warnings": [...] }
    """
    c = dict(DEFAULT_CONFIG)
    if cfg:
        c.update(cfg)

    if now_et is None:
        now_et = datetime.datetime.now(ET)

    results = []
    budget = float(c.get("budget", 5000))
    cash_buf_pct = float(c.get("cash_buffer_pct", 10))
    buffer_usd = budget * cash_buf_pct / 100.0
    max_loss_cap = float(c.get("max_loss_per_trade_usd", 50))
    min_rr_cap = float(c.get("min_reward_risk", 1.0))
    min_order_cap = float(c.get("min_order_usd", 5))
    max_order_cap = float(c.get("max_order_usd", 4000))
    max_pos_pct = float(c.get("max_position_pct", 75))
    pos_cap_usd = budget * max_pos_pct / 100.0
    blocked_list = set(s.upper() for s in (c.get("blocked") or []))

    no_before = c.get("no_entries_before", "09:45")
    no_after = c.get("no_entries_after", "15:30")

    warnings = []
    if c.get("paper", True):
        warnings.append("Paper trading mode active (simulated orders only)")
    else:
        warnings.append("LIVE trading mode active: real money at risk")

    for idx, o in enumerate(orders, 1):
        reasons = []
        warns = []
        sym = str(o.get("symbol", "")).upper()
        side = str(o.get("side", "buy")).lower()
        qty = float(o.get("qty", 0))

        # Check format
        if not sym:
            reasons.append("Missing symbol")
        if side not in ("buy", "sell"):
            reasons.append(f"Invalid side: {side}")
        if qty <= 0:
            reasons.append(f"Invalid qty: {qty}")

        # Blocked list
        if sym in blocked_list:
            reasons.append(f"{sym} is on your blocked list")

        # Plan info
        plan = o.get("plan", {})
        entry = float(plan.get("entry", 0))
        stop = float(plan.get("stop", o.get("stop_loss_stop_price", 0)))
        target = float(plan.get("target", o.get("take_profit_limit_price", 0)))

        order_val = qty * entry if entry > 0 else 0

        # Min / Max Order size
        if order_val > 0:
            if order_val < min_order_cap:
                reasons.append(f"Order value ${order_val:.2f} is under min ${min_order_cap:.2f}")
            if order_val > max_order_cap:
                reasons.append(f"Order value ${order_val:.2f} exceeds max order ${max_order_cap:.2f}")
            if order_val > pos_cap_usd:
                reasons.append(
                    f"Position ${order_val:.2f} exceeds {max_pos_pct}% cap (${pos_cap_usd:.2f})"
                )

        # Stop & Risk checks
        if c.get("require_stop", True) and stop <= 0:
            reasons.append("Missing stop price (require_stop is enabled)")
        elif stop > 0 and entry > 0:
            if stop >= entry:
                reasons.append(f"Stop (${stop:.2f}) must be below entry (${entry:.2f})")
            else:
                risk_per_share = entry - stop
                max_loss = qty * risk_per_share
                if max_loss > max_loss_cap + 0.01:
                    reasons.append(
                        f"Max loss ${max_loss:.2f} ({qty} shares x ${risk_per_share:.2f}) "
                        f"exceeds limit ${max_loss_cap:.2f}"
                    )

                if target > 0:
                    reward = target - entry
                    rr = reward / risk_per_share if risk_per_share > 0 else 0
                    if rr < min_rr_cap - 0.001:
                        reasons.append(
                            f"Reward:risk {rr:.2f} is under minimum {min_rr_cap:.2f}"
                        )

        # Time Window check (entry orders)
        if no_before or no_after:
            t_curr = now_et.time()
            if no_before:
                hb, mb = map(int, no_before.split(":"))
                if t_curr < datetime.time(hb, mb):
                    warns.append(f"Entry before {no_before} ET (window starts at {no_before})")
            if no_after:
                ha, ma = map(int, no_after.split(":"))
                if t_curr > datetime.time(ha, ma):
                    reasons.append(f"Entry after {no_after} ET (window ends at {no_after})")

        verdict = "BLOCK" if reasons else "PASS"
        results.append({
            "index": idx,
            "symbol": sym,
            "side": side,
            "qty": qty,
            "order_value": round(order_val, 2),
            "verdict": verdict,
            "reasons": reasons,
            "warnings": warns,
        })

    passes = sum(1 for r in results if r["verdict"] == "PASS")
    blocks = sum(1 for r in results if r["verdict"] == "BLOCK")

    return {
        "checked_at": now_et.strftime("%Y-%m-%d %H:%M:%S"),
        "paper": c.get("paper", True),
        "results": results,
        "pass": passes,
        "block": blocks,
        "warnings": warnings,
    }
