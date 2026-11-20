//+------------------------------------------------------------------+
//|                                        Ratchet_AI_Trader.mq5     |
//|                             Copyright 2026, Quantitative EA Dev |
//|                                             https://trade.local |
//+------------------------------------------------------------------+
#property copyright   "Quantitative EA Dev"
#property link        "https://trade.local"
#property version     "3.10"
#property description "FULL AUTO: Single One-Way Ratchet Trailing Limit EA with Q-Learning AI"
#property description "Hanya 1 Limit Order (Buy Limit ATAU Sell Limit). Trailing Searah (Ratchet)."

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
//--- ENUM MODE AUTO-START (HANYA 1 ORDER, TIDAK PERNAH KEDUANYA)
//====================================================================
enum ENUM_AUTO_START_MODE
{
   AUTO_AI_MARKET_CHOICE = 0, // AI / Indikator Memilih 1 Arah Saja (RSI Overbought=Sell Limit, Oversold=Buy Limit)
   AUTO_ONLY_BUY_LIMIT   = 1, // HANYA Pasang 1 Buy Limit (Mencari Dasar Pantulan)
   AUTO_ONLY_SELL_LIMIT  = 2  // HANYA Pasang 1 Sell Limit (Mencari Pucuk Pantulan)
};

//====================================================================
//--- INPUT PARAMETERS
//====================================================================
sinput string               Section_Auto         = "====== SISTEM OTOMATIS (TUNGGAL) ======";
input ENUM_AUTO_START_MODE  InpAutoStartMode     = AUTO_AI_MARKET_CHOICE; // Pilihan 1 Order Pertama
input int                   InpCooldownSeconds   = 5;                     // Jeda Detik Sebelum Siklus Baru

sinput string               Section_Trading      = "====== PENGATURAN ORDER ======";
input double                InpLotSize           = 0.01;                  // Ukuran Lot
input int                   InpLimitDistanceMin  = 150;                   // Jarak Minimum Limit (Points)
input int                   InpTrailingStep      = 20;                    // Min Pergeseran Harga utk Geser Limit (Points)
input int                   InpMaxPositions      = 5;                     // Batas Maksimal Posisi Aktif (Max Layer)
input ulong                 InpMagicNumber       = 889933;                // Magic Number Unik EA

sinput string               Section_Target       = "====== TARGET & PENGAMAN MODAL ======";
input double                InpTargetProfitUSD   = 5.0;                   // Target Profit Basket Close All ($)
input double                InpMaxDrawdownUSD    = 50.0;                  // Hard Cut Loss / Stop Darurat ($ total rugi)
input int                   InpSlippagePoints    = 30;                    // Maksimal Deviasi / Slippage (Points)

sinput string               Section_AI           = "====== PARAMETER Q-LEARNING (AI) ======";
input bool                  InpEnableAI          = true;                  // Aktifkan Otak Machine Learning
input int                   InpATRPeriod         = 14;                    // Periode ATR (Mengukur Volatilitas)
input int                   InpRSIPeriod         = 14;                    // Periode RSI (Mengukur Momentum)
input double                InpLearningRate      = 0.15;                  // Learning Rate (Alpha: 0.05 - 0.3)
input double                InpExplorationRate   = 0.10;                  // Exploration Rate (Epsilon: 10% peluang coba jarak baru)

//====================================================================
//--- VARIABEL GLOBAL & MATRIKS Q-LEARNING
//====================================================================
#define NUM_STATES   3
#define NUM_ACTIONS  4

double QTable[NUM_STATES][NUM_ACTIONS];
double ActionMultipliers[NUM_ACTIONS] = {0.75, 1.25, 1.75, 2.50};

int      lastState              = 1;
int      lastAction             = 1;
double   currentDynamicDistance = 200.0;
datetime lastCycleCloseTime     = 0;

