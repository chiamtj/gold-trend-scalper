# Gold Trend Scalper EA — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a bi-directional, trend-following ultra-scalp Expert Advisor for XAUUSD (Gold) on MetaTrader 5 that uses tick momentum bursts for entry, an EMA 20 directional filter, hard risk limits, and a live on-chart dashboard.

**Architecture:** Modular MQL5 design — 5 include files (MomentumBurst, TradeManager, RiskManager, TrendFilter, SpreadFilter, Dashboard) wired into a main `GoldScalper.mq5` orchestrator. Each module is a separate `.mqh` with a single responsibility. No martingale, no grid, fixed 0.01 lots throughout.

**Tech Stack:** MQL5 for MetaTrader 5, CTrade for order execution, CAppDialog-free OBJ_LABEL-based dashboard.

## Global Constraints

- XAUUSD only (Gold symbol)
- M1 chart with tick-level momentum detection
- Fixed 0.01 lot size — never changes, no scaling
- Every trade MUST have a hard SL and TP — no exceptions
- All OBJ_LABEL dashboard objects prefixed with `"GOLDSCALPER_"`
- Magic number: `20260716`
- All input parameters prefixed with `Inp` (e.g., `InpStopLossPoints`)

---

## File Structure

```
GoldHammer/
├── GoldScalper.mq5                 # EA entry point (orchestrator)
├── Include/
│   ├── Signal/
│   │   └── MomentumBurst.mqh       # Tick momentum detection + entry logic
│   ├── Core/
│   │   ├── TradeManager.mqh        # Order execution, SL/TP management
│   │   └── RiskManager.mqh         # Daily limits, circuit breakers, P&L tracking
│   ├── Filters/
│   │   ├── TrendFilter.mqh         # EMA 20 directional bias
│   │   └── SpreadFilter.mqh        # Spread threshold check
│   └── UI/
│       └── Dashboard.mqh           # On-chart performance panel
```

### Interface Map (dependency order)

```
GoldScalper.mq5
  ├── RiskManager.mqh      (daily limits, circuit breakers)
  ├── TrendFilter.mqh      (EMA 20 bias — depends on EMA handle)
  ├── SpreadFilter.mqh     (spread check — no dependencies)
  ├── MomentumBurst.mqh    (tick signal — no dependencies)
  ├── TradeManager.mqh     (order execution — uses CTrade)
  └── Dashboard.mqh        (UI — depends on RiskManager + TradeManager state)
```

---

### Task 1: SpreadFilter.mqh

**Files:**
- Create: `Include/Filters/SpreadFilter.mqh`

**Interfaces:**
- Produces: `class CSpreadFilter { void SetMaxSpread(int pts); bool IsSpreadOk(string symbol); }`

Logic: reads `(int)SymbolInfoInteger(symbol, SYMBOL_SPREAD)` and compares to max. Minimal.

- [ ] **Step 1: Write SpreadFilter.mqh**

```mql5
//+------------------------------------------------------------------+
//| SpreadFilter.mqh - Spread threshold check                        |
//+------------------------------------------------------------------+
#ifndef SPREAD_FILTER_MQH
#define SPREAD_FILTER_MQH

class CSpreadFilter
{
private:
   int      m_maxSpread;

public:
   CSpreadFilter() : m_maxSpread(30) {}

   void     SetMaxSpread(int pts)        { m_maxSpread = pts; }
   int      GetMaxSpread() const         { return m_maxSpread; }

   bool     IsSpreadOk(string symbol)
   {
      long spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      if(spread == 0)
      {
         Print("CSpreadFilter::IsSpreadOk - spread=0 (symbol not loaded)");
         return false;
      }
      return (int)spread <= m_maxSpread;
   }
};

#endif
```

- [ ] **Step 2: Review and commit**

```bash
git add Include/Filters/SpreadFilter.mqh
git commit -m "feat: add SpreadFilter module for Gold scalper EA"
```

---

### Task 2: TrendFilter.mqh

**Files:**
- Create: `Include/Filters/TrendFilter.mqh`

**Interfaces:**
- Produces: `class CTrendFilter { bool Init(string symbol, ENUM_TIMEFRAMES tf, int period, int magic); ENUM_SIGNAL GetBias(); bool IsCrossing(); void Release(); }`

Logic: loads EMA indicator handle, reads buffer on each tick. `GetBias()` returns SIGNAL_BUY (price above EMA) or SIGNAL_SELL (price below EMA). `IsCrossing()` returns true when price crosses EMA — blocks trading until 1 candle closes.

Uses `CopyBuffer()` to get 2 bars of EMA data. Price array uses `CopyClose()` for the same period.

- [ ] **Step 1: Write TrendFilter.mqh**

```mql5
//+------------------------------------------------------------------+
//| TrendFilter.mqh - EMA 20 directional bias filter                 |
//+------------------------------------------------------------------+
#ifndef TREND_FILTER_MQH
#define TREND_FILTER_MQH

#include "../Signal/MomentumBurst.mqh"

class CTrendFilter
{
private:
   int            m_handleEMA;
   string         m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int            m_period;
   double         m_prevClose;
   double         m_prevEMA;
   bool           m_wasAbove;
   bool           m_crossing;      // true during candle-cross period

public:
   CTrendFilter() : m_handleEMA(INVALID_HANDLE), m_symbol(""), m_period(20),
                    m_prevClose(0), m_prevEMA(0), m_wasAbove(false), m_crossing(false) {}

   bool Init(string symbol, ENUM_TIMEFRAMES tf, int period)
   {
      m_symbol = symbol;
      m_timeframe = tf;
      m_period = period;
      m_handleEMA = iMA(symbol, tf, period, 0, MODE_EMA, PRICE_CLOSE);
      if(m_handleEMA == INVALID_HANDLE)
      {
         Print("CTrendFilter::Init - Failed to create EMA handle");
         return false;
      }
      return true;
   }

   void Release()
   {
      if(m_handleEMA != INVALID_HANDLE)
         IndicatorRelease(m_handleEMA);
   }

   // Call on each tick to update crossing state
   void Update()
   {
      double ema[2], close[2];
      ArraySetAsSeries(ema, true);
      ArraySetAsSeries(close, true);

      if(CopyBuffer(m_handleEMA, 0, 0, 2, ema) < 2) return;
      if(CopyClose(m_symbol, m_timeframe, 0, 2, close) < 2) return;

      bool isAbove = close[0] > ema[0];

      // Detect crossing on the current bar
      if((m_wasAbove && !isAbove) || (!m_wasAbove && isAbove))
      {
         if(close[1] > ema[1] != isAbove)  // crossed this bar
            m_crossing = true;
      }

      if(m_crossing)
      {
         // Check if candle closed on the new side
         // Use static bar time to detect new candle
         static datetime lastBar = 0;
         datetime currentBar = iTime(m_symbol, m_timeframe, 0);
         if(currentBar != lastBar)
         {
            lastBar = currentBar;
            m_crossing = false;  // new candle started, crossing resolved
         }
      }

      m_wasAbove = isAbove;
      m_prevClose = close[0];
      m_prevEMA = ema[0];
   }

   ENUM_SIGNAL GetBias()
   {
      if(m_crossing) return SIGNAL_NONE;
      double ema[1], close[1];
      if(CopyBuffer(m_handleEMA, 0, 0, 1, ema) < 1) return SIGNAL_NONE;
      if(CopyClose(m_symbol, m_timeframe, 0, 1, close) < 1) return SIGNAL_NONE;
      return (close[0] > ema[0]) ? SIGNAL_BUY : SIGNAL_SELL;
   }

   bool IsCrossing() const { return m_crossing; }
};

#endif
```

