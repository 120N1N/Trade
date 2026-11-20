//+------------------------------------------------------------------+
//|                                        Ratchet_AI_Trader.mq5     |
//|                             Copyright 2026, Quantitative EA Dev |
//|                                             https://trade.local |
//+------------------------------------------------------------------+
#property copyright   "Quantitative EA Dev"
#property link        "https://trade.local"
#property version     "5.30"
#property description "OPTIMIZED RATCHET SCALPER v5.30 - XAUUSD M1"
#property description "Tuned Parameters: Zero Choking, Expanded Profit, Noise-Tolerant SL, R:R Positive"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

CTrade        trade;
CPositionInfo position;
CAccountInfo  account;

//====================================================================
//--- 1. PENGATURAN MODAL & UKURAN LOT
//====================================================================
sinput string Section_Capital           = "====== 1. MODAL & LOT SCALING ======";
input double  InpLotSize                = 0.01;      // Ukuran Lot Dasar (0.01 untuk Akun $20)
input int     InpMaxPositions           = 1;         // Maksimal Posisi Terbuka (Wajib 1 agar Margin Aman)
input bool    InpAutoCompoundLot        = false;     // Auto-Compound Lot saat Saldo Membesar
input double  InpBalancePerMicroLot     = 50.0;      // Tiap Saldo $50 Tambah 0.01 Lot ($100=0.02, $150=0.03)
input ulong   InpMagicNumber            = 889944;    // Magic Number Unik EA
input int     InpSlippagePoints         = 30;        // Toleransi Slippage (Points)
input double  InpMaxSpreadPoints        = 50.0;      // Maksimal Spread Diizinkan (50 pts = $0.50 Gold)

//====================================================================
//--- 2. RISK-TO-REWARD OPTIMAL (SL BERI RUANG NAPAS, TP BESAR)
//====================================================================
sinput string Section_RiskReward        = "====== 2. RISK-TO-REWARD OPTIMAL ======";
input int     InpStopLossPoints         = 220;       // Stop Loss Floor (220 pts = $2.20 Gold, Tahan Noise M1)
input int     InpTakeProfitPoints       = 350;       // Take Profit Target (350 pts = +$3.50 Gold, Menangkap Tren)
input double  InpDailyLossLimitUSD      = 0.0;       // Batas Rugi Harian (0 = Nonaktif / Bebas Trading Sesi London & NY)
input double  InpDailyProfitTargetUSD   = 0.0;       // Target Profit Harian (0 = Nonaktif / Biarkan Untung Maksimal)

//====================================================================
//--- 3. MECHANICAL RATCHET TRAILING (KUNCI UNTUNG LEBAR)
//====================================================================
sinput string Section_Ratchet           = "====== 3. MECHANICAL RATCHET TRAILING STOP ======";
input bool    InpEnableRatchet          = true;      // Aktifkan Mekanisme Ratchet Trailing
input int     InpRatchetTriggerPoints   = 120;       // Trigger Aktif Ratchet (120 pts = +$1.20 Profit)
input int     InpRatchetLockPoints      = 40;        // Kunci Profit Perdana (40 pts = +$0.40 Locked Free Ride)
input int     InpRatchetStepPoints      = 20;        // Step Trailing Ratchet Setiap Melaju (20 pts = $0.20)
input int     InpTrailingStepMin        = 10;        // Pergeseran Minimal Modifikasi Broker (10 pts)

