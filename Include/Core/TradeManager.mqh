//+------------------------------------------------------------------+
//| TradeManager.mqh - Order execution with CTrade                   |
//+------------------------------------------------------------------+
#ifndef TRADE_MANAGER_MQH
#define TRADE_MANAGER_MQH

#include <Trade/Trade.mqh>

class CTradeManager
{
private:
   CTrade         m_trade;
   int            m_magic;
   double         m_lots;
   double         m_slPoints;
   double         m_tpPoints;
   string         m_symbol;

   ulong          m_positionTicket;

   double GetSLPrice(double entryPrice, int direction)
   {
      double point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      int    digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      if(direction == ORDER_TYPE_BUY)
         return NormalizeDouble(entryPrice - m_slPoints * point, digits);
      else
         return NormalizeDouble(entryPrice + m_slPoints * point, digits);
   }

   double GetTPPrice(double entryPrice, int direction)
   {
      double point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      int    digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      if(direction == ORDER_TYPE_BUY)
         return NormalizeDouble(entryPrice + m_tpPoints * point, digits);
      else
         return NormalizeDouble(entryPrice - m_tpPoints * point, digits);
   }

public:
   CTradeManager() : m_magic(20260716), m_lots(0.01),
                     m_slPoints(10), m_tpPoints(15),
                     m_symbol("XAUUSD"), m_positionTicket(0) {}

   void SetParams(int magic, double lots, double slPoints, double tpPoints)
   {
      m_magic    = magic;
      m_lots     = lots;
      m_slPoints = slPoints;
      m_tpPoints = tpPoints;

      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(10);
      m_trade.SetTypeFillingBySymbol(m_symbol);
   }

   void SetSymbol(string symbol) { m_symbol = symbol; }

   // --- Order entry ---

   bool OpenLong(string symbol)
   {
      m_symbol = symbol;
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double sl  = GetSLPrice(ask, ORDER_TYPE_BUY);
      double tp  = GetTPPrice(ask, ORDER_TYPE_BUY);

      if(m_trade.Buy(m_lots, symbol, 0.0, sl, tp, "GOLD_SCALPER_BUY"))
      {
         m_positionTicket = m_trade.ResultOrder();
         Print("CTradeManager::OpenLong - BUY opened. Ticket: ", m_positionTicket);
         return true;
      }

      Print("CTradeManager::OpenLong - BUY failed. Retcode: ", m_trade.ResultRetcode(),
            " Desc: ", m_trade.ResultRetcodeDescription());
      return false;
   }

   bool OpenShort(string symbol)
   {
      m_symbol = symbol;
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double sl  = GetSLPrice(bid, ORDER_TYPE_SELL);
      double tp  = GetTPPrice(bid, ORDER_TYPE_SELL);

      if(m_trade.Sell(m_lots, symbol, 0.0, sl, tp, "GOLD_SCALPER_SELL"))
      {
         m_positionTicket = m_trade.ResultOrder();
         Print("CTradeManager::OpenShort - SELL opened. Ticket: ", m_positionTicket);
         return true;
      }

      Print("CTradeManager::OpenShort - SELL failed. Retcode: ", m_trade.ResultRetcode(),
            " Desc: ", m_trade.ResultRetcodeDescription());
      return false;
   }

   // --- Position management ---

   bool ClosePosition()
   {
      // Try tracked ticket first
      if(m_positionTicket != 0 && PositionSelectByTicket(m_positionTicket))
      {
         if(m_trade.PositionClose(m_positionTicket))
         {
            Print("CTradeManager::ClosePosition - Closed ticket: ", m_positionTicket);
            m_positionTicket = 0;
            return true;
         }
      }

      // Fallback: scan all positions for matching symbol + magic
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

      m_positionTicket = 0;  // position already gone
      return false;
   }

   bool HasOpenPosition()
   {
      if(m_positionTicket == 0) return false;
      return PositionSelectByTicket(m_positionTicket);
   }

   // --- Position info ---

   double GetPositionPnL()
   {
      if(!HasOpenPosition()) return 0.0;
      return PositionGetDouble(POSITION_PROFIT);
   }

   ulong  GetPositionTicket()    { return m_positionTicket; }

   double GetPositionLots()
   {
      if(!PositionSelectByTicket(m_positionTicket)) return 0.0;
      return PositionGetDouble(POSITION_VOLUME);
   }

   double GetPositionOpenPrice()
   {
      if(!PositionSelectByTicket(m_positionTicket)) return 0.0;
      return PositionGetDouble(POSITION_PRICE_OPEN);
   }

   string GetPositionDirection()
   {
      if(!PositionSelectByTicket(m_positionTicket)) return "NONE";
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      return (type == POSITION_TYPE_BUY) ? "LONG" : "SHORT";
   }
};

#endif