int    handleATR = INVALID_HANDLE;
int    handleRSI = INVALID_HANDLE;
string memoryFile = "Ratchet_AI_Memory_" + _Symbol + ".bin";

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   handleATR = iATR(_Symbol, _Period, InpATRPeriod);
   handleRSI = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);

   if(handleATR == INVALID_HANDLE || handleRSI == INVALID_HANDLE)
   {
      Print("[ERROR] Gagal memuat indikator ATR atau RSI!");
      return(INIT_FAILED);
   }

   LoadAIMemory();

   Print("[INFO] Ratchet AI Trader FULL AUTO (SINGLE LIMIT) Aktif pada ", _Symbol);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   SaveAIMemory();
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // StopLevel compliance
   long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDistanceRequired = (stopLevel > 0) ? (double)stopLevel : (double)InpLimitDistanceMin;
   if(minDistanceRequired < (double)InpLimitDistanceMin)
      minDistanceRequired = (double)InpLimitDistanceMin;

   int activePositions = CountActivePositions();
   int pendingOrders   = CountPendingOrders();
   double currentBasketProfit = CalculateBasketProfit();

   // 1. MONITOR TARGET PROFIT & EMERGENCY CUTOFF
   if(activePositions > 0)
   {
      // Target Profit Basket Tercapai -> Close All & Re-learn
      if(currentBasketProfit >= InpTargetProfitUSD)
      {
         Print("[PROFIT] Target Profit Tercapai: +$", DoubleToString(currentBasketProfit, 2), " -> Tutup Semua Posisi.");
         CloseAllPositionsAndOrders();
         UpdateAILearning(1.0);
         lastCycleCloseTime = TimeCurrent();
         return;
      }

      // Hard Drawdown Cutoff Tercapai -> Emergency Cut Loss
      if(currentBasketProfit <= -InpMaxDrawdownUSD)
      {
         Print("[EMERGENCY] Max Drawdown Tercapai: -$", DoubleToString(currentBasketProfit, 2), " -> Cut Loss Darurat!");
         CloseAllPositionsAndOrders();
         UpdateAILearning(-1.5);
         lastCycleCloseTime = TimeCurrent();
         return;
      }
   }

   // 2. OTOMATISASI INITIAL ENTRY: HANYA PASANG 1 PENDING ORDER
   // Hanya pasang jika TIDAK ADA posisi aktif DAN TIDAK ADA pending order sama sekali
   if(activePositions == 0 && pendingOrders == 0)
   {
      if(TimeCurrent() - lastCycleCloseTime >= InpCooldownSeconds)
      {
         ExecuteSingleInitialLimit(ask, bid, point, digits, minDistanceRequired);
      }
   }

   // 3. LOGIKA RATCHET TRAILING PENDING ORDER (Hanya 1 order yang berjalan)
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagicNumber)
         {
            ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            double currentPrice = OrderGetDouble(ORDER_PRICE_OPEN);

            // A. BUY LIMIT: Hanya boleh IKUT TURUN, TIDAK BOLEH IKUT NAIK
            if(orderType == ORDER_TYPE_BUY_LIMIT)
            {
               double distanceToUse = MathMax(currentDynamicDistance, minDistanceRequired);
               double newTargetPrice = NormalizeDouble(ask - (distanceToUse * point), digits);

               if(newTargetPrice < (currentPrice - (InpTrailingStep * point)))
               {
                  trade.OrderModify(ticket, newTargetPrice, 0, 0, ORDER_TIME_GTC, 0);
               }
            }

            // B. SELL LIMIT: Hanya boleh IKUT NAIK, TIDAK BOLEH IKUT TURUN
            else if(orderType == ORDER_TYPE_SELL_LIMIT)
            {
               double distanceToUse = MathMax(currentDynamicDistance, minDistanceRequired);
               double newTargetPrice = NormalizeDouble(bid + (distanceToUse * point), digits);

               if(newTargetPrice > (currentPrice + (InpTrailingStep * point)))
               {
                  trade.OrderModify(ticket, newTargetPrice, 0, 0, ORDER_TIME_GTC, 0);
               }
            }
         }
      }
   }

   // 4. Update Dashboard Tampilan di Chart
   UpdateDashboard(currentBasketProfit, activePositions, pendingOrders);
}

