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