- [ ] **Step 2: Review and commit**

```bash
git add Include/Filters/TrendFilter.mqh
git commit -m "feat: add TrendFilter module with EMA 20 directional bias"
```

---

### Task 3: MomentumBurst.mqh

**Files:**
- Create: `Include/Signal/MomentumBurst.mqh`

**Interfaces:**
- Produces:
  ```mql5
  enum ENUM_SIGNAL { SIGNAL_NONE = 0, SIGNAL_BUY = 1, SIGNAL_SELL = -1 };
  class CMomentumBurst {
    CMomentumBurst();
    void SetParams(int lookbackTicks, int thresholdPoints);
    void SetAcceleration(bool required);  // require 3 consecutive ticks same direction
    void OnTick(double bid, double ask); // feed ticks, maintain tick ring buffer
    ENUM_SIGNAL CheckSignal();
    void Reset();
  };
  ```

Logic: maintains a ring buffer of the last `lookbackTicks` bid and ask prices. On each tick, compares current price to price N ticks ago. If difference >= threshold points AND last 3 ticks show acceleration (each tick price higher for buy, lower for sell), returns signal. After a signal, enters cooldown for 1 second (prevents re-triggering on same burst).

- [ ] **Step 1: Write MomentumBurst.mqh**

```mql5
//+------------------------------------------------------------------+
//| MomentumBurst.mqh - Tick momentum burst detection                |
//+------------------------------------------------------------------+
#ifndef MOMENTUM_BURST_MQH
#define MOMENTUM_BURST_MQH

enum ENUM_SIGNAL { SIGNAL_NONE = 0, SIGNAL_BUY = 1, SIGNAL_SELL = -1 };

class CMomentumBurst
{
private:
   int      m_lookbackTicks;
   int      m_thresholdPoints;
   bool     m_requireAccel;

   double   m_bidRing[];
   double   m_askRing[];
   int      m_head;          // ring buffer current position
   int      m_count;         // entries filled so far

   datetime m_lastSignalTime;
   int      m_cooldownMs;

   bool     CheckAcceleration(int direction)
   {
      if(!m_requireAccel || m_count < 3) return true;
      int c0 = (m_head - 1 + m_lookbackTicks) % m_lookbackTicks;
      int c1 = (m_head - 2 + m_lookbackTicks) % m_lookbackTicks;
      int c2 = (m_head - 3 + m_lookbackTicks) % m_lookbackTicks;

      if(direction > 0)  // BUY: each ask should be higher
         return (m_askRing[c0] > m_askRing[c1] && m_askRing[c1] > m_askRing[c2]);
      else               // SELL: each bid should be lower
         return (m_bidRing[c0] < m_bidRing[c1] && m_bidRing[c1] < m_bidRing[c2]);
   }

public:
   CMomentumBurst() : m_lookbackTicks(5), m_thresholdPoints(8),
                      m_requireAccel(true), m_head(0), m_count(0),
                      m_lastSignalTime(0), m_cooldownMs(1000) {}

   void SetParams(int lookbackTicks, int thresholdPoints)
   {
      m_lookbackTicks = lookbackTicks;
      m_thresholdPoints = thresholdPoints;
      ArrayResize(m_bidRing, m_lookbackTicks);
      ArrayResize(m_askRing, m_lookbackTicks);
   }

   void SetAcceleration(bool required) { m_requireAccel = required; }
   void SetCooldown(int ms)            { m_cooldownMs = ms; }

   void OnTick(double bid, double ask)
   {
      m_bidRing[m_head] = bid;
      m_askRing[m_head] = ask;
      m_head = (m_head + 1) % m_lookbackTicks;
      if(m_count < m_lookbackTicks) m_count++;
   }

   ENUM_SIGNAL CheckSignal()
   {
      // Cooldown check
      if(GetTickCount() - m_lastSignalTime < m_cooldownMs)
         return SIGNAL_NONE;

      if(m_count < m_lookbackTicks) return SIGNAL_NONE;

      // Get oldest entry (the one N ticks ago)
      int oldest = (m_head - m_lookbackTicks + m_lookbackTicks) % m_lookbackTicks;
      // Wait, head points to the next slot to write, so the oldest is at head
      // Actually: when we write at head, then increment head.
      // The last written value is at (head - 1) % N.
      // The oldest is head (the position that will be overwritten next).
      // But on first fill, oldest starts as the first entry.
      int oldestIdx = m_head;

      double askNow = m_askRing[(m_head - 1 + m_lookbackTicks) % m_lookbackTicks];
      double bidNow = m_bidRing[(m_head - 1 + m_lookbackTicks) % m_lookbackTicks];
      double askOld = m_askRing[oldestIdx];
      double bidOld = m_bidRing[oldestIdx];

      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

      // BUY: ask rose by threshold
      if((askNow - askOld) >= m_thresholdPoints * point)
      {
         if(!m_requireAccel || CheckAcceleration(1))
         {
            m_lastSignalTime = GetTickCount();
            return SIGNAL_BUY;
         }
      }

      // SELL: bid fell by threshold
      if((bidOld - bidNow) >= m_thresholdPoints * point)
      {
         if(!m_requireAccel || CheckAcceleration(-1))
         {
            m_lastSignalTime = GetTickCount();
            return SIGNAL_SELL;
         }
      }

      return SIGNAL_NONE;
   }

   void Reset()
   {
      m_count = 0;
      m_head = 0;
      m_lastSignalTime = 0;
   }
};

#endif
```

