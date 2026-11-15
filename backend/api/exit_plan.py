"""
api/exit_plan.py — Exit planner endpoints:
  - POST /api/exit/plan
  - GET /api/exit/plan
"""
from typing import Optional
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from core.exit_plan import compute_plan, save_plan, get_current_plan, PlanError

router = APIRouter(prefix="/exit", tags=["Exit Planner"])


class ExitPlanRequest(BaseModel):
    symbol: str = Field(..., description="Stock ticker, e.g. TSLA")
    entry: float = Field(..., description="Entry price")
    or_high: Optional[float] = Field(None, description="Opening range high")
    or_low: Optional[float] = Field(None, description="Opening range low")
    stop_type: str = Field("or-mid", description="Stop rule: or-mid, or-low, price:X, pct:X, atr:K")
    target_type: str = Field("2R", description="Target rule: 1R, 1.5R, 2R, price:X")
    flat_by: str = Field("15:55", description="Flat by time in HH:MM ET")
    setup: str = Field("orb", description="Setup name (orb or level)")
    or_minutes: int = Field(15, description="Opening range minutes")
    save: bool = Field(True, description="Whether to save to trader/plan.json")


@router.post("/plan")
def create_exit_plan(req: ExitPlanRequest):
    try:
        plan = compute_plan(
            symbol=req.symbol,
            entry=req.entry,
            or_high=req.or_high,
            or_low=req.or_low,
            stop_type=req.stop_type,
            target_type=req.target_type,
            flat_by=req.flat_by,
            setup=req.setup,
            or_minutes=req.or_minutes,
        )
        if req.save:
            save_plan(plan)
        return plan
    except PlanError as pe:
        raise HTTPException(status_code=400, detail=str(pe))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/plan")
def read_current_plan():
    plan = get_current_plan()
    if plan is None:
        raise HTTPException(status_code=404, detail="No current plan found at trader/plan.json")
    return plan
