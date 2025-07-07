//+------------------------------------------------------------------+
//|                                              ArFX_Breakout_EA.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "ArFX Breakout EA - Waits for breakout from recent highs/lows"

//--- Input parameters
input group "=== Strategy Settings ==="
input int MagicNumber = 100;                    // Magic Number
input ENUM_TIMEFRAMES Timeframe = PERIOD_M5;    // Timeframe
input double LotSize = 0.01;                    // Lot Size
input double TakeProfit = 11.0;                 // Take Profit (pips)
input double StopLoss = 9.0;                    // Stop Loss (pips)
input double TrailingSL = 4.5;                  // Trailing SL (pips)
input double TrailingSLTrigger = 1.0;           // Trailing SL Trigger (pips)
input double MaxDrawdownPercent = 90.0;         // Max Drawdown (Equity %)

input group "=== Breakout Settings ==="
input int BarsInput = 20;                       // Bars for High/Low calculation
input bool UseVWAPConfirmation = true;          // Use VWAP Confirmation
input int BarsForVWAP = 6;                      // Bars for VWAP (if used)
input int ResetPendingHours = 24;               // Reset pending orders after hours

input group "=== Position Management ==="
input bool AllowHedging = true;                 // Allow Hedging (multiple positions)

//--- Global variables
CTrade trade;
datetime lastResetTime = 0;
bool pendingOrdersPlaced = false;
int buyStopTicket = 0;
int sellStopTicket = 0;
double currentHigh = 0;
double currentLow = 0;
double vwapValue = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetMarginMode();
    trade.SetTypeFillingBySymbol(Symbol());
    
    Print("ArFX Breakout EA initialized successfully");
    Print("Strategy: Looking for breakouts from ", BarsInput, " bars high/low");
    if(UseVWAPConfirmation)
        Print("VWAP Confirmation enabled with ", BarsForVWAP, " bars");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Close any remaining pending orders
    CleanupPendingOrders();
    Print("ArFX Breakout EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check drawdown limit
    if(!CheckDrawdownLimit())
        return;
    
    // Reset pending orders after specified hours
    if(ShouldResetPendingOrders())
    {
        ResetStrategy();
    }
    
    // Place new pending orders if none exist
    if(!pendingOrdersPlaced || (!OrderExists(buyStopTicket) && !OrderExists(sellStopTicket)))
    {
        PlaceBreakoutOrders();
    }
    
    // Trail existing positions
    TrailOpenPositions();
}

//+------------------------------------------------------------------+
//| Check if drawdown limit is exceeded                             |
//+------------------------------------------------------------------+
bool CheckDrawdownLimit()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    if(balance > 0)
    {
        double drawdownPercent = (1.0 - equity / balance) * 100.0;
        if(drawdownPercent >= MaxDrawdownPercent)
        {
            Print("Maximum drawdown reached: ", drawdownPercent, "%");
            CloseAllPositions();
            CleanupPendingOrders();
            return false;
        }
    }
    return true;
}

//+------------------------------------------------------------------+
//| Check if pending orders should be reset                         |
//+------------------------------------------------------------------+
bool ShouldResetPendingOrders()
{
    if(lastResetTime == 0)
        return false;
        
    datetime currentTime = TimeCurrent();
    int hoursPassed = (int)((currentTime - lastResetTime) / 3600);
    
    return (hoursPassed >= ResetPendingHours);
}

//+------------------------------------------------------------------+
//| Reset strategy - remove pending orders and prepare for new setup|
//+------------------------------------------------------------------+
void ResetStrategy()
{
    Print("Resetting strategy after ", ResetPendingHours, " hours");
    CleanupPendingOrders();
    pendingOrdersPlaced = false;
    buyStopTicket = 0;
    sellStopTicket = 0;
    lastResetTime = 0;
}

//+------------------------------------------------------------------+
//| Place breakout pending orders                                   |
//+------------------------------------------------------------------+
void PlaceBreakoutOrders()
{
    // Calculate recent high and low
    if(!CalculateHighLow())
        return;
    
    // Calculate VWAP if enabled
    if(UseVWAPConfirmation)
    {
        if(!CalculateVWAP())
            return;
    }
    
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    
    // Calculate order prices with small buffer
    double buyPrice = currentHigh + 2 * point;
    double sellPrice = currentLow - 2 * point;
    
    // Ensure minimum distance from current price
    double minDistance = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * point;
    if(buyPrice - ask < minDistance)
        buyPrice = ask + minDistance;
    if(bid - sellPrice < minDistance)
        sellPrice = bid - minDistance;
    
    // Calculate SL and TP
    double buySL = buyPrice - StopLoss * PipValue();
    double buyTP = buyPrice + TakeProfit * PipValue();
    double sellSL = sellPrice + StopLoss * PipValue();
    double sellTP = sellPrice - TakeProfit * PipValue();
    
    // VWAP confirmation logic
    bool allowBuy = true;
    bool allowSell = true;
    
    if(UseVWAPConfirmation && vwapValue > 0)
    {
        allowBuy = (ask > vwapValue);  // Only buy if price above VWAP
        allowSell = (bid < vwapValue); // Only sell if price below VWAP
    }
    
    // Place buy stop order
    if(allowBuy && (AllowHedging || !HasBuyPositions()))
    {
        if(trade.BuyStop(LotSize, buyPrice, Symbol(), buySL, buyTP))
        {
            buyStopTicket = trade.ResultOrder();
            Print("Buy Stop placed at ", buyPrice, " SL: ", buySL, " TP: ", buyTP);
        }
    }
    
    // Place sell stop order
    if(allowSell && (AllowHedging || !HasSellPositions()))
    {
        if(trade.SellStop(LotSize, sellPrice, Symbol(), sellSL, sellTP))
        {
            sellStopTicket = trade.ResultOrder();
            Print("Sell Stop placed at ", sellPrice, " SL: ", sellSL, " TP: ", sellTP);
        }
    }
    
    if(buyStopTicket > 0 || sellStopTicket > 0)
    {
        pendingOrdersPlaced = true;
        lastResetTime = TimeCurrent();
        Print("Breakout orders placed. High: ", currentHigh, " Low: ", currentLow);
        if(UseVWAPConfirmation)
            Print("VWAP Value: ", vwapValue);
    }
}

