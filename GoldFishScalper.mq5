//+------------------------------------------------------------------+
//|                                              GoldFishScalper.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

//====== GoldFish Scalper ======
input int      MAGIC_NUMBER = 100;                    // Magic Number
input ENUM_TIMEFRAMES TIMEFRAME = PERIOD_M2;          // Timeframe
input int      BARS = 0;                              // Bars (0 = current)
input double   LOT_SIZE = 0.01;                       // Lot Size
input double   TAKE_PROFIT_DOLLARS = 25.0;            // Take Profit ($)
input double   STOP_LOSS_DOLLARS = 5.0;               // Stop Loss ($)
input double   TRAILING_SL_DOLLARS = 5.0;             // Trailing SL ($)
input double   TRAILING_SL_TRIGGER_DOLLARS = 2.5;     // Trailing SL Trigger ($)

//====== VWAP Settings ======
input bool     Use_VWAP_Confirmation = true;          // Use VWAP Confirmation
input int      Bars_for_VWAP = 60;                    // Bars for VWAP (0 for current day)

//====== Position Mode ======
input bool     Allow_Hedging = true;                  // Allow Hedging (multiple positions)

//--- Global Variables
double   g_vwap_buffer[];
double   g_price_buffer[];
double   g_volume_buffer[];
datetime g_last_bar_time = 0;
double   g_account_balance = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== GoldFish Scalper EA Initialized ===");
   Print("Magic Number: ", MAGIC_NUMBER);
   Print("Timeframe: ", EnumToString(TIMEFRAME));
   Print("Lot Size: ", LOT_SIZE);
   Print("Take Profit: $", TAKE_PROFIT_DOLLARS);
   Print("Stop Loss: $", STOP_LOSS_DOLLARS);
   Print("VWAP Confirmation: ", Use_VWAP_Confirmation ? "Enabled" : "Disabled");
   Print("Hedging: ", Allow_Hedging ? "Enabled" : "Disabled");
   
   // Initialize arrays
   ArrayResize(g_vwap_buffer, Bars_for_VWAP + 1);
   ArrayResize(g_price_buffer, Bars_for_VWAP + 1);
   ArrayResize(g_volume_buffer, Bars_for_VWAP + 1);
   
   g_account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("GoldFish Scalper EA Deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   datetime current_bar_time = iTime(_Symbol, TIMEFRAME, 0);
   if(current_bar_time == g_last_bar_time)
      return;
   
   g_last_bar_time = current_bar_time;
   
   // Update VWAP
   CalculateVWAP();
   
   // Manage existing positions
   ManagePositions();
   
   // Look for trading signals
   CheckForSignals();
}

//+------------------------------------------------------------------+
//| Calculate VWAP (Volume Weighted Average Price)                   |
//+------------------------------------------------------------------+
void CalculateVWAP()
{
   int bars_to_use = (Bars_for_VWAP == 0) ? GetBarsFromMidnight() : Bars_for_VWAP;
   if(bars_to_use > ArraySize(g_vwap_buffer))
   {
      ArrayResize(g_vwap_buffer, bars_to_use);
      ArrayResize(g_price_buffer, bars_to_use);
      ArrayResize(g_volume_buffer, bars_to_use);
   }
   
   double total_volume = 0;
   double total_price_volume = 0;
   
   for(int i = 0; i < bars_to_use; i++)
   {
      double high = iHigh(_Symbol, TIMEFRAME, i);
      double low = iLow(_Symbol, TIMEFRAME, i);
      double close = iClose(_Symbol, TIMEFRAME, i);
      long volume = iVolume(_Symbol, TIMEFRAME, i);
      
      if(volume == 0) volume = 1; // Avoid division by zero
      
      double typical_price = (high + low + close) / 3.0;
      
      g_price_buffer[i] = typical_price;
      g_volume_buffer[i] = (double)volume;
      
      total_price_volume += typical_price * volume;
      total_volume += volume;
   }
   
   if(total_volume > 0)
   {
      double vwap = total_price_volume / total_volume;
      g_vwap_buffer[0] = vwap;
   }
}

