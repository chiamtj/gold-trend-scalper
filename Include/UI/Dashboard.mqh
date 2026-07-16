//+------------------------------------------------------------------+
//| Dashboard.mqh - On-chart performance panel (OBJ_LABEL based)     |
//+------------------------------------------------------------------+
#ifndef DASHBOARD_MQH
#define DASHBOARD_MQH

#include "../Core/RiskManager.mqh"  // for ENUM_EA_STATUS

#define DASH_PREFIX "GOLDSCALPER_"

// Panel layout constants
#define PANEL_X   20
#define PANEL_Y   20
#define PANEL_W   310
#define PANEL_H   250
#define COL1_X    (PANEL_X + 12)
#define COL2_X    (PANEL_X + 170)
#define VAL_X     (PANEL_X + 190)

// Label object name indices
enum ENUM_DASH_LABELS
{
   DASH_BG,
   DASH_TITLE,
   DASH_SEP1,
   DASH_STATUS_L,
   DASH_STATUS_V,
   DASH_BAL_L,
   DASH_BAL_V,
   DASH_PNL_L,
   DASH_PNL_V,
   DASH_TODAY_L,
   DASH_TODAY_V,
   DASH_TRADES_L,
   DASH_TRADES_V,
   DASH_WINR_L,
   DASH_WINR_V,
   DASH_DD_L,
   DASH_DD_V,
   DASH_POS_L,
   DASH_POS_V,
   DASH_SPR_L,
   DASH_SPR_V,
   DASH_CIRC_L,
   DASH_CIRC_V1,
   DASH_CIRC_V2,
   DASH_LABELS_COUNT
};

string g_dashNames[DASH_LABELS_COUNT];
string g_dashTexts[DASH_LABELS_COUNT];  // for dirty checking

//+------------------------------------------------------------------+
//| Initialize label name array                                       |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Create a single OBJ_LABEL                                        |
//+------------------------------------------------------------------+
void DashboardCreateLabel(string name, int x, int y, string text, color clr, int fontSize = 10)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0,  name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Create all dashboard objects (call in OnInit)                    |
//+------------------------------------------------------------------+
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

   // Separator
   DashboardCreateLabel(g_dashNames[DASH_SEP1], COL1_X, PANEL_Y + 24, "________________________________", clrDimGray, 7);

   // Static labels (left column)
   DashboardCreateLabel(g_dashNames[DASH_STATUS_L], COL1_X, PANEL_Y + 38, "Status:",    clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_BAL_L],    COL1_X, PANEL_Y + 56, "Balance:",   clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_PNL_L],    COL2_X, PANEL_Y + 56, "P&L:",       clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_TODAY_L],  COL1_X, PANEL_Y + 74, "Today:",     clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_TRADES_L], COL2_X, PANEL_Y + 74, "Trades:",    clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_WINR_L],   COL1_X, PANEL_Y + 92, "Win Rate:",  clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_DD_L],     COL1_X, PANEL_Y + 110, "DD:",       clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_POS_L],    COL1_X, PANEL_Y + 128, "Position:", clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_SPR_L],    COL1_X, PANEL_Y + 146, "Spread:",   clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_CIRC_L],   COL1_X, PANEL_Y + 170, "Circuit:",  clrWhite, 9);

   // Value labels (right column — updated on each refresh)
   DashboardCreateLabel(g_dashNames[DASH_STATUS_V], COL1_X + 60, PANEL_Y + 38,  "INIT", clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_BAL_V],    VAL_X - 20,  PANEL_Y + 56,  "...",  clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_PNL_V],    VAL_X + 80,  PANEL_Y + 56,  "...",  clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_TODAY_V],  VAL_X - 20,  PANEL_Y + 74,  "...",  clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_TRADES_V], VAL_X + 80,  PANEL_Y + 74,  "...",  clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_WINR_V],   VAL_X - 20,  PANEL_Y + 92,  "...",  clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_DD_V],     VAL_X - 20,  PANEL_Y + 110, "...",  clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_POS_V],    VAL_X - 20,  PANEL_Y + 128, "...",  clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_SPR_V],    VAL_X - 20,  PANEL_Y + 146, "...",  clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_CIRC_V1],  VAL_X - 20,  PANEL_Y + 170, "...",  clrWhite, 9);
   DashboardCreateLabel(g_dashNames[DASH_CIRC_V2],  VAL_X - 20,  PANEL_Y + 188, "...",  clrWhite, 9);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Remove all dashboard objects (call in OnDeinit)                   |
