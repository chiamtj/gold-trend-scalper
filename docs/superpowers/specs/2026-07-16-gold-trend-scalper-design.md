# Gold Trend Scalper EA — Design Spec

## Overview

A bi-directional, trend-following ultra-scalp Expert Advisor for XAUUSD (Gold) on MetaTrader 5. Designed for a ~$3,000 account with hard risk boundaries that prevent the martingale blowup pattern observed in similar EAs.

## Origin & Motivation

Analysis of `mt5_monitor_log.json` (a real trading session log) revealed an EA that:
- Used a **Fibonacci martingale grid** (0.01 → 0.39 lots) on Sell-only positions
- Achieved 93% win rate during trending windows but was **directionally blind**
- Blew up **$3,235 → $52 (-98.4%)** in under 5 minutes during a sustained uptrend
- Restarted the **same broken pattern** at micro-lot scale immediately after (Zombie mode)

This EA directly addresses every failure mode.

## Strategy: Tick Momentum Burst Tracker

### Core Signal

Price velocity over a short tick window:

```
Momentum = CurrentPrice - Price_N_Ticks_Ago
```

### Entry Logic

All conditions must be true:

| Condition | Long | Short |
|-----------|------|-------|
| Momentum threshold | Ask - Ask[5] ≥ +8 points | Bid[5] - Bid ≥ +8 points |
| Acceleration | Last 3 ticks each moving up | Last 3 ticks each moving down |
| No existing position | ✓ | ✓ |
| Not in cooldown | ✓ | ✓ |
| Daily limits OK | ✓ | ✓ |

### Exit Logic (first one wins)

1. **Take profit**: +15 points from entry price
2. **Stop loss**: -10 points from entry price  
3. **Momentum flip**: 3 consecutive ticks in the opposite direction

## Trend Directional Filter

A 20-period EMA on M1 chart provides the directional bias:

- **Price above EMA 20** → only LONG entries permitted
- **Price below EMA 20** → only SHORT entries permitted  
- **Price crossing EMA** → no trade until 1 M1 candle closes on the new side

Prevents the EA from scalping against the prevailing trend — the fatal flaw of the original.

## Risk Management (Critical)

| Layer | Rule | Purpose |
|-------|------|---------|
| Position size | Fixed 0.01 lots (no scaling, ever) | Flat risk per trade |
| Per-trade risk | SL -10 pts ($1.00), TP +15 pts ($1.50) | 1:1.5 risk:reward |
| Daily loss limit | Hard stop at **-$25** total | Max 0.8% daily loss |
| Daily profit lock | Stop at **+$50** total | Lock in gains |
| Max consecutive losses | Pause 1 hour after 5 losses in a row | Prevent tilt trading |
| Spread filter | Skip if spread > 30 points | Fair entry only |
| No martingale | Size never changes | Cuts the blowup path |

### Position Sizing Math (at $3K, 0.01 lot)

- 0.01 lot Gold = $0.10 per point
- TP +15 pts = $1.50 profit; SL -10 pts = $1.00 loss
- At 60% win rate: expectancy = +$0.50/trade
- ~80 trades/day cap → risk-managed daily expectancy consistent with the $50 profit lock

## EA Architecture

### Module Structure

```
GoldScalper/
├── GoldScalper.mq5                # EA entry point (orchestrator)
├── Include/
│   ├── Signal/
│   │   └── MomentumBurst.mqh      # Tick momentum detection + entry logic
│   ├── Core/
│   │   ├── TradeManager.mqh       # Order execution, stop/TP management
│   │   └── RiskManager.mqh        # Per-trade risk, daily limits, circuit breakers
│   ├── Filters/
│   │   ├── TrendFilter.mqh        # EMA 20 directional bias
│   │   └── SpreadFilter.mqh       # Spread/no-news check
│   └── UI/
│       └── Dashboard.mqh          # On-chart performance panel
```

### Data Flow (per tick)

```
Tick arrives
  → DashboardUpdate() (refresh all displays)
    → RiskManager (check all limits OK?)
      → TrendFilter (price vs EMA 20 — correct side?)
        → SpreadFilter (spread ≤ 30 pts?)
          → MomentumBurst (velocity ≥ 8 pts / 5 ticks?)
            → TradeManager (execute entry with SL/TP)
              → DashboardUpdate() (reflect new position)
```

### Event Handlers

| Handler | Role |
|---------|------|
| `OnInit()` | Load EMA handle, init risk state from GlobalVariables, create dashboard |
| `OnTick()` | Main pipeline: update dashboard → filter → signal → execute |
| `OnTimer()` | 1-hour pause countdown, session reset, refresh dashboard |
| `OnTrade()` | Track P&L for daily limits, consecutive loss counter, update dashboard |
| `OnDeinit()` | Remove dashboard objects from chart |

## On-Chart Dashboard

A lightweight graphical panel rendered on the chart using `OBJ_LABEL` and `OBJ_RECTANGLE_LABEL` objects (not `CAppDialog` — avoids UI event loop overhead that could interfere with ultra-scalp latency).