//+------------------------------------------------------------------+
//| Get bars from midnight for daily VWAP                           |
//+------------------------------------------------------------------+
int GetBarsFromMidnight()
{
   datetime current_time = TimeCurrent();
   datetime midnight = current_time - (current_time % 86400); // Start of day
   
   int bars = 0;
   for(int i = 0; i < 1000; i++) // Limit search
   {
      datetime bar_time = iTime(_Symbol, TIMEFRAME, i);
      if(bar_time >= midnight)
         bars++;
      else
         break;
   }
   
   return MathMax(bars, 10); // Minimum 10 bars
}

//+------------------------------------------------------------------+
//| Check for trading signals                                        |
//+------------------------------------------------------------------+
void CheckForSignals()
{
   if(!Allow_Hedging && PositionsTotal() > 0)
      return; // Don't open new positions if hedging is disabled
   
   double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double vwap = g_vwap_buffer[0];
   
   if(!Use_VWAP_Confirmation)
   {
      // Simple scalping logic without VWAP
      ScalpingSignals();
      return;
   }
   
   // VWAP-based signals
   double price_distance = MathAbs(current_price - vwap);
   double atr = iATR(_Symbol, TIMEFRAME, 14, 1);
   
   // Buy signal: Price below VWAP and showing reversal
   if(current_price < vwap && price_distance > atr * 0.5)
   {
      if(IsReversal(true)) // Bullish reversal
      {
         OpenPosition(ORDER_TYPE_BUY, "VWAP Buy Signal");
      }
   }
   
   // Sell signal: Price above VWAP and showing reversal
   if(current_price > vwap && price_distance > atr * 0.5)
   {
      if(IsReversal(false)) // Bearish reversal
      {
         OpenPosition(ORDER_TYPE_SELL, "VWAP Sell Signal");
      }
   }
}

//+------------------------------------------------------------------+
//| Simple scalping signals without VWAP                            |
//+------------------------------------------------------------------+
void ScalpingSignals()
{
   // Simple momentum-based scalping
   double ma_fast = iMA(_Symbol, TIMEFRAME, 5, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ma_slow = iMA(_Symbol, TIMEFRAME, 20, 0, MODE_EMA, PRICE_CLOSE, 1);
   double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Buy signal
   if(current_price > ma_fast && ma_fast > ma_slow)
   {
      if(IsReversal(true))
      {
         OpenPosition(ORDER_TYPE_BUY, "Scalping Buy Signal");
      }
   }
   
   // Sell signal
   if(current_price < ma_fast && ma_fast < ma_slow)
   {
      if(IsReversal(false))
      {
         OpenPosition(ORDER_TYPE_SELL, "Scalping Sell Signal");
      }
   }
}

//+------------------------------------------------------------------+
//| Check for reversal patterns                                      |
//+------------------------------------------------------------------+
bool IsReversal(bool bullish)
{
   double close1 = iClose(_Symbol, TIMEFRAME, 1);
   double close2 = iClose(_Symbol, TIMEFRAME, 2);
   double close3 = iClose(_Symbol, TIMEFRAME, 3);
   
   if(bullish)
   {
      // Simple bullish reversal: three ascending closes
      return (close1 > close2 && close2 > close3);
   }
   else
   {
      // Simple bearish reversal: three descending closes
      return (close1 < close2 && close2 < close3);
   }
}

//+------------------------------------------------------------------+
//| Open position with money management                              |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE order_type, string comment)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   double price = (order_type == ORDER_TYPE_BUY) ? 
                  SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                  SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Calculate SL and TP in points based on dollar amounts
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lot_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   
   // Calculate points for dollar amounts
   double sl_points = (STOP_LOSS_DOLLARS / (tick_value * LOT_SIZE)) * point;
   double tp_points = (TAKE_PROFIT_DOLLARS / (tick_value * LOT_SIZE)) * point;
   
   double sl_price = 0;
   double tp_price = 0;
   
   if(order_type == ORDER_TYPE_BUY)
   {
      sl_price = price - sl_points;
      tp_price = price + tp_points;
   }
   else
   {
      sl_price = price + sl_points;
      tp_price = price - tp_points;
   }
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = LOT_SIZE;
   request.type = order_type;
   request.price = price;
   request.sl = sl_price;
   request.tp = tp_price;
   request.magic = MAGIC_NUMBER;
   request.comment = comment;
   request.type_filling = ORDER_FILLING_IOC;
   
   if(!OrderSend(request, result))
   {
      Print("Failed to open position. Error: ", GetLastError());
      Print("Result code: ", result.retcode);
   }
   else
   {
      Print("Position opened successfully:");
      Print("Type: ", (order_type == ORDER_TYPE_BUY) ? "BUY" : "SELL");
      Print("Price: ", price);
      Print("SL: ", sl_price);
      Print("TP: ", tp_price);
      Print("Ticket: ", result.order);
   }
}