//+------------------------------------------------------------------+
void DashboardRemove()
{
   for(int i = 0; i < DASH_LABELS_COUNT; i++)
   {
      if(g_dashNames[i] != "")
         ObjectDelete(0, g_dashNames[i]);
   }
}

//+------------------------------------------------------------------+
//| Set label text with dirty checking (avoids unnecessary redraws)  |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Full dashboard refresh with current state                        |
//+------------------------------------------------------------------+
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
   // --- Status ---
   color statusColor = clrLimeGreen;
   if(status == STATUS_PAUSED)       statusColor = clrYellow;
   if(status == STATUS_PROFIT_LOCK)  statusColor = clrGold;
   if(status == STATUS_LOSS_LIMIT)   statusColor = clrRed;

   string statusStr = statusText;
   if(status == STATUS_PAUSED && pauseRemainingSec > 0)
      statusStr = "PAUSED " + IntegerToString(pauseRemainingSec) + "s";

   DashboardSetText(g_dashNames[DASH_STATUS_V], statusStr, statusColor);

   // --- Balance & Session P&L ---
   color pnlColor = (sessionPnL >= 0) ? clrLimeGreen : clrRed;
   DashboardSetText(g_dashNames[DASH_BAL_V], StringFormat("$%.2f", balance), clrWhite);
   DashboardSetText(g_dashNames[DASH_PNL_V], StringFormat("%+.2f", sessionPnL), pnlColor);

   // --- Today's P&L & trade count ---
   color todayColor = (dailyPnL >= 0) ? clrLimeGreen : clrRed;
   DashboardSetText(g_dashNames[DASH_TODAY_V],  StringFormat("%+.2f", dailyPnL), todayColor);
   DashboardSetText(g_dashNames[DASH_TRADES_V], IntegerToString(trades), clrWhite);

   // --- Win rate ---
   DashboardSetText(g_dashNames[DASH_WINR_V],
      StringFormat("%.0f%% (%dW/%dL)", winRate, wins, losses), clrWhite);

   // --- Drawdown ---
   color ddColor = (drawdownDollar <= 0) ? clrLimeGreen : clrRed;
   DashboardSetText(g_dashNames[DASH_DD_V],
      StringFormat("-$%.2f (%.2f%%)", drawdownDollar, drawdownPct), ddColor);

   // --- Position ---
   color posColor = clrGray;
   if(positionDir == "LONG")  posColor = clrLimeGreen;
   if(positionDir == "SHORT") posColor = clrRed;
   if(positionDir != "NONE")
      DashboardSetText(g_dashNames[DASH_POS_V],
         StringFormat("%s %.2f %+.2f", positionDir, positionLots, positionPnL), posColor);
   else
      DashboardSetText(g_dashNames[DASH_POS_V], "NONE", clrGray);

   // --- Spread ---
   color spreadColor = spreadOk ? clrLimeGreen : clrRed;
   DashboardSetText(g_dashNames[DASH_SPR_V],
      StringFormat("%.0f pts %s", spread, spreadOk ? "OK" : "HIGH"), spreadColor);

   // --- Circuit breakers ---
   double profitPct = (dailyProfitUsed > 0) ? MathMin(dailyProfitUsed / 50.0 * 100.0, 100.0) : 0;
   double lossPct   = (dailyLossUsed > 0)   ? MathMin(dailyLossUsed / 25.0 * 100.0, 100.0)   : 0;
   color profitClr  = (profitPct > 80) ? clrGold : clrLimeGreen;
   color lossClr    = (lossPct > 80)   ? clrRed  : clrOrange;

   DashboardSetText(g_dashNames[DASH_CIRC_V1],
      StringFormat("Profit: $%.2f/50", dailyProfitUsed), profitClr);
   DashboardSetText(g_dashNames[DASH_CIRC_V2],
      StringFormat("Loss:  $%.2f/25", dailyLossUsed), lossClr);
}

//+------------------------------------------------------------------+
//| Quick status-only update (lightweight)                            |
//+------------------------------------------------------------------+
void DashboardSetStatus(string text)
{
   ObjectSetString(0, DASH_PREFIX "STATUS_V", OBJPROP_TEXT, text);
   ChartRedraw(0);
}

#endif
