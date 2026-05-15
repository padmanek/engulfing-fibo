//+------------------------------------------------------------------+
//|                                           EngulfingFibSetupEA.mq5 |
//|                        Backtest EA for Engulfing 0.5 Fibo setups |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

enum PendingInvalidationMode
{
   PendingNever = 0,
   PendingWickTouchesTp = 1,
   PendingBodyTouchesTp = 2,
   PendingCloseBeyondTp = 3
};

enum SameBarPriorityMode
{
   SameBarStopFirst = 0,
   SameBarTargetFirst = 1
};

enum PendingSameBarPriorityMode
{
   PendingEntryFirst = 0,
   PendingInvalidationFirst = 1
};

enum PositionSizingMode
{
   SizingFixedLots = 0,
   SizingRiskPercent = 1,
   SizingRiskMoney = 2
};

enum TrendFilterMode
{
   TrendFilterEma = 0,
   TrendFilterSupertrend = 1,
   TrendFilterTtdAlignment = 2
};

enum SupertrendClusterMode
{
   SupertrendClusterWorst = 0,
   SupertrendClusterAverage = 1,
   SupertrendClusterBest = 2
};

enum TtdTrendApproach
{
   TtdSingleEmaDirection = 0,
   TtdTwoEmaComparison = 1
};

input group "Strategia"
input bool   InpRequireOppositeColor = false;       // Wymagaj przeciwnego koloru swiecy objetej
input double InpMinSizeMultiple = 2.0;              // Min. mnoznik rozmiaru swiecy obejmujacej
input double InpSameColorSizeMultiple = 3.0;        // Min. mnoznik gdy swiece nie sa przeciwne
input double InpEntryFib = 0.5;                     // Poziom wejscia Fibo
input double InpRewardR = 2.0;                      // Cel zysku w R
input int    InpSetupExpiryBars = 20;               // Anuluj niewypelniony setup po liczbie swiec, 0 = nigdy
input PendingInvalidationMode InpPendingInvalidation = PendingCloseBeyondTp; // Uniewaznij oczekujacy gdy
input SameBarPriorityMode InpSameBarMode = SameBarStopFirst;                 // Gdy TP i SL trafione na tej samej swiecy
input PendingSameBarPriorityMode InpPendingSameBarMode = PendingEntryFirst;  // Gdy oczekujace: wejscie i TP na tej samej swiecy

input group "Break Even"
input bool   InpUseBreakEven = true;                // Wlacz przesuwanie SL na BE
input double InpBreakEvenTriggerPct = 85.0;         // Przesun SL na BE przy % drogi do TP

input group "Filtr trendu"
input bool   InpUseTrendFilter = false;             // Wlacz filtr trendu
input TrendFilterMode InpTrendFilterMode = TrendFilterEma; // Metoda filtra trendu
input int    InpTrendFastLen = 9;                   // Szybka EMA trendu
input int    InpTrendSlowLen = 21;                  // Wolna EMA trendu
input int    InpSupertrendAtrLength = 10;           // LuxAlgo ST: dlugosc ATR
input double InpSupertrendMinFactor = 1.0;          // LuxAlgo ST: min. faktor
input double InpSupertrendMaxFactor = 5.0;          // LuxAlgo ST: maks. faktor
input double InpSupertrendStep = 0.5;               // LuxAlgo ST: krok faktora
input double InpSupertrendPerfAlpha = 10.0;         // LuxAlgo ST: pamiec performance
input SupertrendClusterMode InpSupertrendCluster = SupertrendClusterBest; // LuxAlgo ST: klaster
input int    InpSupertrendMaxIter = 1000;           // LuxAlgo ST: maks. iteracje
input int    InpSupertrendMaxData = 10000;          // LuxAlgo ST: maks. swiece kalkulacji
input TtdTrendApproach InpTtdTrendApproach = TtdSingleEmaDirection; // TTD: sposob wykrywania trendu
input int    InpTtdEma1Len = 50;                    // TTD: EMA length
input int    InpTtdEma2Len = 200;                   // TTD: dodatkowa EMA length
input bool   InpTtdCatchFlat = false;               // TTD: wykrywaj flat

input group "Filtr ATR"
input bool   InpUseAtrFilter = false;               // Wlacz filtr ATR
input int    InpAtrLength = 14;                     // Dlugosc ATR
input double InpMinBodyAtrPct = 50.0;               // Min. body swiecy setupu (% ATR)
input double InpMaxBodyAtrPct = 300.0;              // Maks. body swiecy setupu (% ATR, 0 = brak)

input group "Filtr knota"
input bool   InpUseCloseWickFilter = false;         // Wlacz filtr knota swiecy zamkniecia
input double InpMaxCloseWickPct = 25.0;             // Maks. knot swiecy setupu (%)

input group "Techniczne"
input double InpMaxCloseOpenGapAtrPct = 5.0;        // Maks. luka close-open (% ATR)
input bool   InpShowFilteredSetups = false;         // Pokazuj odfiltrowane setupy
input bool   InpAlertFilteredSetups = false;        // Alerty dla odfiltrowanych setupow
input bool   InpPrintSetupDiagnostics = false;      // Drukuj diagnostyke setupow do dziennika

input group "Trading MT5"
input long   InpMagicNumber = 505015;               // Magic number
input bool   InpAllowMultipleSetups = true;         // Pozwalaj na wiele setupow naraz
input int    InpDeviationPoints = 20;               // Maks. odchylenie w punktach
input PositionSizingMode InpPositionSizing = SizingFixedLots; // Sposob ustawiania lota
input double InpFixedLots = 0.10;                   // Staly lot
input double InpRiskPercent = 1.0;                  // Ryzyko % salda
input double InpRiskMoney = 100.0;                  // Ryzyko w walucie konta

input group "Rysowanie"
input bool   InpDrawSetups = true;                  // Rysuj setupy i poziomy
input int    InpFibProjectionBars = 24;             // Dlugosc linii Fibo w swiecach

