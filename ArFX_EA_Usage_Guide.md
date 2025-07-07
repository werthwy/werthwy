# ArFX Breakout EA - Usage Guide

## Overview
The ArFX Breakout EA is a simple yet effective breakout strategy that waits for price to break above recent highs or below recent lows. It automatically places pending orders and manages risk.

## How It Works
1. **Identifies Support/Resistance**: Looks at the last N bars to find the highest high and lowest low
2. **Places Pending Orders**: Sets buy stop above the high and sell stop below the low
3. **VWAP Confirmation**: Optionally uses VWAP to filter trades (buy only above VWAP, sell only below VWAP)
4. **Auto Reset**: If no breakout occurs within 24 hours (configurable), it resets and finds new levels
5. **Risk Management**: Includes stop loss, take profit, trailing stops, and drawdown protection

## Key Settings to Focus On

### Essential Settings
- **BarsInput (20)**: Number of bars to look back for high/low calculation
  - Increase for wider breakout zones
  - Decrease for tighter, more sensitive breakouts
  
- **UseVWAPConfirmation (true/false)**: Enable VWAP filter
- **BarsForVWAP (6)**: Number of bars for VWAP calculation when enabled

### Risk Management
- **LotSize (0.01)**: Position size
- **StopLoss (9.0)**: Stop loss in pips
- **TakeProfit (11.0)**: Take profit in pips
- **TrailingSL (4.5)**: Trailing stop distance in pips
- **MaxDrawdownPercent (90%)**: Emergency stop if drawdown exceeds this

### Advanced Settings
- **ResetPendingHours (24)**: Hours to wait before resetting if no breakout
- **AllowHedging (true)**: Allow multiple positions in same direction

## Strategy Optimization

### For Strategy Tester
1. **Primary Parameter**: Focus on optimizing `BarsInput` (try range 10-50)
2. **Secondary Parameter**: If using VWAP, optimize `BarsForVWAP` (try range 3-20)
3. **Risk Parameters**: Adjust SL/TP ratio based on your risk tolerance

### Recommended Timeframes
- **M5**: Good for active trading, more signals
- **M15**: Balanced approach, medium frequency
- **H1**: Longer-term breakouts, fewer but stronger signals

## Installation
1. Copy `ArFX_Breakout_EA.mq5` to your MetaTrader 5 `Experts` folder
2. Compile in MetaEditor (F7)
3. Attach to chart and configure settings
4. Enable "Allow live trading" and "Allow DLL imports" if needed

## Tips for Success
1. **Backtest First**: Always test on historical data before live trading
2. **Start Small**: Use minimum lot sizes when going live
3. **Monitor Spreads**: Strategy works best on low-spread symbols
4. **Avoid News**: Consider disabling during high-impact news events
5. **Optimize Regularly**: Market conditions change, re-optimize periodically

## Common Parameter Combinations

### Conservative Setup
- BarsInput: 30
- StopLoss: 15
- TakeProfit: 10
- UseVWAPConfirmation: true

### Aggressive Setup  
- BarsInput: 15
- StopLoss: 8
- TakeProfit: 12
- UseVWAPConfirmation: false

### Balanced Setup (Default)
- BarsInput: 20
- StopLoss: 9
- TakeProfit: 11
- UseVWAPConfirmation: true

## Troubleshooting
- **No Orders Placed**: Check minimum distance requirements for your broker
- **Orders Not Triggering**: Increase BarsInput for wider breakout zones
- **Too Many Losses**: Consider enabling VWAP confirmation or increasing StopLoss
- **Missing Opportunities**: Decrease BarsInput or disable VWAP confirmation

Remember: No strategy works 100% of the time. Always use proper risk management and never risk more than you can afford to lose.