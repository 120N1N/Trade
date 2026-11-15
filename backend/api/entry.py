"""
api/entry.py — Entry timer endpoints:
  - GET /api/entry/{ticker}
  - GET /api/entry/{ticker}/range
"""
import json
import os
from typing import Optional
from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel

from config import ENTRY_PATH, CONFIG_PATH, DEFAULT_CONFIG
from core.entry import check_entry, get_opening_range

router = APIRouter(prefix="/entry", tags=["Entry Timer"])


def _load_config():
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return DEFAULT_CONFIG


@router.get("/{ticker}")
def get_entry_status(
    ticker: str,
    setup: str = Query("orb", description="Setup name: orb or level"),
    interval: str = Query("5m", description="Bar interval: 5m or 1m"),
    or_minutes: int = Query(15, description="Opening range minutes: 15"),
    level: Optional[float] = Query(None, description="Trigger level for level setup"),
    save: bool = Query(False, description="Whether to write to trader/entry.json if triggered"),
):
    try:
        cfg = _load_config()
        result = check_entry(
            symbol=ticker,
            setup=setup,
            interval=interval,
            or_minutes=or_minutes,
            level=level,
            cfg=cfg,
        )
        if save and result.get("status") == "triggered":
            os.makedirs(os.path.dirname(ENTRY_PATH), exist_ok=True)
            with open(ENTRY_PATH, "w", encoding="utf-8") as f:
                json.dump(result, f, indent=2)
        return result
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/{ticker}/range")
def get_range(
    ticker: str,
    or_minutes: int = Query(15, description="Opening range minutes (default 15)"),
):
    try:
        return get_opening_range(symbol=ticker, or_minutes=or_minutes)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
