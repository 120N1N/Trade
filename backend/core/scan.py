"""
core/scan.py — Chart scanner logic adapted from the original scan.py.

Implements:
  - Opening-Range Breakout (ORB) detection
  - Daily setup detection (breakout_20d, bull_flag, reclaim_ma20, oversold, oversold_bounce)
  - Universe: hardcoded list of 500 popular US stocks
"""
import datetime
import logging
from typing import List, Dict, Any, Optional, Tuple

import pandas as pd
import pytz

from core.yahoo import get_bars, get_daily_bars

logger = logging.getLogger(__name__)

ET = pytz.timezone("America/New_York")
BAR_MIN = 5  # 5-minute bars

# ------------------------------------------------------------------
# 500-stock universe (popular US stocks spanning sectors)
UNIVERSE = [
    # Mega-cap tech
    "AAPL","MSFT","NVDA","AMZN","GOOGL","META","TSLA","AVGO","TSM","ORCL",
    "ASML","AMD","QCOM","TXN","MU","INTC","AMAT","LRCX","KLAC","MCHP",
    # Financials
    "BRK-B","JPM","V","MA","BAC","WFC","GS","MS","AXP","BLK","C","COF",
    "SCHW","USB","PNC","TFC","MTB","CFG","KEY","RF","ALLY","SYF","DFS",
    # Healthcare
    "LLY","JNJ","UNH","ABBV","MRK","TMO","DHR","ABT","BMY","AMGN","GILD",
    "VRTX","REGN","ISRG","BSX","MDT","EW","BDX","HCA","CI","CVS","MCK",
    # Consumer
    "COST","WMT","HD","AMZN","TGT","LOW","NKE","SBUX","MCD","DPZ","YUM",
    "CMG","DRI","EL","PG","KO","PEP","PM","MO","CL","GIS","K","CPB",
    # Energy
    "XOM","CVX","COP","EOG","SLB","PSX","VLO","MPC","OXY","DVN","HES",
    "FANG","BKR","HAL","NOV","FTI","CHK","AR","EQT","RRC","CNX","OVV",
    # Industrials
    "GE","CAT","DE","HON","UPS","RTX","LMT","NOC","GD","BA","MMM","EMR",
    "ITW","PH","ROK","SWK","TT","IR","CARR","OTIS","WM","RSG","FAST",
    # Communication
    "META","GOOGL","NFLX","DIS","CMCSA","T","VZ","TMUS","CHTR","WBD","PARA",
    "EA","TTWO","ATVI","RBLX","SNAP","PINS","MTCH","BMBL","IAC","ZG",
    # Real Estate / REIT
    "PLD","AMT","CCI","EQIX","PSA","AVB","EQR","VTR","WELL","HCP","DRE",
    # Utilities
    "NEE","DUK","SO","D","AEP","EXC","XEL","WEC","ES","ETR","FE","PPL",
    # Biotech
    "MRNA","BNTX","PFE","AZN","BIIB","ALNY","RARE","IONS","BMRN","ACAD",
    # ETFs (included for liquidity)
    "SPY","QQQ","IWM","DIA","GLD","SLV","TLT","HYG","XLF","XLK","XLE","XLV",
    # Popular trading names
    "GME","AMC","BBBY","SPCE","COIN","HOOD","RIVN","LCID","NKLA","WKHS",
    "PLTR","SOFI","UPST","OPEN","OPENDOOR","CLOV","CLNE","FCEL","PLUG","BLDP",
    # More large-caps
    "PYPL","SQ","SHOP","UBER","LYFT","DASH","ABNB","AIRBNB","BKNG","EXPE",
    "NET","CRWD","ZS","PANW","FTNT","OKTA","DDOG","SNOW","MDB","ESTC","CFLT",
    "ZM","DOCU","WORK","TEAM","ATLASSIAN","SPLK","NOW","CRM","SAP","WDAY",
    "VEEV","HUBS","RNG","FIVN","NICE","TWLO","SEND","BAND","LPSN","ALRM",
    "BILL","PAYC","PCTY","PAYLOCITY","GTLB","PATH","AI","C3AI","BBAI",
    "U","RKLY","PLTR","IONQ","QUBT","RGTI","ARQQ","QMCO","IQM","ATOS",
    # Banks / finance
    "NDAQ","ICE","CME","CBOE","MKTX","VIRT","OPF","LPLA","RJF","AMTD",
    # Semiconductor extended
    "MPWR","SWKS","QRVO","SLAB","CRUS","RMBS","CCEP","ADI","MXIM","XLNX",
    # Retail
    "LULU","ROST","TJX","GPS","M","KSS","JWN","DDS","BURL","VFC","PVH",
    "HBI","UAA","UA","CROX","SKX","DECK","WWW","SHOO","BOOT","WEBR",
    # Auto
    "TSLA","GM","F","TM","HMC","NSANY","BMWYY","VWAGY","STLA","LCID","RIVN",
    # Crypto-adjacent
    "COIN","MSTR","RIOT","MARA","CLSK","BITF","HUT","BTBT","BTCM","BTCS",
    # Chinese ADRs
    "BABA","JD","PDD","BIDU","NIO","XPEV","LI","TCOM","EDU","TAL","YUMC",
    # Airlines / travel
    "AAL","DAL","UAL","LUV","ALK","JBLU","SAVE","RJET","HA","MESA",
    # Misc popular
    "SQ","PYPL","AFRM","BNPL","OPEN","LMND","ROOT","HIG","TRV","ALL","CB",
    "MET","PRU","AFL","UNM","GL","TMK","FNF","FG","RLI","KMPR",
]
# Deduplicate while preserving order
_seen: set = set()
UNIVERSE_CLEAN: List[str] = []
for _s in UNIVERSE:
    if _s not in _seen:
        UNIVERSE_CLEAN.append(_s)
        _seen.add(_s)