struct PendingInfo
{
   ulong    ticket;
   datetime setup_time;
   int      direction;
};

CTrade trade;
int fast_ema_handle = INVALID_HANDLE;
int slow_ema_handle = INVALID_HANDLE;
int atr_handle = INVALID_HANDLE;
int supertrend_atr_handle = INVALID_HANDLE;
datetime last_m15_bar_time = 0;
PendingInfo pending_infos[];

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
double TickSize()
{
   double value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return value > 0.0 ? value : _Point;
}

double NormalizePrice(const double price)
{
   const double tick_size = TickSize();
   return NormalizeDouble(MathRound(price / tick_size) * tick_size, _Digits);
}

double NormalizeVolume(const double lots)
{
   const double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   const double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double result = MathMax(min_lot, MathMin(max_lot, lots));

   if(step > 0.0)
      result = MathFloor(result / step) * step;

   return NormalizeDouble(result, 2);
}

double CalculateLots(const double entry, const double stop)
{
   if(InpPositionSizing == SizingFixedLots)
      return NormalizeVolume(InpFixedLots);

   double risk_money = InpRiskMoney;
   if(InpPositionSizing == SizingRiskPercent)
      risk_money = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent * 0.01;

   if(risk_money <= 0.0)
      return NormalizeVolume(InpFixedLots);

   const double tick_size = TickSize();
   const double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   const double ticks_at_risk = MathAbs(entry - stop) / tick_size;
   const double money_at_risk_per_lot = ticks_at_risk * tick_value;

   if(money_at_risk_per_lot <= 0.0)
      return NormalizeVolume(InpFixedLots);

   return NormalizeVolume(risk_money / money_at_risk_per_lot);
}

bool IsM15Chart()
{
   return _Period == PERIOD_M15;
}

bool IsNewM15Bar()
{
   datetime times[];
   ArraySetAsSeries(times, true);

   if(CopyTime(_Symbol, PERIOD_M15, 0, 1, times) != 1)
      return false;

   if(times[0] == last_m15_bar_time)
      return false;

   last_m15_bar_time = times[0];
   return true;
}

bool GetBufferValue(const int handle, const int shift, double &value)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);

   if(CopyBuffer(handle, 0, shift, 1, buffer) != 1)
      return false;

   value = buffer[0];
   return true;
}

bool LoadIndicatorValues(double &fast_ema, double &slow_ema, double &atr_value)
{
   if(!GetBufferValue(fast_ema_handle, 1, fast_ema))
      return false;
   if(!GetBufferValue(slow_ema_handle, 1, slow_ema))
      return false;
   if(!GetBufferValue(atr_handle, 1, atr_value))
      return false;

   return true;
}

double PercentileLinear(const double &source[], const int count, const double percentile)
{
   if(count <= 0)
      return 0.0;

   double sorted[];
   ArrayResize(sorted, count);
   for(int i = 0; i < count; i++)
      sorted[i] = source[i];

   ArraySort(sorted);

   if(count == 1)
      return sorted[0];

   const double rank = MathMax(0.0, MathMin(100.0, percentile)) * 0.01 * (count - 1);
   const int lower_index = (int)MathFloor(rank);
   const int upper_index = (int)MathCeil(rank);
   const double weight = rank - lower_index;

   return sorted[lower_index] + (sorted[upper_index] - sorted[lower_index]) * weight;
}

double SignValue(const double value)
{
   if(value > 0.0)
      return 1.0;
   if(value < 0.0)
      return -1.0;
   return 0.0;
}

bool IsValidSeriesValue(const double value)
{
   return value != EMPTY_VALUE;
}

void CalculateEmaSeries(const double &source[], const int count, const int length, double &result[])
{
   ArrayResize(result, count);
   if(count <= 0 || length <= 0)
      return;

   const double alpha = 2.0 / (length + 1.0);
   for(int i = 0; i < count; i++)
   {
      if(i == 0)
         result[i] = source[i];
      else
         result[i] = alpha * source[i] + (1.0 - alpha) * result[i - 1];
   }
}

void CalculateSmmaSeries(const double &source[], const int count, const int length, double &result[])
{
   ArrayResize(result, count);
   if(count <= 0 || length <= 0)
      return;

   double sum = 0.0;
   for(int i = 0; i < count; i++)
   {
      sum += source[i];
      if(i < length - 1)
      {
         result[i] = EMPTY_VALUE;
      }
      else if(i == length - 1)
      {
         result[i] = sum / length;
      }
      else
      {
         result[i] = (result[i - 1] * (length - 1) + source[i]) / length;
      }
   }
}

double SmaAt(const double &source[], const int index, const int length)
{
   if(length <= 0 || index < length - 1)
      return EMPTY_VALUE;

   double sum = 0.0;
   for(int i = index - length + 1; i <= index; i++)
   {
      if(!IsValidSeriesValue(source[i]))
         return EMPTY_VALUE;
      sum += source[i];
   }

   return sum / length;
}

