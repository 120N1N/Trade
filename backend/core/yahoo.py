"""
core/yahoo.py — yfinance wrapper with TTL caching.

All market data comes through here. Uses a simple dict-based in-memory cache
to avoid Yahoo rate-limiting: 60 seconds for intraday data, 3600 for daily.
"""
import time
import logging
from typing import Optional, Dict, Any, Tuple
import pandas as pd
import yfinance as yf

from config import INTRADAY_CACHE_TTL, DAILY_CACHE_TTL, YFINANCE_PROGRESS

logger = logging.getLogger(__name__)

# ------------------------------------------------------------------
# In-memory cache: { key: (timestamp, data) }
_cache: Dict[str, Tuple[float, Any]] = {}


def _cache_key(*args) -> str:
    return "|".join(str(a) for a in args)


def _get_cached(key: str, ttl: int) -> Optional[Any]:
    entry = _cache.get(key)
    if entry is None:
        return None
    ts, data = entry
    if time.time() - ts > ttl:
        return None
    return data


def _set_cached(key: str, data: Any) -> None:
    _cache[key] = (time.time(), data)


def clear_cache() -> None:
    """Clear all cached data (useful for testing)."""
    _cache.clear()


# ------------------------------------------------------------------
# Public API

def get_bars(symbol: str, period: str = "1d", interval: str = "5m") -> pd.DataFrame:
    """
    Download OHLCV bars for a symbol via yfinance.
    Returns a DataFrame with columns: Open, High, Low, Close, Volume.
    Index is a DatetimeTZAware (America/New_York).

    TTL: 60s for intraday intervals (1m, 5m), 3600s for daily.
    """
    sym = symbol.upper()
    ttl = DAILY_CACHE_TTL if interval in ("1d", "1wk", "1mo") else INTRADAY_CACHE_TTL
    key = _cache_key("bars", sym, period, interval)

    cached = _get_cached(key, ttl)
    if cached is not None:
        return cached

    try:
        df = yf.download(
            sym,
            period=period,
            interval=interval,
            auto_adjust=True,
            progress=YFINANCE_PROGRESS,
        )
        if df is None or df.empty:
            df = pd.DataFrame()
    except Exception as exc:
        logger.warning("yfinance download failed for %s: %s", sym, exc)
        df = pd.DataFrame()

    # Flatten multi-level columns if yfinance returns them
    if isinstance(df.columns, pd.MultiIndex):
        df.columns = df.columns.get_level_values(0)

    _set_cached(key, df)
    return df


def get_quote(symbol: str) -> Dict[str, Any]:
    """
    Return basic quote data: last_price, previous_close, pct_change, volume.
    Uses yf.Ticker.fast_info (lightweight, single request).
    TTL: 60 seconds.
    """
    sym = symbol.upper()
    key = _cache_key("quote", sym)

    cached = _get_cached(key, INTRADAY_CACHE_TTL)
    if cached is not None:
        return cached

    try:
        t = yf.Ticker(sym)
        fi = t.fast_info
        last = getattr(fi, "last_price", None)
        prev = getattr(fi, "previous_close", None)
        volume = getattr(fi, "last_volume", None)
        mkt_cap = getattr(fi, "market_cap", None)
        pct = None
        if last is not None and prev and prev > 0:
            pct = round((last / prev - 1) * 100, 2)
        result = {
            "symbol": sym,
            "last_price": round(last, 2) if last else None,
            "previous_close": round(prev, 2) if prev else None,
            "pct_change": pct,
            "volume": int(volume) if volume else None,
            "market_cap": int(mkt_cap) if mkt_cap else None,
        }
    except Exception as exc:
        logger.warning("get_quote failed for %s: %s", sym, exc)
        result = {"symbol": sym, "error": str(exc)}

    _set_cached(key, result)
    return result


def get_60d_bars(symbol: str) -> pd.DataFrame:
    """60 days of 5-minute bars — used by the Time Machine."""
    return get_bars(symbol, period="60d", interval="5m")


def get_daily_bars(symbol: str, period: str = "3mo") -> pd.DataFrame:
    """Daily bars for the daily scanner."""
    return get_bars(symbol, period=period, interval="1d")
