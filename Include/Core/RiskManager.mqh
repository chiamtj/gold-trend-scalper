//+------------------------------------------------------------------+
//| RiskManager.mqh - Daily limits, circuit breakers, P&L tracking   |
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
                    m_status(STATUS_TRADING), m_pauseStartTime(0),
                    m_pauseDurationSec(3600) {}

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

   // --- Trading gate ---

   bool CanTrade()
   {
      // Pause timeout check
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

      // Hard circuit breakers — trading stopped for the day
      if(m_status == STATUS_PROFIT_LOCK || m_status == STATUS_LOSS_LIMIT)
         return false;

      return true;
   }

   // --- Trade result tracking ---

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

      // Check profit lock (reached daily target)
      if(m_dailyPnL >= m_maxDailyProfit)
      {
         m_status = STATUS_PROFIT_LOCK;
         Print("CRiskManager::OnTrade - Profit lock reached: $",
               DoubleToString(m_dailyPnL, 2));
         return;
      }

      // Check loss limit (breached daily max)
      if(m_dailyPnL <= -m_maxDailyLoss)
      {
         m_status = STATUS_LOSS_LIMIT;
         Print("CRiskManager::OnTrade - Loss limit reached: $",
               DoubleToString(m_dailyPnL, 2));
         return;
      }

      // Check consecutive losses pause
      if(m_consecutiveLosses >= m_maxConsecutiveLosses)
      {
         m_status = STATUS_PAUSED;
         m_pauseStartTime = TimeCurrent();
         Print("CRiskManager::OnTrade - ", m_consecutiveLosses,
               " consecutive losses. Pausing for 1 hour.");
      }
   }

   // --- Equity tracking (for drawdown) ---

   void OnEquityChange(double equity)
   {
      if(equity > m_peakEquity)
         m_peakEquity = equity;
   }

   // --- Getters ---

   ENUM_EA_STATUS GetStatus()                const { return m_status; }
   double         GetDailyPnL()               const { return m_dailyPnL; }
   double         GetPeakEquity()             const { return m_peakEquity; }

   double         GetDrawdown()               const
   {
      double cur = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_peakEquity <= 0) return 0.0;
      return (m_peakEquity - cur) / m_peakEquity * 100.0;
   }

   double         GetDrawdownDollars()        const
   {
      double cur = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_peakEquity <= 0) return 0.0;
      return m_peakEquity - cur;
   }

   int            GetConsecutiveLosses()      const { return m_consecutiveLosses; }
   int            GetWinCount()               const { return m_winCount; }
   int            GetLossCount()              const { return m_lossCount; }
   int            GetTradeCount()             const { return m_winCount + m_lossCount; }

   double         GetWinRate()                const
   {
      int total = m_winCount + m_lossCount;
      if(total == 0) return 0.0;
      return (double)m_winCount / total * 100.0;
   }

   double         GetCurrentMaxDailyLoss()    const { return m_maxDailyLoss; }
   double         GetCurrentMaxDailyProfit()  const { return m_maxDailyProfit; }
   bool           IsPaused()                  const { return m_status == STATUS_PAUSED; }

   int            GetRemainingPauseSeconds()  const
   {
      if(m_status != STATUS_PAUSED) return 0;
      return (int)(m_pauseDurationSec - (TimeCurrent() - m_pauseStartTime));
   }
};

#endif