bool TtdImpulseAt(const double &high_values[],
                  const double &low_values[],
                  const double &hlc3_values[],
                  const int count,
                  const int index)
{
   const int impulse_length = 34;
   const int impulse_strength = 9;
   if(index < impulse_length + impulse_strength + 2 || count <= index)
      return false;

   double smma_high[];
   double smma_low[];
   double ema1[];
   double ema2[];
   double zlema[];
   double md[];

   CalculateSmmaSeries(high_values, count, impulse_length, smma_high);
   CalculateSmmaSeries(low_values, count, impulse_length, smma_low);
   CalculateEmaSeries(hlc3_values, count, impulse_length, ema1);
   CalculateEmaSeries(ema1, count, impulse_length, ema2);
   ArrayResize(zlema, count);
   ArrayResize(md, count);

   for(int i = 0; i < count; i++)
   {
      zlema[i] = ema1[i] + (ema1[i] - ema2[i]);
      if(!IsValidSeriesValue(smma_high[i]) || !IsValidSeriesValue(smma_low[i]))
      {
         md[i] = EMPTY_VALUE;
         continue;
      }

      if(zlema[i] > smma_high[i])
         md[i] = zlema[i] - smma_high[i];
      else if(zlema[i] < smma_low[i])
         md[i] = zlema[i] - smma_low[i];
      else
         md[i] = 0.0;
   }

   const double sb = SmaAt(md, index, impulse_strength);
   const double sb_prev = SmaAt(md, index - 1, impulse_strength);
   if(!IsValidSeriesValue(sb) || !IsValidSeriesValue(sb_prev) || !IsValidSeriesValue(md[index]) || !IsValidSeriesValue(md[index - 1]))
      return false;

   const double sh = md[index] - sb;
   const double sh_prev = md[index - 1] - sb_prev;
   return MathAbs(sh) > 0.0000000001 && MathAbs(sh_prev) > 0.0000000001;
}

bool CalculateTtdTrendForTimeframe(const ENUM_TIMEFRAMES timeframe, int &trend)
{
   trend = 0;

   const int impulse_length = 34;
   const int impulse_strength = 9;
   const int max_length = MathMax(MathMax(InpTtdEma1Len, InpTtdEma2Len), impulse_length + impulse_strength);
   int requested = MathMax(max_length * 10 + 100, 500);
   const int bars_available = Bars(_Symbol, timeframe);
   if(bars_available <= max_length + 5)
      return false;

   requested = MathMin(requested, bars_available);

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   const int copied = CopyRates(_Symbol, timeframe, 0, requested, rates);
   if(copied < max_length + 5)
      return false;

   double close_values[];
   double high_values[];
   double low_values[];
   double hlc3_values[];
   ArrayResize(close_values, copied);
   ArrayResize(high_values, copied);
   ArrayResize(low_values, copied);
   ArrayResize(hlc3_values, copied);

   for(int i = 0; i < copied; i++)
   {
      const int series_index = copied - 1 - i;
      close_values[i] = rates[series_index].close;
      high_values[i] = rates[series_index].high;
      low_values[i] = rates[series_index].low;
      hlc3_values[i] = (rates[series_index].high + rates[series_index].low + rates[series_index].close) / 3.0;
   }

   const int current_index = copied - 2;
   const int previous_index = copied - 3;
   if(current_index <= 0 || previous_index < 0)
      return false;

   if(InpTtdCatchFlat && !TtdImpulseAt(high_values, low_values, hlc3_values, copied, current_index))
   {
      trend = 0;
      return true;
   }

   double ema1[];
   CalculateEmaSeries(close_values, copied, InpTtdEma1Len, ema1);

   if(InpTtdTrendApproach == TtdSingleEmaDirection)
   {
      if(ema1[current_index] > ema1[previous_index])
         trend = 1;
      else if(ema1[current_index] < ema1[previous_index])
         trend = -1;
      else
         trend = 0;

      return true;
   }

   double ema2[];
   CalculateEmaSeries(close_values, copied, InpTtdEma2Len, ema2);
   if(ema1[current_index] > ema2[current_index])
      trend = 1;
   else if(ema1[current_index] < ema2[current_index])
      trend = -1;
   else
      trend = 0;

   return true;
}

bool CalculateTtdAlignment(int &trend_5m, int &trend_15m, int &trend_1h, int &aligned_trend)
{
   trend_5m = 0;
   aligned_trend = 0;

   if(!CalculateTtdTrendForTimeframe(PERIOD_M15, trend_15m))
      return false;
   if(!CalculateTtdTrendForTimeframe(PERIOD_H1, trend_1h))
      return false;

   if(trend_15m == trend_1h)
      aligned_trend = trend_15m;
   else
      aligned_trend = 0;

   return true;
}

string TtdTrendName(const int trend)
{
   if(trend == 1)
      return "Up";
   if(trend == -1)
      return "Down";
   return "Neutral";
}

