//+------------------------------------------------------------------+
//|                Volume Supported Linear Regression Trend          |
//|                         TradingView Exact Conversion             |
//|                              VSLRT.mq5                          |
//+------------------------------------------------------------------+
#property strict
#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots   2

//==================================================================
// SHORT TERM HISTOGRAM
//==================================================================
#property indicator_label1  "Short Trend"
#property indicator_type1   DRAW_COLOR_HISTOGRAM
#property indicator_color1  clrLime,clrGreen,clrPaleGreen,clrRed,clrFireBrick,clrLightCoral
#property indicator_width1  3

//==================================================================
// LONG TERM LINE
//==================================================================
#property indicator_label2  "Long Trend"
#property indicator_type2   DRAW_COLOR_LINE
#property indicator_color2  clrDodgerBlue,clrSteelBlue,clrMidnightBlue,clrOrange,clrDarkOrange,clrSaddleBrown
#property indicator_width2  3

//==================================================================
// INPUTS
//==================================================================
input ENUM_APPLIED_PRICE InpSource = PRICE_CLOSE;
input int InpShortLength = 20;
input int InpLongLength  = 50;

//==================================================================
// BUFFERS
//==================================================================
double HistBuffer[];
double HistColor[];

double LineBuffer[];
double LineColor[];

//==================================================================
// INTERNAL ARRAYS
//==================================================================
double Src[];
double BuyVol[];
double SellVol[];

//+------------------------------------------------------------------+
//| EXACT TradingView Pine linreg()                                 |
//+------------------------------------------------------------------+
double PineLinReg(const double &src[],
                  int shift,
                  int len)
{
   if(shift + len > ArraySize(src))
      return 0.0;

   double sumX  = 0.0;
   double sumY  = 0.0;
   double sumXY = 0.0;
   double sumXX = 0.0;

   for(int i=0; i<len; i++)
   {
      double x = i;

      //===========================================================
      // IMPORTANT FIX:
      // Reverse indexing to match PineScript exactly
      //===========================================================
      double y = src[shift + (len - 1 - i)];

      sumX  += x;
      sumY  += y;
      sumXY += x * y;
      sumXX += x * x;
   }

   double denom =
      len * sumXX - sumX * sumX;

   if(denom == 0.0)
      return 0.0;

   double slope =
      (len * sumXY - sumX * sumY) / denom;

   double intercept =
      (sumY - slope * sumX) / len;

   return intercept + slope * (len - 1);
}

//+------------------------------------------------------------------+
//| Candle Weight Function                                           |
//+------------------------------------------------------------------+
double Rate(bool cond,
            double open,
            double close,
            double high,
            double low)
{
   double tw   = high - MathMax(open, close);
   double bw   = MathMin(open, close) - low;
   double body = MathAbs(close - open);

   double denom = tw + bw + body;

   if(denom <= 0.0)
      return 0.5;

   double ret =
      0.5 * (tw + bw + (cond ? 2.0 * body : 0.0))
      / denom;

   if(!MathIsValidNumber(ret))
      ret = 0.5;

   return ret;
}

