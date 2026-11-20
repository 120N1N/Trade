//+------------------------------------------------------------------+
//|                                        Ratchet_AI_Trader.mq5     |
//|                             Copyright 2026, Quantitative EA Dev |
//|                                             https://trade.local |
//+------------------------------------------------------------------+
#property copyright   "Quantitative EA Dev"
#property link        "https://trade.local"
#property version     "3.20"
#property description "FULL AUTO: Single One-Way Ratchet Trailing Limit EA with Q-Learning AI"
#property description "Auto Diagnostics: Auto Filling Mode, Broker StopLevel Compliance, Live Logging"

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
//--- ENUM MODE AUTO-START (HANYA 1 ORDER TUNGGAL)
//====================================================================
enum ENUM_AUTO_START_MODE
{
   AUTO_AI_MARKET_CHOICE = 0, // AI / RSI Memilih 1 Arah Saja (RSI >= 50: Sell Limit, RSI < 50: Buy Limit)
   AUTO_ONLY_BUY_LIMIT   = 1, // HANYA Pasang 1 Buy Limit
   AUTO_ONLY_SELL_LIMIT  = 2  // HANYA Pasang 1 Sell Limit
};

//====================================================================
//--- INPUT PARAMETERS
//====================================================================
sinput string               Section_Auto         = "====== SISTEM OTOMATIS (TUNGGAL) ======";
input ENUM_AUTO_START_MODE  InpAutoStartMode     = AUTO_AI_MARKET_CHOICE; // Pilihan 1 Order Pertama
input int                   InpCooldownSeconds   = 3;                     // Jeda Detik Sebelum Siklus Baru

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
input double                InpExplorationRate   = 0.10;                  // Exploration Rate (Epsilon: 10% coba jarak baru)

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
string   lastDiagnosisMsg       = "Normal";