- [ ] **Step 2: Review and commit**

```bash
git add Include/Signal/MomentumBurst.mqh
git commit -m "feat: add MomentumBurst module for tick momentum detection"
```

---

### Task 4: RiskManager.mqh

**Files:**
- Create: `Include/Core/RiskManager.mqh`

**Interfaces:**
- Produces:
  ```mql5
  enum ENUM_EA_STATUS { STATUS_TRADING, STATUS_PAUSED, STATUS_PROFIT_LOCK, STATUS_LOSS_LIMIT };
  class CRiskManager {
    CRiskManager();
    void Init();
    void SetLimits(double maxDailyLoss, double maxDailyProfit, int maxConsecutiveLosses);
    bool CanTrade();
    void OnTrade(double pnl);         // called when a trade closes
    void OnEquityChange(double equity); // called on each tick
    void OnTimer();                    // handles pause cooldown
    ENUM_EA_STATUS GetStatus();
    double  GetDailyPnL();
    double  GetPeakEquity() const;
    double  GetDrawdown() const;
    int     GetConsecutiveLosses() const;
    int     GetWinCount() const;
    int     GetLossCount() const;
    int     GetTradeCount() const;
    double  GetCurrentMaxDailyLoss() const;
    double  GetCurrentMaxDailyProfit() const;
    bool    IsPaused() const;
    int     GetRemainingPauseSeconds() const;
  };
  ```

Logic: tracks realized P&L for the day. If P&L <= -maxDailyLoss, sets STATUS_LOSS_LIMIT (trading stopped for the day). If P&L >= maxDailyProfit, sets STATUS_PROFIT_LOCK (trading stopped). Consecutive losses >= max → STATUS_PAUSED for 3600 seconds, then back to TRADING. Tracks peak equity for drawdown calc. P&L persists in memory only (resets on EA reload).

- [ ] **Step 1: Write RiskManager.mqh**

```mql5
//+------------------------------------------------------------------+
//| RiskManager.mqh - Daily limits, circuit breakers                 |
//+------------------------------------------------------------------+
#ifndef RISK_MANAGER_MQH
#define RISK_MANAGER_MQH

enum ENUM_EA_STATUS
{
   STATUS_TRADING,
   STATUS_PAUSED,
   STATUS_PROFIT_LOCK,
   STATUS_LOSS_LIMIT
};

class CRiskManager
{
private:
   double         m_maxDailyLoss;
   double         m_maxDailyProfit;
   int            m_maxConsecutiveLosses;

   double         m_dailyPnL;
   int            m_consecutiveLosses;
   double         m_peakEquity;

   int            m_winCount;
   int            m_lossCount;

   ENUM_EA_STATUS m_status;
   datetime       m_pauseStartTime;
   int            m_pauseDurationSec;

public:
   CRiskManager() : m_maxDailyLoss(25.0), m_maxDailyProfit(50.0),
                    m_maxConsecutiveLosses(5), m_dailyPnL(0.0),
                    m_consecutiveLosses(0), m_peakEquity(0.0),
                    m_winCount(0), m_lossCount(0),
                    m_status(STATUS_TRADING), m_pauseStartTime(0), m_pauseDurationSec(3600) {}

   void Init()
   {
      m_dailyPnL = 0.0;
      m_consecutiveLosses = 0;
      m_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_winCount = 0;
      m_lossCount = 0;
      m_status = STATUS_TRADING;
   }

   void SetLimits(double maxDailyLoss, double maxDailyProfit, int maxConsecutiveLosses)
   {
      m_maxDailyLoss = maxDailyLoss;
      m_maxDailyProfit = maxDailyProfit;
      m_maxConsecutiveLosses = maxConsecutiveLosses;
   }

   bool CanTrade()
   {
      // Check pause timeout
      if(m_status == STATUS_PAUSED)
      {
         if(TimeCurrent() - m_pauseStartTime >= m_pauseDurationSec)
         {
            m_status = STATUS_TRADING;
            m_consecutiveLosses = 0;
            Print("CRiskManager::CanTrade - Pause over. Resuming trading.");
         }
         else
         {
            return false;
         }
      }

      if(m_status == STATUS_PROFIT_LOCK || m_status == STATUS_LOSS_LIMIT)
         return false;

      return true;
   }

   void OnTrade(double pnl)
   {
      m_dailyPnL += pnl;

      if(pnl > 0)
      {
         m_winCount++;
         m_consecutiveLosses = 0;
      }
      else
      {
         m_lossCount++;
         m_consecutiveLosses++;
      }

      // Check profit lock
      if(m_dailyPnL >= m_maxDailyProfit)
      {
         m_status = STATUS_PROFIT_LOCK;
         Print("CRiskManager::OnTrade - Profit lock reached: $", m_dailyPnL);
         return;
      }

      // Check loss limit
      if(m_dailyPnL <= -m_maxDailyLoss)
      {
         m_status = STATUS_LOSS_LIMIT;
         Print("CRiskManager::OnTrade - Loss limit reached: $", m_dailyPnL);
         return;
      }

      // Check consecutive losses pause
      if(m_consecutiveLosses >= m_maxConsecutiveLosses)
      {
         m_status = STATUS_PAUSED;
         m_pauseStartTime = TimeCurrent();
         Print("CRiskManager::OnTrade - ", m_consecutiveLosses, " consecutive losses. Pausing for 1 hour.");
      }
   }

   void OnEquityChange(double equity)
   {
      if(equity > m_peakEquity)
         m_peakEquity = equity;
   }

   ENUM_EA_STATUS GetStatus()                 { return m_status; }
   double  GetDailyPnL()                const { return m_dailyPnL; }
   double  GetPeakEquity()              const { return m_peakEquity; }
   double  GetDrawdown()                const
   {
      double cur = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_peakEquity <= 0) return 0;
      return (m_peakEquity - cur) / m_peakEquity * 100.0;
   }
   double  GetDrawdownDollars()         const
   {
      double cur = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_peakEquity <= 0) return 0;
      return m_peakEquity - cur;
   }
   int     GetConsecutiveLosses()       const { return m_consecutiveLosses; }
   int     GetWinCount()                const { return m_winCount; }
   int     GetLossCount()               const { return m_lossCount; }
   int     GetTradeCount()              const { return m_winCount + m_lossCount; }
   double  GetWinRate()                 const
   {
      int total = m_winCount + m_lossCount;
      if(total == 0) return 0.0;
      return (double)m_winCount / total * 100.0;
   }
   double  GetCurrentMaxDailyLoss()     const { return m_maxDailyLoss; }
   double  GetCurrentMaxDailyProfit()   const { return m_maxDailyProfit; }
   bool    IsPaused()                   const { return m_status == STATUS_PAUSED; }
   int     GetRemainingPauseSeconds()   const
   {
      if(m_status != STATUS_PAUSED) return 0;
      return (int)(m_pauseDurationSec - (TimeCurrent() - m_pauseStartTime));
   }
};

#endif
```