bool CalculateSupertrend(const int shift, int &direction, double &value, double &target_factor)
{
   direction = 0;
   value = 0.0;
   target_factor = 0.0;

   if(InpSupertrendStep <= 0.0 || InpSupertrendMinFactor > InpSupertrendMaxFactor || InpSupertrendPerfAlpha < 2.0)
      return false;

   const int factor_count = (int)MathFloor((InpSupertrendMaxFactor - InpSupertrendMinFactor) / InpSupertrendStep + 0.0000001) + 1;
   if(factor_count <= 0 || factor_count > 200)
      return false;

   const int bars_available = Bars(_Symbol, PERIOD_M15);
   if(bars_available <= shift + InpSupertrendAtrLength + 2)
      return false;

   int requested = InpSupertrendMaxData > 0 ? InpSupertrendMaxData + shift + InpSupertrendAtrLength + 5 : bars_available;
   requested = MathMin(requested, bars_available);
   requested = MathMax(requested, shift + InpSupertrendAtrLength + 10);

   MqlRates rates[];
   double atr[];
   ArraySetAsSeries(rates, true);
   ArraySetAsSeries(atr, true);

   const int copied_rates = CopyRates(_Symbol, PERIOD_M15, 0, requested, rates);
   const int copied_atr = CopyBuffer(supertrend_atr_handle, 0, 0, requested, atr);
   const int count = MathMin(copied_rates, copied_atr);
   if(count <= shift + 2)
      return false;

   double factors[];
   double holder_upper[];
   double holder_lower[];
   double holder_output[];
   double holder_perf[];
   int holder_trend[];

   ArrayResize(factors, factor_count);
   ArrayResize(holder_upper, factor_count);
   ArrayResize(holder_lower, factor_count);
   ArrayResize(holder_output, factor_count);
   ArrayResize(holder_perf, factor_count);
   ArrayResize(holder_trend, factor_count);

   for(int f = 0; f < factor_count; f++)
   {
      factors[f] = InpSupertrendMinFactor + f * InpSupertrendStep;
      holder_upper[f] = (rates[count - 1].high + rates[count - 1].low) * 0.5;
      holder_lower[f] = holder_upper[f];
      holder_output[f] = EMPTY_VALUE;
      holder_perf[f] = 0.0;
      holder_trend[f] = 0;
   }

   const double perf_alpha = 2.0 / (InpSupertrendPerfAlpha + 1.0);

   for(int i = count - 1; i >= shift; i--)
   {
      if(atr[i] <= 0.0 || atr[i] == EMPTY_VALUE)
         continue;

      const double hl2 = (rates[i].high + rates[i].low) * 0.5;
      const bool has_prev_close = i < count - 1;
      const double prev_close = has_prev_close ? rates[i + 1].close : rates[i].close;
      const double close_change = has_prev_close ? rates[i].close - prev_close : 0.0;

      for(int f = 0; f < factor_count; f++)
      {
         const double up = hl2 + atr[i] * factors[f];
         const double dn = hl2 - atr[i] * factors[f];

         if(rates[i].close > holder_upper[f])
            holder_trend[f] = 1;
         else if(rates[i].close < holder_lower[f])
            holder_trend[f] = 0;

         holder_upper[f] = has_prev_close && prev_close < holder_upper[f] ? MathMin(up, holder_upper[f]) : up;
         holder_lower[f] = has_prev_close && prev_close > holder_lower[f] ? MathMax(dn, holder_lower[f]) : dn;

         const double diff = holder_output[f] == EMPTY_VALUE ? 0.0 : SignValue(prev_close - holder_output[f]);
         holder_perf[f] += perf_alpha * (close_change * diff - holder_perf[f]);
         holder_output[f] = holder_trend[f] == 1 ? holder_lower[f] : holder_upper[f];
      }
   }

   double centroids[3];
   centroids[0] = PercentileLinear(holder_perf, factor_count, 25.0);
   centroids[1] = PercentileLinear(holder_perf, factor_count, 50.0);
   centroids[2] = PercentileLinear(holder_perf, factor_count, 75.0);

   double cluster_factor_sum[3];
   double cluster_perf_sum[3];
   int cluster_count[3];
   const int max_iter = MathMax(0, InpSupertrendMaxIter);

   for(int iter = 0; iter <= max_iter; iter++)
   {
      ArrayInitialize(cluster_factor_sum, 0.0);
      ArrayInitialize(cluster_perf_sum, 0.0);
      ArrayInitialize(cluster_count, 0);

      for(int f = 0; f < factor_count; f++)
      {
         int cluster_index = 0;
         double best_distance = MathAbs(holder_perf[f] - centroids[0]);

         for(int c = 1; c < 3; c++)
         {
            const double distance = MathAbs(holder_perf[f] - centroids[c]);
            if(distance < best_distance)
            {
               best_distance = distance;
               cluster_index = c;
            }
         }

         cluster_factor_sum[cluster_index] += factors[f];
         cluster_perf_sum[cluster_index] += holder_perf[f];
         cluster_count[cluster_index]++;
      }

      double new_centroids[3];
      bool unchanged = true;
      for(int c = 0; c < 3; c++)
      {
         new_centroids[c] = cluster_count[c] > 0 ? cluster_perf_sum[c] / cluster_count[c] : centroids[c];
         if(MathAbs(new_centroids[c] - centroids[c]) > 0.0000000001)
            unchanged = false;
      }

      centroids[0] = new_centroids[0];
      centroids[1] = new_centroids[1];
      centroids[2] = new_centroids[2];

      if(unchanged)
         break;
   }

   int selected_cluster = (int)InpSupertrendCluster;
   selected_cluster = MathMax(0, MathMin(2, selected_cluster));

   if(cluster_count[selected_cluster] > 0)
      target_factor = cluster_factor_sum[selected_cluster] / cluster_count[selected_cluster];
   else
      target_factor = (InpSupertrendMinFactor + InpSupertrendMaxFactor) * 0.5;

   bool initialized = false;
   int os = 0;
   double upper_band = 0.0;
   double lower_band = 0.0;
   double trailing_stop = 0.0;

   for(int i = count - 1; i >= shift; i--)
   {
      if(atr[i] <= 0.0 || atr[i] == EMPTY_VALUE)
         continue;

      const double hl2 = (rates[i].high + rates[i].low) * 0.5;
      const double up = hl2 + atr[i] * target_factor;
      const double dn = hl2 - atr[i] * target_factor;
      const bool has_prev_close = i < count - 1;
      const double prev_close = has_prev_close ? rates[i + 1].close : rates[i].close;

      if(!initialized)
      {
         upper_band = hl2;
         lower_band = hl2;
         initialized = true;
      }

      upper_band = has_prev_close && prev_close < upper_band ? MathMin(up, upper_band) : up;
      lower_band = has_prev_close && prev_close > lower_band ? MathMax(dn, lower_band) : dn;

      if(rates[i].close > upper_band)
         os = 1;
      else if(rates[i].close < lower_band)
         os = 0;

      trailing_stop = os == 1 ? lower_band : upper_band;
   }

   if(!initialized)
      return false;

   direction = os == 1 ? 1 : -1;
   value = trailing_stop;
   return true;
}

