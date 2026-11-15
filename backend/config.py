"""
config.py — Application settings loaded from environment variables and defaults.
"""
import os
from pathlib import Path

# Base directory for trader JSON state files
BASE_DIR = Path(__file__).parent
TRADER_DIR = BASE_DIR / "trader"

# File paths for persistent state
CONFIG_PATH = TRADER_DIR / "config.json"
PLAN_PATH = TRADER_DIR / "plan.json"
ENTRY_PATH = TRADER_DIR / "entry.json"
ORDERS_PATH = TRADER_DIR / "orders.json"
WATCHLIST_PATH = TRADER_DIR / "watchlist.json"
TIMEMACHINE_PATH = TRADER_DIR / "timemachine.json"

# Server settings
BACKEND_PORT = int(os.getenv("BACKEND_PORT", "8000"))
FRONTEND_ORIGIN = os.getenv("FRONTEND_ORIGIN", "http://localhost:5173")

# Cache TTLs (seconds)
INTRADAY_CACHE_TTL = int(os.getenv("INTRADAY_CACHE_TTL", "60"))
DAILY_CACHE_TTL = int(os.getenv("DAILY_CACHE_TTL", "3600"))

# yfinance settings
YFINANCE_PROGRESS = False  # suppress download progress bars

# Default trading config (matches config.json defaults)
DEFAULT_CONFIG = {
    "budget": 5000,
    "cash_buffer_pct": 10,
    "max_position_pct": 75,
    "max_order_usd": 4000,
    "min_order_usd": 5,
    "max_loss_per_trade_usd": 50,
    "max_daily_loss_usd": 150,
    "max_trades_per_day": 3,
    "max_orders_per_day": 10,
    "min_reward_risk": 1.0,
    "require_stop": True,
    "no_entries_before": "09:45",
    "no_entries_after": "15:30",
    "flat_by": "15:55",
    "fractional": False,
    "broker": "alpaca",
    "paper": True,
    "blocked": [],
    "allow_options": False,
    "allow_margin": False,
    "allow_short": False,
    "pdt_guard": False,
}