//====================================================================
//--- 4. FILTER TREND & ANTI-CHOP (AKURASI TINGGI)
//====================================================================
sinput string Section_TrendFilter       = "====== 4. FILTER TREND & MOMENTUM CANDLE ======";
input bool    InpUseTrendFilter         = true;      // Wajib Searah Trend EMA
input int     InpFastEMAPeriod          = 20;        // Fast EMA (EMA 20 Lincah M1)
input int     InpSlowEMAPeriod          = 50;        // Slow EMA (EMA 50 Trend Utama M1)
input double  InpMinEMADiffPoints       = 8.0;       // Filter Sideways: Jarak Minimal EMA 20 vs 50 (8 pts = $0.08)
input bool    InpUseDualCandleConfirm   = true;      // Dual Candle: Lilin 1 (Closed) & Lilin 0 (Berjalan) Wajib Searah
input ENUM_APPLIED_PRICE InpEMAPrice    = PRICE_CLOSE;
input int     InpRSIPeriod              = 14;        // Periode RSI
input double  InpRSIOverbought          = 70.0;      // Level 70: Batas Atas Buy (Dilarang Buka Buy di Pucuk)
input double  InpRSIMidline             = 50.0;      // Level 50: Baseline Momentum Trend
input double  InpRSIOversold            = 30.0;      // Level 30: Batas Bawah Sell (Dilarang Buka Sell di Lembah)

//====================================================================
//--- 5. ANTI-MACHINE GUN & JEDA COOLDOWN WAJAR
//====================================================================
sinput string Section_AntiRevenge       = "====== 5. ANTI-MACHINE GUN & JEDA COOLDOWN ======";
input bool    InpOneTradePerBar         = true;      // Wajib 1 Trade per Lilin Candle M1
input int     InpMinTradeIntervalSec    = 15;        // Jeda Minimal Antar Transaksi Selesai (15 Detik)
input int     InpPostLossCooldownSec    = 30;        // Jeda Pasca-Loss Mencegah Revenge Trading (30 Detik)
input bool    InpWaitNewBarAfterLoss    = true;      // Wajib Tunggu Lilin Candlestick Baru Setelah Loss
input int     InpConsecutiveLossLimit   = 4;         // Maksimal Loss Beruntun Sebelum Pause (4x Loss)
input int     InpStreakPauseDurationSec = 120;       // Durasi Pause jika 4x Loss Beruntun (120 Detik)

//====================================================================
//--- 6. AI REINFORCEMENT LEARNING (Q-LEARNING VOLATILITY ENGINE)
//====================================================================
sinput string Section_AI                = "====== 6. PARAMETER Q-LEARNING (AI) ======";
input bool    InpEnableAI               = true;      // Aktifkan Otak Machine Learning
input int     InpATRPeriod              = 14;        // Periode ATR
input double  InpLearningRate           = 0.15;      // Learning Rate
input double  InpExplorationRate        = 0.05;      // Exploration Rate

//====================================================================
//--- VARIABEL GLOBAL & MATRIKS Q-LEARNING
//====================================================================
#define NUM_STATES   3
#define NUM_ACTIONS  4

double QTable[NUM_STATES][NUM_ACTIONS];
double ActionMultipliers[NUM_ACTIONS] = {0.80, 1.00, 1.20, 1.40};

int      lastState              = 1;
int      lastAction             = 1;
double   currentDynamicDistance = 120.0;
string   lastDiagnosisMsg       = "Inisialisasi Sistem Ratchet AI v5.30...";

int    handleEMA20 = INVALID_HANDLE;
int    handleEMA50 = INVALID_HANDLE;
int    handleRSI   = INVALID_HANDLE;
int    handleATR   = INVALID_HANDLE;
string memoryFile  = "Ratchet_AI_Memory_" + _Symbol + ".bin";

datetime lastTradeBarTime    = 0;
datetime lastTradeOpenedTime = 0;
datetime lastTradeClosedTime = 0;
datetime lossBarTime         = 0;
datetime cooldownUntil       = 0;
datetime streakPauseUntil    = 0;
int      consecutiveLosses   = 0;
bool     waitingNewBar       = false;

datetime currentDayDate      = 0;
double   dailyProfitTotal    = 0.0;
double   dailyLossTotal      = 0.0;
int      dailyTradesCount    = 0;
int      dailyWinsCount      = 0;
int      dailyLossesCount    = 0;

//+------------------------------------------------------------------+
//| Auto-Detect Filling Mode yang didukung Broker                    |
//+------------------------------------------------------------------+
void SetProperFillingMode()
{
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) != 0)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
}