//+------------------------------------------------------------------+
//| Calculate recent high and low                                   |
//+------------------------------------------------------------------+
bool CalculateHighLow()
{
    double highs[], lows[];
    
    if(CopyHigh(Symbol(), Timeframe, 1, BarsInput, highs) != BarsInput ||
       CopyLow(Symbol(), Timeframe, 1, BarsInput, lows) != BarsInput)
    {
        Print("Error copying price data");
        return false;
    }
    
    currentHigh = highs[ArrayMaximum(highs)];
    currentLow = lows[ArrayMinimum(lows)];
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate VWAP                                                   |
//+------------------------------------------------------------------+
bool CalculateVWAP()
{
    double highs[], lows[], closes[], volumes[];
    
    if(CopyHigh(Symbol(), Timeframe, 0, BarsForVWAP, highs) != BarsForVWAP ||
       CopyLow(Symbol(), Timeframe, 0, BarsForVWAP, lows) != BarsForVWAP ||
       CopyClose(Symbol(), Timeframe, 0, BarsForVWAP, closes) != BarsForVWAP ||
       CopyTickVolume(Symbol(), Timeframe, 0, BarsForVWAP, volumes) != BarsForVWAP)
    {
        Print("Error copying VWAP data");
        return false;
    }
    
    double totalPriceVolume = 0;
    double totalVolume = 0;
    
    for(int i = 0; i < BarsForVWAP; i++)
    {
        double typicalPrice = (highs[i] + lows[i] + closes[i]) / 3.0;
        totalPriceVolume += typicalPrice * volumes[i];
        totalVolume += volumes[i];
    }
    
    if(totalVolume > 0)
    {
        vwapValue = totalPriceVolume / totalVolume;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Get pip value                                                    |
//+------------------------------------------------------------------+
double PipValue()
{
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    
    if(digits == 5 || digits == 3)
        return point * 10;
    else
        return point * 100;
}

//+------------------------------------------------------------------+
//| Check if order exists                                            |
//+------------------------------------------------------------------+
bool OrderExists(int ticket)
{
    if(ticket <= 0)
        return false;
        
    return OrderSelect(ticket);
}

//+------------------------------------------------------------------+
//| Check if has buy positions                                       |
//+------------------------------------------------------------------+
bool HasBuyPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionSelectByIndex(i))
        {
            if(PositionGetString(POSITION_SYMBOL) == Symbol() &&
               PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
               PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check if has sell positions                                      |
//+------------------------------------------------------------------+
bool HasSellPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionSelectByIndex(i))
        {
            if(PositionGetString(POSITION_SYMBOL) == Symbol() &&
               PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
               PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Trail open positions                                             |
//+------------------------------------------------------------------+
void TrailOpenPositions()
{
    double pipValue = PipValue();
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!PositionSelectByIndex(i))
            continue;
            
        if(PositionGetString(POSITION_SYMBOL) != Symbol() ||
           PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            continue;
        
        ulong ticket = PositionGetInteger(POSITION_TICKET);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        int posType = (int)PositionGetInteger(POSITION_TYPE);
        
        double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
        
        if(posType == POSITION_TYPE_BUY)
        {
            double currentProfit = bid - openPrice;
            if(currentProfit >= TrailingSLTrigger * pipValue)
            {
                double newSL = bid - TrailingSL * pipValue;
                if(newSL > currentSL + pipValue) // Only move SL in favorable direction
                {
                    trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
                }
            }
        }
        else if(posType == POSITION_TYPE_SELL)
        {
            double currentProfit = openPrice - ask;
            if(currentProfit >= TrailingSLTrigger * pipValue)
            {
                double newSL = ask + TrailingSL * pipValue;
                if(newSL < currentSL - pipValue || currentSL == 0) // Only move SL in favorable direction
                {
                    trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionSelectByIndex(i))
        {
            if(PositionGetString(POSITION_SYMBOL) == Symbol() &&
               PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
                ulong ticket = PositionGetInteger(POSITION_TICKET);
                trade.PositionClose(ticket);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Cleanup pending orders                                           |
//+------------------------------------------------------------------+
void CleanupPendingOrders()
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(OrderGetTicket(i)))
        {
            if(OrderGetString(ORDER_SYMBOL) == Symbol() &&
               OrderGetInteger(ORDER_MAGIC) == MagicNumber)
            {
                trade.OrderDelete(OrderGetTicket(i));
            }
        }
    }
    
    buyStopTicket = 0;
    sellStopTicket = 0;
    pendingOrdersPlaced = false;
}

//+------------------------------------------------------------------+
</rewritten_file>