//+------------------------------------------------------------------+
//| Pasang HANYA SATU Pending Order di Awal (Bukan Keduanya)         |
//+------------------------------------------------------------------+
void ExecuteSingleInitialLimit(double ask, double bid, double point, int digits, double minDistanceRequired)
{
   currentDynamicDistance = InpEnableAI ? CalculateAIDistance() : InpLimitDistanceMin;
   double effectiveDist = MathMax(currentDynamicDistance, minDistanceRequired);

   switch(InpAutoStartMode)
   {
      case AUTO_AI_MARKET_CHOICE:
      {
         double rsi[1];
         ArraySetAsSeries(rsi, true);
         CopyBuffer(handleRSI, 0, 0, 1, rsi);

         // Jika RSI >= 50: Pasar di atas, HANYA pasang 1 Sell Limit di atas pucuk
         // Jika RSI < 50:  Pasar di bawah, HANYA pasang 1 Buy Limit di dasar lembah
         if(rsi[0] >= 50.0)
         {
            double sellPrice = NormalizeDouble(bid + (effectiveDist * point), digits);
            trade.SellLimit(InpLotSize, sellPrice, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "Initial Sell Limit");
            Print("[INITIAL ENTRY] Pasar cenderung Naik (RSI ", DoubleToString(rsi[0], 1), ") -> HANYA pasang 1 Sell Limit di ", sellPrice);
         }
         else
         {
            double buyPrice = NormalizeDouble(ask - (effectiveDist * point), digits);
            trade.BuyLimit(InpLotSize, buyPrice, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "Initial Buy Limit");
            Print("[INITIAL ENTRY] Pasar cenderung Turun (RSI ", DoubleToString(rsi[0], 1), ") -> HANYA pasang 1 Buy Limit di ", buyPrice);
         }
         break;
      }

      case AUTO_ONLY_BUY_LIMIT:
      {
         double buyPrice = NormalizeDouble(ask - (effectiveDist * point), digits);
         trade.BuyLimit(InpLotSize, buyPrice, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "Initial Buy Limit");
         Print("[INITIAL ENTRY] HANYA pasang 1 Buy Limit di ", buyPrice);
         break;
      }

      case AUTO_ONLY_SELL_LIMIT:
      {
         double sellPrice = NormalizeDouble(bid + (effectiveDist * point), digits);
         trade.SellLimit(InpLotSize, sellPrice, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "Initial Sell Limit");
         Print("[INITIAL ENTRY] HANYA pasang 1 Sell Limit di ", sellPrice);
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| OnTradeTransaction: Deteksi Saat Pending Order Kena Menjadi Posisi|
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
         long dealType = HistoryDealGetInteger(trans.deal, DEAL_TYPE);

         if(magic == InpMagicNumber && symbol == _Symbol && entry == DEAL_ENTRY_IN)
         {
            // Cek batas maksimal posisi (Max Layers)
            if(CountActivePositions() >= InpMaxPositions)
            {
               Print("[WARNING] Batas Max Posisi (", InpMaxPositions, ") tercapai. Menahan limit baru.");
               return;
            }

            // Pastikan tidak ada pending order lain (selalu strictly 1 pending order)
            if(CountPendingOrders() > 0)
               return;

            currentDynamicDistance = InpEnableAI ? CalculateAIDistance() : InpLimitDistanceMin;

            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

            long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
            double effectiveDist = MathMax(currentDynamicDistance, (double)stopLevel);
            effectiveDist = MathMax(effectiveDist, (double)InpLimitDistanceMin);

            // KASUS 1: Order SELL LIMIT kena -> Sekarang posisi SELL aktif.
            // Respons EA: Pasang HANYA 1 BUY LIMIT di bawah yang HANYA IKUT TURUN (tidak ikut naik).
            if(dealType == DEAL_TYPE_SELL)
            {
               double targetPrice = NormalizeDouble(ask - (effectiveDist * point), digits);
               trade.BuyLimit(InpLotSize, targetPrice, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "Ratchet Buy Limit");
               Print("[RATCHET LIMIT] Posisi SELL aktif -> Pasang HANYA 1 Buy Limit di ", targetPrice, " (hanya ikut turun)");
            }
            // KASUS 2: Order BUY LIMIT kena -> Sekarang posisi BUY aktif.
            // Respons EA: Pasang HANYA 1 SELL LIMIT di atas yang HANYA IKUT NAIK (tidak ikut turun).
            else if(dealType == DEAL_TYPE_BUY)
            {
               double targetPrice = NormalizeDouble(bid + (effectiveDist * point), digits);
               trade.SellLimit(InpLotSize, targetPrice, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "Ratchet Sell Limit");
               Print("[RATCHET LIMIT] Posisi BUY aktif -> Pasang HANYA 1 Sell Limit di ", targetPrice, " (hanya ikut naik)");
            }
         }
      }
   }
}