//+------------------------------------------------------------------+
//| Normalisasi Ukuran Lot Sesuai Aturan Broker                      |
//+------------------------------------------------------------------+
double SanitizeLot(double requestedLot)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(minLot <= 0.0) minLot = 0.01;
   if(stepLot <= 0.0) stepLot = 0.01;

   double lot = MathMax(requestedLot, minLot);
   if(maxLot > 0.0) lot = MathMin(lot, maxLot);

   lot = MathFloor(lot / stepLot) * stepLot;
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Hitung Ukuran Lot (Fixed atau Auto-Compound)                     |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   if(!InpAutoCompoundLot)
      return SanitizeLot(InpLotSize);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0.0) stepLot = 0.01;

   double factor = MathFloor(balance / InpBalancePerMicroLot);
   double calculatedLot = factor * 0.01;
   if(calculatedLot < 0.01) calculatedLot = 0.01;

   return SanitizeLot(calculatedLot);
}

//+------------------------------------------------------------------+
//| Reset Statistik Harian saat Masuk Hari Baru                      |
//+------------------------------------------------------------------+
void CheckAndResetDailyStats()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime todayDate = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00", dt.year, dt.mon, dt.day));
   
   if(todayDate != currentDayDate)
   {
      currentDayDate   = todayDate;
      dailyProfitTotal = 0.0;
      dailyLossTotal   = 0.0;
      dailyTradesCount = 0;
      dailyWinsCount   = 0;
      dailyLossesCount = 0;
      consecutiveLosses= 0;
      streakPauseUntil = 0;
      waitingNewBar    = false;
      Print("[DAILY RESET] Hari baru ", TimeToString(currentDayDate, TIME_DATE), ": Statistik harian di-reset.");
   }
}

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   SetProperFillingMode();

   handleEMA20 = iMA(_Symbol, _Period, InpFastEMAPeriod, 0, MODE_EMA, InpEMAPrice);
   handleEMA50 = iMA(_Symbol, _Period, InpSlowEMAPeriod, 0, MODE_EMA, InpEMAPrice);
   handleRSI   = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   handleATR   = iATR(_Symbol, _Period, InpATRPeriod);

   if(handleEMA20 == INVALID_HANDLE || handleEMA50 == INVALID_HANDLE || 
      handleRSI == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print("[ERROR] Gagal memuat handle indikator MQL5!");
      return(INIT_FAILED);
   }

   LoadAIMemory();
   EventSetTimer(1);

   Print("[INFO] Ratchet AI Trader v5.30 OPTIMIZED Aktif pada ", _Symbol);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   SaveAIMemory();
   Comment("");
}

//+------------------------------------------------------------------+
//| Events: OnTimer & OnTick                                         |
//+------------------------------------------------------------------+
void OnTimer()
{
   CheckAndTradeCore();
}

void OnTick()
{
   CheckAndTradeCore();
}

