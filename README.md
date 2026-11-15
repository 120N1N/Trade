# Day Trader Web App

A browser-based trading dashboard that brings 11 day-trading skills from the [day-trader-skill](https://github.com/jakeschincariol/day-trader-skill) CLI repo into a live, interactive web UI. Scan for setups, time your entries, plan exits, run Monte Carlo simulations, and manage risk — all from one dark-themed dashboard.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend | FastAPI (Python 3.11) |
| Frontend | React + Vite + TailwindCSS |
| Market Data | yfinance |
| AI Analysis | Google Gemini AI |
| Charts | TradingView lightweight-charts |
| Deployment | Docker / Docker Compose |

## Phase 1 Features

| Page | What it does |
|------|-------------|
| **Scanner** | Opening Range Breakout (ORB) scan + pre-market daily setups |
| **Entry / Exit** | Entry timer (triggered/waiting/expired) + stop & target planner |
| **Time Machine** | Monte Carlo backtester — win rate, R-multiple distribution, equity fan |
| **Risk & Budget** | Position sizer + risk-rule checker (max loss, max trades, min R:R) |

## Quick Start (Docker)

```bash
# 1. Clone
git clone https://github.com/jakeschincariol/day-trader-skill
cd Trade

# 2. Configure
cp .env.example .env
# Edit .env — add your GEMINI_API_KEY (and SEC_USER_AGENT for news)

# 3. Run
docker compose up
```

- Backend API: http://localhost:8000
- Frontend UI:  http://localhost:5173
- API docs:     http://localhost:8000/docs

## Dev Mode (no Docker)

### Backend
```bash
cd backend
python -m venv .venv
# Windows:
.venv\Scripts\activate
# macOS/Linux:
source .venv/bin/activate

pip install -r requirements.txt
cp ../.env.example ../.env   # fill in keys
uvicorn main:app --reload --port 8000
```

### Frontend
```bash
cd frontend
npm install
npm run dev        # starts on http://localhost:5173
```

## Project Structure

```
Trade/
├── docker-compose.yml
├── .env.example
├── .gitignore
├── README.md
├── backend/
│   ├── Dockerfile
│   ├── main.py          ← FastAPI app + CORS + router mounts
│   ├── config.py        ← Settings from env vars
│   ├── requirements.txt
│   ├── trader/
│   │   └── config.json  ← Default risk/budget config (persisted)
│   ├── core/            ← Business logic (scan, entry, exit, timemachine…)
│   └── api/             ← FastAPI routers (/api/scan, /api/entry, …)
└── frontend/
    ├── Dockerfile
    ├── package.json
    └── src/
        ├── App.jsx
        ├── pages/       ← Scanner, EntryExit, TimeMachine, RiskBudget
        ├── components/  ← Layout, CandlestickChart, StatCard, StatusBadge
        └── api/         ← axios client + per-feature helpers
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `GEMINI_API_KEY` | ✅ | Google Gemini AI key |
| `SEC_USER_AGENT` | ✅ | `Name email` for SEC EDGAR requests |
| `ALPACA_API_KEY` | Optional | Paper/live trading (Phase 2) |
| `ALPACA_SECRET_KEY` | Optional | Paper/live trading (Phase 2) |
| `ALPACA_BASE_URL` | Optional | Defaults to paper endpoint |
| `PAPER_TRADING` | Optional | `true` (default) prevents live order submission |

## Original CLI Repo

This project is a web UI wrapper around the scripts from:  
👉 https://github.com/jakeschincariol/day-trader-skill

The original repo contains the raw Python scripts that power each trading skill. The backend here adapts those scripts into a FastAPI service with caching and proper error handling.