### Layout (top-left corner of chart)

```
┌──────────────────────────────────┐
│  GOLD TREND SCALPER     v1.0    │
├──────────────────────────────────┤
│  Status:  TRADING                │
│  Balance: $3,042.50     P&L: +42.50│
│  Today:   +$18.20  Trades: 14   │
│  Win Rate: 71%  (10W / 4L)      │
│  DD:      -$4.30 (-0.14%)       │
│  Position: LONG  0.01  +$1.20   │
│  Spread:  22 pts  [   ]  OK     │
│  Circuit: Profit lock: $31.80/50│
│           Loss limit: $0.00/25  │
└──────────────────────────────────┘
```

### Dashboard Fields

| Field | Source | Update |
|-------|--------|--------|
| Status | EA state enum (TRADING / PAUSED / CIRCUIT_BREAKER) | On every state change |
| Balance | `AccountInfoDouble(ACCOUNT_BALANCE)` | OnTick |
| Session P&L | Running total (realized + floating) | OnTick |
| Today's P&L | Realized P&L since midnight server time | OnTrade |
| Trade count | Running counter | OnTrade |
| Win/Loss | Counters + percentage | OnTrade |
| Drawdown | Peak-to-current equity during session | OnTick |
| Current position | Ticket, direction, lots, floating P&L | OnTick |
| Spread | Current spread in points | OnTick |
| Circuit breaker | Profit lock bar + loss limit bar (visual fill) | OnTick |

### Color Coding

| Element | Color | Meaning |
|---------|-------|---------|
| P&L positive | `clrLimeGreen` | Profitable |
| P&L negative | `clrRed` | Losing |
| Circuit bar green | `clrLimeGreen` | Approaching lock |
| Circuit bar red | `clrRed` | Approaching limit |
| Status = PAUSED | `clrYellow` | Cooldown active |
| Status = BREAKER | `clrRed` | Daily limit hit |

### `Dashboard.mqh` Interface

```cpp
void DashboardCreate();          // Create all objects on chart (OnInit)
void DashboardUpdate();          // Update all values (OnTick)
void DashboardRemove();          // Delete objects (OnDeinit)
void DashboardSetStatus(string); // Change status label
```

### Design Notes

- Uses `OBJ_RECTANGLE_LABEL` for the panel background (semi-transparent fill)
- Uses `OBJ_LABEL` for all text fields — fast, no recalc overhead
- Updates only when a value changes (not on every single tick) to minimize chart redraw
- All objects prefixed with `"GOLDSCALPER_"` for clean removal
- Panel is **not selectable/movable** by user to prevent accidental drag

## Input Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `InpMomentumTicks` | 5 | Lookback ticks for velocity calculation |
| `InpMomentumPoints` | 8 | Points required for momentum threshold |
| `InpStopLossPoints` | 10 | Stop loss distance in points |
| `InpTakeProfitPoints` | 15 | Take profit distance in points |
| `InpMaxDailyLoss` | 25 | Hard stop: max daily loss in $ |
| `InpMaxDailyProfit` | 50 | Lock: max daily profit before stopping |
| `InpMaxConsecutiveLosses` | 5 | Pause hours after N consecutive losses |
| `InpMaxSpread` | 30 | Max allowed spread in points |
| `InpEMAPeriod` | 20 | Trend filter EMA period |
| `InpMagicNumber` | 20260716 | Unique EA identifier |

## Anti-Patterns (excluded by design)

| ❌ Excluded | Why |
|-------------|-----|
| Grid accumulation | Single position only, always — no stacking |
| Martingale sizing | Flat 0.01 lots forever, never increases |
| No-SL trades | Every trade has a hard stop loss |
| One-direction bias | EMA 20 flips direction with the trend |
| Position stacking | Strictly one position at a time |
| Post-blowup restart | Daily limits persist, cannot re-enter |

## Future Enhancements (not in initial build)

- **Auto lot sizing**: Scale base position to account balance (e.g., 0.01 per $1K)
- **MTF trend confirmation**: Align M1 and M5 EMA bias before trading
- **News filter**: Economic calendar integration to skip high-impact events
- **Persistent P&L tracking**: Write daily totals to file for session-over-session tracking
- **Trailing stop**: Dynamic partial-profit lock once TP partially reached

## Verification

1. **Compile** the EA in MetaEditor — zero warnings
2. **Backtest** on XAUUSD M1 with Every Tick mode — minimum 2,000 trades
3. **Verify** daily loss limit triggers correctly by simulating consecutive losses
4. **Verify** EMA filter permits only correct-direction entries
5. **Verify** spread filter skips trades during high-spread conditions
6. **Walk-forward** validation: 70% IS / 30% OOS split
7. **Monte Carlo** simulation: 1,000 randomized trade sequences, reject if 95th percentile DD > 15%

---

*Spec written: 2026-07-16*