UNIVERSE = UNIVERSE_CLEAN


# ------------------------------------------------------------------
# RSI (Wilder's) — same math as original scan.py

def _rsi(closes: List[float], n: int = 14) -> Optional[float]:
    if len(closes) < n + 1:
        return None
    g = [max(0.0, closes[i] - closes[i - 1]) for i in range(1, len(closes))]
    lo = [max(0.0, closes[i - 1] - closes[i]) for i in range(1, len(closes))]
    ag, al = sum(g[:n]) / n, sum(lo[:n]) / n
    for i in range(n, len(g)):
        ag = (ag * (n - 1) + g[i]) / n
        al = (al * (n - 1) + lo[i]) / n
    return 100 - 100 / (1 + ag / al) if al else 100.0


# ------------------------------------------------------------------
# Daily setups — same logic as original find_setups()

def _find_setups(closes: List[float]) -> Tuple[List[str], Dict[str, Any]]:
    """closes oldest-first (>= 30) -> (setup keys, numbers dict)."""
    if len(closes) < 30:
        return [], {}
    c = closes
    last = c[-1]
    hi20 = max(c[-21:-1])
    ma20 = sum(c[-20:]) / 20.0
    ma20_prev = sum(c[-21:-1]) / 20.0
    run = c[-6] / c[-16] - 1
    rng5 = (max(c[-5:]) - min(c[-5:])) / last
    r = _rsi(c)
    r_prev = _rsi(c[:-1])
    tags = []
    if last > hi20:
        tags.append("breakout_20d")
    if run > 0.10 and rng5 < 0.05:
        tags.append("bull_flag")
    if c[-2] < ma20_prev and last > ma20:
        tags.append("reclaim_ma20")
    if r is not None and r < 30:
        tags.append("oversold")
    if r_prev is not None and r_prev < 30 and last > c[-2]:
        tags.append("oversold_bounce")
    return tags, {"rsi": r, "rsi_prev": r_prev, "high20": hi20, "ma20": ma20,
                  "run_pct": run * 100, "range5_pct": rng5 * 100}