//====================================================================
//--- OTAK MACHINE LEARNING (Q-LEARNING ALGORITHM)
//====================================================================
double CalculateAIDistance()
{
   double atr[2], rsi[2];
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(handleATR, 0, 0, 2, atr) < 2 || CopyBuffer(handleRSI, 0, 0, 2, rsi) < 2)
      return (double)InpLimitDistanceMin;

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

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double rawPointsFromATR = (atr[0] / point) * ActionMultipliers[chosenAction];

   return MathMax(rawPointsFromATR, (double)InpLimitDistanceMin);
}

void UpdateAILearning(double reward)
{
   if(!InpEnableAI) return;

   double currentQ = QTable[lastState][lastAction];
   QTable[lastState][lastAction] = currentQ + InpLearningRate * (reward - currentQ);

   Print("[AI UPDATE] State: ", lastState, " | Mult: ", ActionMultipliers[lastAction], 
         "x | Reward: ", reward, " | Bobot Q Baru: ", DoubleToString(QTable[lastState][lastAction], 4));

   SaveAIMemory();
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
double CalculateBasketProfit()
{
   double total = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            total += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         }
      }
   }
   return total;
}

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

int CountPendingOrders()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagicNumber)
            count++;
      }
   }
   return count;
}

void CloseAllPositionsAndOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagicNumber)
            trade.OrderDelete(ticket);
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            trade.PositionClose(ticket);
      }
   }
}

void UpdateDashboard(double basketProfit, int layers, int pendings)
{
   string stateDesc = (lastState == 0) ? "Sideways/Calm" : (lastState == 1) ? "Normal" : "High Volatility/RSI Extreme";
   
   string dashboard = "";
   dashboard += "=====================================================\n";
   dashboard += "   RATCHET TRAILING LIMIT (SINGLE ORDER AI v3.1)    \n";
   dashboard += "=====================================================\n";
   dashboard += StringFormat("Symbol / Magic: %s / %d\n", _Symbol, InpMagicNumber);
   dashboard += StringFormat("Posisi Aktif: %d / %d | Pending Aktif (Maks 1): %d\n", layers, InpMaxPositions, pendings);
   dashboard += StringFormat("Floating Basket Profit: $%.2f (Target: +$%.2f | Cut Loss: -$%.2f)\n", 
                             basketProfit, InpTargetProfitUSD, InpMaxDrawdownUSD);
   dashboard += "-----------------------------------------------------\n";
   dashboard += StringFormat("Kondisi Pasar (State): %s (State %d)\n", stateDesc, lastState);
   dashboard += StringFormat("Pengali ATR AI: %.2fx (Jarak Dinamis: %.0f points)\n", 
                             ActionMultipliers[lastAction], currentDynamicDistance);
   dashboard += "Mode: Strictly Single Limit (Bukan Dua-duanya)\n";
   dashboard += "=====================================================\n";

   Comment(dashboard);
}
