# Task 7 Report: GoldScalper.mq5 — Main EA Orchestrator

## Status: DONE

The file was written successfully to:
`C:\Users\user\Documents\Claude Code\Gold Hammer\GoldScalper.mq5`

### Verification
- File matches the plan specification
- Copyright, version (1.00), and description properties set
- Includes all 6 modules + `<Trade/Trade.mqh>`
- 10 input parameters, all prefixed with `Inp`

### Event handler pipeline

**OnInit():**
1. Validates XAUUSD symbol availability
2. Initializes all 5 modules with input parameters
3. Creates dashboard (24 chart objects)
4. Starts 1-second timer
5. Returns `INIT_SUCCEEDED` or `INIT_FAILED` on error

**OnTick() — trading pipeline (matches spec §Data Flow):**
1. Feed tick to momentum ring buffer
2. Update equity → RiskManager
3. Update trend filter crossing state
4. Check position state (closed? → save ticket for OnTrade)
5. Risk gate: `CanTrade()` — blocks on PAUSED/LOCK/LIMIT
6. Trend gate: `GetBias()` — blocks if crossing or wrong side
7. Spread gate: `IsSpreadOk()` — blocks if >30 pts
8. Momentum gate: `CheckSignal()` — blocks if no signal or cooldown
9. Direction match: signal must align with trend bias
10. Execute: `OpenLong()` / `OpenShort()` with hard SL/TP
11. Refresh dashboard (dirty-checked labels)

**OnTrade() — P&L tracking:**
- Uses `g_pendingCloseTicket` bridging pattern:
  - OnTick detects closure → saves ticket → resets `g_lastTicket`
  - OnTrade reads saved ticket, scans history in reverse for the matching OUT deal
  - Filters by magic, symbol, entry type, and position ID
  - Tracks net P&L (profit + commission + swap) → RiskManager + session total
- Reverse iteration ensures most recent deal is found first

**OnTimer():**
- Updates equity tracking + refreshes dashboard every 1 second

**OnDeinit():**
- Releases EMA handle, removes dashboard objects, kills timer

**OnTester():**
- Custom fitness: Sharpe × (Profit / (1 + DD%))
- Gates: < 100 trades = 0, > 15% DD = 0, profit factor < 1.3 = 0

### Improvements over plan draft
- `OnTrade()` scans deals in **reverse** (newest first) for correct P&L matching
- Added `g_pendingCloseTicket` bridging pattern — prevents race between OnTick position detection and OnTrade processing
- P&L now includes commission + swap for accurate net profit tracking
- `g_momentum.Reset()` called on position close to clear stale tick buffer before next signal

### File structure (all 7 files)
```
Gold Scalper/
├── GoldScalper.mq5                 ← orchestrator
├── Include/
│   ├── Signal/
│   │   └── MomentumBurst.mqh       ← tick momentum detection
│   ├── Core/
│   │   ├── TradeManager.mqh        ← CTrade order execution
│   │   └── RiskManager.mqh         ← circuit breakers, P&L tracking
│   ├── Filters/
│   │   ├── TrendFilter.mqh         ← EMA 20 directional bias
│   │   └── SpreadFilter.mqh        ← spread threshold check
│   └── UI/
│       └── Dashboard.mqh           ← on-chart performance panel
```

### Next steps
1. Open `GoldScalper.mq5` in MetaEditor (F4 from MT5)
2. Press F7 to compile — expected: 0 errors, 0 warnings
3. Run backtest on XAUUSD M1 to verify pipeline
