//+------------------------------------------------------------------+
//| TrendFilter.mqh - EMA 20 directional bias filter                 |
//+------------------------------------------------------------------+
#ifndef TREND_FILTER_MQH
#define TREND_FILTER_MQH

#include "../Signal/MomentumBurst.mqh"

class CTrendFilter
{
private:
   int               m_handleEMA;
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   int               m_period;
   double            m_prevClose;
   double            m_prevEMA;
   bool              m_wasAbove;
   bool              m_crossing;      // true during candle-cross period

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
