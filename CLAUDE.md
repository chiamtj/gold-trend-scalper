# Gold Trend Scalper EA

MQL5 Expert Advisor for XAUUSD (Gold) on MetaTrader 5. Bi-directional tick-momentum scalper with EMA 20 trend filter, hard risk limits, and on-chart dashboard. Runs on **M1 timeframe only**.

## Build

1. Open `GoldScalper.mq5` in MetaEditor (F4 from MT5)
2. Press **F7** to compile
3. Expected: 0 errors, 0 warnings
4. Attach to XAUUSD M1 chart in MT5

## Architecture

Modular MQL5 — 6 include files in `Include/` wired into `GoldScalper.mq5`:

```
GoldScalper.mq5                    # Orchestrator — events, pipeline, dashboard refresh
├── Include/Signal/
│   └── MomentumBurst.mqh          # Ring buffer + tick momentum + acceleration check
├── Include/Core/
│   ├── RiskManager.mqh            # Circuit breakers: profit lock, loss limit, consec. loss pause
│   └── TradeManager.mqh           # CTrade wrapper: SL/TP execution, position tracking
├── Include/Filters/
│   ├── TrendFilter.mqh            # EMA 20 crossing detection, directional bias gate
│   └── SpreadFilter.mqh           # Spread threshold check (≤ 30 pts)
└── Include/UI/
    └── Dashboard.mqh              # OBJ_LABEL panel, dirty-checked updates, 24 objects
```

**Dependency graph:** RiskManager and SpreadFilter are leaf nodes. MomentumBurst defines `ENUM_SIGNAL` which TrendFilter depends on. Dashboard depends on RiskManager for `ENUM_EA_STATUS`. TradeManager depends on the MQL5 Standard Library only.

## Conventions

- **Input parameters**: `Inp` prefix (e.g. `InpMomentumTicks`, `InpMaxDailyLoss`)
- **Chart objects**: all prefixed `GOLDSCALPER_` — clean removal on deinit
- **Magic number**: `20260716` — used by all trades, never changes
- **Include guards**: `#ifndef MODULE_NAME_MQH` / `#define` / `#endif`
- **Classes**: `C` prefix (e.g. `CSpreadFilter`, `CTrendFilter`)
- **Enums**: `ENUM_` prefix (e.g. `ENUM_SIGNAL`, `ENUM_EA_STATUS`)
- **Globals**: `g_` prefix (e.g. `g_momentum`, `g_riskMgr`)

## Hard Constraints

- **Single position only** — never more than one trade open
- **Fixed 0.01 lots** — never scaled, no martingale, no grid
- **Every trade has SL + TP** — no exceptions, SL at -10 pts, TP at +15 pts
- **Daily loss limit**: -$25 hard stop
- **Daily profit lock**: +$50 hard stop
- **Consecutive loss pause**: 5 losses in a row → 1-hour cooldown
- **XAUUSD only** — symbol hardcoded, not configurable

## Per-tick pipeline

```
bid/ask → Momentum ring buffer
        → RiskManager equity update
        → TrendFilter crossing update
        → Position check (closed? → OnTrade P&L bridge)
        → CanTrade() gate (blocked on PAUSED / PROFIT_LOCK / LOSS_LIMIT)
        → Trend bias match (price must be correct side of EMA 20)
        → Spread ≤ 30 pts
        → Momentum ≥ 8 pts over 5 ticks + 3-tick acceleration
        → Execute with hard SL/TP
        → Dashboard refresh (dirty-checked labels)
```

## Docs

- Design spec: `docs/superpowers/specs/2026-07-16-gold-trend-scalper-design.md`
- Implementation plan: `docs/superpowers/plans/2026-07-16-gold-trend-scalper.md`
- SDD progress/task reports: `.superpowers/sdd/`