- [ ] **Step 2: Review and commit**

```bash
git add Include/Core/RiskManager.mqh
git commit -m "feat: add RiskManager module with circuit breakers and P&L tracking"
```

---

### Task 5: TradeManager.mqh

**Files:**
- Create: `Include/Core/TradeManager.mqh`

**Interfaces:**
- Produces:
  ```mql5
  class CTradeManager {
    CTradeManager();
    void SetParams(int magic, double lots, double slPoints, double tpPoints);
    bool OpenLong(string symbol);
    bool OpenShort(string symbol);
    bool ClosePosition();
    bool HasOpenPosition();
    double GetPositionPnL();
    ulong  GetPositionTicket();
    string GetPositionDirection();  // "LONG", "SHORT", or "NONE"
    double GetPositionOpenPrice();
    double GetPositionLots();
  };
  ```

Logic: wraps `CTrade` from the MQL5 Standard Library. `OpenLong()` sends `trade.Buy()`. `OpenShort()` sends `trade.Sell()`. Calculates SL/TP in points from entry price. `ClosePosition()` uses `PositionSelectByTicket()` + `trade.PositionClose()`. Uses `PositionGetDouble()` to read floating P&L.

- [ ] **Step 1: Write TradeManager.mqh**

```mql5
//+------------------------------------------------------------------+
//| TradeManager.mqh - Order execution with CTrade                   |
//+------------------------------------------------------------------+
#ifndef TRADE_MANAGER_MQH
#define TRADE_MANAGER_MQH

#include <Trade/Trade.mqh>

class CTradeManager
{
private:
   CTrade        m_trade;
   int           m_magic;
   double        m_lots;
   double        m_slPoints;
   double        m_tpPoints;
   string        m_symbol;

   ulong         m_positionTicket;

   double        GetSLPrice(double entryPrice, int direction)
   {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(direction == ORDER_TYPE_BUY)
         return NormalizeDouble(entryPrice - m_slPoints * point, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
      else
         return NormalizeDouble(entryPrice + m_slPoints * point, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
   }

   double        GetTPPrice(double entryPrice, int direction)
   {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(direction == ORDER_TYPE_BUY)
         return NormalizeDouble(entryPrice + m_tpPoints * point, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
      else
         return NormalizeDouble(entryPrice - m_tpPoints * point, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
   }

public:
   CTradeManager() : m_magic(20260716), m_lots(0.01),
                     m_slPoints(10), m_tpPoints(15),
                     m_symbol("XAUUSD"), m_positionTicket(0) {}

   void SetParams(int magic, double lots, double slPoints, double tpPoints)
   {
      m_magic = magic;
      m_lots = lots;
      m_slPoints = slPoints;
      m_tpPoints = tpPoints;
      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(10);
      m_trade.SetTypeFillingBySymbol(m_symbol);
   }

   void SetSymbol(string symbol) { m_symbol = symbol; }

   bool OpenLong(string symbol)
   {
      m_symbol = symbol;
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double sl = GetSLPrice(ask, ORDER_TYPE_BUY);
      double tp = GetTPPrice(ask, ORDER_TYPE_BUY);

      if(m_trade.Buy(m_lots, symbol, 0.0, sl, tp, "GOLD_SCALPER_BUY"))
      {
         m_positionTicket = m_trade.ResultOrder();
         Print("CTradeManager::OpenLong - BUY opened. Ticket: ", m_positionTicket);
         return true;
      }
      else
      {
         Print("CTradeManager::OpenLong - BUY failed. Retcode: ", m_trade.ResultRetcode(),
               " Desc: ", m_trade.ResultRetcodeDescription());
         return false;
      }
   }

   bool OpenShort(string symbol)
   {
      m_symbol = symbol;
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double sl = GetSLPrice(bid, ORDER_TYPE_SELL);
      double tp = GetTPPrice(bid, ORDER_TYPE_SELL);

      if(m_trade.Sell(m_lots, symbol, 0.0, sl, tp, "GOLD_SCALPER_SELL"))
      {
         m_positionTicket = m_trade.ResultOrder();
         Print("CTradeManager::OpenShort - SELL opened. Ticket: ", m_positionTicket);
         return true;
      }
      else
      {
         Print("CTradeManager::OpenShort - SELL failed. Retcode: ", m_trade.ResultRetcode(),
               " Desc: ", m_trade.ResultRetcodeDescription());
         return false;
      }
   }

   bool ClosePosition()
   {
      if(m_positionTicket == 0) return false;
      if(PositionSelectByTicket(m_positionTicket))
      {
         if(m_trade.PositionClose(m_positionTicket))
         {
            Print("CTradeManager::ClosePosition - Closed ticket: ", m_positionTicket);
            m_positionTicket = 0;
            return true;
         }
      }
      // Ticket might be stale — try selecting first position
      if(PositionsTotal() > 0)
      {
         for(int i = 0; i < PositionsTotal(); i++)
         {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket))
            {
               if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
                  PositionGetInteger(POSITION_MAGIC) == m_magic)
               {
                  if(m_trade.PositionClose(ticket))
                  {
                     m_positionTicket = 0;
                     return true;
                  }
               }
            }
         }
      }
      m_positionTicket = 0;  // position already gone
      return false;
   }

   bool HasOpenPosition()
   {
      if(m_positionTicket == 0) return false;
      return PositionSelectByTicket(m_positionTicket);
   }

   double GetPositionPnL()
   {
      if(!HasOpenPosition()) return 0.0;
      return PositionGetDouble(POSITION_PROFIT);
   }

   ulong  GetPositionTicket()       const { return m_positionTicket; }
   double GetPositionLots()         const
   {
      if(!PositionSelectByTicket(m_positionTicket)) return 0.0;
      return PositionGetDouble(POSITION_VOLUME);
   }
   double GetPositionOpenPrice()    const
   {
      if(!PositionSelectByTicket(m_positionTicket)) return 0.0;
      return PositionGetDouble(POSITION_PRICE_OPEN);
   }

   string GetPositionDirection()    const
   {
      if(!PositionSelectByTicket(m_positionTicket)) return "NONE";
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      return (type == POSITION_TYPE_BUY) ? "LONG" : "SHORT";
   }

   double GetRealizedPnL()          const
   {
      // This is called from OnTrade — returns the P&L of the just-closed trade
      // We track it via the m_trade.ResultProfit() in the main EA
      return 0.0;
   }
};

#endif
```