string TrendStateText(const double fast_ema,
                      const double slow_ema,
                      const int supertrend_direction,
                      const double supertrend_value,
                      const double supertrend_factor,
                      const int ttd_trend_5m,
                      const int ttd_trend_15m,
                      const int ttd_trend_1h,
                      const int ttd_aligned_trend)
{
   if(!InpUseTrendFilter)
      return "Off";

   if(InpTrendFilterMode == TrendFilterSupertrend)
   {
      if(supertrend_direction == 1)
         return "LuxST Up factor=" + DoubleToString(supertrend_factor, 2) + " @" + DoubleToString(supertrend_value, _Digits);
      if(supertrend_direction == -1)
         return "LuxST Down factor=" + DoubleToString(supertrend_factor, 2) + " @" + DoubleToString(supertrend_value, _Digits);
      return "LuxST n/a";
   }

   if(InpTrendFilterMode == TrendFilterTtdAlignment)
   {
      return "TTD 15m=" + TtdTrendName(ttd_trend_15m)
         + " 1h=" + TtdTrendName(ttd_trend_1h)
         + " aligned=" + TtdTrendName(ttd_aligned_trend);
   }

   if(fast_ema > slow_ema)
      return "EMA Up";
   if(fast_ema < slow_ema)
      return "EMA Down";
   return "EMA Flat";
}

void AddPendingInfo(const ulong ticket, const datetime setup_time, const int direction)
{
   const int size = ArraySize(pending_infos);
   ArrayResize(pending_infos, size + 1);
   pending_infos[size].ticket = ticket;
   pending_infos[size].setup_time = setup_time;
   pending_infos[size].direction = direction;
}

void RemovePendingInfoByIndex(const int index)
{
   const int size = ArraySize(pending_infos);
   if(index < 0 || index >= size)
      return;

   for(int i = index; i < size - 1; i++)
      pending_infos[i] = pending_infos[i + 1];

   ArrayResize(pending_infos, size - 1);
}

bool SelectOurOrder(const ulong ticket)
{
   if(!OrderSelect(ticket))
      return false;

   if(OrderGetString(ORDER_SYMBOL) != _Symbol)
      return false;

   if((long)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber)
      return false;

   return true;
}

int CountOurExposure()
{
   int count = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;

      if(OrderGetString(ORDER_SYMBOL) == _Symbol && (long)OrderGetInteger(ORDER_MAGIC) == InpMagicNumber)
         count++;
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol && (long)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         count++;
   }

   return count;
}

int BarsSinceSetup(const datetime setup_time, const datetime closed_bar_time)
{
   const int setup_shift = iBarShift(_Symbol, PERIOD_M15, setup_time, true);
   const int closed_shift = iBarShift(_Symbol, PERIOD_M15, closed_bar_time, true);

   if(setup_shift < 0 || closed_shift < 0)
      return 0;

   return setup_shift - closed_shift;
}

bool PendingInvalidationHit(const int direction, const MqlRates &bar, const double target)
{
   switch(InpPendingInvalidation)
   {
      case PendingWickTouchesTp:
         return direction == 1 ? bar.high >= target : bar.low <= target;

      case PendingBodyTouchesTp:
         return direction == 1 ? MathMax(bar.open, bar.close) >= target : MathMin(bar.open, bar.close) <= target;

      case PendingCloseBeyondTp:
         return direction == 1 ? bar.close >= target : bar.close <= target;

      case PendingNever:
      default:
         return false;
   }
}

void DrawTextObject(const string name, const datetime time, const double price, const string text, const color clr)
{
   if(!InpDrawSetups)
      return;

   ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, time, price))
      return;

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
}

void DrawSegment(const string name, const datetime start_time, const datetime end_time, const double price, const color clr, const ENUM_LINE_STYLE style, const int width)
{
   if(!InpDrawSetups)
      return;

   ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_TREND, 0, start_time, price, end_time, price))
      return;

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
}

void DrawSetup(const int direction, const datetime setup_time, const double entry, const double stop, const double target, const double fib_low, const double fib_high)
{
   if(!InpDrawSetups)
      return;

   const string prefix = "EFIB_" + IntegerToString((int)setup_time) + "_" + (direction == 1 ? "B_" : "S_");
   const datetime end_time = setup_time + InpFibProjectionBars * PeriodSeconds(PERIOD_M15);
   const color setup_color = direction == 1 ? clrSeaGreen : clrCrimson;

   DrawTextObject(prefix + "mark", setup_time, direction == 1 ? fib_low : fib_high, direction == 1 ? "B" : "S", setup_color);
   DrawSegment(prefix + "fib_low", setup_time, end_time, fib_low, setup_color, STYLE_SOLID, 1);
   DrawSegment(prefix + "entry", setup_time, end_time, entry, clrOrange, STYLE_SOLID, 2);
   DrawSegment(prefix + "fib_high", setup_time, end_time, fib_high, setup_color, STYLE_SOLID, 1);
   DrawSegment(prefix + "sl", setup_time, end_time, stop, clrCrimson, STYLE_DOT, 1);
   DrawSegment(prefix + "tp", setup_time, end_time, target, clrDodgerBlue, STYLE_DOT, 1);
}

void DrawFilteredSetup(const int direction, const MqlRates &bar, const string reason)
{
   if(!InpShowFilteredSetups)
      return;

   const string prefix = "EFIB_FILTERED_" + IntegerToString((int)bar.time) + "_" + (direction == 1 ? "B" : "S");
   const double price = direction == 1 ? bar.low : bar.high;
   DrawTextObject(prefix, bar.time, price, (direction == 1 ? "B " : "S ") + reason, clrGold);
}

void PrintSetupDiagnostics(const string status,
                           const int direction,
                           const MqlRates &bar,
                           const double body,
                           const double atr_value,
                           const double close_wick_pct,
                           const bool trend_ok,
                           const bool atr_ok,
                           const bool wick_ok,
                           const string reason,
                           const string trend_state)
{
   if(!InpPrintSetupDiagnostics)
      return;

   const double body_atr_pct = atr_value > 0.0 ? body / atr_value * 100.0 : 0.0;

   Print("EFIB setup diagnostics: ",
         status,
         " ",
         direction == 1 ? "LONG" : "SHORT",
         " setup_candle=",
         TimeToString(bar.time, TIME_DATE | TIME_MINUTES),
         " O=",
         DoubleToString(bar.open, _Digits),
         " H=",
         DoubleToString(bar.high, _Digits),
         " L=",
         DoubleToString(bar.low, _Digits),
         " C=",
         DoubleToString(bar.close, _Digits),
         " body=",
         DoubleToString(body, _Digits),
         " ATR=",
         DoubleToString(atr_value, _Digits),
         " body_ATR_pct=",
         DoubleToString(body_atr_pct, 2),
         " min_pct=",
         DoubleToString(InpMinBodyAtrPct, 2),
         " max_pct=",
         DoubleToString(InpMaxBodyAtrPct, 2),
         " close_wick_pct=",
         DoubleToString(close_wick_pct, 2),
         " trend_ok=",
         trend_ok ? "true" : "false",
         trend_state == "" ? "" : " trend_state=" + trend_state,
         " atr_ok=",
         atr_ok ? "true" : "false",
         " wick_ok=",
         wick_ok ? "true" : "false",
         reason == "" ? "" : " reason=" + reason);
}

