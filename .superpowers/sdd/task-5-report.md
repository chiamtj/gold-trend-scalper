# Task 5 Report: TradeManager.mqh

## Status: DONE

The file was written successfully to:
`C:\Users\user\Documents\Claude Code\Gold Hammer\Include\Core\TradeManager.mqh`

### Verification
- File matches the plan specification
- Header guard (`TRADE_MANAGER_MQH`) is present and correct
- Includes `<Trade/Trade.mqh>` for CTrade
- Class `CTradeManager` implements all required methods:

**Configuration:**
- `SetParams(magic, lots, slPoints, tpPoints)` — configures CTrade with magic number, deviation (10 pts), and filling mode
- `SetSymbol(symbol)` — sets the trading symbol

**Order entry:**
- `OpenLong(symbol)` — sends `trade.Buy()` with hard SL/TP, returns ticket on success
- `OpenShort(symbol)` — sends `trade.Sell()` with hard SL/TP, returns ticket on success
- Both log failures with retcode + description

**Position management:**
- `ClosePosition()` — two-tier close: direct ticket close → fallback scan of all positions by symbol+magic
- `HasOpenPosition()` — verifies tracked ticket is still alive

**Position info (6 getters):**
- `GetPositionPnL()` — floating profit/loss
- `GetPositionTicket()` — current position ticket
- `GetPositionLots()` — position volume
- `GetPositionOpenPrice()` — entry price
- `GetPositionDirection()` — "LONG", "SHORT", or "NONE"

### Concerns / Observations
- SL/TP are set at order entry with `NormalizeDouble` to symbol digits — price precision is correct
- `ClosePosition()` fallback scan handles EA reload scenarios where `m_positionTicket` is stale
- Default lot size is 0.01 (fixed, no scaling per the spec's anti-martingale rule)
- Depends on the MQL5 Standard Library (`<Trade/Trade.mqh>`) — standard in all MT5 installations
