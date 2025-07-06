//+------------------------------------------------------------------+
//|                                                   TradingBot.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

//--- Input parameters
input string   InpSymbol = "XAUUSD";           // Trading Symbol
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M30; // Main Timeframe
input ENUM_TIMEFRAMES InpSignalTimeframe = PERIOD_M1; // Signal Timeframe
input double   InpVolume = 0.01;               // Trading Volume
input int      InpRollPeriod = 100;            // Data Period
input int      InpSLPoints = 1000;             // Stop Loss in Points
input int      InpTPPoints = 2000;             // Take Profit in Points
input int      InpMagicNumber = 100;           // Magic Number
input int      InpSleepSeconds = 60;           // Sleep Between Cycles

//--- Global variables
struct CandleData
{
   datetime time;
   double open;
   double high;
   double low;
   double close;
   string candle_type;
   string trend;
   string highlow;
   string BOS;
   string OB;
   string consolidation;
   string validity;
   int signal;
};

CandleData g_data[];
string g_lastDirection = "flat";
datetime g_lastProcessTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Trading Bot EA Initialized");
   Print("Symbol: ", InpSymbol);
   Print("Timeframe: ", EnumToString(InpTimeframe));
   Print("Volume: ", InpVolume);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Trading Bot EA Deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Process only on new bar
   datetime currentTime = iTime(InpSymbol, InpTimeframe, 0);
   if(currentTime <= g_lastProcessTime)
      return;
      
   g_lastProcessTime = currentTime;
   
   // Get market data and perform analysis
   if(!GetMarketData())
   {
      Print("Failed to get market data");
      return;
   }
   
   // Perform technical analysis
   PerformTechnicalAnalysis();
   
   // Generate signals and execute trades
   string direction = GenerateSignal();
   ExecuteTrade(direction);
   
   // Log information
   LogInformation(direction);
}