void CleanupPendingInfos()
{
   for(int i = ArraySize(pending_infos) - 1; i >= 0; i--)
   {
      if(!SelectOurOrder(pending_infos[i].ticket))
         RemovePendingInfoByIndex(i);
   }
}

//+------------------------------------------------------------------+
//| Trade management                                                  |
//+------------------------------------------------------------------+
void ManageBreakEven()
{
   if(!InpUseBreakEven)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      const ENUM_POSITION_TYPE position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      const double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      const double stop = PositionGetDouble(POSITION_SL);
      const double target = PositionGetDouble(POSITION_TP);

      if(target <= 0.0 || MathAbs(stop - entry) <= TickSize() * 0.5)
         continue;

      const double trigger = position_type == POSITION_TYPE_BUY
         ? entry + (target - entry) * InpBreakEvenTriggerPct * 0.01
         : entry - (entry - target) * InpBreakEvenTriggerPct * 0.01;

      const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      const bool hit_trigger = position_type == POSITION_TYPE_BUY ? bid >= trigger : ask <= trigger;

      if(hit_trigger)
         trade.PositionModify(ticket, NormalizePrice(entry), target);
   }
}

void ManagePendingOrders(const MqlRates &closed_bar)
{
   for(int i = ArraySize(pending_infos) - 1; i >= 0; i--)
   {
      const ulong ticket = pending_infos[i].ticket;

      if(!SelectOurOrder(ticket))
      {
         RemovePendingInfoByIndex(i);
         continue;
      }

      const ENUM_ORDER_TYPE order_type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(order_type != ORDER_TYPE_BUY_LIMIT && order_type != ORDER_TYPE_SELL_LIMIT)
      {
         RemovePendingInfoByIndex(i);
         continue;
      }

      const int direction = order_type == ORDER_TYPE_BUY_LIMIT ? 1 : -1;
      const double entry = OrderGetDouble(ORDER_PRICE_OPEN);
      const double target = OrderGetDouble(ORDER_TP);
      const int age = BarsSinceSetup(pending_infos[i].setup_time, closed_bar.time);

      const bool touched_entry = direction == 1 ? closed_bar.low <= entry : closed_bar.high >= entry;
      const bool invalidation_hit = PendingInvalidationHit(direction, closed_bar, target);
      const bool should_invalidate = age > 0 && invalidation_hit && (!touched_entry || InpPendingSameBarMode == PendingInvalidationFirst);
      const bool expired = InpSetupExpiryBars > 0 && age > InpSetupExpiryBars;

      if(should_invalidate || expired)
      {
         trade.OrderDelete(ticket);
         RemovePendingInfoByIndex(i);
      }
   }
}