//+------------------------------------------------------------------+
//| Manage existing positions (trailing stop)                       |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER)
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double current_sl = PositionGetDouble(POSITION_SL);
         ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         // Calculate current profit in dollars
         double current_profit = CalculatePositionProfitDollars(ticket);
         
         // Apply trailing stop if profit exceeds trigger
         if(current_profit >= TRAILING_SL_TRIGGER_DOLLARS)
         {
            ApplyTrailingStop(ticket, pos_type, current_sl);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate position profit in dollars                             |
//+------------------------------------------------------------------+
double CalculatePositionProfitDollars(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return 0;
   
   return PositionGetDouble(POSITION_PROFIT);
}

//+------------------------------------------------------------------+
//| Apply trailing stop                                              |
//+------------------------------------------------------------------+
void ApplyTrailingStop(ulong ticket, ENUM_POSITION_TYPE pos_type, double current_sl)
{
   double current_price = (pos_type == POSITION_TYPE_BUY) ? 
                         SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Calculate trailing distance in price
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double trailing_distance = (TRAILING_SL_DOLLARS / (tick_value * LOT_SIZE)) * point;
   
   double new_sl = 0;
   bool modify = false;
   
   if(pos_type == POSITION_TYPE_BUY)
   {
      new_sl = current_price - trailing_distance;
      if(new_sl > current_sl + point) // Only move SL up
         modify = true;
   }
   else
   {
      new_sl = current_price + trailing_distance;
      if(new_sl < current_sl - point) // Only move SL down
         modify = true;
   }
   
   if(modify)
   {
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_SLTP;
      request.position = ticket;
      request.sl = new_sl;
      request.tp = PositionGetDouble(POSITION_TP);
      
      if(OrderSend(request, result))
      {
         Print("Trailing stop updated for ticket ", ticket, " New SL: ", new_sl);
      }
   }
}

//+------------------------------------------------------------------+
//| Get current account profit                                        |
//+------------------------------------------------------------------+
double GetAccountProfit()
{
   double total_profit = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER)
      {
         total_profit += PositionGetDouble(POSITION_PROFIT);
      }
   }
   return total_profit;
}

//+------------------------------------------------------------------+
//| Emergency close all positions                                    |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER)
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         ClosePosition(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| Close specific position                                          |
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return false;
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = PositionGetString(POSITION_SYMBOL);
   request.volume = PositionGetDouble(POSITION_VOLUME);
   request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price = (request.type == ORDER_TYPE_SELL) ? 
                   SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                   SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.magic = MAGIC_NUMBER;
   request.comment = "Close Position";
   request.type_filling = ORDER_FILLING_IOC;
   
   if(OrderSend(request, result))
   {
      Print("Position closed: ", ticket);
      return true;
   }
   else
   {
      Print("Failed to close position ", ticket, ". Error: ", GetLastError());
      return false;
   }
}