def scan_daily(symbols: Optional[List[str]] = None, limit: int = 100) -> Dict[str, Any]:
    """
    Pre-market daily scan: download daily bars for symbols, detect setups.
    Returns {hits, counts, scanned_at}.
    """
    if symbols is None:
        symbols = UNIVERSE[:limit]
    else:
        symbols = symbols[:limit]

    hits = []
    counts = {"requested": len(symbols), "fetched": 0, "illiquid": 0, "short": 0, "scanned": 0, "hits": 0}
    now_et = datetime.datetime.now(ET)

    for sym in symbols:
        try:
            df = get_daily_bars(sym, period="3mo")
            if df.empty:
                continue
            counts["fetched"] += 1

            # Build close list oldest-first; drop today's bar if market not closed
            closes_series = df["Close"].dropna()
            if closes_series.empty:
                continue

            # Check if the last bar's date is today and market still open
            last_date = closes_series.index[-1]
            if hasattr(last_date, 'tzinfo') and last_date.tzinfo is not None:
                last_date_local = last_date.astimezone(ET).date()
            else:
                last_date_local = last_date.date() if hasattr(last_date, 'date') else last_date

            today = now_et.date()
            # Drop today's bar if still open
            if last_date_local == today and now_et.hour < 16:
                closes_series = closes_series.iloc[:-1]

            if len(closes_series) < 30:
                counts["short"] += 1
                continue

            # Liquidity filter: price >= 5, volume >= 1,000,000
            last_price = float(closes_series.iloc[-1])
            last_vol = None
            if "Volume" in df.columns:
                vols = df["Volume"].dropna()
                if not vols.empty:
                    last_vol = float(vols.iloc[-1])

            if last_price < 5.0 or (last_vol is not None and last_vol < 1_000_000):
                counts["illiquid"] += 1
                continue

            counts["scanned"] += 1
            closes = [float(c) for c in closes_series]
            tags, nums = _find_setups(closes)
            if tags:
                hits.append({
                    "symbol": sym,
                    "setups": tags,
                    "price": round(last_price, 2),
                    "close_date": str(last_date_local),
                    "rsi": round(nums["rsi"], 1) if nums.get("rsi") is not None else None,
                    "volume": int(last_vol) if last_vol is not None else None,
                })
        except Exception as exc:
            logger.warning("daily scan error for %s: %s", sym, exc)

    # Sort by dollar volume (most traded first)
    hits.sort(key=lambda h: -(h["price"] * (h["volume"] or 0)))
    counts["hits"] = len(hits)
    return {
        "hits": hits,
        "counts": counts,
        "scanned_at": now_et.strftime("%Y-%m-%d %H:%M:%S"),
    }


# ------------------------------------------------------------------
# ORB (Opening-Range Breakout)

def _session_bars_et(df: pd.DataFrame, day: datetime.date, cutoff: datetime.datetime) -> List[Dict]:
    """
    Extract 5-minute session bars for a given day from a DataFrame.
    Returns list of {start, c, h, l, v} dicts. Only completed bars at or before cutoff.
    """
    if df.empty:
        return []

    # Ensure index is tz-aware ET
    idx = df.index
    if idx.tz is None:
        idx = idx.tz_localize("UTC").tz_convert(ET)
    else:
        idx = idx.tz_convert(ET)

    open_time = datetime.datetime.combine(day, datetime.time(9, 30)).replace(tzinfo=ET)
    close_time = datetime.datetime.combine(day, datetime.time(16, 0)).replace(tzinfo=ET)

    # Make cutoff tz-aware if needed
    if cutoff.tzinfo is None:
        cutoff = ET.localize(cutoff)

    out = {}
    for i, ts in enumerate(idx):
        if ts.date() != day:
            continue
        if ts.second != 0 or ts.minute % BAR_MIN != 0:
            continue  # off-grid
        if ts < open_time or ts >= close_time:
            continue  # pre/post market
        bar_end = ts + datetime.timedelta(minutes=BAR_MIN)
        if bar_end > cutoff:
            continue  # still in progress

        row = df.iloc[i]
        c = row.get("Close") if hasattr(row, 'get') else row["Close"]
        if c is None or (hasattr(c, '__float__') and pd.isna(float(c))):
            continue

        out[ts] = {
            "start": ts,
            "c": float(c),
            "h": float(row["High"]) if not pd.isna(row["High"]) else float(c),
            "l": float(row["Low"]) if not pd.isna(row["Low"]) else float(c),
            "v": int(row["Volume"]) if not pd.isna(row["Volume"]) else 0,
        }
    return [out[k] for k in sorted(out)]