bool SendSetupOrder(const int direction, const MqlRates &setup_bar, const double entry, const double stop, const double target)
{
   if(!InpAllowMultipleSetups && CountOurExposure() > 0)
      return false;

   const double volume = CalculateLots(entry, stop);
   if(volume <= 0.0)
      return false;

   const string setup_time_text = TimeToString(setup_bar.time, TIME_DATE | TIME_MINUTES);
   const string comment = "EFIB " + (direction == 1 ? "LONG " : "SHORT ") + setup_time_text;
   bool ok = false;

   if(direction == 1)
   {
      ok = trade.BuyLimit(volume, entry, _Symbol, stop, target, ORDER_TIME_GTC, 0, comment);
   }
   else
   {
      ok = trade.SellLimit(volume, entry, _Symbol, stop, target, ORDER_TIME_GTC, 0, comment);
   }

   if(!ok)
   {
      Print("EFIB order failed. Retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      return false;
   }

   AddPendingInfo(trade.ResultOrder(), setup_bar.time, direction);

   return true;
}

//+------------------------------------------------------------------+
//| Setup detection                                                   |
//+------------------------------------------------------------------+
string FilterReasons(const bool trend_fail, const bool atr_fail, const bool wick_fail)
{
   string result = "";

   if(trend_fail)
      result = "Trend";
   if(atr_fail)
      result = result == "" ? "ATR" : result + ", ATR";
   if(wick_fail)
      result = result == "" ? "Knot" : result + ", Knot";

   return result;
}

void EvaluateSetup()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(_Symbol, PERIOD_M15, 0, 3, rates) < 3)
      return;

   double fast_ema = 0.0;
   double slow_ema = 0.0;
   double atr_value = 0.0;
   int supertrend_direction = 0;
   double supertrend_value = 0.0;
   double supertrend_factor = 0.0;
   int ttd_trend_5m = 0;
   int ttd_trend_15m = 0;
   int ttd_trend_1h = 0;
   int ttd_aligned_trend = 0;

   if(!LoadIndicatorValues(fast_ema, slow_ema, atr_value))
      return;

   if(InpUseTrendFilter && InpTrendFilterMode == TrendFilterSupertrend)
   {
      if(!CalculateSupertrend(1, supertrend_direction, supertrend_value, supertrend_factor))
         return;
   }

   if(InpUseTrendFilter && InpTrendFilterMode == TrendFilterTtdAlignment)
   {
      if(!CalculateTtdAlignment(ttd_trend_5m, ttd_trend_15m, ttd_trend_1h, ttd_aligned_trend))
         return;
   }

   const MqlRates curr = rates[1];
   const MqlRates prev = rates[2];

   const bool prev_bear = prev.close < prev.open;
   const bool prev_bull = prev.close > prev.open;
   const bool curr_bull = curr.close > curr.open;
   const bool curr_bear = curr.close < curr.open;

   const double curr_body_high = MathMax(curr.open, curr.close);
   const double curr_body_low = MathMin(curr.open, curr.close);
   const double prev_body_high = MathMax(prev.open, prev.close);
   const double prev_body_low = MathMin(prev.open, prev.close);
   const double close_open_gap = MathAbs(curr.open - prev.close);
   const double gap_atr_cap = atr_value * InpMaxCloseOpenGapAtrPct * 0.01;
   const double gap_tolerance = MathMin(close_open_gap, gap_atr_cap);

   const bool body_bull_engulf = curr_body_low <= prev_body_low + gap_tolerance && curr_body_high >= prev_body_high - gap_tolerance;
   const bool body_bear_engulf = curr_body_high >= prev_body_high - gap_tolerance && curr_body_low <= prev_body_low + gap_tolerance;

   const double bull_engulfing_size = curr.close - curr.open;
   const double bear_engulfing_size = curr.open - curr.close;
   const double bull_engulfed_size = prev.high - prev.close;
   const double bear_engulfed_size = prev.close - prev.low;

   const bool bull_opposite_color = prev_bear;
   const bool bear_opposite_color = prev_bull;
   const bool bull_same_color = prev_bull;
   const bool bear_same_color = prev_bear;

   const bool bull_classic_size_ok = bull_engulfed_size > TickSize() && bull_engulfing_size >= bull_engulfed_size * InpMinSizeMultiple;
   const bool bear_classic_size_ok = bear_engulfed_size > TickSize() && bear_engulfing_size >= bear_engulfed_size * InpMinSizeMultiple;

   const double bull_same_color_engulfed_size = prev.high - prev.open;
   const double bear_same_color_engulfed_size = prev.open - prev.low;
   const bool bull_same_color_size_ok = bull_same_color_engulfed_size > TickSize() && bull_engulfing_size >= bull_same_color_engulfed_size * InpSameColorSizeMultiple;
   const bool bear_same_color_size_ok = bear_same_color_engulfed_size > TickSize() && bear_engulfing_size >= bear_same_color_engulfed_size * InpSameColorSizeMultiple;

   const bool bull_same_color_breakout = curr.close >= prev.high - gap_tolerance;
   const bool bear_same_color_breakout = curr.close <= prev.low + gap_tolerance;

   const bool ema_trend_up = fast_ema > slow_ema;
   const bool ema_trend_down = fast_ema < slow_ema;
   const bool supertrend_up = supertrend_direction == 1;
   const bool supertrend_down = supertrend_direction == -1;
   const bool ttd_trend_up = ttd_aligned_trend == 1;
   const bool ttd_trend_down = ttd_aligned_trend == -1;
   const bool trend_up = InpTrendFilterMode == TrendFilterSupertrend ? supertrend_up : InpTrendFilterMode == TrendFilterTtdAlignment ? ttd_trend_up : ema_trend_up;
   const bool trend_down = InpTrendFilterMode == TrendFilterSupertrend ? supertrend_down : InpTrendFilterMode == TrendFilterTtdAlignment ? ttd_trend_down : ema_trend_down;
   const bool trend_allows_long = !InpUseTrendFilter || trend_up;
   const bool trend_allows_short = !InpUseTrendFilter || trend_down;
   const string trend_state = TrendStateText(fast_ema, slow_ema, supertrend_direction, supertrend_value, supertrend_factor, ttd_trend_5m, ttd_trend_15m, ttd_trend_1h, ttd_aligned_trend);

   const bool atr_max_disabled = InpMaxBodyAtrPct == 0.0;
   const bool bull_atr_ok = !InpUseAtrFilter || (atr_value > 0.0 && bull_engulfing_size >= atr_value * InpMinBodyAtrPct * 0.01 && (atr_max_disabled || bull_engulfing_size <= atr_value * InpMaxBodyAtrPct * 0.01));
   const bool bear_atr_ok = !InpUseAtrFilter || (atr_value > 0.0 && bear_engulfing_size >= atr_value * InpMinBodyAtrPct * 0.01 && (atr_max_disabled || bear_engulfing_size <= atr_value * InpMaxBodyAtrPct * 0.01));

   const double candle_range = curr.high - curr.low;
   const double bull_close_wick_pct = candle_range > TickSize() ? (curr.high - curr.close) / candle_range * 100.0 : 100.0;
   const double bear_close_wick_pct = candle_range > TickSize() ? (curr.close - curr.low) / candle_range * 100.0 : 100.0;
   const bool bull_close_wick_ok = !InpUseCloseWickFilter || bull_close_wick_pct <= InpMaxCloseWickPct;
   const bool bear_close_wick_ok = !InpUseCloseWickFilter || bear_close_wick_pct <= InpMaxCloseWickPct;

   const bool bull_classic_setup = bull_opposite_color && curr_bull && body_bull_engulf && bull_classic_size_ok;
   const bool bear_classic_setup = bear_opposite_color && curr_bear && body_bear_engulf && bear_classic_size_ok;
   const bool bull_same_color_setup = !InpRequireOppositeColor && bull_same_color && curr_bull && bull_same_color_size_ok && bull_same_color_breakout;
   const bool bear_same_color_setup = !InpRequireOppositeColor && bear_same_color && curr_bear && bear_same_color_size_ok && bear_same_color_breakout;

   const bool bull_pattern_setup = bull_classic_setup || bull_same_color_setup;
   const bool bear_pattern_setup = bear_classic_setup || bear_same_color_setup;

   const bool bull_trend_fail = !trend_allows_long;
   const bool bear_trend_fail = !trend_allows_short;
   const bool bull_atr_fail = !bull_atr_ok;
   const bool bear_atr_fail = !bear_atr_ok;
   const bool bull_wick_fail = !bull_close_wick_ok;
   const bool bear_wick_fail = !bear_close_wick_ok;

   const bool bull_filter_fail = bull_trend_fail || bull_atr_fail || bull_wick_fail;
   const bool bear_filter_fail = bear_trend_fail || bear_atr_fail || bear_wick_fail;

   if(bull_pattern_setup && bull_filter_fail)
   {
      const string reason = FilterReasons(bull_trend_fail, bull_atr_fail, bull_wick_fail);
      PrintSetupDiagnostics("FILTERED", 1, curr, bull_engulfing_size, atr_value, bull_close_wick_pct, trend_allows_long, bull_atr_ok, bull_close_wick_ok, reason, trend_state);
      DrawFilteredSetup(1, curr, reason);
      if(InpAlertFilteredSetups)
         Alert("Odfiltrowany wzrostowy setup EFIB: ", reason);
      return;
   }

   if(bear_pattern_setup && bear_filter_fail)
   {
      const string reason = FilterReasons(bear_trend_fail, bear_atr_fail, bear_wick_fail);
      PrintSetupDiagnostics("FILTERED", -1, curr, bear_engulfing_size, atr_value, bear_close_wick_pct, trend_allows_short, bear_atr_ok, bear_close_wick_ok, reason, trend_state);
      DrawFilteredSetup(-1, curr, reason);
      if(InpAlertFilteredSetups)
         Alert("Odfiltrowany spadkowy setup EFIB: ", reason);
      return;
   }

   if(bull_pattern_setup && trend_allows_long && bull_atr_ok && bull_close_wick_ok)
   {
      const double fib_low = MathMin(curr.low, prev.low);
      const double fib_high = MathMax(curr.high, prev.high);
      const double entry = NormalizePrice(fib_low + (fib_high - fib_low) * InpEntryFib);
      const double stop = NormalizePrice(fib_low);
      const double risk = entry - stop;
      const double target = NormalizePrice(entry + risk * InpRewardR);

      if(risk > TickSize())
      {
         PrintSetupDiagnostics("ACCEPTED", 1, curr, bull_engulfing_size, atr_value, bull_close_wick_pct, trend_allows_long, bull_atr_ok, bull_close_wick_ok, "", trend_state);
         DrawSetup(1, curr.time, entry, stop, target, fib_low, fib_high);
         SendSetupOrder(1, curr, entry, stop, target);
      }
   }

   if(bear_pattern_setup && trend_allows_short && bear_atr_ok && bear_close_wick_ok)
   {
      const double fib_high = MathMax(curr.high, prev.high);
      const double fib_low = MathMin(curr.low, prev.low);
      const double entry = NormalizePrice(fib_high + (fib_low - fib_high) * InpEntryFib);
      const double stop = NormalizePrice(fib_high);
      const double risk = stop - entry;
      const double target = NormalizePrice(entry - risk * InpRewardR);

      if(risk > TickSize())
      {
         PrintSetupDiagnostics("ACCEPTED", -1, curr, bear_engulfing_size, atr_value, bear_close_wick_pct, trend_allows_short, bear_atr_ok, bear_close_wick_ok, "", trend_state);
         DrawSetup(-1, curr.time, entry, stop, target, fib_low, fib_high);
         SendSetupOrder(-1, curr, entry, stop, target);
      }
   }
}

