"""
api/quotes.py — Market data endpoints:
  - GET /api/quote/{ticker}
  - GET /api/bars/{ticker}
"""
from typing import Optional, List, Dict, Any
from fastapi import APIRouter, Query, HTTPException
import pandas as pd
import pytz

from core.yahoo import get_quote, get_bars

router = APIRouter(tags=["Quotes & Bars"])
ET = pytz.timezone("America/New_York")


@router.get("/quote/{ticker}")
def quote(ticker: str):
    """Return latest price, previous close, and percentage change."""
    try:
        data = get_quote(ticker)
        if "error" in data and data.get("last_price") is None:
            raise HTTPException(status_code=404, detail=f"No quote data for {ticker}")
        return data
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/bars/{ticker}")
def bars(
    ticker: str,
    interval: str = Query("5m", description="Bar interval: 1m, 5m, 15m, 1h, 1d"),
    period: str = Query("1d", description="Lookback period: 1d, 5d, 1mo, 3mo, 1y"),
):
    """
    Return OHLCV bars for the specified ticker.
    Formatted for TradingView Lightweight Charts:
      [{ time: <unix_seconds>, open, high, low, close, volume }]
    """
    try:
        df = get_bars(ticker, period=period, interval=interval)
        if df.empty:
            return {"symbol": ticker.upper(), "interval": interval, "bars": []}

        idx = df.index
        # Convert index to UTC timestamps (seconds)
        if idx.tz is None:
            idx = idx.tz_localize("UTC")
        else:
            idx = idx.tz_convert("UTC")

        result_bars: List[Dict[str, Any]] = []
        for i, ts in enumerate(idx):
            row = df.iloc[i]
            c = float(row["Close"]) if not pd.isna(row["Close"]) else None
            if c is None:
                continue
            o = float(row["Open"]) if not pd.isna(row["Open"]) else c
            h = float(row["High"]) if not pd.isna(row["High"]) else c
            l = float(row["Low"]) if not pd.isna(row["Low"]) else c
            v = int(row["Volume"]) if ("Volume" in row and not pd.isna(row["Volume"])) else 0

            # Lightweight charts takes unix timestamp in seconds
            time_val = int(ts.timestamp())
            result_bars.append({
                "time": time_val,
                "open": round(o, 2),
                "high": round(h, 2),
                "low": round(l, 2),
                "close": round(c, 2),
                "volume": v,
            })

        return {
            "symbol": ticker.upper(),
            "interval": interval,
            "period": period,
            "count": len(result_bars),
            "bars": result_bars,
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