//+------------------------------------------------------------------+
//| Get market data function                                         |
//+------------------------------------------------------------------+
bool GetMarketData()
{
   ArrayResize(g_data, InpRollPeriod);
   ArrayInitialize(g_data, {0});
   
   MqlRates rates[];
   if(CopyRates(InpSymbol, InpTimeframe, 0, InpRollPeriod, rates) != InpRollPeriod)
   {
      Print("Failed to copy rates");
      return false;
   }
   
   for(int i = 0; i < InpRollPeriod; i++)
   {
      g_data[i].time = rates[i].time;
      g_data[i].open = rates[i].open;
      g_data[i].high = rates[i].high;
      g_data[i].low = rates[i].low;
      g_data[i].close = rates[i].close;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Specify candle type function                                     |
//+------------------------------------------------------------------+
string SpecifyCandleType(double open_price, double close_price)
{
   if(open_price < close_price)
      return "bullish";
   else if(open_price > close_price)
      return "bearish";
   else
      return "doji";
}

//+------------------------------------------------------------------+
//| Trend detection function                                         |
//+------------------------------------------------------------------+
void TrendDetection()
{
   for(int i = 15; i < ArraySize(g_data); i++)
   {
      int bearish_count = 0;
      int bullish_count = 0;
      double bearish_sum = 0;
      double bullish_sum = 0;
      
      for(int j = 0; j <= 15; j++)
      {
         int idx = i - j;
         if(idx < 0) break;
         
         if(g_data[idx].candle_type == "bearish")
         {
            bearish_count++;
            bearish_sum += MathAbs(g_data[idx].open - g_data[idx].close);
         }
         else if(g_data[idx].candle_type == "bullish")
         {
            bullish_count++;
            bullish_sum += MathAbs(g_data[idx].close - g_data[idx].open);
         }
      }
      
      if(bullish_count < bearish_count && bullish_sum < bearish_sum)
         g_data[i].trend = "downtrend";
      else if(bullish_count > bearish_count && bullish_sum > bearish_sum)
         g_data[i].trend = "uptrend";
      else
         g_data[i].trend = "ranging";
   }
}

//+------------------------------------------------------------------+
//| Pinbar detection function                                        |
//+------------------------------------------------------------------+
string DetectPinbar(int index)
{
   if(index < 1 || index >= ArraySize(g_data) - 1)
      return "none";
      
   double body_size = MathAbs(g_data[index].close - g_data[index].open);
   double upper_wick = 0;
   double lower_wick = 0;
   
   if(g_data[index].candle_type == "bullish")
   {
      upper_wick = g_data[index].high - g_data[index].close;
      lower_wick = g_data[index].open - g_data[index].low;
   }
   else if(g_data[index].candle_type == "bearish")
   {
      upper_wick = g_data[index].high - g_data[index].open;
      lower_wick = g_data[index].close - g_data[index].low;
   }
   
   // Bullish pinbar detection
   if(g_data[index].low < g_data[index-1].low && 
      g_data[index].low < g_data[index+1].low && 
      lower_wick > body_size * 2)
      return "bullish_pinbar";
      
   // Bearish pinbar detection
   if(g_data[index].high > g_data[index-1].high && 
      g_data[index].high > g_data[index+1].high && 
      upper_wick > body_size * 2)
      return "bearish_pinbar";
      
   return "none";
}

//+------------------------------------------------------------------+
//| Higher highs, lower lows analysis                               |
//+------------------------------------------------------------------+
void AnalyzeHighLow()
{
   for(int i = 2; i < ArraySize(g_data); i++)
   {
      if(g_data[i].trend == "downtrend")
      {
         if(g_data[i-2].candle_type == "bearish" && 
            g_data[i-1].candle_type == "bearish" && 
            g_data[i].candle_type == "bearish")
         {
            g_data[i].highlow = "motion";
         }
         else if(g_data[i-2].low > g_data[i-1].low && g_data[i].low > g_data[i-1].low)
         {
            g_data[i].highlow = "lowerlow";
         }
         else if(g_data[i-2].high < g_data[i-1].high && g_data[i].high < g_data[i-1].high)
         {
            g_data[i].highlow = "lowerhigh";
         }
         else
         {
            g_data[i].highlow = "motion";
         }
      }
      else if(g_data[i].trend == "uptrend")
      {
         if(g_data[i-2].candle_type == "bullish" && 
            g_data[i-1].candle_type == "bullish" && 
            g_data[i].candle_type == "bullish")
         {
            g_data[i].highlow = "motion";
         }
         else if(g_data[i-2].high < g_data[i-1].high && g_data[i].high < g_data[i-1].high)
         {
            g_data[i].highlow = "higherhigh";
         }
         else if(g_data[i-2].low > g_data[i-1].low && g_data[i].low > g_data[i-1].low)
         {
            g_data[i].highlow = "higherlow";
         }
         else
         {
            g_data[i].highlow = "motion";
         }
      }
      else
      {
         g_data[i].highlow = "motion";
      }
   }
}

//+------------------------------------------------------------------+
//| Break of structure analysis                                      |
//+------------------------------------------------------------------+
void AnalyzeBreakOfStructure()
{
   for(int i = 0; i < ArraySize(g_data); i++)
   {
      if(g_data[i].highlow == "higherhigh")
      {
         // Look for previous higher high
         bool found_break = false;
         for(int j = i - 1; j >= 0; j--)
         {
            if(g_data[j].highlow == "higherhigh")
            {
               if(g_data[i].high > g_data[j].high)
               {
                  found_break = true;
                  break;
               }
            }
         }
         if(found_break)
            g_data[i].BOS = "UPBOS";
         else
            g_data[i].BOS = "motion";
      }
      else if(g_data[i].highlow == "lowerlow")
      {
         // Look for previous lower low
         bool found_break = false;
         for(int j = i - 1; j >= 0; j--)
         {
            if(g_data[j].highlow == "lowerlow")
            {
               if(g_data[i].low < g_data[j].low)
               {
                  found_break = true;
                  break;
               }
            }
         }
         if(found_break)
            g_data[i].BOS = "DOWNBOS";
         else
            g_data[i].BOS = "motion";
      }
      else
      {
         g_data[i].BOS = "motion";
      }
   }
}

//+------------------------------------------------------------------+
//| Order block analysis                                             |
//+------------------------------------------------------------------+
void AnalyzeOrderBlocks()
{
   for(int i = 0; i < ArraySize(g_data); i++)
   {
      if(g_data[i].highlow == "higherlow")
      {
         g_data[i].OB = "HL";
      }
      else if(g_data[i].highlow == "lowerhigh")
      {
         g_data[i].OB = "LH";
      }
      else
      {
         g_data[i].OB = "motion";
      }
   }
}

//+------------------------------------------------------------------+
//| Consolidation analysis                                           |
//+------------------------------------------------------------------+
void AnalyzeConsolidation()
{
   for(int i = 20; i < ArraySize(g_data); i++)
   {
      int ranging_count = 0;
      for(int j = 0; j <= 20; j++)
      {
         int idx = i - j;
         if(idx >= 0 && g_data[idx].trend == "ranging")
            ranging_count++;
      }
      
      if(ranging_count >= 5)
         g_data[i].consolidation = "invalid";
      else
         g_data[i].consolidation = "valid";
   }
}

//+------------------------------------------------------------------+
//| Validity analysis                                                |
//+------------------------------------------------------------------+
void AnalyzeValidity()
{
   for(int i = 0; i < ArraySize(g_data); i++)
   {
      if(g_data[i].consolidation == "valid" && g_data[i].OB == "HL")
         g_data[i].validity = "sell";
      else if(g_data[i].consolidation == "valid" && g_data[i].OB == "LH")
         g_data[i].validity = "buy";
      else
         g_data[i].validity = "motion";
   }
}

//+------------------------------------------------------------------+
//| Perform complete technical analysis                              |
//+------------------------------------------------------------------+
void PerformTechnicalAnalysis()
{
   // Step 1: Classify candle types
   for(int i = 0; i < ArraySize(g_data); i++)
   {
      g_data[i].candle_type = SpecifyCandleType(g_data[i].open, g_data[i].close);
   }
   
   // Step 2: Detect trends
   TrendDetection();
   
   // Step 3: Analyze higher highs/lower lows
   AnalyzeHighLow();
   
   // Step 4: Analyze break of structure
   AnalyzeBreakOfStructure();
   
   // Step 5: Analyze order blocks
   AnalyzeOrderBlocks();
   
   // Step 6: Analyze consolidation
   AnalyzeConsolidation();
   
   // Step 7: Analyze validity
   AnalyzeValidity();
}

//+------------------------------------------------------------------+
//| Generate trading signal                                          |
//+------------------------------------------------------------------+
string GenerateSignal()
{
   if(ArraySize(g_data) == 0)
      return "pass";
      
   int lastIndex = ArraySize(g_data) - 1;
   string lastValidity = g_data[lastIndex].validity;
   
   // Check for pinbar signals
   string pinbar = DetectPinbar(lastIndex);
   
   if(lastValidity == "buy" || pinbar == "bullish_pinbar")
      return "buy";
   else if(lastValidity == "sell" || pinbar == "bearish_pinbar")
      return "sell";
   else
      return "pass";
}

//+------------------------------------------------------------------+
//| Execute trade based on signal                                    |
//+------------------------------------------------------------------+
void ExecuteTrade(string direction)
{
   if(direction == "pass")
      return;
      
   // Check if we already have a position
   if(PositionSelect(InpSymbol))
   {
      Print("Position already exists for ", InpSymbol);
      return;
   }
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   double price = 0;
   double sl = 0;
   double tp = 0;
   double point = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
   
   if(direction == "buy")
   {
      price = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
      sl = price - InpSLPoints * point;
      tp = price + InpTPPoints * point;
      
      request.action = TRADE_ACTION_DEAL;
      request.symbol = InpSymbol;
      request.volume = InpVolume;
      request.type = ORDER_TYPE_BUY;
      request.price = price;
      request.sl = sl;
      request.tp = tp;
      request.magic = InpMagicNumber;
      request.comment = "TradingBot Buy";
      request.type_filling = ORDER_FILLING_IOC;
   }
   else if(direction == "sell")
   {
      price = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
      sl = price + InpSLPoints * point;
      tp = price - InpTPPoints * point;
      
      request.action = TRADE_ACTION_DEAL;
      request.symbol = InpSymbol;
      request.volume = InpVolume;
      request.type = ORDER_TYPE_SELL;
      request.price = price;
      request.sl = sl;
      request.tp = tp;
      request.magic = InpMagicNumber;
      request.comment = "TradingBot Sell";
      request.type_filling = ORDER_FILLING_IOC;
   }
   
   if(!OrderSend(request, result))
   {
      Print("OrderSend failed with error: ", GetLastError());
      Print("Result retcode: ", result.retcode);
   }
   else
   {
      Print("Order executed successfully:");
      Print("- Direction: ", direction);
      Print("- Price: ", price);
      Print("- SL: ", sl);
      Print("- TP: ", tp);
      Print("- Ticket: ", result.order);
   }
   
   g_lastDirection = direction;
}

//+------------------------------------------------------------------+
//| Get current exposure                                             |
//+------------------------------------------------------------------+
double GetExposure()
{
   double totalVolume = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == InpSymbol)
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            totalVolume += PositionGetDouble(POSITION_VOLUME);
         }
      }
   }
   return totalVolume;
}