//+------------------------------------------------------------------+
//| Expert lifecycle                                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);

   fast_ema_handle = iMA(_Symbol, PERIOD_M15, InpTrendFastLen, 0, MODE_EMA, PRICE_CLOSE);
   slow_ema_handle = iMA(_Symbol, PERIOD_M15, InpTrendSlowLen, 0, MODE_EMA, PRICE_CLOSE);
   atr_handle = iATR(_Symbol, PERIOD_M15, InpAtrLength);
   supertrend_atr_handle = iATR(_Symbol, PERIOD_M15, InpSupertrendAtrLength);

   if(fast_ema_handle == INVALID_HANDLE || slow_ema_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE || supertrend_atr_handle == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles.");
      return INIT_FAILED;
   }

   if(!IsM15Chart())
      Print("EngulfingFibSetupEA trades only on M15 charts.");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(fast_ema_handle != INVALID_HANDLE)
      IndicatorRelease(fast_ema_handle);
   if(slow_ema_handle != INVALID_HANDLE)
      IndicatorRelease(slow_ema_handle);
   if(atr_handle != INVALID_HANDLE)
      IndicatorRelease(atr_handle);
   if(supertrend_atr_handle != INVALID_HANDLE)
      IndicatorRelease(supertrend_atr_handle);
}

void OnTick()
{
   if(!IsM15Chart())
      return;

   ManageBreakEven();

   if(!IsNewM15Bar())
      return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(_Symbol, PERIOD_M15, 0, 2, rates) < 2)
      return;

   ManagePendingOrders(rates[1]);
   CleanupPendingInfos();
   EvaluateSetup();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   if(trans.deal == 0 || !HistoryDealSelect(trans.deal))
      return;

   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;

   if((long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber)
      return;

   const ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(deal_entry != DEAL_ENTRY_IN && deal_entry != DEAL_ENTRY_INOUT)
      return;

   const ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   if(deal_type != DEAL_TYPE_BUY && deal_type != DEAL_TYPE_SELL)
      return;

   const string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
   const string side = deal_type == DEAL_TYPE_BUY ? "LONG" : "SHORT";
   const double price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   const double volume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);

   Print("EFIB transaction opened: ",
         side,
         " setup candle ",
         comment,
         " price=",
         DoubleToString(price, _Digits),
         " volume=",
         DoubleToString(volume, 2));
}