int    handleATR = INVALID_HANDLE;
int    handleRSI = INVALID_HANDLE;
string memoryFile = "Ratchet_AI_Memory_" + _Symbol + ".bin";

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
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   SetProperFillingMode();

   handleATR = iATR(_Symbol, _Period, InpATRPeriod);
   handleRSI = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);

   if(handleATR == INVALID_HANDLE || handleRSI == INVALID_HANDLE)
   {
      Print("[ERROR] Gagal memuat indikator ATR atau RSI!");
      return(INIT_FAILED);
   }

   LoadAIMemory();

   Print("[INFO] Ratchet AI Trader FULL AUTO v3.20 Berhasil Dimuat pada ", _Symbol);
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
   // 1. DIAGNOSA KESIAPAN TRADING OTOMATIS
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      lastDiagnosisMsg = "PERINGATAN: Tombol Algo Trading di Toolbar MT5 masih NONAKTIF (Merah)! Silakan KLIK tombol Algo Trading agar HIJAU.";
      UpdateDashboard(0, 0, 0);
      return;
   }
   if(!MqlInfoInteger(MQL_TRADE_ALLOWED))
   {
      lastDiagnosisMsg = "PERINGATAN: Opsi 'Allow Algo Trading' pada Tab Common EA belum dicentang! Tekan F7 di chart lalu centang.";
      UpdateDashboard(0, 0, 0);
      return;
   }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   {
      lastDiagnosisMsg = "PERINGATAN: Akun ini tidak diizinkan trading oleh broker (Cek password investor/read-only).";
      UpdateDashboard(0, 0, 0);
      return;
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(ask <= 0.0 || bid <= 0.0)
   {
      lastDiagnosisMsg = "Menunggu kuotasi harga Ask/Bid dari broker...";
      UpdateDashboard(0, 0, 0);
      return;
   }

   // StopLevel compliance (Jarak minimal pending order)
   long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDistanceRequired = (stopLevel > 0) ? (double)stopLevel : (double)InpLimitDistanceMin;
   if(minDistanceRequired < (double)InpLimitDistanceMin)
      minDistanceRequired = (double)InpLimitDistanceMin;

   int activePositions = CountActivePositions();
   int pendingOrders   = CountPendingOrders();
   double currentBasketProfit = CalculateBasketProfit();

   // 2. MONITOR BASKET PROFIT & DRAWDOWN
   if(activePositions > 0)
   {
      if(currentBasketProfit >= InpTargetProfitUSD)
      {
         Print("[PROFIT] Target Basket Profit Tercapai: +$", DoubleToString(currentBasketProfit, 2), " -> Tutup Semua Posisi.");
         CloseAllPositionsAndOrders();
         UpdateAILearning(1.0);
         lastCycleCloseTime = TimeCurrent();
         lastDiagnosisMsg = "Basket Profit Tercapai! Menutup semua posisi.";
         return;
      }

      if(currentBasketProfit <= -InpMaxDrawdownUSD)
      {
         Print("[EMERGENCY] Max Drawdown Tercapai: -$", DoubleToString(currentBasketProfit, 2), " -> Cut Loss Darurat!");
         CloseAllPositionsAndOrders();
         UpdateAILearning(-1.5);
         lastCycleCloseTime = TimeCurrent();
         lastDiagnosisMsg = "Max Drawdown Tersentuh! Cut Loss darurat dilakukan.";
         return;
      }
   }

   // 3. AUTO INITIAL ENTRY: PASANG HANYA 1 LIMIT ORDER
   if(activePositions == 0 && pendingOrders == 0)
   {
      if(TimeCurrent() - lastCycleCloseTime >= InpCooldownSeconds)
      {
         lastDiagnosisMsg = "Menganalisis pasar & memasang 1 Pending Order perdana...";
         ExecuteSingleInitialLimit(ask, bid, point, digits, minDistanceRequired);
      }
      else
      {
         lastDiagnosisMsg = StringFormat("Jeda Cooldown (%d detik tersisa)...", 
                                        InpCooldownSeconds - (int)(TimeCurrent() - lastCycleCloseTime));
      }
   }
   else if(activePositions > 0)
   {
      lastDiagnosisMsg = StringFormat("Posisi Berjalan (%d aktif) | Memantau Basket TP +$%.2f", 
                                     activePositions, InpTargetProfitUSD);
   }
   else if(pendingOrders > 0)
   {
      lastDiagnosisMsg = "Menunggu Pending Limit tersentuh harga...";
   }

   // 4. LOGIKA RATCHET TRAILING SATU ARAH
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
                  if(!trade.OrderModify(ticket, newTargetPrice, 0, 0, ORDER_TIME_GTC, 0))
                  {
                     Print("[WARN] Gagal geser Buy Limit! Retcode: ", trade.ResultRetcode(), " (", trade.ResultRetcodeDescription(), ")");
                  }
               }
            }

            // B. SELL LIMIT: Hanya boleh IKUT NAIK, TIDAK BOLEH IKUT TURUN
            else if(orderType == ORDER_TYPE_SELL_LIMIT)
            {
               double distanceToUse = MathMax(currentDynamicDistance, minDistanceRequired);
               double newTargetPrice = NormalizeDouble(bid + (distanceToUse * point), digits);

               if(newTargetPrice > (currentPrice + (InpTrailingStep * point)))
               {
                  if(!trade.OrderModify(ticket, newTargetPrice, 0, 0, ORDER_TIME_GTC, 0))
                  {
                     Print("[WARN] Gagal geser Sell Limit! Retcode: ", trade.ResultRetcode(), " (", trade.ResultRetcodeDescription(), ")");
                  }
               }
            }
         }
      }
   }

   // 5. Update Dashboard Tampilan di Chart
   UpdateDashboard(currentBasketProfit, activePositions, pendingOrders);
}

