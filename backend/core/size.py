"""
core/size.py — Position sizing adapted from original size.py.

Sizes one day trade from a plan and config to determine shares to buy,
subject to:
  1. max_loss_per_trade_usd / risk_per_share
  2. budget * max_position_pct / entry
  3. max_order_usd / entry
  4. (budget - cash_buffer) / entry
Whole shares only. Generates an Alpaca-style bracket order.
"""
import json
import logging
import math
import os
from typing import Dict, Any, Optional, List

from config import ORDERS_PATH, CONFIG_PATH, DEFAULT_CONFIG

logger = logging.getLogger(__name__)


def _round_cent(x: float) -> float:
    return math.floor(float(x) * 100 + 0.5 + 1e-9) / 100.0


def _shares_for(usd: float, per_share: float) -> int:
    u = int(round(float(usd) * 100))
    p = int(round(float(per_share) * 100))
    if p <= 0 or u <= 0:
        return 0
    return u // p


def size_position(plan: Dict[str, Any], cfg: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """
    Given a plan and config, calculate the optimal position size (whole shares)
    and produce a proposed bracket order.
    """
    c = dict(DEFAULT_CONFIG)
    if cfg:
        c.update(cfg)

    sym = str(plan.get("symbol", "")).strip().upper()
    if not sym:
        raise ValueError("Plan missing symbol")

    entry = _round_cent(float(plan.get("entry", 0)))
    stop = _round_cent(float(plan.get("stop", 0)))
    target = _round_cent(float(plan.get("target", 0)))

    if entry <= 0 or stop <= 0 or target <= 0:
        raise ValueError("Plan entry, stop, and target must be positive numbers")

    if stop >= entry:
        raise ValueError(f"Stop (${stop:.2f}) must be below entry (${entry:.2f})")
    if target <= entry:
        raise ValueError(f"Target (${target:.2f}) must be above entry (${entry:.2f})")

    risk_per_share = round(entry - stop, 2)
    reward_per_share = round(target - entry, 2)
    rr = round(reward_per_share / risk_per_share, 2)

    budget = float(c.get("budget", 5000))
    cash_buf_pct = float(c.get("cash_buffer_pct", 10))
    max_pos_pct = float(c.get("max_position_pct", 75))
    max_order_usd = float(c.get("max_order_usd", 4000))
    max_loss_usd = float(c.get("max_loss_per_trade_usd", 50))
    min_order_usd = float(c.get("min_order_usd", 5))
    min_rr = float(c.get("min_reward_risk", 1.0))

    cash_buffer = round(budget * cash_buf_pct / 100.0, 2)
    available_cash = max(0.0, round(budget - cash_buffer, 2))
    cap_usd = round(budget * max_pos_pct / 100.0, 2)

    limits: List[Dict[str, Any]] = []

    # 1. Max loss constraint
    s_loss = _shares_for(max_loss_usd, risk_per_share)
    limits.append({
        "name": "max loss",
        "shares": s_loss,
        "detail": f"${max_loss_usd:.0f} max loss / ${risk_per_share:.2f} risk/share",
    })

    # 2. Position cap constraint
    s_cap = _shares_for(cap_usd, entry)
    limits.append({
        "name": "position cap",
        "shares": s_cap,
        "detail": f"{max_pos_pct}% of ${budget:.0f} = ${cap_usd:.0f} / ${entry:.2f}",
    })

    # 3. Max order USD constraint
    s_order = _shares_for(max_order_usd, entry)
    limits.append({
        "name": "max order",
        "shares": s_order,
        "detail": f"${max_order_usd:.0f} / ${entry:.2f}",
    })

    # 4. Available cash constraint
    s_cash = _shares_for(available_cash, entry)
    limits.append({
        "name": "cash",
        "shares": s_cash,
        "detail": f"${available_cash:.0f} available cash / ${entry:.2f}",
    })

    qty = min(l["shares"] for l in limits)
    bound_by = next(l["name"] for l in limits if l["shares"] == qty)

    cost = round(qty * entry, 2)
    max_loss = round(qty * risk_per_share, 2)

    # Validate refusal conditions
    refusal = None
    if qty == 0:
        refusal = f"Zero shares: {bound_by} limit restricts trade to 0 shares"
    elif rr < min_rr:
        refusal = f"Reward:Risk {rr:.2f} is below minimum {min_rr:.2f}"
    elif cost < min_order_usd:
        refusal = f"Total order ${cost:.2f} is below minimum ${min_order_usd:.2f}"

    bracket = None
    if not refusal and qty > 0:
        bracket = {
            "symbol": sym,
            "side": "buy",
            "qty": str(qty),
            "type": "market",
            "time_in_force": "day",
            "order_class": "bracket",
            "take_profit_limit_price": f"{target:.2f}",
            "stop_loss_stop_price": f"{stop:.2f}",
            "why": f"ORB day trade: {qty} shares, bound by {bound_by} (${max_loss:.2f} max loss at stop)",
            "plan": {
                "entry": entry,
                "stop": stop,
                "target": target,
                "risk_per_share": risk_per_share,
                "max_loss": max_loss,
                "setup": plan.get("setup", "orb"),
                "flat_by": plan.get("flat_by", "15:55"),
            },
        }

    return {
        "symbol": sym,
        "qty": qty,
        "entry": entry,
        "stop": stop,
        "target": target,
        "risk_per_share": risk_per_share,
        "reward_risk": rr,
        "cost": cost,
        "max_loss": max_loss,
        "bound_by": bound_by,
        "limits": limits,
        "refusal": refusal,
        "bracket_order": bracket,
        "budget": budget,
        "available_cash": available_cash,
    }


def save_orders(orders_doc: Dict[str, Any], path=ORDERS_PATH) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(orders_doc, f, indent=2)


def get_current_orders(path=ORDERS_PATH) -> Optional[Dict[str, Any]]:
    if not os.path.exists(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as exc:
        logger.warning("Could not read orders from %s: %s", path, exc)
        return None
