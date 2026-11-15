"""
api/scanner.py — Scanner endpoints:
  - GET /api/scan/orb
  - GET /api/scan/daily
  - GET /api/scan/status
"""
from typing import Optional
from fastapi import APIRouter, Query, HTTPException

from core.scan import scan_orb, scan_daily, scan_status

router = APIRouter(prefix="/scan", tags=["Scanner"])


@router.get("/orb")
def get_orb_scan(
    at: Optional[str] = Query(None, description="Cutoff time in HH:MM ET (e.g. 10:15)"),
    or_minutes: int = Query(15, description="Opening range length in minutes (default 15)"),
    limit: int = Query(50, ge=1, le=200, description="Max candidates to return"),
    symbols: Optional[str] = Query(None, description="Comma-separated symbol list (optional)"),
):
    try:
        sym_list = [s.strip().upper() for s in symbols.split(",")] if symbols else None
        result = scan_orb(at=at, or_minutes=or_minutes, limit=limit, symbols=sym_list)
        return result
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/daily")
def get_daily_scan(
    limit: int = Query(100, ge=1, le=500, description="Max symbols to scan"),
    symbols: Optional[str] = Query(None, description="Comma-separated symbol list (optional)"),
):
    try:
        sym_list = [s.strip().upper() for s in symbols.split(",")] if symbols else None
        result = scan_daily(symbols=sym_list, limit=limit)
        return result
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/status")
def get_scan_status():
    try:
        return scan_status()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