//+------------------------------------------------------------------+
//| Pasang HANYA SATU Pending Order di Awal                          |
//+------------------------------------------------------------------+
void ExecuteSingleInitialLimit(double ask, double bid, double point, int digits, double minDistanceRequired)
{
   currentDynamicDistance = InpEnableAI ? CalculateAIDistance() : InpLimitDistanceMin;
   double effectiveDist = MathMax(currentDynamicDistance, minDistanceRequired);
   double lot = SanitizeLot(InpLotSize);

   SetProperFillingMode();

   switch(InpAutoStartMode)
   {
      case AUTO_AI_MARKET_CHOICE:
      {
         double rsi[1];
         ArraySetAsSeries(rsi, true);
         int copied = CopyBuffer(handleRSI, 0, 0, 1, rsi);

         // Jika RSI belum siap, gunakan default 50
         double rsiVal = (copied > 0) ? rsi[0] : 50.0;

         if(rsiVal >= 50.0)
         {
            double sellPrice = NormalizeDouble(bid + (effectiveDist * point), digits);
            if(trade.SellLimit(lot, sellPrice, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "Initial Sell Limit"))
            {
               Print("[BERHASIL] 1 Sell Limit dipasang di ", sellPrice, " | RSI: ", DoubleToString(rsiVal, 1));
            }
            else
            {
               Print("[GAGAL PASANG SELL LIMIT] Retcode: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
               lastDiagnosisMsg = "Order Gagal: " + trade.ResultRetcodeDescription();
            }
         }
         else
         {
            double buyPrice = NormalizeDouble(ask - (effectiveDist * point), digits);
            if(trade.BuyLimit(lot, buyPrice, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "Initial Buy Limit"))
            {
               Print("[BERHASIL] 1 Buy Limit dipasang di ", buyPrice, " | RSI: ", DoubleToString(rsiVal, 1));
            }
            else
            {
               Print("[GAGAL PASANG BUY LIMIT] Retcode: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
               lastDiagnosisMsg = "Order Gagal: " + trade.ResultRetcodeDescription();
            }
         }
         break;
      }

      case AUTO_ONLY_BUY_LIMIT:
      {
         double buyPrice = NormalizeDouble(ask - (effectiveDist * point), digits);
         if(trade.BuyLimit(lot, buyPrice, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "Initial Buy Limit"))
         {
            Print("[BERHASIL] 1 Buy Limit dipasang di ", buyPrice);
         }
         else
         {
            Print("[GAGAL PASANG BUY LIMIT] Retcode: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
            lastDiagnosisMsg = "Order Gagal: " + trade.ResultRetcodeDescription();
         }
         break;
      }

      case AUTO_ONLY_SELL_LIMIT:
      {
         double sellPrice = NormalizeDouble(bid + (effectiveDist * point), digits);
         if(trade.SellLimit(lot, sellPrice, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "Initial Sell Limit"))
         {
            Print("[BERHASIL] 1 Sell Limit dipasang di ", sellPrice);
         }
         else
         {
            Print("[GAGAL PASANG SELL LIMIT] Retcode: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
            lastDiagnosisMsg = "Order Gagal: " + trade.ResultRetcodeDescription();
         }
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
            if(CountActivePositions() >= InpMaxPositions)
            {
               Print("[WARNING] Batas Max Posisi (", InpMaxPositions, ") tercapai. Menahan limit baru.");
               return;
            }

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
            double lot = SanitizeLot(InpLotSize);

            SetProperFillingMode();

            // POSISI SELL AKTIF -> Pasang HANYA 1 Buy Limit di bawah yang hanya boleh geser turun
            if(dealType == DEAL_TYPE_SELL)
            {
               double targetPrice = NormalizeDouble(ask - (effectiveDist * point), digits);
               if(trade.BuyLimit(lot, targetPrice, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "Ratchet Buy Limit"))
               {
                  Print("[ORDER RATCHET] Posisi SELL aktif -> Pasang Buy Limit di ", targetPrice, " (Hanya ikut turun)");
               }
               else
               {
                  Print("[GAGAL PASANG RATCHET BUY LIMIT] Retcode: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
               }
            }
            // POSISI BUY AKTIF -> Pasang HANYA 1 Sell Limit di atas yang hanya boleh geser naik
            else if(dealType == DEAL_TYPE_BUY)
            {
               double targetPrice = NormalizeDouble(bid + (effectiveDist * point), digits);
               if(trade.SellLimit(lot, targetPrice, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "Ratchet Sell Limit"))
               {
                  Print("[ORDER RATCHET] Posisi BUY aktif -> Pasang Sell Limit di ", targetPrice, " (Hanya ikut naik)");
               }
               else
               {
                  Print("[GAGAL PASANG RATCHET SELL LIMIT] Retcode: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
               }
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
   dashboard += "   RATCHET TRAILING LIMIT (SINGLE ORDER AI v3.2)    \n";
   dashboard += "=====================================================\n";
   dashboard += StringFormat("Symbol / Magic: %s / %d\n", _Symbol, InpMagicNumber);
   dashboard += StringFormat("Posisi Aktif: %d / %d | Pending Aktif: %d\n", layers, InpMaxPositions, pendings);
   dashboard += StringFormat("Floating Basket Profit: $%.2f (Target: +$%.2f | Cut Loss: -$%.2f)\n", 
                             basketProfit, InpTargetProfitUSD, InpMaxDrawdownUSD);
   dashboard += "-----------------------------------------------------\n";
   dashboard += StringFormat("Kondisi Pasar (State): %s (State %d)\n", stateDesc, lastState);
   dashboard += StringFormat("Pengali ATR AI: %.2fx (Jarak Dinamis: %.0f points)\n", 
                             ActionMultipliers[lastAction], currentDynamicDistance);
   dashboard += "-----------------------------------------------------\n";
   dashboard += StringFormat("STATUS EA: %s\n", lastDiagnosisMsg);
   dashboard += "=====================================================\n";

   Comment(dashboard);
}