//+------------------------------------------------------------------+
//| Log information                                                  |
//+------------------------------------------------------------------+
void LogInformation(string direction)
{
   double exposure = GetExposure();
   
   Print("=== Trading Bot Status ===");
   Print("Time: ", TimeToString(TimeCurrent()));
   Print("Symbol: ", InpSymbol);
   Print("Exposure: ", DoubleToString(exposure, 2));
   Print("Signal: ", direction);
   Print("Last Direction: ", g_lastDirection);
   Print("========================");
}

//+------------------------------------------------------------------+
//| Close order by ticket                                           |
//+------------------------------------------------------------------+
bool CloseOrder(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return false;
      
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = PositionGetString(POSITION_SYMBOL);
   request.volume = PositionGetDouble(POSITION_VOLUME);
   request.type = (ENUM_ORDER_TYPE)(1 - PositionGetInteger(POSITION_TYPE));
   request.magic = InpMagicNumber;
   request.comment = "TradingBot Close";
   
   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      request.price = SymbolInfoDouble(request.symbol, SYMBOL_BID);
   else
      request.price = SymbolInfoDouble(request.symbol, SYMBOL_ASK);
      
   request.type_filling = ORDER_FILLING_IOC;
   
   if(!OrderSend(request, result))
   {
      Print("Failed to close order ", ticket, ". Error: ", GetLastError());
      return false;
   }
   
   Print("Order ", ticket, " closed successfully");
   return true;
}

//+------------------------------------------------------------------+
//| Close all positions for symbol                                   |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == InpSymbol)
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            CloseOrder(PositionGetInteger(POSITION_TICKET));
         }
      }
   }
}