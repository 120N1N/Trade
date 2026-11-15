"""
main.py — FastAPI application entry point.
Mounts all routers and configures CORS.
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from api import scanner, entry, exit_plan, timemachine, budget, risk, quotes

app = FastAPI(
    title="Day Trader API",
    description="Scanner, entry timer, exit planner, time machine, and risk checker for day trading.",
    version="1.0.0",
)

# Allow all origins (frontend on port 5173)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount routers
app.include_router(scanner.router, prefix="/api")
app.include_router(entry.router, prefix="/api")
app.include_router(exit_plan.router, prefix="/api")
app.include_router(timemachine.router, prefix="/api")
app.include_router(budget.router, prefix="/api")
app.include_router(risk.router, prefix="/api")
app.include_router(quotes.router, prefix="/api")


@app.get("/")
def root():
    return {"status": "ok", "message": "Day Trader API — see /docs"}


@app.get("/health")
def health():
    return {"status": "ok"}
