"""
api/timemachine.py — Time Machine endpoints:
  - POST /api/timemachine/run
"""
import json
import os
from typing import Optional
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from config import TIMEMACHINE_PATH
from core.timemachine import run_timemachine

router = APIRouter(prefix="/timemachine", tags=["Time Machine"])


class TimeMachineRequest(BaseModel):
    symbol: str = Field(..., description="Stock ticker, e.g. TSLA")
    entry: float = Field(..., description="Entry price")
    stop: float = Field(..., description="Stop loss price")
    target: float = Field(..., description="Target profit price")
    entry_time: str = Field("10:15", description="Entry time (e.g. 10:15 or 10:15 AM)")
    until: str = Field("15:55", description="Simulate until time (default 15:55)")
    replays: int = Field(10000, ge=100, le=100000, description="Monte Carlo replay count")
    seed: int = Field(19, description="Random seed for deterministic output")
    or_minutes: int = Field(15, description="Opening range minutes")
    save: bool = Field(True, description="Whether to save result to trader/timemachine.json")


@router.post("/run")
def execute_timemachine(req: TimeMachineRequest):
    try:
        result = run_timemachine(
            symbol=req.symbol,
            entry=req.entry,
            stop=req.stop,
            target=req.target,
            entry_time=req.entry_time,
            until=req.until,
            replays=req.replays,
            seed=req.seed,
            or_minutes=req.or_minutes,
        )
        if req.save:
            os.makedirs(os.path.dirname(TIMEMACHINE_PATH), exist_ok=True)
            with open(TIMEMACHINE_PATH, "w", encoding="utf-8") as f:
                json.dump(result, f, indent=2)
        return result
    except ValueError as ve:
        raise HTTPException(status_code=400, detail=str(ve))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
