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
input int    InpMomentumTicks        = 5;        // Momentum lookback (ticks)
input int    InpMomentumPoints       = 8;        // Momentum threshold (points)
input int    InpStopLossPoints       = 10;       // Stop Loss (points)
input int    InpTakeProfitPoints     = 15;       // Take Profit (points)
input double InpMaxDailyLoss         = 25.0;     // Max daily loss ($)
input double InpMaxDailyProfit       = 50.0;     // Max daily profit lock ($)
input int    InpMaxConsecutiveLosses = 5;        // Consecutive losses before pause
input int    InpMaxSpread            = 30;       // Max spread (points)
input int    InpEMAPeriod            = 20;       // Trend filter EMA period
input int    InpMagicNumber          = 20260716; // EA Magic Number

// --- Module instances ---
CMomentumBurst  g_momentum;
CTradeManager   g_tradeMgr;
CRiskManager    g_riskMgr;
CTrendFilter    g_trendFilter;
CSpreadFilter   g_spreadFilter;

// --- State ---
string  g_symbol             = "XAUUSD";
double  g_sessionPnL         = 0.0;
ulong   g_lastTicket         = 0;    // currently open position
ulong   g_pendingCloseTicket = 0;    // ticket awaiting OnTrade P&L processing

//+------------------------------------------------------------------+
//| Refresh dashboard with all current state                          |
//+------------------------------------------------------------------+
void RefreshDashboard()
{
   ENUM_EA_STATUS status     = g_riskMgr.GetStatus();
   string statusText         = "";
   switch(status)
   {
      case STATUS_TRADING:     statusText = "TRADING";      break;
      case STATUS_PAUSED:      statusText = "PAUSED";       break;
      case STATUS_PROFIT_LOCK: statusText = "PROFIT LOCK";  break;
      case STATUS_LOSS_LIMIT:  statusText = "LOSS LIMIT";   break;
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

   long   spread     = SymbolInfoInteger(g_symbol, SYMBOL_SPREAD);
   bool   spreadOk   = (int)spread <= InpMaxSpread;

   double dailyLoss  = MathAbs(MathMin(dailyPnL, 0.0));
   double dailyProfit = MathMax(dailyPnL, 0.0);
   int    pauseRemaining = g_riskMgr.GetRemainingPauseSeconds();

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
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate symbol availability
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

   // Init trend filter (EMA 20 on M1)
   if(!g_trendFilter.Init(g_symbol, PERIOD_M1, InpEMAPeriod))
   {
      Print("Failed to initialize trend filter EMA handle");
      return INIT_FAILED;
   }

   // Init spread filter
   g_spreadFilter.SetMaxSpread(InpMaxSpread);

   // Init state
   g_sessionPnL         = 0.0;
   g_lastTicket         = 0;
   g_pendingCloseTicket = 0;

   // Create dashboard
   DashboardCreate();

   // 1-second timer for periodic dashboard refresh + pause countdown
   EventSetTimer(1);

   Print("Gold Trend Scalper initialized. Symbol: ", g_symbol,
         " Magic: ", InpMagicNumber, " Lots: 0.01");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_trendFilter.Release();
   DashboardRemove();
   EventKillTimer();
   Comment("");
}

//+------------------------------------------------------------------+
//| Timer — periodic refresh + pause cooldown                         |
//+------------------------------------------------------------------+
void OnTimer()
{
   g_riskMgr.OnEquityChange(AccountInfoDouble(ACCOUNT_EQUITY));
   RefreshDashboard();
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Tick handler — main trading pipeline                              |
//+------------------------------------------------------------------+
void OnTick()
{
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);

   // Feed tick data to momentum detector
   g_momentum.OnTick(bid, ask);

   // Update equity tracking
   g_riskMgr.OnEquityChange(AccountInfoDouble(ACCOUNT_EQUITY));

   // Update trend filter crossing state
   g_trendFilter.Update();

   // --- Position management ---
   if(g_lastTicket > 0)
   {
      if(!PositionSelectByTicket(g_lastTicket))
      {
         // Position was closed (SL/TP hit) — save ticket for OnTrade P&L processing
         g_pendingCloseTicket = g_lastTicket;
         g_lastTicket = 0;
         g_momentum.Reset();  // clear stale tick buffer
      }
      else
      {
         // Position still open — single-position rule, no new entries
         RefreshDashboard();
         return;
      }
   }

   // --- Trading gate: risk limits ---
   if(!g_riskMgr.CanTrade())
   {
      RefreshDashboard();
      return;
   }

   // --- Trend filter: directional bias ---
   ENUM_SIGNAL trendBias = g_trendFilter.GetBias();
   if(trendBias == SIGNAL_NONE || g_trendFilter.IsCrossing())
   {
      RefreshDashboard();
      return;  // EMA crossing — wait for candle close
   }

   // --- Spread filter ---
   if(!g_spreadFilter.IsSpreadOk(g_symbol))
   {
      RefreshDashboard();
      return;
   }

   // --- Momentum signal ---
   ENUM_SIGNAL signal = g_momentum.CheckSignal();
   if(signal == SIGNAL_NONE)
   {
      RefreshDashboard();
      return;
   }

   // --- Signal must align with trend bias ---
   if(signal != trendBias)
   {
      RefreshDashboard();
      return;  // momentum against trend — ignore
   }

   // --- Execute ---
   bool opened = false;
   if(signal == SIGNAL_BUY)
      opened = g_tradeMgr.OpenLong(g_symbol);
   else if(signal == SIGNAL_SELL)
      opened = g_tradeMgr.OpenShort(g_symbol);

   if(opened)
   {
      g_lastTicket = g_tradeMgr.GetPositionTicket();
      Print("Trade opened. Ticket: ", g_lastTicket,
            " Direction: ", (signal == SIGNAL_BUY) ? "BUY" : "SELL");
   }

   RefreshDashboard();
}

//+------------------------------------------------------------------+
//| Trade event — track closed P&L                                    |
//+------------------------------------------------------------------+
void OnTrade()
{
   if(g_pendingCloseTicket == 0) return;

   if(HistorySelect(TimeCurrent() - 86400, TimeCurrent()))  // last 24h
   {
      // Scan newest deals first to find the OUT deal for our position
      int total = HistoryDealsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong dealTicket = HistoryDealGetTicket(i);

         // Filter: our magic, our symbol, closing deal
         if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != InpMagicNumber)
            continue;
         if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != g_symbol)
            continue;

         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
            continue;

         // Filter by position ID to ensure it's our specific position
         if(HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == g_pendingCloseTicket)
         {
            double pnl = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
            double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
            double netPnl = pnl + commission + swap;

            g_riskMgr.OnTrade(netPnl);
            g_sessionPnL += netPnl;

            Print("Trade closed. Ticket: ", g_pendingCloseTicket,
                  " P&L: ", DoubleToString(pnl, 2),
                  " Net: ", DoubleToString(netPnl, 2),
                  " Session: ", DoubleToString(g_sessionPnL, 2));
            break;
         }
      }
   }

   g_pendingCloseTicket = 0;
   RefreshDashboard();
}

//+------------------------------------------------------------------+
//| Tester — custom optimization criteria                             |
//+------------------------------------------------------------------+
double OnTester()
{
   double profit     = TesterStatistics(STAT_PROFIT);
   double profitFact = TesterStatistics(STAT_PROFIT_FACTOR);
   double sharpe     = TesterStatistics(STAT_SHARPE_RATIO);
   double maxDD      = TesterStatistics(STAT_EQUITY_DD_RELATIVE);
   int    trades     = (int)TesterStatistics(STAT_TRADES);

   // Gate: insufficient sample or catastrophic drawdown
   if(trades < 100)     return 0.0;
   if(maxDD > 15.0)     return 0.0;
   if(profitFact < 1.3) return 0.0;

   return sharpe * (profit / (1.0 + maxDD / 100.0));
}
