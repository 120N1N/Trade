"""
api/risk.py — Risk checking and config endpoints:
  - GET /api/risk/check
  - POST /api/risk/check
  - GET /api/risk/config
  - POST /api/risk/config
"""
import json
import os
from typing import Optional, Dict, Any, List
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from config import ORDERS_PATH, CONFIG_PATH, DEFAULT_CONFIG
from core.check import check_orders

router = APIRouter(prefix="/risk", tags=["Risk Management"])


class ConfigUpdateRequest(BaseModel):
    config: Dict[str, Any]


class RiskCheckRequest(BaseModel):
    orders: Optional[List[Dict[str, Any]]] = None
    config: Optional[Dict[str, Any]] = None


def _load_config():
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return dict(DEFAULT_CONFIG)


def _load_orders():
    if os.path.exists(ORDERS_PATH):
        try:
            with open(ORDERS_PATH, "r", encoding="utf-8") as f:
                doc = json.load(f)
                return doc.get("orders", []) if isinstance(doc, dict) else doc
        except Exception:
            pass
    return []


@router.get("/check")
def check_saved_orders():
    """Check orders currently in trader/orders.json against trader/config.json."""
    try:
        cfg = _load_config()
        orders = _load_orders()
        if not orders:
            return {
                "checked_at": "",
                "paper": cfg.get("paper", True),
                "results": [],
                "pass": 0,
                "block": 0,
                "warnings": ["No proposed orders in trader/orders.json to check"],
            }
        return check_orders(orders=orders, cfg=cfg)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.post("/check")
def check_custom_orders(req: RiskCheckRequest):
    """Check provided orders against provided or current config."""
    try:
        cfg = _load_config()
        if req.config:
            cfg.update(req.config)
        orders = req.orders if req.orders is not None else _load_orders()
        return check_orders(orders=orders, cfg=cfg)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/config")
def get_config():
    """Return the current trading config."""
    return _load_config()


@router.post("/config")
def update_config(req: ConfigUpdateRequest):
    """Update and persist config in trader/config.json."""
    try:
        current = _load_config()
        current.update(req.config)
        os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
        with open(CONFIG_PATH, "w", encoding="utf-8") as f:
            json.dump(current, f, indent=2)
        return {"status": "ok", "config": current}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