//+------------------------------------------------------------------+
//| Get Applied Price                                                |
//+------------------------------------------------------------------+
double GetPrice(ENUM_APPLIED_PRICE type,
                double open,
                double high,
                double low,
                double close)
{
   switch(type)
   {
      case PRICE_OPEN:
         return open;

      case PRICE_HIGH:
         return high;

      case PRICE_LOW:
         return low;

      case PRICE_MEDIAN:
         return (high + low) / 2.0;

      case PRICE_TYPICAL:
         return (high + low + close) / 3.0;

      case PRICE_WEIGHTED:
         return (high + low + close + close) / 4.0;

      default:
         return close;
   }
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //==============================================================
   // INDICATOR BUFFERS
   //==============================================================
   SetIndexBuffer(0, HistBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, HistColor, INDICATOR_COLOR_INDEX);

   SetIndexBuffer(2, LineBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, LineColor, INDICATOR_COLOR_INDEX);

   //==============================================================
   // SERIES MODE
   //==============================================================
   ArraySetAsSeries(HistBuffer, true);
   ArraySetAsSeries(HistColor, true);

   ArraySetAsSeries(LineBuffer, true);
   ArraySetAsSeries(LineColor, true);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      "VSLRT");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Main Calculation                                                 |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   int minBars =
      MathMax(InpShortLength,
              InpLongLength) + 10;

   if(rates_total < minBars)
      return 0;

   //==============================================================
   // FORCE SERIES MODE
   //==============================================================
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(tick_volume, true);

   //==============================================================
   // RESIZE ARRAYS
   //==============================================================
   ArrayResize(Src, rates_total);
   ArrayResize(BuyVol, rates_total);
   ArrayResize(SellVol, rates_total);

   ArraySetAsSeries(Src, true);
   ArraySetAsSeries(BuyVol, true);
   ArraySetAsSeries(SellVol, true);

   //==============================================================
   // BUILD SOURCE + BUY/SELL VOLUME
   //==============================================================
   for(int i=0; i<rates_total; i++)
   {
      Src[i] =
         GetPrice(InpSource,
                  open[i],
                  high[i],
                  low[i],
                  close[i]);

      double rateUp =
         Rate(open[i] <= close[i],
              open[i],
              close[i],
              high[i],
              low[i]);

      double rateDown =
         Rate(open[i] > close[i],
              open[i],
              close[i],
              high[i],
              low[i]);

      double vol =
         (volume[i] > 0)
         ? (double)volume[i]
         : (double)tick_volume[i];

      BuyVol[i] =
         vol * rateUp;

      SellVol[i] =
         vol * rateDown;
   }

   //==============================================================
   // CALCULATION LIMIT
   //==============================================================
   int limit;

   if(prev_calculated == 0)
      limit = rates_total - InpLongLength - 2;
   else
      limit = 10;

   //==============================================================
   // MAIN LOOP
   //==============================================================
   for(int i=limit; i>=0; i--)
   {
      //===========================================================
      // PRICE REGRESSION
      //===========================================================
      double slope_price =
         PineLinReg(Src, i, InpShortLength)
         -
         PineLinReg(Src, i + 1, InpShortLength);

      double slope_price_lt =
         PineLinReg(Src, i, InpLongLength)
         -
         PineLinReg(Src, i + 1, InpLongLength);

      //===========================================================
      // SHORT VOLUME REGRESSION
      //===========================================================
      double slope_volume_up =
         PineLinReg(BuyVol, i, InpShortLength)
         -
         PineLinReg(BuyVol, i + 1, InpShortLength);

      double slope_volume_down =
         PineLinReg(SellVol, i, InpShortLength)
         -
         PineLinReg(SellVol, i + 1, InpShortLength);

      //===========================================================
      // LONG VOLUME REGRESSION
      //===========================================================
      double slope_volume_up_lt =
         PineLinReg(BuyVol, i, InpLongLength)
         -
         PineLinReg(BuyVol, i + 1, InpLongLength);

      double slope_volume_down_lt =
         PineLinReg(SellVol, i, InpLongLength)
         -
         PineLinReg(SellVol, i + 1, InpLongLength);

      //===========================================================
      // OUTPUT VALUES
      //===========================================================
      HistBuffer[i] =
         slope_price * InpShortLength;

      LineBuffer[i] =
         slope_price_lt * InpLongLength;

      //===========================================================
      // SHORT TERM COLORS
      //===========================================================
      if(slope_price > 0)
      {
         if(slope_volume_up > 0)
         {
            if(slope_volume_up > slope_volume_down)
               HistColor[i] = 0;
            else
               HistColor[i] = 1;
         }
         else
         {
            HistColor[i] = 2;
         }
      }
      else if(slope_price < 0)
      {
         if(slope_volume_down > 0)
         {
            if(slope_volume_up < slope_volume_down)
               HistColor[i] = 3;
            else
               HistColor[i] = 4;
         }
         else
         {
            HistColor[i] = 5;
         }
      }
      else
      {
         HistColor[i] = 0;
      }

      //===========================================================
      // LONG TERM COLORS
      //===========================================================
      if(slope_price_lt > 0)
      {
         if(slope_volume_up_lt > 0)
         {
            if(slope_volume_up_lt > slope_volume_down_lt)
               LineColor[i] = 0;
            else
               LineColor[i] = 1;
         }
         else
         {
            LineColor[i] = 2;
         }
      }
      else if(slope_price_lt < 0)
      {
         if(slope_volume_down_lt > 0)
         {
            if(slope_volume_up_lt < slope_volume_down_lt)
               LineColor[i] = 3;
            else
               LineColor[i] = 4;
         }
         else
         {
            LineColor[i] = 5;
         }
      }
      else
      {
         LineColor[i] = 0;
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+