//+------------------------------------------------------------------+
//| Logika Utama Eksekusi & Trailing Ratchet                         |
//+------------------------------------------------------------------+
void CheckAndTradeCore()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || 
      !MQLInfoInteger(MQL_TRADE_ALLOWED) || 
      !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   {
      lastDiagnosisMsg = "Algo Trading belum diizinkan di Toolbar atau Pengaturan EA!";
      UpdateDashboard();
      return;
   }

   CheckAndResetDailyStats();

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(ask <= 0.0 || bid <= 0.0 || point <= 0.0)
   {
      lastDiagnosisMsg = "Menunggu kuotasi harga Ask/Bid aktif...";
      UpdateDashboard();
      return;
   }

   // Filter Spread Berlebihan
   double currentSpread = (ask - bid) / point;
   if(currentSpread > InpMaxSpreadPoints)
   {
      lastDiagnosisMsg = StringFormat("Spread Melebar: %.1f pts > Max %.1f pts (Menahan Entry)", 
                                     currentSpread, InpMaxSpreadPoints);
      UpdateDashboard();
      return;
   }

   int activePositions = CountActivePositions();

   // 1. CEK PROTEKSI LOSS HARIAN (Hanya jika diaktifkan > 0)
   if(InpDailyLossLimitUSD > 0.0 && dailyLossTotal >= InpDailyLossLimitUSD)
   {
      lastDiagnosisMsg = StringFormat("PAUSED HINGGA BESOK: Batas Loss Harian (-$%.2f / Max $%.2f) Tercapai!", 
                                     dailyLossTotal, InpDailyLossLimitUSD);
      UpdateDashboard();
      return;
   }

   // 2. CEK TARGET PROFIT HARIAN (Hanya jika diaktifkan > 0)
   if(InpDailyProfitTargetUSD > 0.0 && dailyProfitTotal >= InpDailyProfitTargetUSD)
   {
      lastDiagnosisMsg = StringFormat("TARGET HARIAN TERCAPAI: Profit Hari Ini (+$%.2f) Selesai!", dailyProfitTotal);
      UpdateDashboard();
      return;
   }

   // 3. JIKA ADA POSISI AKTIF: JALANKAN MECHANICAL RATCHET TRAILING STOP
   if(activePositions > 0)
   {
      ManageRatchetTrailing(ask, bid, point, digits);
      UpdateDashboard();
      return;
   }

   // 4. JIKA TIDAK ADA POSISI: PERIKSA JEDA COOLDOWN
   datetime now = TimeCurrent();
   datetime currentBarTime = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);

   // A. Anti-Machine Gun Bar Lock: Dilarang buka lebih dari 1 trade di bar yang sama
   if(InpOneTradePerBar && currentBarTime == lastTradeBarTime)
   {
      lastDiagnosisMsg = "Standby: Menunggu Bar M1 Baru (Aturan 1 Trade Per Candle)...";
      UpdateDashboard();
      return;
   }

   // B. Jeda Minimal Antar-Trade
   if(lastTradeClosedTime > 0 && (now < lastTradeClosedTime + InpMinTradeIntervalSec))
   {
      int secLeft = (int)(lastTradeClosedTime + InpMinTradeIntervalSec - now);
      lastDiagnosisMsg = StringFormat("Jeda Antar-Trade: Menstabilkan pergerakan (%d dtk)", secLeft);
      UpdateDashboard();
      return;
   }

   // C. Jeda Streak Pause (jika 4x berturut-turut loss)
   if(now < streakPauseUntil)
   {
      int secLeft = (int)(streakPauseUntil - now);
      lastDiagnosisMsg = StringFormat("PAUSED SEMENTARA: 4x Loss Beruntun. Menunggu pasar stabil (%d dtk)", secLeft);
      UpdateDashboard();
      return;
   }

   // D. Jeda Pasca-Loss Cooldown
   if(now < cooldownUntil)
   {
      int secLeft = (int)(cooldownUntil - now);
      lastDiagnosisMsg = StringFormat("Jeda Pasca Loss: Mencegah revenge trading (%d dtk)", secLeft);
      UpdateDashboard();
      return;
   }

   // E. Wajib Lilin Candlestick Baru Setelah Loss
   if(InpWaitNewBarAfterLoss && waitingNewBar)
   {
      if(currentBarTime <= lossBarTime)
      {
         lastDiagnosisMsg = "Menunggu Candle Baru: Pasca loss, tunggu lilin M1 berikutnya.";
         UpdateDashboard();
         return;
      }
      else
      {
         waitingNewBar = false;
      }
   }

   // 5. EVALUASI SINYAL ENTRY SEARAH TREND (HIGH-PROBABILITY)
   EvaluateAndExecuteEntry(ask, bid, point, digits, currentBarTime);

   // 6. Update Dashboard
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Evaluasi Sinyal & Eksekusi Order Searah Trend                    |
//+------------------------------------------------------------------+
void EvaluateAndExecuteEntry(double ask, double bid, double point, int digits, datetime currentBarTime)
{
   double ema20[];
   double ema50[];
   double rsi[];
   ArraySetAsSeries(ema20, true);
   ArraySetAsSeries(ema50, true);
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(handleEMA20, 0, 0, 2, ema20) < 2 ||
      CopyBuffer(handleEMA50, 0, 0, 2, ema50) < 2 ||
      CopyBuffer(handleRSI, 0, 0, 2, rsi) < 2)
   {
      lastDiagnosisMsg = "Menunggu data buffer indikator terisi...";
      return;
   }

   // Filter Sideways: Periksa Jarak Minimal EMA 20 vs EMA 50
   double emaDistancePoints = MathAbs(ema20[0] - ema50[0]) / point;
   if(emaDistancePoints < InpMinEMADiffPoints)
   {
      lastDiagnosisMsg = StringFormat("Pasar Sideways: Jarak EMA %.1f pts < Min %.1f pts (Menahan Entry)", 
                                     emaDistancePoints, InpMinEMADiffPoints);
      return;
   }

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, _Period, 0, 2, rates) < 2)
   {
      lastDiagnosisMsg = "Menunggu data candle chart...";
      return;
   }

   bool isTrendBullish = (ema20[0] > ema50[0]);
   bool isTrendBearish = (ema20[0] < ema50[0]);

   bool isBar1Bullish = (rates[1].close > rates[1].open);
   bool isBar1Bearish = (rates[1].close < rates[1].open);
   bool isBar0Bullish = (rates[0].close >= rates[0].open);
   bool isBar0Bearish = (rates[0].close <= rates[0].open);

   bool buyCandleConfirmed  = InpUseDualCandleConfirm ? (isBar1Bullish && isBar0Bullish) : isBar0Bullish;
   bool sellCandleConfirmed = InpUseDualCandleConfirm ? (isBar1Bearish && isBar0Bearish) : isBar0Bearish;

   double currentRSI = rsi[0];
   double lot = CalculateLotSize();

   bool signalBuy  = false;
   bool signalSell = false;
   string reason   = "";

   // Logika Sinyal BUY:
   // 1. Trend Bullish (EMA 20 > EMA 50)
   // 2. Dual Candle Hijau
   // 3. RSI sehat: 50 - 70 (momentum bullish) atau rebound oversold <= 30
   if(isTrendBullish && buyCandleConfirmed)
   {
      if((currentRSI >= 50.0 && currentRSI < InpRSIOverbought) || (currentRSI <= InpRSIOversold))
      {
         signalBuy = true;
         reason = StringFormat("Trend Bullish + Dual Hijau + RSI %.1f (Jarak EMA %.1f pts)", 
                               currentRSI, emaDistancePoints);
      }
   }

   // Logika Sinyal SELL:
   // 1. Trend Bearish (EMA 20 < EMA 50)
   // 2. Dual Candle Merah
   // 3. RSI sehat: 30 - 50 (momentum bearish) atau rejection overbought >= 70
   if(isTrendBearish && sellCandleConfirmed)
   {
      if((currentRSI <= 50.0 && currentRSI > InpRSIOversold) || (currentRSI >= InpRSIOverbought))
      {
         signalSell = true;
         reason = StringFormat("Trend Bearish + Dual Merah + RSI %.1f (Jarak EMA %.1f pts)", 
                               currentRSI, emaDistancePoints);
      }
   }

   // EKSEKUSI ORDER BUY DENGAN SL BERI RUANG NAPAS & TP BESAR
   if(signalBuy)
   {
      double slPrice = NormalizeDouble(ask - (InpStopLossPoints * point), digits);
      double tpPrice = NormalizeDouble(ask + (InpTakeProfitPoints * point), digits);

      SetProperFillingMode();
      if(trade.Buy(lot, _Symbol, ask, slPrice, tpPrice, "Ratchet Buy v5.30"))
      {
         lastTradeBarTime    = currentBarTime;
         lastTradeOpenedTime = TimeCurrent();
         Print("[ENTRY BUY SUKSES] Lot: ", lot, " | Harga: ", ask, " | SL: ", slPrice, " (-$", DoubleToString(InpStopLossPoints * point * 10.0, 2), 
               ") | TP: ", tpPrice, " (+$", DoubleToString(InpTakeProfitPoints * point * 10.0, 2), ") | ", reason);
         lastDiagnosisMsg = "Posisi BUY Terbuka: " + reason;
      }
      else
      {
         Print("[GAGAL BUY] Retcode: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
         lastDiagnosisMsg = "Gagal Buka BUY: " + trade.ResultRetcodeDescription();
      }
      return;
   }

   // EKSEKUSI ORDER SELL DENGAN SL BERI RUANG NAPAS & TP BESAR
   if(signalSell)
   {
      double slPrice = NormalizeDouble(bid + (InpStopLossPoints * point), digits);
      double tpPrice = NormalizeDouble(bid - (InpTakeProfitPoints * point), digits);

      SetProperFillingMode();
      if(trade.Sell(lot, _Symbol, bid, slPrice, tpPrice, "Ratchet Sell v5.30"))
      {
         lastTradeBarTime    = currentBarTime;
         lastTradeOpenedTime = TimeCurrent();
         Print("[ENTRY SELL SUKSES] Lot: ", lot, " | Harga: ", bid, " | SL: ", slPrice, " (-$", DoubleToString(InpStopLossPoints * point * 10.0, 2), 
               ") | TP: ", tpPrice, " (+$", DoubleToString(InpTakeProfitPoints * point * 10.0, 2), ") | ", reason);
         lastDiagnosisMsg = "Posisi SELL Terbuka: " + reason;
      }
      else
      {
         Print("[GAGAL SELL] Retcode: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
         lastDiagnosisMsg = "Gagal Buka SELL: " + trade.ResultRetcodeDescription();
      }
      return;
   }

   lastDiagnosisMsg = StringFormat("Standby Mencari Konfirmasi: M1 %s | RSI: %.1f | EMA Diff: %.1f pts", 
                                  (isTrendBullish ? "BULLISH (Wait Buy)" : "BEARISH (Wait Sell)"), currentRSI, emaDistancePoints);
}

//+------------------------------------------------------------------+
//| Mechanical Ratchet Trailing Engine (One-Way Click Lock)          |
//+------------------------------------------------------------------+
void ManageRatchetTrailing(double ask, double bid, double point, int digits)
{
   if(!InpEnableRatchet) return;

   double dynamicTrigger = InpEnableAI ? CalculateAIDistance(InpRatchetTriggerPoints) : (double)InpRatchetTriggerPoints;
   double dynamicLock    = InpEnableAI ? (dynamicTrigger * 0.35) : (double)InpRatchetLockPoints;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentTP = PositionGetDouble(POSITION_TP);

            // A. RATCHET UNTUK POSISI BUY
            if(posType == POSITION_TYPE_BUY)
            {
               double profitPoints = (bid - openPrice) / point;

               if(profitPoints >= dynamicTrigger)
               {
                  double steps = MathFloor((profitPoints - dynamicTrigger) / (double)InpRatchetStepPoints);
                  double lockDistance = dynamicLock + (steps * (double)InpRatchetStepPoints);
                  double targetSL = NormalizeDouble(openPrice + (lockDistance * point), digits);

                  if(targetSL > (currentSL + (InpTrailingStepMin * point)) && targetSL < bid)
                  {
                     if(trade.PositionModify(ticket, targetSL, currentTP))
                     {
                        Print("[RATCHET LOCK BUY] Profit +", DoubleToString(profitPoints, 1), 
                              " pts -> SL Dikunci Maju ke ", targetSL, " (+$", DoubleToString(lockDistance * point * 10.0, 2), " Terkunci Bebas Risiko)");
                     }
                  }
               }
            }

            // B. RATCHET UNTUK POSISI SELL
            else if(posType == POSITION_TYPE_SELL)
            {
               double profitPoints = (openPrice - ask) / point;

               if(profitPoints >= dynamicTrigger)
               {
                  double steps = MathFloor((profitPoints - dynamicTrigger) / (double)InpRatchetStepPoints);
                  double lockDistance = dynamicLock + (steps * (double)InpRatchetStepPoints);
                  double targetSL = NormalizeDouble(openPrice - (lockDistance * point), digits);

                  if((currentSL == 0.0 || targetSL < (currentSL - (InpTrailingStepMin * point))) && targetSL > ask)
                  {
                     if(trade.PositionModify(ticket, targetSL, currentTP))
                     {
                        Print("[RATCHET LOCK SELL] Profit +", DoubleToString(profitPoints, 1), 
                              " pts -> SL Dikunci Maju ke ", targetSL, " (+$", DoubleToString(lockDistance * point * 10.0, 2), " Terkunci Bebas Risiko)");
                     }
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OnTradeTransaction: Deteksi Transaksi Selesai & AI Update        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(HistoryDealSelect(trans.deal))
      {
         long magic    = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
         string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
         long entry    = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

         if(magic == InpMagicNumber && symbol == _Symbol && entry == DEAL_ENTRY_OUT)
         {
            double dealProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
            double dealSwap   = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
            double netPnL     = dealProfit + dealSwap;

            dailyTradesCount++;
            lastTradeClosedTime = TimeCurrent();

            // KASUS PROFIT
            if(netPnL >= 0.0)
            {
               dailyProfitTotal += netPnL;
               dailyWinsCount++;
               consecutiveLosses = 0;
               waitingNewBar = false;
               cooldownUntil = TimeCurrent() + InpMinTradeIntervalSec;

               UpdateAILearning(+1.0 * (netPnL / 1.0));
               Print("[TRADE WIN] Hasil: +$", DoubleToString(netPnL, 2), 
                     " | Total Profit Hari Ini: +$", DoubleToString(dailyProfitTotal, 2));
            }
            // KASUS LOSS
            else
            {
               dailyLossTotal += MathAbs(netPnL);
               dailyLossesCount++;
               consecutiveLosses++;
               waitingNewBar = true;
               lossBarTime = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
               cooldownUntil = TimeCurrent() + InpPostLossCooldownSec;

               if(consecutiveLosses >= InpConsecutiveLossLimit)
               {
                  streakPauseUntil = TimeCurrent() + InpStreakPauseDurationSec;
                  Print("[SAFETY STREAK] 4x Loss Beruntun! Membekukan entry selama ", 
                        InpStreakPauseDurationSec, " detik.");
               }

               UpdateAILearning(-1.0);
               Print("[TRADE LOSS] Hasil: -$ ", DoubleToString(MathAbs(netPnL), 2), 
                     " | Total Loss Hari Ini: -$ ", DoubleToString(dailyLossTotal, 2));
            }

            SaveAIMemory();
         }
      }
   }
}

//====================================================================
//--- OTAK MACHINE LEARNING (Q-LEARNING ALGORITHM)
//====================================================================
double CalculateAIDistance(double basePoints)
{
   double atr[];
   double rsi[];
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(handleATR, 0, 0, 2, atr) < 2 || CopyBuffer(handleRSI, 0, 0, 2, rsi) < 2)
      return basePoints;

   int state = 1;
   if(rsi[0] >= 45.0 && rsi[0] <= 55.0)
      state = 0;
   else if(rsi[0] >= 70.0 || rsi[0] <= 30.0)
      state = 2;

   int chosenAction = 0;
   double randomChance = (double)MathRand() / 32767.0;

   if(randomChance < InpExplorationRate)
   {
      chosenAction = MathRand() % NUM_ACTIONS;
   }
   else
   {
      double bestQ = QTable[state][0];
      for(int a = 1; a < NUM_ACTIONS; a++)
      {
         if(QTable[state][a] > bestQ)
         {
            bestQ = QTable[state][a];
            chosenAction = a;
         }
      }
   }

   lastState  = state;
   lastAction = chosenAction;

   double dynamicCalculated = basePoints * ActionMultipliers[chosenAction];
   currentDynamicDistance = MathMax(dynamicCalculated, 80.0);
   return currentDynamicDistance;
}

void UpdateAILearning(double reward)
{
   if(!InpEnableAI) return;

   double currentQ = QTable[lastState][lastAction];
   QTable[lastState][lastAction] = currentQ + InpLearningRate * (reward - currentQ);

   Print("[AI UPDATE] State: ", lastState, " | Mult: ", ActionMultipliers[lastAction], 
         "x | Reward: ", reward, " | Bobot Q: ", DoubleToString(QTable[lastState][lastAction], 4));
}

void SaveAIMemory()
{
   int handle = FileOpen(memoryFile, FILE_WRITE | FILE_BIN);
   if(handle != INVALID_HANDLE)
   {
      FileWriteArray(handle, QTable);
      FileClose(handle);
   }
}

void LoadAIMemory()
{
   if(FileIsExist(memoryFile))
   {
      int handle = FileOpen(memoryFile, FILE_READ | FILE_BIN);
      if(handle != INVALID_HANDLE)
      {
         FileReadArray(handle, QTable);
         FileClose(handle);
         Print("[AI] Memori Q-Table berhasil dimuat dari ", memoryFile);
         return;
      }
   }
   ArrayInitialize(QTable, 0.0);
}

//====================================================================
//--- UTILITIES & DASHBOARD
//====================================================================
int CountActivePositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            count++;
      }
   }
   return count;
}

