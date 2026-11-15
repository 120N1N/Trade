"""
api/budget.py — Budget and position sizing endpoints:
  - POST /api/budget/size
  - GET /api/budget/orders
"""
import json
import os
from typing import Optional, Dict, Any
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from config import ORDERS_PATH, CONFIG_PATH, DEFAULT_CONFIG
from core.size import size_position, save_orders, get_current_orders

router = APIRouter(prefix="/budget", tags=["Budget & Sizing"])


class SizeRequest(BaseModel):
    plan: Dict[str, Any] = Field(..., description="Exit plan dict (or entry/stop/target fields)")
    config: Optional[Dict[str, Any]] = Field(None, description="Optional config overrides")
    save_orders: bool = Field(True, description="Whether to write proposed bracket to trader/orders.json")


def _load_config():
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return DEFAULT_CONFIG


@router.post("/size")
def calculate_size(req: SizeRequest):
    try:
        cfg = _load_config()
        if req.config:
            cfg.update(req.config)
        result = size_position(plan=req.plan, cfg=cfg)

        if req.save_orders and result.get("bracket_order"):
            orders_doc = {
                "created_by": "trader-budget",
                "status": "proposed",
                "paper": cfg.get("paper", True),
                "orders": [result["bracket_order"]],
            }
            save_orders(orders_doc)

        return result
    except ValueError as ve:
        raise HTTPException(status_code=400, detail=str(ve))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/orders")
def get_orders():
    orders = get_current_orders()
    if orders is None:
        raise HTTPException(status_code=404, detail="No orders found at trader/orders.json")
    return orders