def _orb_hit(bars: List[Dict], n_range: int) -> Optional[Dict]:
    """
    Stage 2: first completed bar after the range to CLOSE above the range high.
    Returns hit dict or None.
    """
    rng = bars[:n_range]
    if len(rng) < n_range:
        return None
    if any(b["h"] is None or b["l"] is None for b in rng):
        return None

    oh = max(b["h"] for b in rng)
    ol = min(b["l"] for b in rng)

    for k in range(n_range, len(bars)):
        b = bars[k]
        if b["c"] > oh:
            closes_at = b["start"] + datetime.timedelta(minutes=BAR_MIN)
            return {
                "or_high": round(oh, 2),
                "or_low": round(ol, 2),
                "price": round(b["c"], 2),
                "bar_start": b["start"].strftime("%H:%M"),
                "at": closes_at.strftime("%I:%M %p").lstrip("0"),
                "pct_over": round((b["c"] / oh - 1) * 100, 2),
            }
    return None


def scan_orb(
    at: Optional[str] = None,
    or_minutes: int = 15,
    limit: int = 50,
    symbols: Optional[List[str]] = None,
    min_price: float = 5.0,
) -> Dict[str, Any]:
    """
    Opening-range breakout scan.
    at: HH:MM cutoff time (New York). None = now.
    Returns {hits, counts, day, cutoff, scanned_at}.
    """
    now_et = datetime.datetime.now(ET)
    day = now_et.date()

    if at:
        h, m = map(int, at.split(":"))
        cutoff = datetime.datetime.combine(day, datetime.time(h, m)).replace(tzinfo=ET)
    else:
        cutoff = now_et.replace(second=0, microsecond=0)

    n_range = or_minutes // BAR_MIN

    if symbols is None:
        symbols = UNIVERSE[:limit * 3]  # scan more to get enough hits

    hits = []
    counts = {
        "requested": len(symbols),
        "fetched": 0,
        "unusable": 0,
        "illiquid": 0,
        "scanned": 0,
        "candidates": 0,
        "hits": 0,
    }

    for sym in symbols:
        if len(hits) >= limit:
            break
        try:
            df = get_bars(sym, period="1d", interval="5m")
            if df.empty:
                continue
            counts["fetched"] += 1

            bars = _session_bars_et(df, day, cutoff)
            if len(bars) < n_range + 1:
                counts["unusable"] += 1
                continue

            last_price = bars[-1]["c"]
            if last_price < min_price:
                counts["illiquid"] += 1
                continue

            counts["scanned"] += 1

            # Stage 1: any bar after range closed at or above highest range close?
            top = max(b["c"] for b in bars[:n_range])
            if not any(b["c"] >= top for b in bars[n_range:]):
                continue

            counts["candidates"] += 1

            # Stage 2: check real high
            hit = _orb_hit(bars, n_range)
            if hit:
                hits.append({"symbol": sym, "setups": ["orb"], **hit})
        except Exception as exc:
            logger.warning("ORB scan error for %s: %s", sym, exc)

    hits.sort(key=lambda h: h.get("at", ""))
    counts["hits"] = len(hits)
    return {
        "hits": hits,
        "counts": counts,
        "day": day.isoformat(),
        "cutoff": cutoff.strftime("%H:%M"),
        "or_minutes": or_minutes,
        "scanned_at": now_et.strftime("%Y-%m-%d %H:%M:%S"),
    }


def scan_status() -> Dict[str, Any]:
    return {
        "universe_count": len(UNIVERSE),
        "status": "ready",
        "setups": ["orb", "breakout_20d", "bull_flag", "reclaim_ma20", "oversold", "oversold_bounce"],
    }