double GetCurrentPositionFloating()
{
   double profit = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            profit += (PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP));
      }
   }
   return profit;
}

void UpdateDashboard()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double floating= GetCurrentPositionFloating();
   int    active  = CountActivePositions();

   double netDailyPnL = dailyProfitTotal - dailyLossTotal;
   double winRate = (dailyTradesCount > 0) ? ((double)dailyWinsCount / (double)dailyTradesCount) * 100.0 : 0.0;

   string stateDesc = (lastState == 0) ? "Sideways / Tenang" : (lastState == 1) ? "Normal Trending" : "Volatilitas Tinggi";

   string dashboard = "";
   dashboard += "=====================================================\n";
   dashboard += "   RATCHET AI TRADER v5.30 (OPTIMIZED HIGH-YIELD)    \n";
   dashboard += "=====================================================\n";
   dashboard += StringFormat("Saldo / Equity: $%.2f / $%.2f | Margin Free: $%.2f\n", 
                             balance, equity, AccountInfoDouble(ACCOUNT_MARGIN_FREE));
   dashboard += StringFormat("Posisi Aktif: %d / %d | Floating PnL: $%.2f\n", active, InpMaxPositions, floating);
   dashboard += StringFormat("Target TP: +$%.2f (350 pts) | SL Floor: -$%.2f (220 pts)\n", 
                             (double)InpTakeProfitPoints * 0.01, (double)InpStopLossPoints * 0.01);
   dashboard += "-----------------------------------------------------\n";
   dashboard += StringFormat("Performa Hari Ini: %d Trade (%d Win / %d Loss) | Win Rate: %.1f%%\n", 
                             dailyTradesCount, dailyWinsCount, dailyLossesCount, winRate);
   dashboard += StringFormat("Net PnL Hari Ini: $%.2f (Profit: +$%.2f | Loss: -$%.2f)\n", 
                             netDailyPnL, dailyProfitTotal, dailyLossTotal);
   dashboard += "-----------------------------------------------------\n";
   dashboard += StringFormat("Adaptasi AI (State %d): %s | Multiplier: %.2fx\n", 
                             lastState, stateDesc, ActionMultipliers[lastAction]);
   dashboard += StringFormat("Trigger Ratchet: %.0f pts (+$%.2f) | Lock: +$0.40 | Step: %d pts\n", 
                             currentDynamicDistance, currentDynamicDistance * 0.01, InpRatchetStepPoints);
   dashboard += "-----------------------------------------------------\n";
   dashboard += StringFormat("STATUS SISTEM: %s\n", lastDiagnosisMsg);
   dashboard += "=====================================================\n";

   Comment(dashboard);
}