- [ ] **Step 2: Review and commit**

```bash
git add Include/Core/TradeManager.mqh
git commit -m "feat: add TradeManager module with CTrade-based execution"
```

---

### Task 6: Dashboard.mqh

**Files:**
- Create: `Include/UI/Dashboard.mqh`

**Interfaces:**
- Produces: free functions (no class — lightweight, avoids object overhead for UI):
  ```mql5
  void DashboardCreate();
  void DashboardRemove();
  void DashboardUpdate(
    ENUM_EA_STATUS status, string statusText,
    double balance, double dailyPnL, double sessionPnL,
    int trades, double winRate, int wins, int losses,
    double drawdownPct, double drawdownDollar,
    string positionDir, double positionLots, double positionPnL,
    double spread, bool spreadOk,
    double dailyLossUsed, double dailyProfitUsed,
    int pauseRemainingSec
  );
  void DashboardSetStatus(string text);
  ```

Logic: Creates static OBJ_LABEL + OBJ_RECTANGLE_LABEL objects in OnInit. Update modifies OBJPROP_TEXT on labels. Uses dirty checking — only updates a label if its text actually changed. All objects prefixed `"GOLDSCALPER_"`.

- [ ] **Step 1: Write Dashboard.mqh**

```mql5
//+------------------------------------------------------------------+
//| Dashboard.mqh - On-chart performance panel (OBJ_LABEL based)     |
//+------------------------------------------------------------------+
#ifndef DASHBOARD_MQH
#define DASHBOARD_MQH

#include "../Core/RiskManager.mqh"  // for ENUM_EA_STATUS

#define DASH_PREFIX "GOLDSCALPER_"

// Panel layout constants
#define PANEL_X  20
#define PANEL_Y  20
#define PANEL_W  310
#define PANEL_H  250
#define LINE_H   20
#define COL1_X   (PANEL_X + 12)
#define COL2_X   (PANEL_X + 170)
#define VAL_X    (PANEL_X + 190)

// Label object names
enum ENUM_DASH_LABELS
{
   DASH_BG,        // background rectangle
   DASH_TITLE,     // "GOLD TREND SCALPER v1.0"
   DASH_SEP1,
   DASH_STATUS_L,  // "Status:"
   DASH_STATUS_V,  // "TRADING"
   DASH_BAL_L,     // "Balance:"
   DASH_BAL_V,     // "$3,042.50"
   DASH_PNL_L,     // "P&L:"
   DASH_PNL_V,     // "+42.50"
   DASH_TODAY_L,   // "Today:"
   DASH_TODAY_V,   // "+$18.20"
   DASH_TRADES_L,  // "Trades:"
   DASH_TRADES_V,  // "14"
   DASH_WINR_L,    // "Win Rate:"
   DASH_WINR_V,    // "71% (10W/4L)"
   DASH_DD_L,      // "DD:"
   DASH_DD_V,      // "-$4.30 (-0.14%)"
   DASH_POS_L,     // "Position:"
   DASH_POS_V,     // "LONG 0.01 +$1.20"
   DASH_SPR_L,     // "Spread:"
   DASH_SPR_V,     // "22 pts OK"
   DASH_CIRC_L,    // "Circuit:"
   DASH_CIRC_V1,   // "Profit: $31.80/50"
   DASH_CIRC_V2,   // "Loss:  $0.00/25"
   DASH_LABELS_COUNT
};

string g_dashNames[DASH_LABELS_COUNT];
string g_dashTexts[DASH_LABELS_COUNT];  // for dirty checking

void DashboardInitNames()
{
   g_dashNames[DASH_BG]       = DASH_PREFIX "BG";
   g_dashNames[DASH_TITLE]    = DASH_PREFIX "TITLE";
   g_dashNames[DASH_SEP1]     = DASH_PREFIX "SEP1";
   g_dashNames[DASH_STATUS_L] = DASH_PREFIX "STATUS_L";
   g_dashNames[DASH_STATUS_V] = DASH_PREFIX "STATUS_V";
   g_dashNames[DASH_BAL_L]    = DASH_PREFIX "BAL_L";
   g_dashNames[DASH_BAL_V]    = DASH_PREFIX "BAL_V";
   g_dashNames[DASH_PNL_L]    = DASH_PREFIX "PNL_L";
   g_dashNames[DASH_PNL_V]    = DASH_PREFIX "PNL_V";
   g_dashNames[DASH_TODAY_L]  = DASH_PREFIX "TODAY_L";
   g_dashNames[DASH_TODAY_V]  = DASH_PREFIX "TODAY_V";
   g_dashNames[DASH_TRADES_L] = DASH_PREFIX "TRADES_L";
   g_dashNames[DASH_TRADES_V] = DASH_PREFIX "TRADES_V";
   g_dashNames[DASH_WINR_L]   = DASH_PREFIX "WINR_L";
   g_dashNames[DASH_WINR_V]   = DASH_PREFIX "WINR_V";
   g_dashNames[DASH_DD_L]     = DASH_PREFIX "DD_L";
   g_dashNames[DASH_DD_V]     = DASH_PREFIX "DD_V";
   g_dashNames[DASH_POS_L]    = DASH_PREFIX "POS_L";
   g_dashNames[DASH_POS_V]    = DASH_PREFIX "POS_V";
   g_dashNames[DASH_SPR_L]    = DASH_PREFIX "SPR_L";
   g_dashNames[DASH_SPR_V]    = DASH_PREFIX "SPR_V";
   g_dashNames[DASH_CIRC_L]   = DASH_PREFIX "CIRC_L";
   g_dashNames[DASH_CIRC_V1]  = DASH_PREFIX "CIRC_V1";
   g_dashNames[DASH_CIRC_V2]  = DASH_PREFIX "CIRC_V2";

   for(int i = 0; i < DASH_LABELS_COUNT; i++)
      g_dashTexts[i] = "";
}

void DashboardCreateLabel(string name, int x, int y, string text, color clr, int fontSize = 10)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DashboardCreate()
{
   DashboardInitNames();

   // Background panel
   ObjectCreate(0, g_dashNames[DASH_BG], OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_dashNames[DASH_BG], OBJPROP_XDISTANCE, PANEL_X);
   ObjectSetInteger(0, g_dashNames[DASH_BG], OBJPROP_YDISTANCE, PANEL_Y);
   ObjectSetInteger(0, g_dashNames[DASH_BG], OBJPROP_XSIZE, PANEL_W);
   ObjectSetInteger(0, g_dashNames[DASH_BG], OBJPROP_YSIZE, PANEL_H);
   ObjectSetInteger(0, g_dashNames[DASH_BG], OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, g_dashNames[DASH_BG], OBJPROP_BORDER_COLOR, clrDimGray);
   ObjectSetInteger(0, g_dashNames[DASH_BG], OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, g_dashNames[DASH_BG], OBJPROP_COLOR, clrNONE);
   ObjectSetInteger(0, g_dashNames[DASH_BG], OBJPROP_BACK, true);
   ObjectSetInteger(0, g_dashNames[DASH_BG], OBJPROP_SELECTABLE, false);

   // Title
   DashboardCreateLabel(g_dashNames[DASH_TITLE], COL1_X, PANEL_Y + 4, "GOLD TREND SCALPER  v1.0", clrGold, 11);

   // Separator line via a thin label
   DashboardCreateLabel(g_dashNames[DASH_SEP1], COL1_X, PANEL_Y + 24, "________________________________", clrDimGray, 7);

   // Labels (left column)
   DashboardCreateLabel(g_dashNames[DASH_STATUS_L], COL1_X, PANEL_Y + 38, "Status:", clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_BAL_L],    COL1_X, PANEL_Y + 56, "Balance:", clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_PNL_L],    COL2_X, PANEL_Y + 56, "P&L:", clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_TODAY_L],  COL1_X, PANEL_Y + 74, "Today:", clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_TRADES_L], COL2_X, PANEL_Y + 74, "Trades:", clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_WINR_L],   COL1_X, PANEL_Y + 92, "Win Rate:", clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_DD_L],     COL1_X, PANEL_Y + 110, "DD:", clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_POS_L],    COL1_X, PANEL_Y + 128, "Position:", clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_SPR_L],    COL1_X, PANEL_Y + 146, "Spread:", clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_CIRC_L],   COL1_X, PANEL_Y + 170, "Circuit:", clrWhite, 9);

   // Value labels (right column) — will be updated
   DashboardCreateLabel(g_dashNames[DASH_STATUS_V], COL1_X + 60, PANEL_Y + 38, "INIT", clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_BAL_V],    VAL_X - 20, PANEL_Y + 56, "...", clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_PNL_V],    VAL_X + 80, PANEL_Y + 56, "...", clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_TODAY_V],  VAL_X - 20, PANEL_Y + 74, "...", clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_TRADES_V], VAL_X + 80, PANEL_Y + 74, "...", clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_WINR_V],   VAL_X - 20, PANEL_Y + 92, "...", clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_DD_V],     VAL_X - 20, PANEL_Y + 110, "...", clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_POS_V],    VAL_X - 20, PANEL_Y + 128, "...", clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_SPR_V],    VAL_X - 20, PANEL_Y + 146, "...", clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_CIRC_V1],  VAL_X - 20, PANEL_Y + 170, "...", clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_CIRC_V2],  VAL_X - 20, PANEL_Y + 188, "...", clrWhite, 9);

   ChartRedraw(0);
}

void DashboardRemove()
{
   for(int i = 0; i < DASH_LABELS_COUNT; i++)
   {
      if(g_dashNames[i] != "")
         ObjectDelete(0, g_dashNames[i]);
   }
}

// Dirty-checked update: only redraws when text changes
void DashboardSetText(string name, string newText, color clr = clrWhite)
{
   for(int i = 0; i < DASH_LABELS_COUNT; i++)
   {
      if(g_dashNames[i] == name)
      {
         if(g_dashTexts[i] != newText)
         {
            g_dashTexts[i] = newText;
            ObjectSetString(0, name, OBJPROP_TEXT, newText);
            ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
         }
         return;
      }
   }
}

void DashboardUpdate(
   ENUM_EA_STATUS status, string statusText,
   double balance, double dailyPnL, double sessionPnL,
   int trades, double winRate, int wins, int losses,
   double drawdownPct, double drawdownDollar,
   string positionDir, double positionLots, double positionPnL,
   double spread, bool spreadOk,
   double dailyLossUsed, double dailyProfitUsed,
   int pauseRemainingSec)
{
   // Status
   color statusColor = clrLimeGreen;
   if(status == STATUS_PAUSED)       statusColor = clrYellow;
   if(status == STATUS_PROFIT_LOCK)  statusColor = clrGold;
   if(status == STATUS_LOSS_LIMIT)   statusColor = clrRed;

   string statusStr = statusText;
   if(status == STATUS_PAUSED && pauseRemainingSec > 0)
      statusStr = "PAUSED " + IntegerToString(pauseRemainingSec) + "s";

   DashboardSetText(g_dashNames[DASH_STATUS_V], statusStr, statusColor);

   // Balance & P&L
   color pnlColor = (sessionPnL >= 0) ? clrLimeGreen : clrRed;
   DashboardSetText(g_dashNames[DASH_BAL_V], StringFormat("$%.2f", balance), clrWhite);
   DashboardSetText(g_dashNames[DASH_PNL_V], StringFormat("%+.2f", sessionPnL), pnlColor);

   // Today
   color todayColor = (dailyPnL >= 0) ? clrLimeGreen : clrRed;
   DashboardSetText(g_dashNames[DASH_TODAY_V], StringFormat("%+.2f", dailyPnL), todayColor);
   DashboardSetText(g_dashNames[DASH_TRADES_V], IntegerToString(trades), clrWhite);

   // Win rate
   DashboardSetText(g_dashNames[DASH_WINR_V],
      StringFormat("%.0f%% (%dW/%dL)", winRate, wins, losses), clrWhite);

   // Drawdown
   color ddColor = (drawdownDollar <= 0) ? clrLimeGreen : clrRed;
   DashboardSetText(g_dashNames[DASH_DD_V],
      StringFormat("-$%.2f (%.2f%%)", drawdownDollar, drawdownPct), ddColor);

   // Position
   color posColor = clrGray;
   if(positionDir == "LONG")  posColor = clrLimeGreen;
   if(positionDir == "SHORT") posColor = clrRed;
   if(positionDir != "NONE")
      DashboardSetText(g_dashNames[DASH_POS_V],
         StringFormat("%s %.2f %+.2f", positionDir, positionLots, positionPnL), posColor);
   else
      DashboardSetText(g_dashNames[DASH_POS_V], "NONE", clrGray);

   // Spread
   color spreadColor = spreadOk ? clrLimeGreen : clrRed;
   DashboardSetText(g_dashNames[DASH_SPR_V],
      StringFormat("%.0f pts %s", spread, spreadOk ? "OK" : "HIGH"), spreadColor);

   // Circuit breaker bars
   double profitPct = (dailyProfitUsed > 0) ? MathMin(dailyProfitUsed / 50.0 * 100.0, 100.0) : 0;
   double lossPct   = (dailyLossUsed > 0)   ? MathMin(dailyLossUsed / 25.0 * 100.0, 100.0)  : 0;
   color profitClr  = (profitPct > 80) ? clrGold : clrLimeGreen;
   color lossClr    = (lossPct > 80)   ? clrRed  : clrOrange;

   DashboardSetText(g_dashNames[DASH_CIRC_V1],
      StringFormat("Profit: $%.2f/50", dailyProfitUsed), profitClr);
   DashboardSetText(g_dashNames[DASH_CIRC_V2],
      StringFormat("Loss:  $%.2f/25", dailyLossUsed), lossClr);
}

void DashboardSetStatus(string text)
{
   ObjectSetString(0, DASH_PREFIX "STATUS_V", OBJPROP_TEXT, text);
   ChartRedraw(0);
}

#endif
```

