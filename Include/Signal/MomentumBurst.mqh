//+------------------------------------------------------------------+
//| MomentumBurst.mqh - Tick momentum burst detection                |
//+------------------------------------------------------------------+
#ifndef MOMENTUM_BURST_MQH
#define MOMENTUM_BURST_MQH

enum ENUM_SIGNAL { SIGNAL_NONE = 0, SIGNAL_BUY = 1, SIGNAL_SELL = -1 };

class CMomentumBurst
{
private:
   int         m_lookbackTicks;
   int         m_thresholdPoints;
   bool        m_requireAccel;

   double      m_bidRing[];
   double      m_askRing[];
   int         m_head;          // next write position (also oldest when full)
   int         m_count;         // entries filled so far

   datetime    m_lastSignalTime;
   int         m_cooldownMs;

   bool CheckAcceleration(int direction)
   {
      if(!m_requireAccel || m_count < 3) return true;

      // c0 = newest, c1 = 2nd newest, c2 = 3rd newest
      int c0 = (m_head - 1 + m_lookbackTicks) % m_lookbackTicks;
      int c1 = (m_head - 2 + m_lookbackTicks) % m_lookbackTicks;
      int c2 = (m_head - 3 + m_lookbackTicks) % m_lookbackTicks;

      if(direction > 0)  // BUY: each ask should be higher than the previous
         return (m_askRing[c0] > m_askRing[c1] && m_askRing[c1] > m_askRing[c2]);
      else               // SELL: each bid should be lower than the previous
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
      // Cooldown check — prevent re-triggering on same burst
      if(GetTickCount() - m_lastSignalTime < m_cooldownMs)
         return SIGNAL_NONE;

      // Wait until ring buffer is full
      if(m_count < m_lookbackTicks) return SIGNAL_NONE;

      // oldest entry = head (next to be overwritten)
      // newest entry = head - 1 (last written, adjusted for wrap)
      int oldestIdx = m_head;
      int newestIdx = (m_head - 1 + m_lookbackTicks) % m_lookbackTicks;

      double askNow = m_askRing[newestIdx];
      double bidNow = m_bidRing[newestIdx];
      double askOld = m_askRing[oldestIdx];
      double bidOld = m_bidRing[oldestIdx];

      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

      // BUY: ask rose by threshold points over the lookback window
      if((askNow - askOld) >= m_thresholdPoints * point)
      {
         if(CheckAcceleration(1))
         {
            m_lastSignalTime = GetTickCount();
            return SIGNAL_BUY;
         }
      }

      // SELL: bid fell by threshold points over the lookback window
      if((bidOld - bidNow) >= m_thresholdPoints * point)
      {
         if(CheckAcceleration(-1))
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