- [ ] **Step 2: Review and commit**

```bash
git add Include/UI/Dashboard.mqh
git commit -m "feat: add Dashboard module with on-chart performance panel"
```

---

### Task 7: GoldScalper.mq5 — Main EA orchestrator

**Files:**
- Create: `GoldScalper.mq5`

**Interfaces:**
- Consumes: all include files above
- Produces: compiled EA

Wires everything together in the standard MQL5 event handlers. The OnTick pipeline follows the spec's data flow: DashboardUpdate → RiskManager.CanTrade → TrendFilter.Update+GetBias → SpreadFilter.IsSpreadOk → MomentumBurst.CheckSignal → TradeManager.OpenLong/OpenShort.

Tracks trade results via OnTrade handler. Detects position closure by polling PositionSelect + monitoring ticket changes.

- [ ] **Step 1: Write GoldScalper.mq5**

```mql5
//+------------------------------------------------------------------+
//| GoldScalper.mq5 - Gold Trend Scalper EA                          |
//| Bi-directional trend-following ultra-scalp for XAUUSD            |
//+------------------------------------------------------------------+
#property copyright "Gold Hammer"
#property version   "1.00"
#property description "Gold Trend Scalper EA - Tick Momentum Burst Tracker"
#property description "Trades XAUUSD using tick momentum with EMA 20 trend filter"
#property description "Hard risk limits: no martingale, daily loss cap, profit lock"

#include <Trade/Trade.mqh>
#include "Include/Signal/MomentumBurst.mqh"
#include "Include/Core/TradeManager.mqh"
#include "Include/Core/RiskManager.mqh"
#include "Include/Filters/TrendFilter.mqh"
#include "Include/Filters/SpreadFilter.mqh"
#include "Include/UI/Dashboard.mqh"

// --- Input Parameters ---
input int    InpMomentumTicks      = 5;          // Momentum lookback (ticks)
input int    InpMomentumPoints     = 8;          // Momentum threshold (points)
input int    InpStopLossPoints     = 10;         // Stop Loss (points)
input int    InpTakeProfitPoints   = 15;         // Take Profit (points)
input double InpMaxDailyLoss       = 25.0;       // Max daily loss ($)
input double InpMaxDailyProfit     = 50.0;       // Max daily profit lock ($)
input int    InpMaxConsecutiveLosses = 5;        // Consecutive losses before pause
input int    InpMaxSpread          = 30;         // Max spread (points)
input int    InpEMAPeriod          = 20;         // Trend filter EMA period
input int    InpMagicNumber        = 20260716;   // EA Magic Number

// --- Global Objects ---
CMomentumBurst  g_momentum;
CTradeManager   g_tradeMgr;
CRiskManager    g_riskMgr;
CTrendFilter    g_trendFilter;
CSpreadFilter   g_spreadFilter;

// --- State ---
string          g_symbol = "XAUUSD";
double          g_sessionPnL;
ulong           g_lastTicket;   // track position changes

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate symbol
   if(!SymbolSelect(g_symbol, true))
   {
      Print("Symbol ", g_symbol, " not available. Please add to Market Watch.");
      return INIT_FAILED;
   }

   // Init momentum burst detector
   g_momentum.SetParams(InpMomentumTicks, InpMomentumPoints);
   g_momentum.SetAcceleration(true);
   g_momentum.SetCooldown(1000);

   // Init trade manager
   g_tradeMgr.SetSymbol(g_symbol);
   g_tradeMgr.SetParams(InpMagicNumber, 0.01, InpStopLossPoints, InpTakeProfitPoints);

   // Init risk manager
   g_riskMgr.Init();
   g_riskMgr.SetLimits(InpMaxDailyLoss, InpMaxDailyProfit, InpMaxConsecutiveLosses);

   // Init trend filter
   if(!g_trendFilter.Init(g_symbol, PERIOD_M1, InpEMAPeriod))
   {
      Print("Failed to initialize trend filter EMA handle");
      return INIT_FAILED;
   }

   // Init spread filter
   g_spreadFilter.SetMaxSpread(InpMaxSpread);

   // Init state
   g_sessionPnL = 0.0;
   g_lastTicket = 0;

   // Create dashboard
   DashboardCreate();

   // Set timer for 1-second refresh
   EventSetTimer(1);

   Print("Gold Trend Scalper initialized. Symbol: ", g_symbol, " Magic: ", InpMagicNumber);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_trendFilter.Release();
   DashboardRemove();
   EventKillTimer();
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert timer function                                             |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Risk manager handles pause cooldown
   g_riskMgr.OnEquityChange(AccountInfoDouble(ACCOUNT_EQUITY));

   // Update dashboard
   RefreshDashboard();

   // Force chart redraw periodically
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Feed tick data to momentum detector
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   g_momentum.OnTick(bid, ask);

   // Update equity for drawdown tracking
   g_riskMgr.OnEquityChange(AccountInfoDouble(ACCOUNT_EQUITY));

   // Update trend filter
   g_trendFilter.Update();

   // --- Pipeline logic ---

   // 1. If we have an open position, check if it was closed (by SL/TP)
   if(g_lastTicket > 0)
   {
      if(!PositionSelectByTicket(g_lastTicket))
      {
         // Position was closed — track result in OnTrade will handle this
         g_lastTicket = 0;
      }
      // If position still open, we don't enter another — single position rule
      else
      {
         // Still have position, just update dashboard
         RefreshDashboard();
         return;
      }
   }

   // 2. Risk check
   if(!g_riskMgr.CanTrade())
   {
      RefreshDashboard();
      return;
   }

   // 3. Trend filter — directional bias
   ENUM_SIGNAL trendBias = g_trendFilter.GetBias();
   if(trendBias == SIGNAL_NONE || g_trendFilter.IsCrossing())
   {
      RefreshDashboard();
      return;  // Wait for candle close after cross
   }

   // 4. Spread check
   if(!g_spreadFilter.IsSpreadOk(g_symbol))
   {
      RefreshDashboard();
      return;
   }

   // 5. Momentum check
   ENUM_SIGNAL signal = g_momentum.CheckSignal();
   if(signal == SIGNAL_NONE)
   {
      RefreshDashboard();
      return;
   }

   // 6. Signal must match trend bias
   if(signal != trendBias)
   {
      RefreshDashboard();
      return;
   }

   // 7. Execute trade
   bool opened = false;
   if(signal == SIGNAL_BUY)
      opened = g_tradeMgr.OpenLong(g_symbol);
   else if(signal == SIGNAL_SELL)
      opened = g_tradeMgr.OpenShort(g_symbol);

   if(opened)
   {
      g_lastTicket = g_tradeMgr.GetPositionTicket();
      Print("Trade opened: ", g_lastTicket);
   }

   RefreshDashboard();
}

//+------------------------------------------------------------------+
//| Trade event handler                                               |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Detect if our position was closed and track P&L
   // Use the trade manager's execution result
   if(g_lastTicket > 0 && !PositionSelectByTicket(g_lastTicket))
   {
      // Our position is no longer open — it was closed by SL/TP or manually
      // We track the result from history
      if(HistorySelect(TimeCurrent() - 86400, TimeCurrent()))  // last 24h
      {
         int total = HistoryDealsTotal();
         for(int i = 0; i < total; i++)
         {
            ulong dealTicket = HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != InpMagicNumber)
               continue;
            if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != g_symbol)
               continue;

            ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
            {
               double pnl = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
               g_riskMgr.OnTrade(pnl);
               g_sessionPnL += pnl;
               Print("Trade closed. P&L: ", pnl, " Session: ", g_sessionPnL);
               break;
            }
         }
      }

      g_lastTicket = 0;
   }

   RefreshDashboard();
}

//+------------------------------------------------------------------+
//| Refresh dashboard with current state                              |
//+------------------------------------------------------------------+
void RefreshDashboard()
{
   ENUM_EA_STATUS status = g_riskMgr.GetStatus();
   string statusText = "";
   switch(status)
   {
      case STATUS_TRADING:     statusText = "TRADING"; break;
      case STATUS_PAUSED:      statusText = "PAUSED"; break;
      case STATUS_PROFIT_LOCK: statusText = "PROFIT LOCK"; break;
      case STATUS_LOSS_LIMIT:  statusText = "LOSS LIMIT"; break;
   }

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyPnL   = g_riskMgr.GetDailyPnL();
   int    trades     = g_riskMgr.GetTradeCount();
   double winRate    = g_riskMgr.GetWinRate();
   int    wins       = g_riskMgr.GetWinCount();
   int    losses     = g_riskMgr.GetLossCount();
   double ddPct      = g_riskMgr.GetDrawdown();
   double ddDollar   = g_riskMgr.GetDrawdownDollars();

   string posDir     = g_tradeMgr.GetPositionDirection();
   double posLots    = g_tradeMgr.HasOpenPosition() ? g_tradeMgr.GetPositionLots() : 0.0;
   double posPnL     = g_tradeMgr.GetPositionPnL();

   long spread       = SymbolInfoInteger(g_symbol, SYMBOL_SPREAD);
   bool spreadOk     = (int)spread <= InpMaxSpread;

   double dailyLoss  = MathAbs(MathMin(dailyPnL, 0.0));
   double dailyProfit = MathMax(dailyPnL, 0.0);

   int pauseRemaining = g_riskMgr.GetRemainingPauseSeconds();

   DashboardUpdate(
      status, statusText,
      balance, dailyPnL, g_sessionPnL,
      trades, winRate, wins, losses,
      ddPct, ddDollar,
      posDir, posLots, posPnL,
      (double)spread, spreadOk,
      dailyLoss, dailyProfit,
      pauseRemaining
   );
}

//+------------------------------------------------------------------+
//| Tester function (custom optimization criteria)                   |
//+------------------------------------------------------------------+
double OnTester()
{
   double profit     = TesterStatistics(STAT_PROFIT);
   double profitFact = TesterStatistics(STAT_PROFIT_FACTOR);
   double sharpe     = TesterStatistics(STAT_SHARPE_RATIO);
   double maxDD      = TesterStatistics(STAT_EQUITY_DD_RELATIVE);
   int    trades     = (int)TesterStatistics(STAT_TRADES);

   if(trades < 100)     return 0;
   if(maxDD > 15)      return 0;
   if(profitFact < 1.3) return 0;

   return sharpe * (profit / (1 + maxDD / 100.0));
}
```

- [ ] **Step 2: Verify the main EA compiles in MetaEditor**

Open `GoldScalper.mq5` in MetaEditor (F4 from MT5). Press F7 to compile. Expected: 0 errors, 0 warnings. If errors occur: check include paths, verify all enum/class names match between files.

- [ ] **Step 3: Commit**

```bash
git add GoldScalper.mq5
git commit -m "feat: add Gold Trend Scalper EA main orchestrator"
```

---

## Verification

After all tasks complete, run these verifications:

1. **Compile check**: Open `GoldScalper.mq5` in MetaEditor → F7. 0 errors, 0 warnings.
2. **Backtest (Open Prices)**: Run XAUUSD M1, 1 year of data. Verify trades happen and the EMA filter blocks wrong-direction entries.
3. **Backtest (Every Tick)**: Run same period with Every Tick. Verify at least 2,000 trades.
4. **Circuit breaker test**: Manually set InpMaxDailyLoss = 1 (very small). Run backtest. Verify EA stops trading after ~1 loss.
5. **Spread filter test**: Set InpMaxSpread = 1. Verify no trades fire.
6. **Dashboard visual check**: Attach EA to live chart. Verify all fields display and update.
7. **Walk-forward**: 70% IS / 30% OOS. Verify OOS performance >= 50% of IS.
8. **Monte Carlo**: Run 1,000 randomized trade sequences. Verify 95th percentile DD < 15%.
