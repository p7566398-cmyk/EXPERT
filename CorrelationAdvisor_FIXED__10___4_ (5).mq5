//+------------------------------------------------------------------+
//|                                         CorrelationAdvisor.mq5  |
//|                                    Correlation EA for MT5        |
//|                                         Version 1.1              |
//+------------------------------------------------------------------+
#property copyright "Correlation Advisor"
#property link      ""
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Перечисления
enum ENUM_DIRECTION    { DIR_BUY = 0, DIR_SELL = 1 };
enum ENUM_CORRELATION  { CORR_DIRECT = 0, CORR_INVERSE = 1 };
enum ENUM_EA_STATE     { STATE_STANDBY = 0, STATE_RUNNING = 1, STATE_STOPPED = 2 };
enum ENUM_BLOCK_STATE  { BLOCK_IDLE = 0, BLOCK_PHASE1 = 1, BLOCK_PHASE2 = 2, BLOCK_DONE = 3 };

//============================================================
//  ВХОДНЫЕ ПАРАМЕТРЫ
//============================================================
input group "=== ОБЩИЕ НАСТРОЙКИ ==="
input bool   InpAutoRestart     = false;    // Автоперезапуск ON/OFF
input double InpStopPercent     = 0.3;      // STOP % профит депозита
input string InpStopTime        = "23:00";  // STOP TIME (HH:MM)
input double InpStopDepoPercent = -30.0;    // STOP DEPO % просадка депозита
input double InpB1ClosePercent  = 0.5;      // CLOSE % блок 1 (от TP)
input double InpB2ClosePercent  = 0.5;      // CLOSE % блок 2 (от TP)

input group "=== ОБЩИЕ ПАРАМЕТРЫ СЕТОВ (используются когда ALL SET = ON) ==="
input double InpAllMainLot  = 0.10;   // ALL: лот основной
input double InpAllCorrLot  = 0.10;   // ALL: лот корреляционный
input double InpAllSafeLot  = 0.03;   // ALL: лот SAFE
input double InpAllE1Lot    = 0.03;   // ALL: лот EXTRA 1
input double InpAllE2Lot    = 0.03;   // ALL: лот EXTRA 2
input double InpAllE3Lot    = 0.04;   // ALL: лот EXTRA 3
input int    InpAllTP       = 100;    // ALL: TP (пункты)
input int    InpAllSL       = 120;    // ALL: SL (пункты)
input double InpAllExtThr   = 60.0;   // ALL: SL EXTRA %
input double InpAllExtDev   = 10.0;   // ALL: ШАГ EXTRA %
input double InpAllExtCls   = 0.8;    // ALL: закрытие EXTRA %

input group "=== АВТОЛОТ (используется когда A-LOT = ON) ==="
input double InpALotDivisor = 1000.0; // A-LOT: делитель депозита (депозит/N = mainLot)
input double InpALotSafeDiv = 2.5;    // A-LOT: кратность SAFE меньше MAIN (mainLot/N = safeLot)

input group "=== CORR АВТОПИЛОТ — СЕТЫ ==="
// 4 сета: 2 для Sym1 (buy/sell), 2 для Sym2 (buy/sell)
// Имя сета используется только для отображения — должно содержать "buy" или "sell"
input string InpSet1MainPair= "EURUSD";      // Сет 1: основная пара
input string InpSet1CorrPair= "USDCHF";      // Сет 1: корреляционная пара
input ENUM_DIRECTION InpSet1Direction  = DIR_BUY;       // Сет 1: направление
input ENUM_CORRELATION InpSet1Corr     = CORR_INVERSE;  // Сет 1: корреляция

input group "--- Сет 2 ---"
input string InpSet2MainPair= "EURUSD";      // Сет 2: основная пара
input string InpSet2CorrPair= "USDCHF";      // Сет 2: корреляционная пара
input ENUM_DIRECTION InpSet2Direction  = DIR_SELL;      // Сет 2: направление
input ENUM_CORRELATION InpSet2Corr     = CORR_INVERSE;  // Сет 2: корреляция

input group "--- Сет 3 ---"
input string InpSet3MainPair= "USDCHF";      // Сет 3: основная пара
input string InpSet3CorrPair= "EURUSD";      // Сет 3: корреляционная пара
input ENUM_DIRECTION InpSet3Direction  = DIR_BUY;       // Сет 3: направление
input ENUM_CORRELATION InpSet3Corr     = CORR_INVERSE;  // Сет 3: корреляция

input group "--- Сет 4 ---"
input string InpSet4MainPair= "USDCHF";      // Сет 4: основная пара
input string InpSet4CorrPair= "EURUSD";      // Сет 4: корреляционная пара
input ENUM_DIRECTION InpSet4Direction  = DIR_SELL;      // Сет 4: направление
input ENUM_CORRELATION InpSet4Corr     = CORR_INVERSE;  // Сет 4: корреляция

//============================================================
//  СТРУКТУРА БЛОКА
//============================================================
struct SBlock
{
   bool             enabled;
   ENUM_BLOCK_STATE state;
   ENUM_DIRECTION   direction;
   ENUM_CORRELATION correlation;
   double  closePercent;
   double  extraThreshold;
   int     tp;
   int     sl;
   string  mainPair;
   string  corrPair;
   double  mainLot;
   double  corrLot;
   double  safeLot;
   double  extra1Lot;
   double  extra2Lot;
   double  extra3Lot;
   double  extraDeviation;
   double  extraClosePercent;
   double  takenProfit;
   double  startBalance;
   bool    profitTaken;
   ulong   ticketMainBuy;
   ulong   ticketMainSell;
   ulong   ticketMain2;
   ulong   ticketCorr2;
   ulong   ticketSafeMain;
   ulong   ticketSafeCorr;
   ulong   ticketExtra1Main;
   ulong   ticketExtra1Corr;
   ulong   ticketExtra2Main;
   ulong   ticketExtra2Corr;
   ulong   ticketExtra3Main;
   ulong   ticketExtra3Corr;
   bool    extra1Active;
   bool    extra2Active;
   bool    extra3Active;
   bool    extraAlgoEnabled;
   // Флаги "закрыто вручную" для правильного отображения кнопок
   bool    extra1ManuallyClosed;
   bool    extra2ManuallyClosed;
   bool    extra3ManuallyClosed;
   // 5 уровней EXTRA: L1,L5 — технические, L2,L3,L4 — рабочие
   double  extraLevel1;   // технический (= -takenProfit)
   double  extraLevel2;   // рабочий 1
   double  extraLevel3;   // рабочий 2
   double  extraLevel4;   // рабочий 3
   double  extraLevel5;   // технический (= -takenProfit - 4*step)
   bool    visitedLevel1;
   bool    visitedLevel2;
   bool    visitedLevel3;
   bool    visitedLevel4;
   bool    visitedLevel5;
   // Максимальный баланс каждой двойки EXTRA — для закрытия на обратном ходу цены
   double  maxBalExtra1;
   double  maxBalExtra2;
   double  maxBalExtra3;
   bool    phase2CloseReady; // true = прошло 10 сек после старта фазы2 → closePercent активен
   datetime phase2StartTime; // время старта фазы 2
   bool    cycleFinished;   // true = цикл завершён, сет можно менять (визуальный флаг)

   SBlock()
   {
      enabled=false; state=BLOCK_IDLE; direction=DIR_BUY; correlation=CORR_INVERSE;
      closePercent=0.5; extraThreshold=60; tp=100; sl=120;
      mainPair="EURUSD"; corrPair="USDCHF";
      mainLot=0.1; corrLot=0.1; safeLot=0.03;
      extra1Lot=0.03; extra2Lot=0.03; extra3Lot=0.04;
      extraDeviation=20; extraClosePercent=0.8;
      takenProfit=0; startBalance=0; profitTaken=false;
      ticketMainBuy=0; ticketMainSell=0;
      ticketMain2=0; ticketCorr2=0;
      ticketSafeMain=0; ticketSafeCorr=0;
      ticketExtra1Main=0; ticketExtra1Corr=0;
      ticketExtra2Main=0; ticketExtra2Corr=0;
      ticketExtra3Main=0; ticketExtra3Corr=0;
      extra1Active=false; extra2Active=false; extra3Active=false;
      extra1ManuallyClosed=false; extra2ManuallyClosed=false; extra3ManuallyClosed=false;
      extraAlgoEnabled=true;
      extraLevel1=0; extraLevel2=0; extraLevel3=0; extraLevel4=0; extraLevel5=0;
      visitedLevel1=false; visitedLevel2=false; visitedLevel3=false;
      visitedLevel4=false; visitedLevel5=false;
      maxBalExtra1=0; maxBalExtra2=0; maxBalExtra3=0;
      phase2CloseReady=false; phase2StartTime=0;
      cycleFinished=false;
   }
};

//============================================================
//  ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
//============================================================
CTrade        trade;
SBlock        g_block1;
SBlock        g_block2;
ENUM_EA_STATE g_eaState     = STATE_STANDBY;
double        g_startDeposit  = 0;
double        g_stopLevelDepo = 0;
datetime      g_stopTime      = 0;
string        g_prefix        = "CA_";

//--- Координаты панели
int PX = 5;
int PY = 30;
bool g_extraLevelsVisible = true;  // видимость выносных панелей уровней EXTRA
bool g_corrVisible        = true;  // видимость индикатора CORR
bool g_autoPilot          = false; // автопилот: запуск по сигналу CORR_BOLD_SIGNAL

// Сохранённая прибыль блоков — показывается пока идёт следующий цикл,
// сбрасывается когда оба блока завершают новый цикл (CheckAutoRestart)
double g_savedProfit1 = 0;
double g_savedProfit2 = 0;

// Выбранные сеты: 2 из 4, любые. g_selSet[0]=сет для блока1, g_selSet[1]=сет для блока2
// Значения 0=нет, 1..4=номер сета
int g_selSet[2];  // [0]=блок1, [1]=блок2
bool g_allSetActive = false; // ALL SET: единые параметры для всех сетов
bool g_aLotActive   = false; // A-LOT: автоматический подбор лотов

// Защита от ложных срабатываний сразу после старта/перезагрузки:
// ProcessBlocks не вызывается, пока MT5 не загрузил все позиции (~5 сек)
datetime g_initTime = 0;
#define INIT_DELAY_SEC 5

// Сохранить позицию панели в GlobalVariable
void SavePanelPos()
{
   GlobalVariableSet(g_prefix+"PNL_PX", PX);
   GlobalVariableSet(g_prefix+"PNL_PY", PY);
}

// Загрузить позицию панели из GlobalVariable
void LoadPanelPos()
{
   if(GlobalVariableCheck(g_prefix+"PNL_PX"))
      PX = (int)GlobalVariableGet(g_prefix+"PNL_PX");
   if(GlobalVariableCheck(g_prefix+"PNL_PY"))
      PY = (int)GlobalVariableGet(g_prefix+"PNL_PY");
}

//--- Цвета
color C_BG        = C'15,15,15';
color C_BORDER    = C'90,90,90';
color C_FRAME     = C'128,128,128';  // среднесерый — обрамление блоков и подблоков
color C_BTN_DEF   = C'60,60,60';
color C_BTN_GREEN = C'0,130,0';
color C_BTN_RED   = C'150,0,0';
color C_BTN_YEL   = C'200,180,0';  // ярко-жёлтый для активных SET-кнопок
color C_BTN_ORG   = C'180,80,0';   // оранжевый — ручное управление EXTRA
color C_BTN_CYAN  = C'0,110,120';
color C_FRAME_BLK = C'0,160,200';  // голубой контур блоков
color C_LBL_ACTIVE = C'160,0,160';     // тёмный маджента — фон названия активной двойки
color C_TXT_W     = clrWhite;
color C_TXT_Y     = clrYellow;
color C_TXT_G     = C'0,210,0';
color C_TXT_R     = C'220,80,80';
color C_TXT_GRAY  = C'140,140,140';


//============================================================
//  БЛОК CORR — встроенный индикатор корреляции
//  (перенесён из CORR_Triple_v13/14, является частью советника)
//============================================================

//--- Параметры CORR (input-параметры советника)
input group "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
input group "════════ CORR ИНДИКАТОР ════════"
input string InpCorrSym1       = "EURUSD"; // CORR: Пара 1 (целевая, голубая)
input string InpCorrSym2       = "USDCHF"; // CORR: Пара 2 (целевая, зелёная)
input string InpCorrSym3       = "EURCHF"; // CORR: Пара 3 (нейтральная, флет)
input int    InpCorrWindowMin  = 60;       // CORR: Окно наблюдения (мин)
input int    InpCorrFlatBand   = 15;       // CORR: Коридор флета пары 3 (пункты)
input int    InpCorrMinDist    = 20;       // CORR: Мин. дистанция пар 1/2 от черточки
input int    InpCorrBoldDist   = 40;       // CORR: Разлёт пар 1 и 2 для жирного
input int    InpCorrWarnPct    = 80;       // CORR: % от минут удержания до предупреждения
input int    InpCorrBoldMin    = 3;        // CORR: Минут удержания до жирного
input int    InpCorrSpreadAlert= 30;       // CORR: Спред-порог (пункты)
input string InpCorrWorkStart  = "08:00"; // CORR: Начало рабочего времени
input string InpCorrWorkEnd    = "22:00"; // CORR: Конец рабочего времени
input int    InpCorrBlinkMs    = 120;     // CORR: Спред — интервал мигания (мс)
input int    InpCorrShimmerMs  = 700;     // CORR: Новости — период перелива (мс)

//--- Геометрия CORR панели (прикреплена к советнику справа)
int CORR_W   = 220;  // ширина панели CORR
int CORR_GAP = 6;    // зазор между панелью советника и CORR
int CORR_HDR = 14;   // высота drag-bar (совпадает с советником)
int CORR_SYM_H = 32; // высота строки пары
int CORR_D_H   = 20; // высота строки D-значений
int CORR_SYM_FS = 13;
int CORR_D_FS   =  9;
int CORR_D_PAD  =  5;

//--- Глобальные переменные CORR
datetime g_corrBoldSince= 0;
bool     g_corrBlinkOn  = false;
bool     g_corrBlinkPh  = false;
uint     g_corrLastBlnk = 0;
bool     g_corrNewsOn   = false;
int      g_corrWorkStartMin = 0;
int      g_corrWorkEndMin   = 0;
string   g_corrSymTxt[3];
bool     g_corrIsBold   = false;
bool     g_corrBoldSym1 = false;
bool     g_corrBoldSym2 = false;
int      g_corrDirSym1  = 0;
int      g_corrDirSym2  = 0;
int      g_corrActiveSet= 0;

// Тест-панель CORR
bool     g_corrTPVisible  = false;
bool     g_corrForceSpread= false;
bool     g_corrForceNews  = false;
bool     g_corrForceOff   = false;
bool     g_corrForceBold  = false;
bool     g_corrForceWarn  = false;  // форс жёлтого warn-порога

//--- Утилиты CORR
int CorrParseHHMM(string s)
{
   int col = StringFind(s,":");
   if(col < 1) return 0;
   return (int)StringToInteger(StringSubstr(s,0,col))*60
         +(int)StringToInteger(StringSubstr(s,col+1));
}

bool CorrIsWorkingHours()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   int cur = dt.hour*60 + dt.min;
   if(g_corrWorkStartMin <= g_corrWorkEndMin)
      return(cur >= g_corrWorkStartMin && cur < g_corrWorkEndMin);
   return(cur >= g_corrWorkStartMin || cur < g_corrWorkEndMin);
}

bool CorrCheckNews()
{
   datetime now = TimeCurrent();
   int tot = ObjectsTotal(0,0,OBJ_VLINE);
   for(int i=0;i<tot;i++)
   {
      string nm = ObjectName(0,i,0,OBJ_VLINE);
      long   t  = (long)(datetime)ObjectGetInteger(0,nm,OBJPROP_TIME,0);
      long   dt = (long)now - t;
      if(dt < -1800 || dt > 1800) continue;
      color c = (color)ObjectGetInteger(0,nm,OBJPROP_COLOR);
      if(c==clrRed || c==C'255,0,0' || c==C'204,0,0' || c==C'220,20,60') return true;
   }
   return false;
}

//--- Создание/удаление объектов CORR панели
void CorrMakeRect(string nm, int z, color bg)
{
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,nm,OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0,nm,OBJPROP_BACK,      false);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,nm,OBJPROP_ZORDER,    z);
   ObjectSetInteger(0,nm,OBJPROP_BGCOLOR,   bg);
   ObjectSetString(0, nm,OBJPROP_TOOLTIP,   "\n");
}

void CorrMakeBorder(string nm, int z, color clr)
{
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,nm,OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0,nm,OBJPROP_BACK,       false);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0,nm,OBJPROP_ZORDER,     z);
   ObjectSetInteger(0,nm,OBJPROP_BGCOLOR,    clrNONE);
   ObjectSetInteger(0,nm,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,      clr);
   ObjectSetString(0, nm,OBJPROP_TOOLTIP,    "\n");
}

void CorrMakeLbl(string nm, int z, string font, int fs)
{
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,nm,OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0,nm,OBJPROP_BACK,      false);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,nm,OBJPROP_ZORDER,    z);
   ObjectSetString(0, nm,OBJPROP_FONT,      font);
   ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,  fs);
   ObjectSetString(0, nm,OBJPROP_TEXT,      " ");
   ObjectSetString(0, nm,OBJPROP_TOOLTIP,   "\n");
}

void CorrSetRect(string nm, int x, int y, int w, int h)
{
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,nm,OBJPROP_XSIZE,    w);
   ObjectSetInteger(0,nm,OBJPROP_YSIZE,    h);
}

void CorrSetVis(string nm, bool v)
{
   ObjectSetInteger(0,nm,OBJPROP_TIMEFRAMES, v ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
}

// Кнопка тест-панели CORR — OBJ_BUTTON с суффиксами _BG (кнопка) и _TX (не используется)
// Используем OBJ_BUTTON: текст прямо на кнопке, STATE сбрасываем сами
void CorrMakeBtn(string nm, int z, string txt, color bg, color tc)
{
   string bg_nm = nm+"_BG";
   if(ObjectFind(0,bg_nm)<0) ObjectCreate(0,bg_nm,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,bg_nm,OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0,bg_nm,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,bg_nm,OBJPROP_HIDDEN,    true);
   ObjectSetInteger(0,bg_nm,OBJPROP_ZORDER,    z);
   ObjectSetInteger(0,bg_nm,OBJPROP_BGCOLOR,   bg);
   ObjectSetInteger(0,bg_nm,OBJPROP_COLOR,     tc);
   ObjectSetString(0, bg_nm,OBJPROP_FONT,      "Arial Bold");
   ObjectSetInteger(0,bg_nm,OBJPROP_FONTSIZE,  8);
   ObjectSetString(0, bg_nm,OBJPROP_TEXT,      txt);
   ObjectSetString(0, bg_nm,OBJPROP_TOOLTIP,   "\n");
}

void CorrSetBtnPos(string nm, int x, int y, int w, int h)
{
   ObjectSetInteger(0,nm+"_BG",OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,nm+"_BG",OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,nm+"_BG",OBJPROP_XSIZE,    w);
   ObjectSetInteger(0,nm+"_BG",OBJPROP_YSIZE,    h);
}

void CorrSetBtnVis(string nm, bool v)
{
   long tf = v ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
   ObjectSetInteger(0,nm+"_BG",OBJPROP_TIMEFRAMES,tf);
}

void CorrSetBtnClr(string nm, color bg, color tc)
{
   ObjectSetInteger(0,nm+"_BG",OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,nm+"_BG",OBJPROP_COLOR,  tc);
}

void CorrDelBtn(string nm)
{
   ObjectDelete(0,nm+"_BG");
}

//--- Создание панели CORR
void CreateCorrPanel()
{
   CorrMakeRect  ("CORR_BG",     0, clrBlack);
   CorrMakeBorder("CORR_BORDER", 1, C'90,90,90');
   // CORR_DRAG убран — полоска заменена расширением DRAG_CORR советника

   for(int i=1;i<=3;i++)
      CorrMakeLbl("CORR_R"+(string)i, 4, "Courier New", CORR_SYM_FS);

   CorrMakeRect  ("CORR_DBG",    2, clrBlack);
   CorrMakeBorder("CORR_DBORDER",3, C'90,90,90');
   for(int i=1;i<=3;i++)
      CorrMakeLbl("CORR_D"+(string)i, 4, "Courier New Bold", CORR_D_FS);

   // Тест-панель кнопки
   CorrMakeBtn("CORR_TP_TOG",    10, "TEST ►", C'30,30,50', clrSilver);
   CorrMakeBtn("CORR_TP_SPREAD", 10, "SPREAD TEST",    C'40,40,60', clrSilver);
   CorrMakeBtn("CORR_TP_NEWS",   10, "NEWS TEST",      C'40,40,60', clrSilver);
   CorrMakeBtn("CORR_TP_OFF",    10, "OFF-HOURS TEST", C'40,40,60', clrSilver);
   CorrMakeBtn("CORR_TP_BOLD",   10, "BOLD SIGNAL TEST",C'40,40,60',clrSilver);
   CorrMakeBtn("CORR_TP_WARN",   10, "WARN SIGNAL TEST",C'40,40,60',clrSilver);
   CorrMakeRect("CORR_TP_BG",    9,  C'15,15,30');
   ObjectSetInteger(0,"CORR_TP_BG",OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,"CORR_TP_BG",OBJPROP_COLOR,C'60,60,100');
}

//--- Компоновка CORR панели (вызывается при каждом перемещении советника)
void UpdateCorrLayout(int eaPX, int eaPY, int eaPNL_W, int eaPNL_H)
{
   // CORR прикреплена справа от панели советника, выровнена по верху
   int cx = eaPX + eaPNL_W + CORR_GAP;
   int cy = eaPY;

   int symBlockH = 3*CORR_SYM_H + 4;  // без HDR — полоска убрана
   int dBlockH   = CORR_D_PAD + 3*CORR_D_H + CORR_D_PAD;

   bool show = g_corrVisible;
   CorrSetVis("CORR_BG",     show); CorrSetVis("CORR_BORDER", show);
   // CORR_DRAG и CORR_DRAGTXT убраны — вместо них DRAG_CORR советника
   CorrSetVis("CORR_DBG",    show); CorrSetVis("CORR_DBORDER",show);
   for(int i=1;i<=3;i++)
   {
      CorrSetVis("CORR_R"+(string)i, show);
      CorrSetVis("CORR_D"+(string)i, show);
   }
   if(!show)
   {
      CorrSetBtnVis("CORR_TP_TOG",false);
      CorrSetBtnVis("CORR_TP_SPREAD",false); CorrSetBtnVis("CORR_TP_NEWS",false);
      CorrSetBtnVis("CORR_TP_OFF",false);    CorrSetBtnVis("CORR_TP_BOLD",false);
      CorrSetBtnVis("CORR_TP_WARN",false);
      ObjectSetInteger(0,"CORR_TP_BG",OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
      return;
   }

   CorrSetRect("CORR_BG",    cx, cy, CORR_W, symBlockH);
   CorrSetRect("CORR_BORDER",cx, cy, CORR_W, symBlockH);
   // CORR_DRAG убран — полоска заменена расширением DRAG советника

   for(int i=0;i<3;i++)
   {
      ObjectSetInteger(0,"CORR_R"+(string)(i+1),OBJPROP_XDISTANCE,cx+26);  // отступ для стрелки слева
      ObjectSetInteger(0,"CORR_R"+(string)(i+1),OBJPROP_YDISTANCE,cy+4+i*CORR_SYM_H);
   }
   // Стрелки — слева от строк R1/R2
   if(ObjectFind(0,"CORR_ARR1")>=0)
   {
      ObjectSetInteger(0,"CORR_ARR1",OBJPROP_XDISTANCE,cx+1);
      ObjectSetInteger(0,"CORR_ARR1",OBJPROP_YDISTANCE,cy+4);
   }
   if(ObjectFind(0,"CORR_ARR2")>=0)
   {
      ObjectSetInteger(0,"CORR_ARR2",OBJPROP_XDISTANCE,cx+1);
      ObjectSetInteger(0,"CORR_ARR2",OBJPROP_YDISTANCE,cy+4+CORR_SYM_H);
   }

   int dY = cy + symBlockH + 4;
   CorrSetRect("CORR_DBG",    cx, dY, CORR_W, dBlockH);
   CorrSetRect("CORR_DBORDER",cx, dY, CORR_W, dBlockH);
   for(int i=0;i<3;i++)
   {
      ObjectSetInteger(0,"CORR_D"+(string)(i+1),OBJPROP_XDISTANCE,cx+10);
      ObjectSetInteger(0,"CORR_D"+(string)(i+1),OBJPROP_YDISTANCE,dY+CORR_D_PAD+i*CORR_D_H);
   }

   // TEST кнопка — внутри D-блока, правый край, по центру по высоте
   int togW=68, togH=30;
   int togX=cx + CORR_W - togW - 4;  // внутри D-зоны, прижата к правому краю
   int togY=dY + (dBlockH - togH) / 2;  // вертикально по центру D-блока
   CorrSetBtnPos("CORR_TP_TOG", togX, togY, togW, togH);
   CorrSetBtnVis("CORR_TP_TOG", true);
   ObjectSetString(0,"CORR_TP_TOG_BG",OBJPROP_TEXT, g_corrTPVisible ? "◄ TEST" : "TEST ►");

   if(!g_corrTPVisible)
   {
      CorrSetBtnVis("CORR_TP_SPREAD",false); CorrSetBtnVis("CORR_TP_NEWS",false);
      CorrSetBtnVis("CORR_TP_OFF",false);    CorrSetBtnVis("CORR_TP_BOLD",false);
      CorrSetBtnVis("CORR_TP_WARN",false);
      ObjectSetInteger(0,"CORR_TP_BG",OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
      return;
   }

   int tpW=170, tpBtnH=22, tpPad=5;
   int tpX=togX, tpY=togY+togH+2;
   int tpH = 20 + 5*(tpBtnH+3) + tpPad;
   ObjectSetInteger(0,"CORR_TP_BG",OBJPROP_XDISTANCE,tpX);
   ObjectSetInteger(0,"CORR_TP_BG",OBJPROP_YDISTANCE,tpY);
   ObjectSetInteger(0,"CORR_TP_BG",OBJPROP_XSIZE,    tpW);
   ObjectSetInteger(0,"CORR_TP_BG",OBJPROP_YSIZE,    tpH);
   ObjectSetInteger(0,"CORR_TP_BG",OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);

   string tpBtns[] = {"CORR_TP_SPREAD","CORR_TP_NEWS","CORR_TP_OFF","CORR_TP_BOLD","CORR_TP_WARN"};
   bool   tpStates[]= {g_corrForceSpread,g_corrForceNews,g_corrForceOff,g_corrForceBold,g_corrForceWarn};
   color  tpOnBg[]  = {C'120,0,0', C'60,60,60', C'0,0,80', C'80,60,0', C'80,70,0'};
   color  tpOnTx[]  = {clrRed, clrWhite, C'100,100,255', clrYellow, clrYellow};
   for(int i=0;i<5;i++)
   {
      bool act = tpStates[i];
      CorrSetBtnClr(tpBtns[i], act?tpOnBg[i]:C'40,40,60', act?tpOnTx[i]:C'140,140,160');
      CorrSetBtnPos(tpBtns[i], tpX+tpPad, tpY+18+i*(tpBtnH+3), tpW-tpPad*2, tpBtnH);
      CorrSetBtnVis(tpBtns[i], true);
   }
}

//--- Удаление CORR панели
void DeleteCorrPanel()
{
   string objs[] = {"CORR_BG","CORR_BORDER","CORR_DRAG","CORR_DRAGTXT",
                    "CORR_DBG","CORR_DBORDER","CORR_TP_BG"};
   for(int i=0;i<ArraySize(objs);i++) ObjectDelete(0,objs[i]);
   for(int i=1;i<=3;i++)
   {
      ObjectDelete(0,"CORR_R"+(string)i);
      ObjectDelete(0,"CORR_D"+(string)i);
   }
   CorrDelBtn("CORR_TP_TOG");
   CorrDelBtn("CORR_TP_SPREAD"); CorrDelBtn("CORR_TP_NEWS");
   CorrDelBtn("CORR_TP_OFF");    CorrDelBtn("CORR_TP_BOLD");
   CorrDelBtn("CORR_TP_WARN");
   ObjectDelete(0,"CORR_ARR1");
   ObjectDelete(0,"CORR_ARR2");
   for(int i=1;i<=3;i++) ObjectDelete(0,"CORR_DASH"+(string)i);
}


//--- Черточки опорной цены — как в v17: одна линия на текущем чарте
//    Если текущий символ = одна из 3 пар — рисуется на уровне iOpen startBar назад
void UpdateCorrDashes()
{
   ENUM_TIMEFRAMES tf = _Period;
   int startBar = iBarShift(_Symbol, tf, TimeCurrent() - InpCorrWindowMin*60);
   if(startBar < 0) startBar = 0;
   if(startBar < 1) startBar = 1;

   // Черточка рисуется только если текущий символ совпадает с одной из пар
   string syms[3]; syms[0]=InpCorrSym1; syms[1]=InpCorrSym2; syms[2]=InpCorrSym3;
   string matchSym = "";
   for(int i=0;i<3;i++) if(_Symbol == syms[i]) { matchSym = syms[i]; break; }

   // Удаляем лишние черточки
   for(int i=1;i<=3;i++)
   {
      string nm = "CORR_DASH"+(string)i;
      if(i > 1 || matchSym == "") { ObjectDelete(0,nm); continue; }
   }

   if(matchSym == "" || !g_corrVisible) return;

   // Одна черточка: M_Line — как в v17
   string nm     = "CORR_DASH1";
   datetime tS   = iTime(_Symbol, tf, startBar);
   datetime tE   = iTime(_Symbol, tf, MathMax(0, startBar-1));
   double   price = iOpen(_Symbol, tf, startBar);
   if(tS==0 || price<=0) { ObjectDelete(0,nm); return; }

   if(ObjectFind(0,nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_TREND, 0, tS, price, tE, price);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH,     10);  // толстая черта как в v17
      ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nm, OBJPROP_RAY_LEFT,  false);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN,    false);
      ObjectSetInteger(0, nm, OBJPROP_BACK,      false);
      ObjectSetString(0,  nm, OBJPROP_TOOLTIP,   _Symbol+" open @ "+DoubleToString(price,5));
   }
   ObjectSetInteger(0, nm, OBJPROP_TIME,  0, tS);
   ObjectSetInteger(0, nm, OBJPROP_TIME,  1, tE);
   ObjectSetDouble(0,  nm, OBJPROP_PRICE, 0, price);
   ObjectSetDouble(0,  nm, OBJPROP_PRICE, 1, price);
   // Цвет черточки: красный всегда (исходная точка)
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//--- Расчёт и обновление данных CORR (вызывается из OnTimer советника)
void UpdateCorrData()
{
   //=== АЛГОРИТМ v17 ===
   ENUM_TIMEFRAMES tf = _Period;

   // startBar — через iBarShift по времени (точнее, чем деление периода)
   int startBar = iBarShift(_Symbol, tf, TimeCurrent() - InpCorrWindowMin*60);
   if(startBar < 0) startBar = 0;
   if(startBar < 1) startBar = 1;

   // Исходная точка для каждой пары — бар startBar на том же времени
   datetime tStart = iTime(_Symbol, tf, startBar);
   double pt1 = SymbolInfoDouble(InpCorrSym1,SYMBOL_POINT); if(pt1<=0) pt1=0.0001;
   double pt2 = SymbolInfoDouble(InpCorrSym2,SYMBOL_POINT); if(pt2<=0) pt2=0.0001;
   double pt3 = SymbolInfoDouble(InpCorrSym3,SYMBOL_POINT); if(pt3<=0) pt3=0.0001;

   double o1 = iOpen(InpCorrSym1, tf, iBarShift(InpCorrSym1, tf, tStart));
   double o2 = iOpen(InpCorrSym2, tf, iBarShift(InpCorrSym2, tf, tStart));
   double o3 = iOpen(InpCorrSym3, tf, iBarShift(InpCorrSym3, tf, tStart));
   double c1 = SymbolInfoDouble(InpCorrSym1, SYMBOL_BID);
   double c2 = SymbolInfoDouble(InpCorrSym2, SYMBOL_BID);
   double c3 = SymbolInfoDouble(InpCorrSym3, SYMBOL_BID);

   // v1/v2/v3 — дистанция со знаком (пункты) от исходной точки
   int v1 = (int)MathRound((c1 - o1) / pt1);
   int v2 = (int)MathRound((c2 - o2) / pt2);
   int v3 = (int)MathRound((c3 - o3) / pt3);
   int abs_v1 = MathAbs(v1);
   int abs_v2 = MathAbs(v2);
   int abs_v3 = MathAbs(v3);

   // Спред / новости / рабочие часы
   int sp1 = (int)SymbolInfoInteger(InpCorrSym1, SYMBOL_SPREAD);
   int sp2 = (int)SymbolInfoInteger(InpCorrSym2, SYMBOL_SPREAD);
   g_corrBlinkOn = (MathMax(sp1,sp2) >= InpCorrSpreadAlert);
   g_corrNewsOn  = (!g_corrBlinkOn && CorrCheckNews());
   bool offHours = !CorrIsWorkingHours();

   if(g_corrForceSpread) { g_corrBlinkOn=true;  g_corrNewsOn=false;  offHours=false; }
   if(g_corrForceNews)   { g_corrNewsOn=true;   g_corrBlinkOn=false; offHours=false; }
   if(g_corrForceOff)    { offHours=true;       g_corrBlinkOn=false; g_corrNewsOn=false; }

   //--- v17: Алгоритм цвета и жирного
   // 1. Пара 3 во флете?
   bool pair3Flat   = (abs_v3 <= InpCorrFlatBand);
   // 2. Пары 1 и 2 ушли дальше MinDist?
   bool pair1Active = (abs_v1 >= InpCorrMinDist);
   bool pair2Active = (abs_v2 >= InpCorrMinDist);
   bool bothActive  = (pair1Active && pair2Active);
   // 3. Разлёт между парами 1 и 2
   int  divergence  = MathAbs(v1 - v2);
   bool boldCond    = (divergence >= InpCorrBoldDist);
   // 4. Кто сильнее? (для определения цвета)
   bool pair1Stronger = (abs_v1 > abs_v2);
   bool pair2Stronger = (abs_v2 > abs_v1);
   // 5. Целевая пара = та у которой МЕНЬШЕ отклонение от расчетной точки (ближе к нулю)
   //    ИСПРАВЛЕНО: была обратная логика - выбиралась пара с большим отклонением
   bool pair1IsTarget = (abs_v1 < abs_v2);  // пара 1 ближе к расчетной точке
   bool pair2IsTarget = (abs_v2 < abs_v1);  // пара 2 ближе к расчетной точке

   // 6. Цвет - определяется по тому, кто СИЛЬНЕЕ (больше ушел от расчетной точки)
   color clr = clrWhite;
   if(pair3Flat && bothActive)
   {
      if(pair1Stronger)      clr = clrCyan;   // пара 1 сильнее → голубой
      else if(pair2Stronger) clr = clrGreen;  // пара 2 сильнее → зелёный
   }

   // 7. Условия для жирного: разлёт достиг порога И обе пары активны И пара 3 в флете
   //    ИСПРАВЛЕНО: проверяем условия ПОСТОЯННО - если нарушаются, таймер сбрасывается
   bool canBeBold  = (pair3Flat && bothActive && boldCond &&
                      (clr == clrCyan || clr == clrGreen));

   // 8. Таймер для жирного и предупреждения
   //    КРИТИЧЕСКИ ВАЖНО: если canBeBold становится false - таймер СБРАСЫВАЕТСЯ
   //    Это означает что все 3 условия должны НЕПРЕРЫВНО выполняться в течение заданного времени:
   //    1) Пара 3 в флете (abs_v3 <= InpCorrFlatBand)
   //    2) Обе пары активны (abs_v1 >= InpCorrMinDist && abs_v2 >= InpCorrMinDist)
   //    3) Разлёт достиг порога (divergence >= InpCorrBoldDist)
   datetime now = TimeCurrent();
   if(!canBeBold)
   {
      // Условия НЕ выполнены - сбрасываем таймер и цвет в белый
      g_corrBoldSince = 0;
   }
   else if(g_corrBoldSince == 0)
   {
      // Условия выполнены впервые - запускаем таймер
      g_corrBoldSince = now;
   }
   // else: условия продолжают выполняться - таймер идет

   // Время в секундах
   long boldSec = (long)InpCorrBoldMin * 60;
   long warnSec = (long)(InpCorrBoldMin * InpCorrWarnPct / 100.0 * 60);  // % от минут удержания
   long elapsedSec = (g_corrBoldSince > 0) ? (now - g_corrBoldSince) : 0;

   // Предупреждение: если прошло >= warnSec, но < boldSec
   bool warnCond = (canBeBold && g_corrBoldSince > 0 && 
                    elapsedSec >= warnSec && elapsedSec < boldSec);
   
   // Жирный: если прошло >= boldSec
   bool isBold   = (canBeBold && g_corrBoldSince > 0 && elapsedSec >= boldSec);

   // Отладка: выводим информацию при предупреждении или жирном
   static datetime lastDebugPrint = 0;
   if((warnCond || isBold) && pair3Flat && bothActive && (pair1IsTarget || pair2IsTarget))
   {
      if(TimeCurrent() - lastDebugPrint >= 5)  // раз в 5 секунд
      {
         Print("CORR ", (isBold ? "ЖИРНЫЙ" : "Предупреждение"), ": время=", elapsedSec, "с",
               ", warnSec=", warnSec, "с (", InpCorrWarnPct, "% от ", InpCorrBoldMin, "мин)",
               ", boldSec=", boldSec, "с",
               ", pair1IsTarget=", pair1IsTarget, ", pair2IsTarget=", pair2IsTarget,
               ", abs_v1=", abs_v1, ", abs_v2=", abs_v2);
         lastDebugPrint = TimeCurrent();
      }
   }

   // При предупреждении — жёлтый цвет
   if(warnCond && pair3Flat && bothActive && (pair1IsTarget || pair2IsTarget))
      clr = clrYellow;

   // 9. Какая пара жирная/желтая + направление
   //    ЦЕЛЕВАЯ пара (с меньшим отклонением) становится жирной или желтой
   bool boldSym1 = (isBold  && pair1IsTarget);  // жирная = целевая (меньше отклонение)
   bool boldSym2 = (isBold  && pair2IsTarget);  // жирная = целевая (меньше отклонение)
   bool warnSym1 = (warnCond && pair1IsTarget); // предупреждение = целевая
   bool warnSym2 = (warnCond && pair2IsTarget); // предупреждение = целевая

   // Форс-болд (тест)
   if(g_corrForceBold && !offHours)
   {
      boldSym1=true; boldSym2=false;
      warnSym1=false; warnSym2=false;
      clr = clrCyan;
      g_corrBlinkOn=false; g_corrNewsOn=false;
   }
   // Форс-варн (тест жёлтого предупреждения)
   if(g_corrForceWarn && !offHours)
   {
      boldSym1=false; boldSym2=false;
      warnSym1=true;  warnSym2=false;
      clr = clrYellow;
      g_corrBlinkOn=false; g_corrNewsOn=false;
   }

   // Направление: знак v1/v2
   g_corrDirSym1 = (v1 > 0) ? 1 : ((v1 < 0) ? -1 : 0);
   g_corrDirSym2 = (v2 > 0) ? 1 : ((v2 < 0) ? -1 : 0);

   // Глобальные флаги для автопилота
   g_corrBoldSym1 = boldSym1 || warnSym1;
   g_corrBoldSym2 = boldSym2 || warnSym2;
   g_corrIsBold   = (!offHours && !g_corrBlinkOn && !g_corrNewsOn &&
                     (boldSym1 != boldSym2));

   if(!g_corrVisible) return;

   // Кэш текстов — со знаком + как в v17
   g_corrSymTxt[0] = InpCorrSym1 + ": " + (v1 >= 0 ? "+" : "") + (string)v1;
   g_corrSymTxt[1] = InpCorrSym2 + ": " + (v2 >= 0 ? "+" : "") + (string)v2;
   g_corrSymTxt[2] = InpCorrSym3 + ": " + (v3 >= 0 ? "+" : "") + (string)v3;

   if(!g_corrBlinkOn && !g_corrNewsOn && !g_corrForceBold)
   {
      for(int i=0;i<3;i++)
      {
         bool bld = (i==0 && (boldSym1||warnSym1)) || (i==1 && (boldSym2||warnSym2));
         color rc = offHours ? C'0,0,160' : clr;
         ObjectSetString(0, "CORR_R"+(string)(i+1),OBJPROP_TEXT, g_corrSymTxt[i]);
         ObjectSetString(0, "CORR_R"+(string)(i+1),OBJPROP_FONT, bld?"Courier New Bold":"Courier New");
         ObjectSetInteger(0,"CORR_R"+(string)(i+1),OBJPROP_COLOR,rc);
         ObjectSetInteger(0,"CORR_R"+(string)(i+1),OBJPROP_FONTSIZE,CORR_SYM_FS);
      }
      bool arr1 = (boldSym1||warnSym1) && g_corrDirSym1!=0;
      bool arr2 = (boldSym2||warnSym2) && g_corrDirSym2!=0;
      CorrSetArrow(0, arr1 ? g_corrDirSym1 : 0);
      CorrSetArrow(1, arr2 ? g_corrDirSym2 : 0);
   }

   // D-блок: d12 / d13 / d23 (v1-v2, v1-v3, v2-v3)
   int d12 = MathAbs(v1-v2), d13 = MathAbs(v1-v3), d23 = MathAbs(v2-v3);
   color dc = C'160,160,170';
   string ds[3];
   ds[0] = "d12: " + (string)d12;
   ds[1] = "d13: " + (string)d13;
   ds[2] = "d23: " + (string)d23;
   for(int i=0;i<3;i++)
   {
      ObjectSetString(0, "CORR_D"+(string)(i+1),OBJPROP_TEXT,ds[i]);
      ObjectSetString(0, "CORR_D"+(string)(i+1),OBJPROP_FONT,"Courier New Bold");
      ObjectSetInteger(0,"CORR_D"+(string)(i+1),OBJPROP_COLOR,dc);
      ObjectSetInteger(0,"CORR_D"+(string)(i+1),OBJPROP_FONTSIZE,CORR_D_FS);
   }
}

//--- Установить/скрыть стрелку у строки i (0=Sym1, 1=Sym2)
void CorrSetArrow(int idx, int dir)
{
   string nm = "CORR_ARR"+(string)(idx+1);
   if(ObjectFind(0,nm)<0)
   {
      ObjectCreate(0,nm,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,nm,OBJPROP_CORNER,    CORNER_LEFT_UPPER);
      ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,nm,OBJPROP_BACK,      false);
      ObjectSetInteger(0,nm,OBJPROP_ZORDER,    6);
      ObjectSetString(0, nm,OBJPROP_TOOLTIP,   "\n");
   }
   if(dir != 0)
   {
      string arrowTxt = (dir>0) ? "▲" : "▼";
      color  arrowClr = (dir>0) ? clrLime : clrRed;
      ObjectSetString(0, nm,OBJPROP_FONT,      "Arial Bold");
      ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,  11);
      ObjectSetString(0, nm,OBJPROP_TEXT,      arrowTxt);
      ObjectSetInteger(0,nm,OBJPROP_COLOR,     arrowClr);
      ObjectSetInteger(0,nm,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
   }
   else
      ObjectSetInteger(0,nm,OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
}

//--- Мигание CORR (вызывается из OnTimer советника ~40мс)
void UpdateCorrBlink()
{
   if(!g_corrVisible) return;
   uint tnow = GetTickCount();
   bool needRedraw = false;

   if(g_corrBlinkOn)
   {
      // Спред: мигание 120мс, яркий красный <-> почти чёрный
      if((int)(tnow - g_corrLastBlnk) >= InpCorrBlinkMs)
      {
         g_corrLastBlnk = tnow;
         g_corrBlinkPh  = !g_corrBlinkPh;
      }
      color  sc = g_corrBlinkPh ? clrRed : C'40,0,0';
      string fn = g_corrBlinkPh ? "Courier New Bold" : "Courier New";
      for(int i=0;i<3;i++)
      {
         ObjectSetString(0, "CORR_R"+(string)(i+1),OBJPROP_TEXT,    g_corrSymTxt[i]);
         ObjectSetString(0, "CORR_R"+(string)(i+1),OBJPROP_FONT,    fn);
         ObjectSetInteger(0,"CORR_R"+(string)(i+1),OBJPROP_COLOR,   sc);
         ObjectSetInteger(0,"CORR_R"+(string)(i+1),OBJPROP_FONTSIZE,CORR_SYM_FS);
      }
      // Скрываем стрелки во время мигания спреда
      CorrSetArrow(0, 0);
      CorrSetArrow(1, 0);
      needRedraw = true;
   }
   else if(g_corrNewsOn)
   {
      // Новости: плавное переливание белым, период 700мс
      double phase = (double)(tnow % (uint)InpCorrShimmerMs) / (double)InpCorrShimmerMs;
      double s     = (MathSin(phase * 2.0 * M_PI) + 1.0) / 2.0;
      uchar  br    = (uchar)(30 + (int)(s * 225));
      color  nc    = (color)((int)br | ((int)br << 8) | ((int)br << 16));
      string fn    = (s > 0.5) ? "Courier New Bold" : "Courier New";
      for(int i=0;i<3;i++)
      {
         ObjectSetString(0, "CORR_R"+(string)(i+1),OBJPROP_TEXT,    g_corrSymTxt[i]);
         ObjectSetString(0, "CORR_R"+(string)(i+1),OBJPROP_FONT,    fn);
         ObjectSetInteger(0,"CORR_R"+(string)(i+1),OBJPROP_COLOR,   nc);
         ObjectSetInteger(0,"CORR_R"+(string)(i+1),OBJPROP_FONTSIZE,CORR_SYM_FS);
      }
      // Скрываем стрелки во время новостей
      CorrSetArrow(0, 0);
      CorrSetArrow(1, 0);
      needRedraw = true;
   }
   else if(g_corrForceBold)
   {
      // BOLD TEST: строка 1 жирная зелёная + стрелка ▲, строки 2 и 3 — обычные
      ObjectSetString(0, "CORR_R1",OBJPROP_TEXT,    g_corrSymTxt[0]);
      ObjectSetString(0, "CORR_R1",OBJPROP_FONT,    "Courier New Bold");
      ObjectSetInteger(0,"CORR_R1",OBJPROP_COLOR,   clrGreen);
      ObjectSetInteger(0,"CORR_R1",OBJPROP_FONTSIZE,CORR_SYM_FS);
      for(int i=1;i<3;i++)
      {
         ObjectSetString(0, "CORR_R"+(string)(i+1),OBJPROP_TEXT,    g_corrSymTxt[i]);
         ObjectSetString(0, "CORR_R"+(string)(i+1),OBJPROP_FONT,    "Courier New");
         ObjectSetInteger(0,"CORR_R"+(string)(i+1),OBJPROP_COLOR,   clrGreen);
         ObjectSetInteger(0,"CORR_R"+(string)(i+1),OBJPROP_FONTSIZE,CORR_SYM_FS);
      }
      CorrSetArrow(0, 1);   // стрелка ▲ у Sym1
      CorrSetArrow(1, 0);   // нет стрелки у Sym2
      needRedraw = true;
   }

   if(needRedraw) ChartRedraw();
}

//--- Обработка кликов кнопок тест-панели CORR
bool CorrHandleClick(string nm)
{
   // Скрытие панели — сбрасываем все форс-флаги
   if(nm=="CORR_TP_TOG_BG")
   {
      g_corrTPVisible=!g_corrTPVisible;
      if(!g_corrTPVisible)
      {
         g_corrForceSpread=false;
         g_corrForceNews  =false;
         g_corrForceOff   =false;
         g_corrForceBold  =false;
         g_corrForceWarn  =false;
      }
      return true;
   }
   // Все 5 кнопок взаимоисключающие — нажатие активной = выкл, нажатие другой = переключение
   if(nm=="CORR_TP_SPREAD_BG")
   {
      bool was=g_corrForceSpread;
      g_corrForceSpread=false; g_corrForceNews=false; g_corrForceOff=false; g_corrForceBold=false; g_corrForceWarn=false;
      if(!was) g_corrForceSpread=true;
      return true;
   }
   if(nm=="CORR_TP_NEWS_BG")
   {
      bool was=g_corrForceNews;
      g_corrForceSpread=false; g_corrForceNews=false; g_corrForceOff=false; g_corrForceBold=false; g_corrForceWarn=false;
      if(!was) g_corrForceNews=true;
      return true;
   }
   if(nm=="CORR_TP_OFF_BG")
   {
      bool was=g_corrForceOff;
      g_corrForceSpread=false; g_corrForceNews=false; g_corrForceOff=false; g_corrForceBold=false; g_corrForceWarn=false;
      if(!was) g_corrForceOff=true;
      return true;
   }
   if(nm=="CORR_TP_BOLD_BG")
   {
      bool was=g_corrForceBold;
      g_corrForceSpread=false; g_corrForceNews=false; g_corrForceOff=false;
      g_corrForceBold=false; g_corrForceWarn=false;
      if(!was) g_corrForceBold=true;
      return true;
   }
   if(nm=="CORR_TP_WARN_BG")
   {
      bool was=g_corrForceWarn;
      g_corrForceSpread=false; g_corrForceNews=false; g_corrForceOff=false;
      g_corrForceBold=false; g_corrForceWarn=false;
      if(!was) g_corrForceWarn=true;
      return true;
   }
   return false;
}

//============================================================
//  КОНЕЦ БЛОКА CORR
//============================================================

//============================================================
//  OnInit / OnDeinit / OnTimer / OnTick / OnChartEvent
//============================================================
// Вспомогательная функция — заполняет один блок из параметров сета N
void FillBlockFromSet(SBlock &blk, int setNum)
{
   blk.extraAlgoEnabled = true;
   // Пары и направление — всегда индивидуальные
   switch(setNum)
   {
      case 1: blk.mainPair=InpSet1MainPair; blk.corrPair=InpSet1CorrPair;
              blk.direction=InpSet1Direction; blk.correlation=InpSet1Corr; break;
      case 2: blk.mainPair=InpSet2MainPair; blk.corrPair=InpSet2CorrPair;
              blk.direction=InpSet2Direction; blk.correlation=InpSet2Corr; break;
      case 3: blk.mainPair=InpSet3MainPair; blk.corrPair=InpSet3CorrPair;
              blk.direction=InpSet3Direction; blk.correlation=InpSet3Corr; break;
      case 4: blk.mainPair=InpSet4MainPair; blk.corrPair=InpSet4CorrPair;
              blk.direction=InpSet4Direction; blk.correlation=InpSet4Corr; break;
   }
   // Числовые параметры: общие (ALL SET) или из общего блока
   blk.tp               = InpAllTP;
   blk.sl               = InpAllSL;
   blk.mainLot          = InpAllMainLot;
   blk.corrLot          = InpAllMainLot;
   blk.safeLot          = InpAllSafeLot;
   blk.extra1Lot        = InpAllE1Lot;
   blk.extra2Lot        = InpAllE2Lot;
   blk.extra3Lot        = InpAllE3Lot;
   blk.extraThreshold   = InpAllExtThr;
   blk.extraDeviation   = InpAllExtDev;
   blk.extraClosePercent= InpAllExtCls;
   // Если A-LOT активен — пересчитываем лоты по депозиту
   if(g_aLotActive) CalcAutoLots(blk);
}

// Матрица сетов для двух блоков:
//   Сигнал              Б1    Б2
//   Sym1 зелёный ▲      1     3
//   Sym1 зелёный ▼      2     4
//   Sym2 голубой ▲      3     1
//   Sym2 голубой ▼      4     2
void ApplySet(int b1Set, int b2Set)
{
   g_block1 = SBlock(); g_block1.enabled = true;
   g_block2 = SBlock(); g_block2.enabled = true;
   g_savedProfit1 = 0;
   g_savedProfit2 = 0;

   FillBlockFromSet(g_block1, b1Set);
   FillBlockFromSet(g_block2, b2Set);

   g_corrActiveSet = b1Set;  // запоминаем сет Б1 как идентификатор текущего сценария

   // Применяем общие параметры / автолоты если активны
   if(g_allSetActive) { ApplyAllSetParams(g_block1); ApplyAllSetParams(g_block2); }
   if(g_aLotActive)   { CalcAutoLots(g_block1);     CalcAutoLots(g_block2); }

   Print("Автопилот: Б1=сет", b1Set, " Б2=сет", b2Set, ". Запуск советника.");
   StartEA();
}

int OnInit()
{
   ArrayInitialize(g_selSet, 0);
   LoadBlockSettings();
   LoadPanelPos();
   g_corrWorkStartMin = CorrParseHHMM(InpCorrWorkStart);
   g_corrWorkEndMin   = CorrParseHHMM(InpCorrWorkEnd);
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   CreatePanel();
   CreateCorrPanel();

   if(!RestoreState())
      Print("CorrelationAdvisor v1.1 запущен. StandBy.");

   g_initTime = TimeCurrent();
   UpdatePanel();

   EventSetMillisecondTimer(40);  // 40мс — плавное мигание CORR (~25 fps)
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(reason != REASON_REMOVE && reason != REASON_INITFAILED)
      SaveState();
   else
      ClearState();
   DeletePanel();
   DeleteCorrPanel();
}

void OnTimer()
{
   static uint s_lastSecTick = 0;
   uint now = GetTickCount();
   bool isSecond = ((int)(now - s_lastSecTick) >= 1000);

   if(isSecond)
   {
      s_lastSecTick = now;
      if(g_eaState == STATE_RUNNING)
      {
         ProcessBlocks();
         CheckGlobalStops();
         SaveState();
      }

      // Автопилот: запускаем советник с нужным сетом когда CORR даёт жирный сигнал
      if(g_autoPilot && g_eaState != STATE_RUNNING)
      {
         if(g_corrIsBold)
         {
            int b1Set=0, b2Set=0;
            if     (g_corrBoldSym1 && g_corrDirSym1 > 0)  { b1Set=1; b2Set=3; }
            else if(g_corrBoldSym1 && g_corrDirSym1 < 0)  { b1Set=2; b2Set=4; }
            else if(g_corrBoldSym2 && g_corrDirSym2 > 0)  { b1Set=3; b2Set=1; }
            else if(g_corrBoldSym2 && g_corrDirSym2 < 0)  { b1Set=4; b2Set=2; }
            if(b1Set > 0 && b1Set != g_corrActiveSet)
               ApplySet(b1Set, b2Set);
         }
         else
            g_corrActiveSet = 0;
      }

      UpdateCorrData();  // тяжёлые рыночные запросы — раз в секунду
      UpdateCorrDashes(); // черточки опорной цены на графике
      UpdatePanel();
   }

   // Мигание CORR — каждые 40мс (плавная анимация)
   UpdateCorrBlink();
}

void OnTick()
{
   if(g_eaState == STATE_RUNNING)
      ProcessBlocks();
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      // Сначала проверяем клики CORR тест-панели
      if(CorrHandleClick(sparam))
      {
         // Сбрасываем физическое нажатие кнопки — состояние хранится в g_corrForce* флагах
         // Цвет кнопки обновляется в UpdateCorrLayout по этим флагам
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         return;
      }
      OnButtonClick(sparam);
   }

   static bool  s_dragging  = false;
   static int   s_dragOffX  = 0;
   static int   s_dragOffY  = 0;

   int dragH = 20;
   int dragY = PY - dragH - 2;

   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int mx = (int)lparam;
      int my = (int)dparam;
      bool lbtn = ((int)StringToInteger(sparam) & 1) != 0;

      if(!s_dragging && lbtn)
      {
         int pw = (int)ObjectGetInteger(0, g_prefix+"DRAG", OBJPROP_XSIZE);
         // DRAG_CORR расширяет зону перетаскивания вправо над CORR панелью
         int pwC = g_corrVisible ? pw + CORR_GAP + CORR_W : pw;
         if(mx >= PX && mx <= PX + pwC && my >= dragY && my <= dragY + dragH)
         {
            s_dragging = true;
            s_dragOffX = mx - PX;
            s_dragOffY = my - dragY;
            // Блокируем скролл графика на время перетаскивания
            ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
         }
      }
      else if(s_dragging && lbtn)
      {
         int newPX = MathMax(0, mx - s_dragOffX);
         int newPY = MathMax(dragH + 4, my - s_dragOffY + dragH + 2);
         if(newPX != PX || newPY != PY)
         {
            PX = newPX;
            PY = newPY;
            SavePanelPos();
            DeletePanel();
            CreatePanel();
            DeleteCorrPanel();
            CreateCorrPanel();
            UpdatePanel();
         }
      }
      else if(!lbtn && s_dragging)
      {
         s_dragging = false;
         // Восстанавливаем скролл графика
         ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
      }
   }
}

//============================================================
//  ЗАГРУЗКА НАСТРОЕК
//============================================================
void LoadBlockSettings()
{
   // Настройки блоков загружаются из выбранных сетов (кнопки S1-S4 на панели).
   // Если сет не выбран — оставляем текущие значения блока без изменений.
   if(g_selSet[0] > 0) ApplySetToBlock(g_block1, g_selSet[0]);
   if(g_selSet[1] > 0) ApplySetToBlock(g_block2, g_selSet[1]);
   // % закрытия блоков из общих настроек (переопределяют значение из сета)
   g_block1.closePercent = InpB1ClosePercent;
   g_block2.closePercent = InpB2ClosePercent;
   
   // Отладка: выводим значения closePercent после загрузки
   Print("LoadBlockSettings: B1.closePercent=", DoubleToString(g_block1.closePercent,2),
         "%, B2.closePercent=", DoubleToString(g_block2.closePercent,2), "%");
}

//============================================================
//  ЗАПУСК / ОСТАНОВКА
//============================================================
void StartEA()
{
   // Если EA уже запущен — перезапускаем только завершённые блоки (DONE/IDLE)
   if(g_eaState == STATE_RUNNING)
   {
      if(g_block1.enabled && (g_block1.state == BLOCK_DONE || g_block1.state == BLOCK_IDLE))
      {
         g_savedProfit1 = 0;
         bool en1 = true;
         g_block1 = SBlock();
         g_block1.enabled = en1;
         ApplySetToBlock(g_block1, g_selSet[0]);
         g_block1.closePercent = InpB1ClosePercent;
         StartBlock(g_block1, 1);
         Print("Блок 1 перезапущен (EA продолжает работу).");
      }
      if(g_block2.enabled && (g_block2.state == BLOCK_DONE || g_block2.state == BLOCK_IDLE))
      {
         g_savedProfit2 = 0;
         bool en2 = true;
         g_block2 = SBlock();
         g_block2.enabled = en2;
         ApplySetToBlock(g_block2, g_selSet[1]);
         g_block2.closePercent = InpB2ClosePercent;
         StartBlock(g_block2, 2);
         Print("Блок 2 перезапущен (EA продолжает работу).");
      }
      return;
   }

   g_eaState       = STATE_RUNNING;
   g_startDeposit  = AccountInfoDouble(ACCOUNT_BALANCE);
   g_stopLevelDepo = g_startDeposit * (1.0 + InpStopDepoPercent / 100.0);
   ParseStopTime();
   if(g_block1.enabled) StartBlock(g_block1, 1);
   if(g_block2.enabled) StartBlock(g_block2, 2);
   Print("Советник запущен. Депозит: ", g_startDeposit);
   PlaySound("alert.wav");
}

void StopEA(bool removeEA = false)
{
   CloseAllPositions();
   g_eaState      = STATE_STOPPED;
   g_block1.state = BLOCK_IDLE;
   g_block2.state = BLOCK_IDLE;
   g_savedProfit1 = 0;  // сброс при полной остановке
   g_savedProfit2 = 0;
   Print("Советник остановлен. Все позиции закрыты.");
   PlaySound("alert.wav");
   if(removeEA) ExpertRemove();
}

//============================================================
//  ЗАПУСК БЛОКА — ФАЗА 1
//  TP и SL — только на целевом ордере (Направление профита)
//============================================================
void StartBlock(SBlock &blk, int blockNum)
{
   blk.state        = BLOCK_PHASE1;
   blk.profitTaken  = false;
   blk.takenProfit  = 0;
   blk.cycleFinished = false;
   blk.startBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   double pt   = SymbolInfoDouble(blk.mainPair, SYMBOL_POINT);
   int    digs = (int)SymbolInfoInteger(blk.mainPair, SYMBOL_DIGITS);
   double ask  = SymbolInfoDouble(blk.mainPair, SYMBOL_ASK);
   double bid  = SymbolInfoDouble(blk.mainPair, SYMBOL_BID);
   double tpD  = blk.tp * pt;
   double slD  = blk.sl * pt;

   string bn   = IntegerToString(blockNum);

   trade.SetAsyncMode(false);

   if(blk.direction == DIR_BUY)
   {
      double tpB = NormalizeDouble(ask + tpD, digs);
      double slB = NormalizeDouble(ask - slD, digs);
      trade.SetExpertMagicNumber(GetMagic(blockNum, 1));
      if(trade.Buy(blk.mainLot, blk.mainPair, ask, slB, tpB, "CA_B"+bn+"_MAIN_BUY"))
         blk.ticketMainBuy = trade.ResultOrder();
      else
         Print("Блок ", bn, " ошибка BUY: ", trade.ResultRetcodeDescription());

      trade.SetExpertMagicNumber(GetMagic(blockNum, 2));
      if(trade.Sell(blk.mainLot, blk.mainPair, bid, 0, 0, "CA_B"+bn+"_MAIN_SELL"))
         blk.ticketMainSell = trade.ResultOrder();
      else
         Print("Блок ", bn, " ошибка SELL: ", trade.ResultRetcodeDescription());
   }
   else // DIR_SELL
   {
      double tpS = NormalizeDouble(bid - tpD, digs);
      double slS = NormalizeDouble(bid + slD, digs);
      trade.SetExpertMagicNumber(GetMagic(blockNum, 2));
      if(trade.Sell(blk.mainLot, blk.mainPair, bid, slS, tpS, "CA_B"+bn+"_MAIN_SELL"))
         blk.ticketMainSell = trade.ResultOrder();
      else
         Print("Блок ", bn, " ошибка SELL: ", trade.ResultRetcodeDescription());

      trade.SetExpertMagicNumber(GetMagic(blockNum, 1));
      if(trade.Buy(blk.mainLot, blk.mainPair, ask, 0, 0, "CA_B"+bn+"_MAIN_BUY"))
         blk.ticketMainBuy = trade.ResultOrder();
      else
         Print("Блок ", bn, " ошибка BUY: ", trade.ResultRetcodeDescription());
   }

   Print("Блок ", bn, " открыт: ticketBuy=", blk.ticketMainBuy, " ticketSell=", blk.ticketMainSell);
}

//============================================================
//  ОБРАБОТКА БЛОКОВ
//============================================================
void ProcessBlocks()
{
   // Защита от ложных срабатываний при перезагрузке:
   // MT5 может ещё не загрузить позиции в первые секунды после старта
   if(TimeCurrent() - g_initTime < INIT_DELAY_SEC)
   {
      static datetime s_lastPrint = 0;
      if(TimeCurrent() != s_lastPrint) {
         Print("ProcessBlocks заблокирован: ждём загрузки позиций. Осталось ",
               INIT_DELAY_SEC - (int)(TimeCurrent() - g_initTime), " сек.");
         s_lastPrint = TimeCurrent();
      }
      return;
   }

   if(g_block1.enabled && g_block1.state == BLOCK_PHASE1) CheckPhase1(g_block1, 1);
   if(g_block1.enabled && g_block1.state == BLOCK_PHASE2) CheckPhase2(g_block1, 1);
   if(g_block2.enabled && g_block2.state == BLOCK_PHASE1) CheckPhase1(g_block2, 2);
   if(g_block2.enabled && g_block2.state == BLOCK_PHASE2) CheckPhase2(g_block2, 2);
   CheckBlocksInteraction();
   CheckAutoRestart();
}

//============================================================
//  ФАЗА 1
//============================================================

//--- Проверяет, закрылся ли ордер по SL (профит отрицательный)
bool WasClosedBySL(ulong ticket)
{
   if(ticket == 0) return false;
   double profit = GetClosedProfit(ticket);
   return (profit < 0);
}

//--- Завершает блок: ставит BLOCK_DONE и помечает цикл завершённым
void FinishBlock(SBlock &blk, int blockNum)
{
   blk.state = BLOCK_DONE;
   blk.cycleFinished = true;
}
void CheckPhase1(SBlock &blk, int blockNum)
{
   if(blk.ticketMainBuy == 0 && blk.ticketMainSell == 0)
   { Print("Блок ", blockNum, ": тикеты=0, ожидаем."); return; }

   bool buyOpen  = IsPositionOpen(blk.ticketMainBuy);
   bool sellOpen = IsPositionOpen(blk.ticketMainSell);

   // Оба закрылись
   if(!buyOpen && !sellOpen)
   {
      double buyProfit  = GetClosedProfit(blk.ticketMainBuy);
      double sellProfit = GetClosedProfit(blk.ticketMainSell);
      
      // Защита: если история пустая для обоих тикетов — возможно MT5 ещё не загрузил позиции.
      // Ждём пока хотя бы один тикет появится в истории (exit deal).
      bool buyHasHistory  = (blk.ticketMainBuy  > 0 && HistorySelectByPosition(blk.ticketMainBuy)  && HistoryDealsTotal() > 0);
      bool sellHasHistory = (blk.ticketMainSell > 0 && HistorySelectByPosition(blk.ticketMainSell) && HistoryDealsTotal() > 0);
      
      // Если ни один тикет не нашёлся в истории — скорее всего позиции просто не загружены.
      // Пропускаем до следующего тика.
      if(!buyHasHistory && !sellHasHistory)
      {
         Print("Блок ", blockNum, ": оба тикета не найдены в истории — пропускаем (возможно MT5 не загрузил позиции).");
         return;
      }
      
      FinishBlock(blk, blockNum);
      bool   bySL   = (buyProfit < 0 || sellProfit < 0);
      string reason = bySL ? "SL достигнут!" : "Оба ордера закрыты (TP/вручную).";
      Print("Блок ", blockNum, ": ", reason,
            " BuyP=", DoubleToString(buyProfit,2),
            " SellP=", DoubleToString(sellProfit,2));
      PlaySound("alert.wav");
      Alert("Блок ", blockNum, ": ", reason);
      return;
   }

   if(blk.direction == DIR_BUY)
   {
      // BUY закрылся — определяем: TP или SL
      if(!buyOpen && sellOpen)
      {
         double closedProfit = GetClosedProfit(blk.ticketMainBuy);
         if(closedProfit < 0)
         {
            // SL сработал на целевом BUY — закрываем нецелевой SELL и завершаем блок
            Print("Блок ", blockNum, ": BUY SL! Убыток=", DoubleToString(closedProfit,2), ". Закрываем SELL.");
            ClosePosition(blk.ticketMainSell);
            FinishBlock(blk, blockNum);
            PlaySound("alert.wav");
            Alert("Блок ", blockNum, ": SL достигнут! Оба ордера закрыты. Блок завершён.");
            return;
         }
         else
         {
            // TP сработал — переход к фазе 2
            blk.takenProfit = closedProfit;
            blk.profitTaken = true;
            blk.ticketMain2 = blk.ticketMainSell;
            Print("Блок ", blockNum, ": BUY TP. Профит=", DoubleToString(blk.takenProfit,2));
            StartPhase2(blk, blockNum);
            return;
         }
      }
      // SELL закрылся раньше BUY — проверяем историю
      if(buyOpen && !sellOpen)
      {
         double sellProfit = GetClosedProfit(blk.ticketMainSell);
         if(sellProfit < 0)
         {
            // Реальный SL по нецелевому SELL
            Print("Блок ", blockNum, ": SELL SL досрочно. Убыток=", DoubleToString(sellProfit,2), ". Закрываем BUY.");
            ClosePosition(blk.ticketMainBuy);
            FinishBlock(blk, blockNum);
            PlaySound("alert.wav");
            Alert("Блок ", blockNum, ": SL достигнут! Оба ордера закрыты. Блок завершён.");
         }
         else
         {
            // SELL закрылся с профитом или нулём (TP / вручную) — переходим в Phase2
            Print("Блок ", blockNum, ": SELL закрылся с профитом=", DoubleToString(sellProfit,2), ". Переход Phase2.");
            blk.takenProfit = sellProfit;
            blk.profitTaken = true;
            blk.ticketMain2 = blk.ticketMainBuy;
            StartPhase2(blk, blockNum);
         }
         return;
      }
      // Ручной SL на нецелевом SELL (у него нет SL в MT5)
      CheckManualSL(blk, blockNum);
   }
   else // DIR_SELL
   {
      // SELL закрылся — определяем: TP или SL
      if(!sellOpen && buyOpen)
      {
         double closedProfit = GetClosedProfit(blk.ticketMainSell);
         if(closedProfit < 0)
         {
            // SL сработал на целевом SELL — закрываем нецелевой BUY и завершаем блок
            Print("Блок ", blockNum, ": SELL SL! Убыток=", DoubleToString(closedProfit,2), ". Закрываем BUY.");
            ClosePosition(blk.ticketMainBuy);
            FinishBlock(blk, blockNum);
            PlaySound("alert.wav");
            Alert("Блок ", blockNum, ": SL достигнут! Оба ордера закрыты. Блок завершён.");
            return;
         }
         else
         {
            // TP сработал
            blk.takenProfit = closedProfit;
            blk.profitTaken = true;
            blk.ticketMain2 = blk.ticketMainBuy;
            Print("Блок ", blockNum, ": SELL TP. Профит=", DoubleToString(blk.takenProfit,2));
            StartPhase2(blk, blockNum);
            return;
         }
      }
      // BUY закрылся раньше SELL — проверяем историю
      if(sellOpen && !buyOpen)
      {
         double buyProfit = GetClosedProfit(blk.ticketMainBuy);
         if(buyProfit < 0)
         {
            // Реальный SL по нецелевому BUY
            Print("Блок ", blockNum, ": BUY SL досрочно. Убыток=", DoubleToString(buyProfit,2), ". Закрываем SELL.");
            ClosePosition(blk.ticketMainSell);
            FinishBlock(blk, blockNum);
            PlaySound("alert.wav");
            Alert("Блок ", blockNum, ": SL достигнут! Оба ордера закрыты. Блок завершён.");
         }
         else
         {
            // BUY закрылся с профитом или нулём (TP / вручную) — переходим в Phase2
            Print("Блок ", blockNum, ": BUY закрылся с профитом=", DoubleToString(buyProfit,2), ". Переход Phase2.");
            blk.takenProfit = buyProfit;
            blk.profitTaken = true;
            blk.ticketMain2 = blk.ticketMainSell;
            StartPhase2(blk, blockNum);
         }
         return;
      }
      CheckManualSL(blk, blockNum);
   }
}

//--- Ручной SL для нецелевого ордера
void CheckManualSL(SBlock &blk, int blockNum)
{
   double pt   = SymbolInfoDouble(blk.mainPair, SYMBOL_POINT);
   double slD  = blk.sl * pt;

   if(blk.direction == DIR_BUY)
   {
      // Нецелевой — SELL. SL = если цена выросла на sl пунктов от цены открытия
      if(IsPositionOpen(blk.ticketMainSell) && PositionSelectByTicket(blk.ticketMainSell))
      {
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double curAsk    = SymbolInfoDouble(blk.mainPair, SYMBOL_ASK);
         if(curAsk - openPrice >= slD)
         {
            Print("Блок ", blockNum, ": ручной SL SELL (ask=", DoubleToString(curAsk,5),
                  " open=", DoubleToString(openPrice,5), " slD=", DoubleToString(slD,5), ") — закрытие обоих.");
            // ВАЖНО: сначала закрываем, потом Alert — Alert блокирует выполнение до нажатия OK
            { ulong _st[2]; _st[0]=blk.ticketMainBuy; _st[1]=blk.ticketMainSell; CloseTickets(_st,2); }
            FinishBlock(blk, blockNum);
            PlaySound("alert.wav");
            Alert("Блок ", blockNum, ": SL достигнут! Оба ордера закрыты. Блок завершён.");
         }
      }
   }
   else
   {
      // Нецелевой — BUY. SL = если цена упала на sl пунктов
      if(IsPositionOpen(blk.ticketMainBuy) && PositionSelectByTicket(blk.ticketMainBuy))
      {
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double curBid    = SymbolInfoDouble(blk.mainPair, SYMBOL_BID);
         if(openPrice - curBid >= slD)
         {
            Print("Блок ", blockNum, ": ручной SL BUY (bid=", DoubleToString(curBid,5),
                  " open=", DoubleToString(openPrice,5), " slD=", DoubleToString(slD,5), ") — закрытие обоих.");
            // ВАЖНО: сначала закрываем, потом Alert
            { ulong _st[2]; _st[0]=blk.ticketMainBuy; _st[1]=blk.ticketMainSell; CloseTickets(_st,2); }
            FinishBlock(blk, blockNum);
            PlaySound("alert.wav");
            Alert("Блок ", blockNum, ": SL достигнут! Оба ордера закрыты. Блок завершён.");
         }
      }
   }
}

//============================================================
//  ЗАПУСК ФАЗЫ 2
//============================================================
void StartPhase2(SBlock &blk, int blockNum)
{
   blk.state = BLOCK_PHASE2;
   blk.phase2CloseReady = false;  // сброс — ждём 10 сек после старта
   blk.phase2StartTime  = TimeCurrent();

   // Отладочный вывод для проверки closePercent
   Print("Блок ", blockNum, " Phase2: closePercent=", DoubleToString(blk.closePercent,2),
         "%, TP=", DoubleToString(blk.takenProfit,2), "$, targetClose=",
         DoubleToString(blk.takenProfit * blk.closePercent / 100.0, 2), "$");
   bool remainIsSell = (blk.direction == DIR_BUY);

   // Коррелирующий ордер — противовес оставшемуся в рынке
   ENUM_ORDER_TYPE corrDir;
   if(blk.correlation == CORR_INVERSE)
      corrDir = remainIsSell ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   else
      corrDir = remainIsSell ? ORDER_TYPE_BUY  : ORDER_TYPE_SELL;

   // SAFE: противовес оставшемуся ордеру на каждой паре
   ENUM_ORDER_TYPE safeMainDir = remainIsSell ? ORDER_TYPE_BUY  : ORDER_TYPE_SELL;
   ENUM_ORDER_TYPE safeCorrDir = (corrDir == ORDER_TYPE_SELL) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   string bn = IntegerToString(blockNum);

   // Открываем коррелирующий ордер
   blk.ticketCorr2 = OpenOrder(blk.corrPair, corrDir, blk.corrLot, "CA_B"+bn+"_CORR");

   // Открываем SAFE пары
   blk.ticketSafeMain = OpenOrder(blk.mainPair, safeMainDir, blk.safeLot, "CA_B"+bn+"_SAFE_M");
   blk.ticketSafeCorr = OpenOrder(blk.corrPair, safeCorrDir, blk.safeLot, "CA_B"+bn+"_SAFE_C");

   Print("Блок ", blockNum, " Фаза 2 запущена: CORR + SAFE открыты.");

   // Расчёт 5 уровней EXTRA
   // L1 = -takenProfit (технический старт)
   // Шаг = takenProfit * extraDeviation / 100
   // L2 = L1 - step, L3 = L1 - 2*step, L4 = L1 - 3*step, L5 = L1 - 4*step (технический конец)
   double step        = blk.takenProfit * blk.extraDeviation / 100.0;
   blk.extraLevel1    = -blk.takenProfit;
   blk.extraLevel2    = blk.extraLevel1 - step;
   blk.extraLevel3    = blk.extraLevel1 - step * 2.0;
   blk.extraLevel4    = blk.extraLevel1 - step * 3.0;
   blk.extraLevel5    = blk.extraLevel1 - step * 4.0;
   blk.visitedLevel1  = false;
   blk.visitedLevel2  = false;
   blk.visitedLevel3  = false;
   blk.visitedLevel4  = false;
   blk.visitedLevel5  = false;

   Print("Блок ", blockNum, " EXTRA уровни:",
         " L1=", DoubleToString(blk.extraLevel1,2),
         " L2=", DoubleToString(blk.extraLevel2,2),
         " L3=", DoubleToString(blk.extraLevel3,2),
         " L4=", DoubleToString(blk.extraLevel4,2),
         " L5=", DoubleToString(blk.extraLevel5,2),
         " (шаг=", DoubleToString(step,2), "$, TP=", DoubleToString(blk.takenProfit,2), "$)");
}

//============================================================
//  ФАЗА 2
//============================================================
void CheckPhase2(SBlock &blk, int blockNum)
{
   // mainBal — баланс MAIN двойки (ticketMain2 + ticketCorr2)
   // Используется для: уровней EXTRA, стоп-лосса, открытия EXTRA
   double mainBal  = GetPairBalance(blk.ticketMain2, blk.ticketCorr2);
   // totalBal — суммарный баланс всего блока
   // Используется только для: общего закрытия по closePercent
   double totalBal = GetBlockBalance(blk);

   // Разблокируем проверку закрытия через 10 секунд после старта фазы 2.
   if(!blk.phase2CloseReady && (TimeCurrent() - blk.phase2StartTime) >= 10)
      blk.phase2CloseReady = true;

   // СТОП-ЛОСС: привязан к балансу MAIN двойки
   // Пример: TP=10$, threshold=60% → стоп если mainBal <= -10-6=-16$
   if(blk.profitTaken && blk.takenProfit > 0)
   {
      double stopLevel = -blk.takenProfit - blk.takenProfit * blk.extraThreshold / 100.0;
      if(mainBal <= stopLevel)
      {
         Print("Блок ", blockNum, ": стоп-лосс по MAIN. mainBal=", DoubleToString(mainBal,2),
               "$ <= stopLevel=", DoubleToString(stopLevel,2),
               "$ (TP=", DoubleToString(blk.takenProfit,2), "$, threshold=",
               blk.extraThreshold, "%). Закрытие.");
         CloseBlock(blk, blockNum);
         return;
      }
   }

   // ОБЩЕЕ ЗАКРЫТИЕ % от TP — по суммарному балансу блока
   if(blk.profitTaken && blk.takenProfit > 0 && blk.phase2CloseReady)
   {
      double targetClose = blk.takenProfit * blk.closePercent / 100.0;
      if(totalBal >= targetClose)
      {
         Print("Блок ", blockNum, ": достигнут targetClose=", DoubleToString(targetClose,2),
               "$ (closePercent=", DoubleToString(blk.closePercent,2),
               "% от TP=", DoubleToString(blk.takenProfit,2),
               "$, totalBal=", DoubleToString(totalBal,2), "$). Закрытие.");
         CloseBlock(blk, blockNum);
         return;
      }
   }

   // EXTRA алгоритм — передаём mainBal (уровни привязаны к MAIN двойке)
   if(blk.extraAlgoEnabled && blk.profitTaken && blk.takenProfit > 0)
      ManageExtraOrders(blk, blockNum, mainBal);
}

//============================================================
//  УПРАВЛЕНИЕ EXTRA
//============================================================
//
//  Уровни (пример: TP=10$, deviation=20%):
//  L1=-10$ [tech]  L2=-12$ [work]  L3=-14$ [work]  L4=-16$ [work]  L5=-18$ [tech]
//
//  ОТКРЫТИЕ (каждый раз при достижении рабочего уровня, если пара не активна):
//    totalBal <= L2  → открыть EXTRA1
//    totalBal <= L3  → открыть EXTRA2
//    totalBal <= L4  → открыть EXTRA3
//
//  ЗАКРЫТИЕ по % (разблокируется только после посещения следующего уровня):
//    EXTRA1: разблокируется после посещения L3, закрывается когда баланс EXTRA1 >= extraClosePercent% от TP
//    EXTRA2: разблокируется после посещения L4, закрывается когда баланс EXTRA2 >= extraClosePercent% от TP
//    EXTRA3: разблокируется после посещения L5, закрывается когда баланс EXTRA3 >= extraClosePercent% от TP
//
//  После закрытия EXTRA по % — пара сбрасывается и может быть открыта снова при повторном
//  достижении своего уровня (многократное качание баланса в диапазоне уровней).
//
//  ЗАКРЫТИЕ БЛОКА: если фактический totalBal <= L4 (последний рабочий) → CloseBlock.
//
void ManageExtraOrders(SBlock &blk, int blockNum, double mainBal)
{
   // Направления EXTRA = те же что и SAFE (противовес основным ордерам)
   bool remainIsSell = (blk.direction == DIR_BUY);
   ENUM_ORDER_TYPE eMainDir = remainIsSell ? ORDER_TYPE_BUY  : ORDER_TYPE_SELL;
   ENUM_ORDER_TYPE eCorrDir;
   if(blk.correlation == CORR_INVERSE)
      eCorrDir = remainIsSell ? ORDER_TYPE_BUY  : ORDER_TYPE_SELL;
   else
      eCorrDir = remainIsSell ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;

   string bn  = IntegerToString(blockNum);
   // pct = целевая отметка закрытия EXTRA = takenProfit * extraClosePercent / 100
   double pct = blk.takenProfit * blk.extraClosePercent / 100.0;

   //----------------------------------------------------------
   // ОТКРЫТИЕ EXTRA1 при достижении L2
   //----------------------------------------------------------
   if(!blk.extra1Active && mainBal <= blk.extraLevel2)
   {
      ulong tm = OpenOrder(blk.mainPair, eMainDir, blk.extra1Lot, "CA_B"+bn+"_E1M");
      ulong tc = OpenOrder(blk.corrPair, eCorrDir, blk.extra1Lot, "CA_B"+bn+"_E1C");
      if(tm > 0 && tc > 0)
      {
         blk.ticketExtra1Main = tm;
         blk.ticketExtra1Corr = tc;
         blk.extra1Active  = true;
         blk.visitedLevel2 = true;
         blk.visitedLevel3 = false;
         blk.maxBalExtra1 = 0;
         Print("Блок ", blockNum, ": EXTRA1 открыта (bal=", DoubleToString(mainBal,2), "$)");
      }
      else
      {
         if(tm > 0) { trade.PositionClose(tm); }
         if(tc > 0) { trade.PositionClose(tc); }
         Print("Блок ", blockNum, ": EXTRA1 ошибка открытия — откат.");
      }
   }

   if(!blk.extra2Active && mainBal <= blk.extraLevel3)
   {
      ulong tm = OpenOrder(blk.mainPair, eMainDir, blk.extra2Lot, "CA_B"+bn+"_E2M");
      ulong tc = OpenOrder(blk.corrPair, eCorrDir, blk.extra2Lot, "CA_B"+bn+"_E2C");
      if(tm > 0 && tc > 0)
      {
         blk.ticketExtra2Main = tm;
         blk.ticketExtra2Corr = tc;
         blk.extra2Active  = true;
         blk.visitedLevel3 = true;
         blk.visitedLevel4 = false;
         blk.maxBalExtra2 = 0;
         Print("Блок ", blockNum, ": EXTRA2 открыта (bal=", DoubleToString(mainBal,2), "$)");
      }
      else
      {
         if(tm > 0) { trade.PositionClose(tm); }
         if(tc > 0) { trade.PositionClose(tc); }
         Print("Блок ", blockNum, ": EXTRA2 ошибка открытия — откат.");
      }
   }

   if(!blk.extra3Active && mainBal <= blk.extraLevel4)
   {
      ulong tm = OpenOrder(blk.mainPair, eMainDir, blk.extra3Lot, "CA_B"+bn+"_E3M");
      ulong tc = OpenOrder(blk.corrPair, eCorrDir, blk.extra3Lot, "CA_B"+bn+"_E3C");
      if(tm > 0 && tc > 0)
      {
         blk.ticketExtra3Main = tm;
         blk.ticketExtra3Corr = tc;
         blk.extra3Active  = true;
         blk.visitedLevel4 = true;
         blk.visitedLevel5 = false;
         blk.maxBalExtra3 = 0;
         Print("Блок ", blockNum, ": EXTRA3 открыта (bal=", DoubleToString(mainBal,2), "$)");
      }
      else
      {
         if(tm > 0) { trade.PositionClose(tm); }
         if(tc > 0) { trade.PositionClose(tc); }
         Print("Блок ", blockNum, ": EXTRA3 ошибка открытия — откат.");
      }
   }

   //----------------------------------------------------------
   // Фиксируем посещение L5 (технический — разблокирует закрытие EXTRA3)
   //----------------------------------------------------------
   // Фиксируем посещение уровней независимо от открытия EXTRA
   // Это разблокирует закрытие EXTRA по % даже если соответствующая пара уже была открыта ранее
   if(mainBal <= blk.extraLevel3) blk.visitedLevel3 = true;
   if(mainBal <= blk.extraLevel4) blk.visitedLevel4 = true;
   if(mainBal <= blk.extraLevel5) blk.visitedLevel5 = true;

   // Целевая отметка закрытия для всех двоек EXTRA (фиксированная, одинаковая)
   // = takenProfit * extraClosePercent / 100
   // Пример: TP=10$, extraClosePercent=0.8% → pct=0.08$

   //----------------------------------------------------------
   // ЗАКРЫТИЕ EXTRA по проценту — логика на ОБРАТНОМ ходу цены:
   //   1. Отслеживаем максимум баланса пока цена идёт вниз (maxBal растёт)
   //   2. Как только maxBal > pct (цель достигнута на пути вниз),
   //      закрываем пару когда баланс ОПУСКАЕТСЯ до pct на обратном ходу
   // Разблокировка: EXTRA1 — после посещения L3, EXTRA2 — L4, EXTRA3 — L5
   //----------------------------------------------------------

   // ЗАКРЫТИЕ EXTRA1 (разблокировано после посещения L3)
   if(blk.extra1Active && blk.visitedLevel3)
   {
      double b1 = GetPairBalance(blk.ticketExtra1Main, blk.ticketExtra1Corr);
      if(b1 > blk.maxBalExtra1) blk.maxBalExtra1 = b1;  // запоминаем пик
      // Закрываем когда: пик был достигнут (maxBal > pct) И баланс вернулся к pct
      if(blk.maxBalExtra1 > pct && b1 <= pct)
      {
         { ulong _et[2]; _et[0]=blk.ticketExtra1Main; _et[1]=blk.ticketExtra1Corr; CloseTickets(_et,2); }
         double peak1 = blk.maxBalExtra1;
         blk.extra1Active  = false;
         blk.visitedLevel2 = false;
         blk.visitedLevel3 = false;
         blk.maxBalExtra1  = 0;
         Print("Блок ", blockNum, ": EXTRA1 закрыта на обратном ходу. pct=",
               DoubleToString(pct,2), "$ peak=", DoubleToString(peak1,2),
               "$ cur=", DoubleToString(b1,2), "$");
      }
   }

   // ЗАКРЫТИЕ EXTRA2 (разблокировано после посещения L4)
   if(blk.extra2Active && blk.visitedLevel4)
   {
      double b2 = GetPairBalance(blk.ticketExtra2Main, blk.ticketExtra2Corr);
      if(b2 > blk.maxBalExtra2) blk.maxBalExtra2 = b2;
      if(blk.maxBalExtra2 > pct && b2 <= pct)
      {
         { ulong _et[2]; _et[0]=blk.ticketExtra2Main; _et[1]=blk.ticketExtra2Corr; CloseTickets(_et,2); }
         double peak2 = blk.maxBalExtra2;
         blk.extra2Active  = false;
         blk.visitedLevel3 = false;
         blk.visitedLevel4 = false;
         blk.maxBalExtra2  = 0;
         Print("Блок ", blockNum, ": EXTRA2 закрыта на обратном ходу. pct=",
               DoubleToString(pct,2), "$ peak=", DoubleToString(peak2,2),
               "$ cur=", DoubleToString(b2,2), "$");
      }
   }

   // ЗАКРЫТИЕ EXTRA3 (разблокировано после посещения L5)
   if(blk.extra3Active && blk.visitedLevel5)
   {
      double b3 = GetPairBalance(blk.ticketExtra3Main, blk.ticketExtra3Corr);
      if(b3 > blk.maxBalExtra3) blk.maxBalExtra3 = b3;
      if(blk.maxBalExtra3 > pct && b3 <= pct)
      {
         { ulong _et[2]; _et[0]=blk.ticketExtra3Main; _et[1]=blk.ticketExtra3Corr; CloseTickets(_et,2); }
         double peak3 = blk.maxBalExtra3;
         blk.extra3Active  = false;
         blk.visitedLevel4 = false;
         blk.visitedLevel5 = false;
         blk.maxBalExtra3  = 0;
         Print("Блок ", blockNum, ": EXTRA3 закрыта на обратном ходу. pct=",
               DoubleToString(pct,2), "$ peak=", DoubleToString(peak3,2),
               "$ cur=", DoubleToString(b3,2), "$");
      }
   }
}

//============================================================
//  ВЗАИМОДЕЙСТВИЕ БЛОКОВ
//============================================================
void CheckBlocksInteraction()
{
   // Ситуация А: один блок взял профит, второй нет →
   //   обрабатывается в CloseBlock при закрытии первого блока
   // Ситуация Б: оба взяли профит → каждый закрывается самостоятельно в CheckPhase2
   // Ситуация В: общий % от депозита → обрабатывается в CheckGlobalStops
}

//============================================================
//  ЗАКРЫТИЕ БЛОКА
//============================================================
void CloseBlock(SBlock &blk, int blockNum)
{
   // Сохраняем накопленную прибыль блока для отображения в следующем цикле
   double finalProfit = blk.takenProfit + GetBlockBalance(blk);
   if(blockNum == 1) g_savedProfit1 = finalProfit;
   else              g_savedProfit2 = finalProfit;

   ulong t[12];
   t[0]=blk.ticketMainBuy;    t[1]=blk.ticketMainSell;
   t[2]=blk.ticketMain2;      t[3]=blk.ticketCorr2;
   t[4]=blk.ticketSafeMain;   t[5]=blk.ticketSafeCorr;
   t[6]=blk.ticketExtra1Main; t[7]=blk.ticketExtra1Corr;
   t[8]=blk.ticketExtra2Main; t[9]=blk.ticketExtra2Corr;
   t[10]=blk.ticketExtra3Main;t[11]=blk.ticketExtra3Corr;
   CloseTickets(t, 12);
   blk.state = BLOCK_DONE;
   blk.cycleFinished = true;
   
   // Сбрасываем все кнопки в серый цвет по завершению блока
   string pfx = (blockNum == 1) ? "B1_" : "B2_";
   SetBtnGray(pfx, "MAIN");
   SetBtnGray(pfx, "SAFE");
   SetBtnGray(pfx, "EXTRA1");
   SetBtnGray(pfx, "EXTRA2");
   SetBtnGray(pfx, "EXTRA3");
   
   Print("Блок ", blockNum, " закрыт. Итог=", DoubleToString(finalProfit,2), "$");
   PlaySound("alert.wav");

   // Ситуация А: этот блок завершил полный цикл →
   // если второй блок ещё активен (PHASE1 или PHASE2), закрываем его одновременно
   if(blk.profitTaken)
   {
      if(blockNum == 1)
      {
         bool otherActive = g_block2.enabled &&
                            (g_block2.state == BLOCK_PHASE1 || g_block2.state == BLOCK_PHASE2);
         if(otherActive)
         {
            double otherFinal = g_block2.takenProfit + GetBlockBalance(g_block2);
            g_savedProfit2 = otherFinal;
            ulong t2[12];
            t2[0]=g_block2.ticketMainBuy;    t2[1]=g_block2.ticketMainSell;
            t2[2]=g_block2.ticketMain2;      t2[3]=g_block2.ticketCorr2;
            t2[4]=g_block2.ticketSafeMain;   t2[5]=g_block2.ticketSafeCorr;
            t2[6]=g_block2.ticketExtra1Main; t2[7]=g_block2.ticketExtra1Corr;
            t2[8]=g_block2.ticketExtra2Main; t2[9]=g_block2.ticketExtra2Corr;
            t2[10]=g_block2.ticketExtra3Main;t2[11]=g_block2.ticketExtra3Corr;
            CloseTickets(t2, 12);
            g_block2.state = BLOCK_DONE;
            g_block2.cycleFinished = true;
            SetBtnGray("B2_", "MAIN"); SetBtnGray("B2_", "SAFE");
            SetBtnGray("B2_", "EXTRA1"); SetBtnGray("B2_", "EXTRA2"); SetBtnGray("B2_", "EXTRA3");
            Print("Блок 1 завершил цикл — блок 2 закрыт одновременно. Итог=",
                  DoubleToString(otherFinal,2), "$");
            PlaySound("alert.wav");
         }
      }
      else
      {
         bool otherActive = g_block1.enabled &&
                            (g_block1.state == BLOCK_PHASE1 || g_block1.state == BLOCK_PHASE2);
         if(otherActive)
         {
            double otherFinal = g_block1.takenProfit + GetBlockBalance(g_block1);
            g_savedProfit1 = otherFinal;
            ulong t2[12];
            t2[0]=g_block1.ticketMainBuy;    t2[1]=g_block1.ticketMainSell;
            t2[2]=g_block1.ticketMain2;      t2[3]=g_block1.ticketCorr2;
            t2[4]=g_block1.ticketSafeMain;   t2[5]=g_block1.ticketSafeCorr;
            t2[6]=g_block1.ticketExtra1Main; t2[7]=g_block1.ticketExtra1Corr;
            t2[8]=g_block1.ticketExtra2Main; t2[9]=g_block1.ticketExtra2Corr;
            t2[10]=g_block1.ticketExtra3Main;t2[11]=g_block1.ticketExtra3Corr;
            CloseTickets(t2, 12);
            g_block1.state = BLOCK_DONE;
            g_block1.cycleFinished = true;
            SetBtnGray("B1_", "MAIN"); SetBtnGray("B1_", "SAFE");
            SetBtnGray("B1_", "EXTRA1"); SetBtnGray("B1_", "EXTRA2"); SetBtnGray("B1_", "EXTRA3");
            Print("Блок 2 завершил цикл — блок 1 закрыт одновременно. Итог=",
                  DoubleToString(otherFinal,2), "$");
            PlaySound("alert.wav");
         }
      }
   }
   // CheckAutoRestart НЕ вызывается здесь — только из ProcessBlocks.
   // Это гарантирует что STOP1/STOP2 не приведут к автоперезапуску.
}


//============================================================
//  ГЛОБАЛЬНЫЕ СТОПЫ
//============================================================
void CheckGlobalStops()
{
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   // STOP DEPO — всегда активен
   if(InpStopDepoPercent < 0 && g_stopLevelDepo > 0 && equity <= g_stopLevelDepo)
   {
      Print("STOP DEPO: просадка ", InpStopDepoPercent, "%");
      StopEA(true); return;
   }

   // STOP % — включается только после взятия профита в любом блоке (TP-триггер)
   bool anyProfitTaken = (g_block1.enabled && g_block1.profitTaken) ||
                         (g_block2.enabled && g_block2.profitTaken);
   if(anyProfitTaken && InpStopPercent > 0)
   {
      double pct = (balance - g_startDeposit) / g_startDeposit * 100.0;
      if(pct >= InpStopPercent)
      {
         Print("STOP %: профит ", InpStopPercent, "% достигнут после взятия TP.");
         StopEA(true); return;
      }
   }

   // STOP TIME
   if(g_stopTime > 0 && TimeCurrent() >= g_stopTime)
   {
      Print("STOP TIME");
      StopEA(true); return;
   }
}

//============================================================
//  АВТОПЕРЕЗАПУСК
//============================================================
void CheckAutoRestart()
{
   bool b1done = (!g_block1.enabled || g_block1.state == BLOCK_DONE);
   bool b2done = (!g_block2.enabled || g_block2.state == BLOCK_DONE);
   if(!b1done || !b2done) return;
   Print("Полный цикл завершен.");
   PlaySound("alert.wav");
   if(InpAutoRestart)
   {
      g_savedProfit1 = 0;
      g_savedProfit2 = 0;
      bool en1 = g_block1.enabled;
      bool en2 = g_block2.enabled;
      g_block1 = SBlock(); g_block1.enabled = en1;
      g_block2 = SBlock(); g_block2.enabled = en2;
      LoadBlockSettings();
      g_eaState = STATE_STANDBY;
      StartEA();
   }
   else
      g_eaState = STATE_STANDBY;
}

//============================================================
//  ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
//============================================================
ulong OpenOrder(string symbol, ENUM_ORDER_TYPE type, double lot, string comment)
{
   double price = (type==ORDER_TYPE_BUY) ?
                  SymbolInfoDouble(symbol,SYMBOL_ASK) :
                  SymbolInfoDouble(symbol,SYMBOL_BID);
   trade.SetExpertMagicNumber(1001);
   bool res = (type==ORDER_TYPE_BUY) ?
              trade.Buy(lot,symbol,price,0,0,comment) :
              trade.Sell(lot,symbol,price,0,0,comment);
   if(res) return trade.ResultOrder();
   Print("Ошибка открытия ",comment,": ",trade.ResultRetcodeDescription());
   return 0;
}

bool IsPositionOpen(ulong ticket)
{
   if(ticket==0) return false;
   return PositionSelectByTicket(ticket);
}

bool ClosePosition(ulong ticket)
{
   if(ticket==0) return false;
   if(!PositionSelectByTicket(ticket)) return false;
   return trade.PositionClose(ticket);
}

double GetPairBalance(ulong t1, ulong t2)
{
   double p = 0;
   if(t1 > 0 && PositionSelectByTicket(t1))
   {
      p += PositionGetDouble(POSITION_PROFIT);
      // После выбора t1 сразу читаем — не даём контексту переключиться
   }
   if(t2 > 0 && t2 != t1 && PositionSelectByTicket(t2))
   {
      p += PositionGetDouble(POSITION_PROFIT);
   }
   return p;
}

double GetBlockBalance(SBlock &blk)
{
   double total = 0;
   ulong t[10];
   t[0]=blk.ticketMain2;      t[1]=blk.ticketCorr2;
   t[2]=blk.ticketSafeMain;   t[3]=blk.ticketSafeCorr;
   t[4]=blk.ticketExtra1Main; t[5]=blk.ticketExtra1Corr;
   t[6]=blk.ticketExtra2Main; t[7]=blk.ticketExtra2Corr;
   t[8]=blk.ticketExtra3Main; t[9]=blk.ticketExtra3Corr;
   for(int i = 0; i < 10; i++)
   {
      if(t[i] == 0) continue;
      // Защита от дублирующихся тикетов
      bool dup = false;
      for(int j = 0; j < i; j++) if(t[j] == t[i]) { dup = true; break; }
      if(dup) continue;
      if(PositionSelectByTicket(t[i]))
         total += PositionGetDouble(POSITION_PROFIT);
   }
   return total;
}

double GetBlockBalancePhase1(SBlock &blk)
{
   return GetPairBalance(blk.ticketMainBuy,blk.ticketMainSell);
}

// Синхронное закрытие списка позиций — все запросы отправляются подряд
// без ожидания подтверждения каждого. Дубли пропускаются.
void CloseTickets(ulong &tickets[], int count)
{
   trade.SetAsyncMode(true);
   for(int i = 0; i < count; i++)
   {
      if(tickets[i] == 0) continue;
      bool dup = false;
      for(int j = 0; j < i; j++) if(tickets[j] == tickets[i]) { dup = true; break; }
      if(dup) continue;
      if(PositionSelectByTicket(tickets[i]))
         trade.PositionClose(tickets[i]);
   }
   trade.SetAsyncMode(false);
}

void CloseAllPositions()
{
   int total = PositionsTotal();
   ulong tickets[];
   ArrayResize(tickets, total);
   for(int i = 0; i < total; i++)
      tickets[i] = PositionGetTicket(i);
   trade.SetAsyncMode(true);
   for(int i = total - 1; i >= 0; i--)
      if(tickets[i] > 0) trade.PositionClose(tickets[i]);
   trade.SetAsyncMode(false);
}

long GetMagic(int bn,int on) { return 10000+bn*100+on; }

double GetClosedProfit(ulong ticket)
{
   double profit = 0;
   if(ticket == 0) return 0;
   HistorySelect(0, TimeCurrent());
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(deal, DEAL_POSITION_ID) == (long)ticket &&
         HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_OUT)
      {
         profit += HistoryDealGetDouble(deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(deal, DEAL_SWAP)
                 + HistoryDealGetDouble(deal, DEAL_COMMISSION);
      }
   }
   return profit;
}

void ParseStopTime()
{
   string p[];
   if(StringSplit(InpStopTime,':',p)==2)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(),dt);
      dt.hour=(int)StringToInteger(p[0]);
      dt.min =(int)StringToInteger(p[1]);
      dt.sec =0;
      g_stopTime=StructToTime(dt);
      if(g_stopTime<TimeCurrent()) g_stopTime+=86400;
   }
}

//============================================================
//  СОХРАНЕНИЕ / ВОССТАНОВЛЕНИЕ СОСТОЯНИЯ (после прерывания сессии)
//  Используем GlobalVariables MT5 — они сохраняются между сессиями
//============================================================
string GV(string key) { return g_prefix + key; }  // префикс для GlobalVariable

void SaveBlockState(SBlock &blk, string pfx)
{
   GlobalVariableSet(GV(pfx+"enabled"),      blk.enabled ? 1.0 : 0.0);  // ДОБАВЛЕНО
   GlobalVariableSet(GV(pfx+"cycleDone"),    blk.cycleFinished ? 1.0 : 0.0);
   GlobalVariableSet(GV(pfx+"state"),        (double)blk.state);
   GlobalVariableSet(GV(pfx+"profitTaken"),  blk.profitTaken ? 1.0 : 0.0);
   GlobalVariableSet(GV(pfx+"takenProfit"),  blk.takenProfit);
   GlobalVariableSet(GV(pfx+"startBal"),     blk.startBalance);
   GlobalVariableSet(GV(pfx+"extraEnabled"), blk.extraAlgoEnabled ? 1.0 : 0.0);
   // Тикеты открытых позиций
   GlobalVariableSet(GV(pfx+"tMainBuy"),   (double)blk.ticketMainBuy);
   GlobalVariableSet(GV(pfx+"tMainSell"),  (double)blk.ticketMainSell);
   GlobalVariableSet(GV(pfx+"tMain2"),     (double)blk.ticketMain2);
   GlobalVariableSet(GV(pfx+"tCorr2"),     (double)blk.ticketCorr2);
   GlobalVariableSet(GV(pfx+"tSafeMain"),  (double)blk.ticketSafeMain);
   GlobalVariableSet(GV(pfx+"tSafeCorr"),  (double)blk.ticketSafeCorr);
   GlobalVariableSet(GV(pfx+"tE1M"),       (double)blk.ticketExtra1Main);
   GlobalVariableSet(GV(pfx+"tE1C"),       (double)blk.ticketExtra1Corr);
   GlobalVariableSet(GV(pfx+"tE2M"),       (double)blk.ticketExtra2Main);
   GlobalVariableSet(GV(pfx+"tE2C"),       (double)blk.ticketExtra2Corr);
   GlobalVariableSet(GV(pfx+"tE3M"),       (double)blk.ticketExtra3Main);
   GlobalVariableSet(GV(pfx+"tE3C"),       (double)blk.ticketExtra3Corr);
   // Флаги EXTRA
   GlobalVariableSet(GV(pfx+"e1Active"),   blk.extra1Active  ? 1.0 : 0.0);
   GlobalVariableSet(GV(pfx+"e2Active"),   blk.extra2Active  ? 1.0 : 0.0);
   GlobalVariableSet(GV(pfx+"e3Active"),   blk.extra3Active  ? 1.0 : 0.0);
   GlobalVariableSet(GV(pfx+"vis2"),       blk.visitedLevel2 ? 1.0 : 0.0);
   GlobalVariableSet(GV(pfx+"vis3"),       blk.visitedLevel3 ? 1.0 : 0.0);
   GlobalVariableSet(GV(pfx+"vis4"),       blk.visitedLevel4 ? 1.0 : 0.0);
   GlobalVariableSet(GV(pfx+"vis5"),       blk.visitedLevel5 ? 1.0 : 0.0);
   // Уровни EXTRA
   GlobalVariableSet(GV(pfx+"lvl1"),  blk.extraLevel1);
   GlobalVariableSet(GV(pfx+"lvl2"),  blk.extraLevel2);
   GlobalVariableSet(GV(pfx+"lvl3"),  blk.extraLevel3);
   GlobalVariableSet(GV(pfx+"lvl4"),  blk.extraLevel4);
   GlobalVariableSet(GV(pfx+"lvl5"),  blk.extraLevel5);
   // Предыдущие балансы EXTRA для определения пересечения
   GlobalVariableSet(GV(pfx+"maxE1"), blk.maxBalExtra1);
   GlobalVariableSet(GV(pfx+"maxE2"), blk.maxBalExtra2);
   GlobalVariableSet(GV(pfx+"maxE3"), blk.maxBalExtra3);
   GlobalVariableSet(GV(pfx+"p2ready"), blk.phase2CloseReady ? 1.0 : 0.0);
   GlobalVariableSet(GV(pfx+"p2start"), (double)blk.phase2StartTime);
}

void SaveState()
{
   GlobalVariableSet(GV("eaState"),      (double)g_eaState);
   GlobalVariableSet(GV("startDeposit"), g_startDeposit);
   GlobalVariableSet(GV("stopLevelDepo"),g_stopLevelDepo);
   GlobalVariableSet(GV("stopTime"),     (double)g_stopTime);
   // Сохраняем выбранные сеты
   GlobalVariableSet(GV("selSet0"),      (double)g_selSet[0]);
   GlobalVariableSet(GV("selSet1"),      (double)g_selSet[1]);
   SaveBlockState(g_block1, "B1_");
   SaveBlockState(g_block2, "B2_");
}

bool RestoreBlockState(SBlock &blk, string pfx)
{
   if(!GlobalVariableCheck(GV(pfx+"state"))) return false;

   blk.enabled       = GlobalVariableCheck(GV(pfx+"enabled")) && 
                       GlobalVariableGet(GV(pfx+"enabled")) > 0.5;  // ДОБАВЛЕНО
   blk.cycleFinished = GlobalVariableCheck(GV(pfx+"cycleDone")) &&
                       GlobalVariableGet(GV(pfx+"cycleDone")) > 0.5;
   blk.state         = (ENUM_BLOCK_STATE)(int)GlobalVariableGet(GV(pfx+"state"));
   blk.profitTaken  = GlobalVariableGet(GV(pfx+"profitTaken")) > 0.5;
   blk.takenProfit  = GlobalVariableGet(GV(pfx+"takenProfit"));
   blk.startBalance = GlobalVariableGet(GV(pfx+"startBal"));
   blk.extraAlgoEnabled = GlobalVariableGet(GV(pfx+"extraEnabled")) > 0.5;

   blk.ticketMainBuy    = (ulong)GlobalVariableGet(GV(pfx+"tMainBuy"));
   blk.ticketMainSell   = (ulong)GlobalVariableGet(GV(pfx+"tMainSell"));
   blk.ticketMain2      = (ulong)GlobalVariableGet(GV(pfx+"tMain2"));
   blk.ticketCorr2      = (ulong)GlobalVariableGet(GV(pfx+"tCorr2"));
   blk.ticketSafeMain   = (ulong)GlobalVariableGet(GV(pfx+"tSafeMain"));
   blk.ticketSafeCorr   = (ulong)GlobalVariableGet(GV(pfx+"tSafeCorr"));
   blk.ticketExtra1Main = (ulong)GlobalVariableGet(GV(pfx+"tE1M"));
   blk.ticketExtra1Corr = (ulong)GlobalVariableGet(GV(pfx+"tE1C"));
   blk.ticketExtra2Main = (ulong)GlobalVariableGet(GV(pfx+"tE2M"));
   blk.ticketExtra2Corr = (ulong)GlobalVariableGet(GV(pfx+"tE2C"));
   blk.ticketExtra3Main = (ulong)GlobalVariableGet(GV(pfx+"tE3M"));
   blk.ticketExtra3Corr = (ulong)GlobalVariableGet(GV(pfx+"tE3C"));

   blk.extra1Active  = GlobalVariableGet(GV(pfx+"e1Active")) > 0.5;
   blk.extra2Active  = GlobalVariableGet(GV(pfx+"e2Active")) > 0.5;
   blk.extra3Active  = GlobalVariableGet(GV(pfx+"e3Active")) > 0.5;
   blk.visitedLevel2 = GlobalVariableGet(GV(pfx+"vis2")) > 0.5;
   blk.visitedLevel3 = GlobalVariableGet(GV(pfx+"vis3")) > 0.5;
   blk.visitedLevel4 = GlobalVariableGet(GV(pfx+"vis4")) > 0.5;
   blk.visitedLevel5 = GlobalVariableGet(GV(pfx+"vis5")) > 0.5;

   blk.extraLevel1 = GlobalVariableGet(GV(pfx+"lvl1"));
   blk.extraLevel2 = GlobalVariableGet(GV(pfx+"lvl2"));
   blk.extraLevel3 = GlobalVariableGet(GV(pfx+"lvl3"));
   blk.extraLevel4 = GlobalVariableGet(GV(pfx+"lvl4"));
   blk.extraLevel5 = GlobalVariableGet(GV(pfx+"lvl5"));

   blk.maxBalExtra1 = GlobalVariableGet(GV(pfx+"maxE1"));
   blk.maxBalExtra2 = GlobalVariableGet(GV(pfx+"maxE2"));
   blk.maxBalExtra3 = GlobalVariableGet(GV(pfx+"maxE3"));
   blk.phase2CloseReady = GlobalVariableCheck(GV(pfx+"p2ready")) &&
                          GlobalVariableGet(GV(pfx+"p2ready")) > 0.5;
   blk.phase2StartTime  = GlobalVariableCheck(GV(pfx+"p2start")) ?
                          (datetime)GlobalVariableGet(GV(pfx+"p2start")) : TimeCurrent();
   return true;
}

bool RestoreState()
{
   if(!GlobalVariableCheck(GV("eaState"))) return false;

   g_eaState       = (ENUM_EA_STATE)(int)GlobalVariableGet(GV("eaState"));
   g_startDeposit  = GlobalVariableGet(GV("startDeposit"));
   g_stopLevelDepo = GlobalVariableGet(GV("stopLevelDepo"));
   g_stopTime      = (datetime)GlobalVariableGet(GV("stopTime"));
   
   // Восстанавливаем выбранные сеты
   if(GlobalVariableCheck(GV("selSet0")))
      g_selSet[0] = (int)GlobalVariableGet(GV("selSet0"));
   if(GlobalVariableCheck(GV("selSet1")))
      g_selSet[1] = (int)GlobalVariableGet(GV("selSet1"));

   RestoreBlockState(g_block1, "B1_");
   RestoreBlockState(g_block2, "B2_");
   if(g_selSet[0] > 0) ApplySetToBlock(g_block1, g_selSet[0]);
   if(g_selSet[1] > 0) ApplySetToBlock(g_block2, g_selSet[1]);

   Print("Состояние восстановлено. EA State=", (int)g_eaState,
         " B1=", BlockStateStr(g_block1.state), " enabled=", g_block1.enabled,
         " B2=", BlockStateStr(g_block2.state), " enabled=", g_block2.enabled,
         " Sets=", g_selSet[0], ",", g_selSet[1],
         " B1.main=", g_block1.mainPair, " B2.main=", g_block2.mainPair);
   return true;
}

void ClearState()
{
   // Удаляем все GlobalVariables советника вручную по префиксу
   int total = GlobalVariablesTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      string varName = GlobalVariableName(i);
      if(StringFind(varName, g_prefix) == 0)
         GlobalVariableDel(varName);
   }
   Print("Сохранённое состояние очищено.");
}

string BlockStateStr(ENUM_BLOCK_STATE st)
{
   if(st==BLOCK_IDLE)   return "IDLE";
   if(st==BLOCK_PHASE1) return "PH1";
   if(st==BLOCK_PHASE2) return "PH2";
   if(st==BLOCK_DONE)   return "DONE";
   return "?";
}

//============================================================
//  ПАНЕЛЬ УПРАВЛЕНИЯ
//============================================================
void CreatePanel()
{
   int PAD  = 6;    // внутренний отступ панели
   int GAP  = 4;    // зазор между элементами в строке
   int VGAP = 4;    // вертикальный зазор между строками
   int IP   = 4;    // внутренний отступ рамок подблоков (MAIN+SAFE, EXTRA)

   // Высоты строк
   int RH0  = 34;   // START / STOP / BLOCK — размер кнопок
   int RHB  = 30;   // BLOCK 1/2 кнопки (-10% от RH0)
   int RH0_ROW = 56; // высота строки START (кнопки центрируются внутри)
   int RH2  = 26;   // STOP1/BAL1
   int RHR  = 22;   // строка пары (MAIN/SAFE/EXTRA) — теперь = высоте кнопок
   int RHS  = 16;   // STATUS

   // Ширины элементов строки пары
   int LBL_W = 78;  // метка названия двойки (было 70, +8px для размещения EXTRA1/EXTRA2/EXTRA3)
   int BTN_W = 78;  // OPEN / CLOSE (было 86, -8px для балансов)
   int BAL_W = 68;  // баланс двойки — "-99.99$" (было 52)

   // COL_W = только LBL + OPEN + CLOSE + зазоры — без BAL
   // Рамки и границы блока строятся по этой ширине
   int COL_W = LBL_W + BTN_W*2 + GAP*2;

   // COL2_X начинается сразу после BAL блока 1 (BAL — текст между блоками)
   int COL1_X = PX + PAD;
   int COL2_X = COL1_X + COL_W + BAL_W + GAP;   // LBL блока 2 вплотную после цифр блока 1
   int PNL_W  = COL2_X + COL_W + BAL_W + PAD - PX;

   // X кнопок OPEN для каждой колонки
   int ox  = COL1_X + LBL_W + GAP + 8;
   int ox2 = COL2_X + LBL_W + GAP + 8;

   int btnW0 = 99;   // ширина START / STOP / BLOCK кнопок (-10%)

   // --- Вычисляем Y-координаты ---
   int y0   = PY + PAD - 4;                  // Строка 0: START + БАЛАНС + STOP (чуть выше рамки)

   int yB   = y0 + RH0_ROW + VGAP + 4;      // Строка BLOCK1 / BLOCK2
   int yS1  = yB + RH0 + VGAP;             // STOP1/BAL1 и STOP2/BAL2

   // Обрамление подблока MAIN+SAFE
   int yMS    = yS1 + RH2 + VGAP + IP;     // MAIN
   int yS     = yMS + RHR + VGAP;          // SAFE
   int yMSend = yS  + RHR + IP;            // конец подблока MAIN+SAFE

   // Обрамление подблока EXTRA
   int yEX    = yMSend + VGAP + IP;        // EXTRA1
   int yE2    = yEX + RHR + VGAP;          // EXTRA2
   int yE3    = yE2 + RHR + VGAP;          // EXTRA3
   int yEON   = yE3 + RHR + VGAP;         // AUTO/MANUAL кнопки
   int yEXend = yEON + RHR + IP;           // конец подблока EXTRA

   int yStatus = yEXend + VGAP + PAD;
   int PNL_H   = yStatus + RHS + PAD - PY;

   //----------------------------------------------------------
   // ПОЛОСКА ПЕРЕТАСКИВАНИЯ (drag handle) — над панелью
   //----------------------------------------------------------
   int dragH = 20;
   int dragY = PY - dragH - 2;
   // Чёрная заплатка между полоской и панелью — закрывает просвет графика
   PanelRect(g_prefix+"DRAG_GAP", PX, dragY + dragH, PNL_W, PY - (dragY + dragH) + 1, C_BG, C_BG);
   ObjectCreate(0, g_prefix+"DRAG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_prefix+"DRAG", OBJPROP_XDISTANCE,   PX);
   ObjectSetInteger(0, g_prefix+"DRAG", OBJPROP_YDISTANCE,   dragY);
   ObjectSetInteger(0, g_prefix+"DRAG", OBJPROP_XSIZE,       PNL_W);
   ObjectSetInteger(0, g_prefix+"DRAG", OBJPROP_YSIZE,       dragH);
   ObjectSetInteger(0, g_prefix+"DRAG", OBJPROP_BGCOLOR,     C'30,60,90');
   ObjectSetInteger(0, g_prefix+"DRAG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, g_prefix+"DRAG", OBJPROP_BORDER_COLOR,C'60,120,180');
   ObjectSetInteger(0, g_prefix+"DRAG", OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0, g_prefix+"DRAG", OBJPROP_SELECTABLE,  true);
   ObjectSetInteger(0, g_prefix+"DRAG", OBJPROP_SELECTED,    false);
   ObjectSetInteger(0, g_prefix+"DRAG", OBJPROP_HIDDEN,      false);
   ObjectSetInteger(0, g_prefix+"DRAG", OBJPROP_ZORDER,      10);
   // Текстовая метка на полоске — убрана по запросу
   // Расширение drag-bar над CORR панелью (видно только когда CORR видна)
   if(ObjectFind(0, g_prefix+"DRAG_CORR") < 0)
      ObjectCreate(0, g_prefix+"DRAG_CORR", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   {
      int corrDragX = PX + PNL_W + CORR_GAP;
      int corrDragW = CORR_W;
      ObjectSetInteger(0, g_prefix+"DRAG_CORR", OBJPROP_XDISTANCE,   corrDragX);
      ObjectSetInteger(0, g_prefix+"DRAG_CORR", OBJPROP_YDISTANCE,   dragY);
      ObjectSetInteger(0, g_prefix+"DRAG_CORR", OBJPROP_XSIZE,       corrDragW);
      ObjectSetInteger(0, g_prefix+"DRAG_CORR", OBJPROP_YSIZE,       dragH);
      ObjectSetInteger(0, g_prefix+"DRAG_CORR", OBJPROP_BGCOLOR,     C'30,60,90');
      ObjectSetInteger(0, g_prefix+"DRAG_CORR", OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, g_prefix+"DRAG_CORR", OBJPROP_BORDER_COLOR,C'60,120,180');
      ObjectSetInteger(0, g_prefix+"DRAG_CORR", OBJPROP_CORNER,      CORNER_LEFT_UPPER);
      ObjectSetInteger(0, g_prefix+"DRAG_CORR", OBJPROP_SELECTABLE,  true);
      ObjectSetInteger(0, g_prefix+"DRAG_CORR", OBJPROP_SELECTED,    false);
      ObjectSetInteger(0, g_prefix+"DRAG_CORR", OBJPROP_HIDDEN,      false);
      ObjectSetInteger(0, g_prefix+"DRAG_CORR", OBJPROP_ZORDER,      10);
      // Видимость: только когда CORR панель видна
      ObjectSetInteger(0, g_prefix+"DRAG_CORR", OBJPROP_TIMEFRAMES,
         g_corrVisible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   }

   //----------------------------------------------------------
   // ФОН ПАНЕЛИ
   //----------------------------------------------------------
   PanelRect(g_prefix+"BG", PX, PY, PNL_W, PNL_H, C_BORDER, C_BG);

   // Границы внешнего контура каждого блока
   int LW     = 4;
   int b1L    = COL1_X - PAD;              // левый край — с отступом от панели
   int b1R    = COL1_X + COL_W + BAL_W;
   int b2L    = COL2_X - GAP;              // левый край блока 2 — после BAL блока 1
   int b2R    = COL2_X + COL_W + BAL_W;
   int fTop   = yB - VGAP - 2 - 4;   // зазор ~10px между полоской и кнопками BLOCK
   int fBot   = yEXend;
   int fH     = fBot - fTop;
   int fW1    = b1R - b1L;
   int fW2    = b2R - b2L;

   // КОНТУР БЛОКА 1 — 4 стороны голубого цвета
   PanelRect(g_prefix+"F1_T", b1L,    fTop,       fW1, LW,  C_FRAME_BLK, C_FRAME_BLK); // верх
   PanelRect(g_prefix+"F1_B", b1L,    fBot,       fW1, LW,  C_FRAME_BLK, C_FRAME_BLK); // низ
   PanelRect(g_prefix+"F1_L", b1L,    fTop,       LW,  fH,  C_FRAME_BLK, C_FRAME_BLK); // лево
   PanelRect(g_prefix+"F1_R", b1R-LW, fTop,       LW,  fH+LW, C_FRAME_BLK, C_FRAME_BLK); // право

   // КОНТУР БЛОКА 2 — 4 стороны голубого цвета
   PanelRect(g_prefix+"F2_T", b2L,    fTop,       fW2, LW,  C_FRAME_BLK, C_FRAME_BLK); // верх
   PanelRect(g_prefix+"F2_B", b2L,    fBot,       fW2, LW,  C_FRAME_BLK, C_FRAME_BLK); // низ
   PanelRect(g_prefix+"F2_L", b2L,    fTop,       LW,  fH,  C_FRAME_BLK, C_FRAME_BLK); // лево
   PanelRect(g_prefix+"F2_R", b2R-LW, fTop,       LW,  fH+LW, C_FRAME_BLK, C_FRAME_BLK); // право

   // Горизонтальная линия над подблоком EXTRA (для обоих блоков)
   int exLineY = yMSend + VGAP/2;
   PanelRect(g_prefix+"F1_EX", b1L, exLineY, fW1, LW, C_FRAME_BLK, C_FRAME_BLK);
   PanelRect(g_prefix+"F2_EX", b2L, exLineY, fW2, LW, C_FRAME_BLK, C_FRAME_BLK);

   //----------------------------------------------------------
   // СТРОКА 0: START | [БАЛАНС] | [ПРИБЫЛЬ TOTAL] | STOP
   // Кнопки высотой RH0=34, центрированы внутри строки RH0_ROW=46
   //----------------------------------------------------------
   int r0off = (RH0_ROW - RH0) / 2;   // смещение кнопок от верха строки
   int btnMidY = y0 + r0off + RH0 / 2;  // центр кнопок по вертикали

   PanelBtn(g_prefix+"BTN_START", "START", COL1_X, y0+r0off, btnW0, RH0, C_BTN_DEF, C_TXT_W);

   int balOffX  = 20;
   int balFullW = COL2_X-COL1_X-btnW0-GAP*2-balOffX;
   int balDlrX  = COL1_X+btnW0+GAP+balOffX+balFullW;
   int balLblH  = 14;  // высота текста fs=11
   int balDlrH  = 11;  // высота текста fs=9
   PanelLbl(g_prefix+"LBL_BALANCE",     "---", COL1_X+btnW0+GAP+balOffX, btnMidY-balLblH/2, balFullW, balLblH, C_TXT_Y, 11);
   PanelLbl(g_prefix+"LBL_BALANCE_DLR", "$",   balDlrX, btnMidY-balDlrH/2, 12, balDlrH, C_TXT_G, 9);

   // LBL_PROFIT_TOTAL: рамка + число + знак $ — центрированы внутри строки RH0_ROW
   int pTotShift = 18 + 20;  // +20px сдвиг вправо
   int pTotTxtW  = 68;  int pTotTxtH = 20;
   int pDlrW     = 10;
   int pPadW     = 8;
   int pTotBrdW  = pTotTxtW + pDlrW + pPadW*2;
   int pTotHalf  = (pTotTxtH + 8) / 2;
   int pTotYTop  = btnMidY - pTotHalf;
   int pTotYBot  = y0 + r0off + RH0 + 3;
   int pTotX     = (COL1_X + btnW0 + GAP + COL2_X) / 2 - pTotBrdW/2 + pTotShift;
   color C_PROFIT = clrAqua;
   PanelBorder(g_prefix+"LBL_PROFIT_TOTAL_BRD", pTotX, pTotYTop, pTotBrdW, pTotYBot, clrWhite);
   int pTotLblY  = btnMidY - pTotTxtH / 2;
   PanelLbl(g_prefix+"LBL_PROFIT_TOTAL", "---",
            pTotX+pPadW,          pTotLblY, pTotTxtW, pTotTxtH, C_PROFIT, 13);
   PanelLbl(g_prefix+"LBL_PROFIT_TOTAL_DLR", "$",
            pTotX+pPadW+pTotTxtW, pTotLblY+(pTotTxtH-11)/2, pDlrW, pTotTxtH, C_PROFIT, 11);

   PanelBtn(g_prefix+"BTN_STOP",  "STOP",  COL2_X, y0+r0off, btnW0, RH0, C_BTN_DEF, C_TXT_W);

   // Кнопки AUTO / CORR / ELVL — справа в строке START (слева направо: AUTO, CORR, ON)
   int elvlBtnW  = 46;
   int autoBtnW  = 62;
   int corrBtnW  = 62;
   int elvlBtnX  = b2R - elvlBtnW;
   int corrBtnX  = elvlBtnX - corrBtnW - 2;
   int autoBtnX  = corrBtnX - autoBtnW - 2;

   PanelBtn(g_prefix+"BTN_AUTO", "AUTO",
            autoBtnX, y0+r0off, autoBtnW, RH0,
            g_autoPilot   ? C_BTN_GREEN : C_BTN_DEF, C_TXT_W);
   PanelBtn(g_prefix+"BTN_CORR", "CORR",
            corrBtnX, y0+r0off, corrBtnW, RH0,
            g_corrVisible ? C_BTN_GREEN : C_BTN_DEF, C_TXT_W);
   PanelBtn(g_prefix+"BTN_ELVL", g_extraLevelsVisible ? "ON" : "OFF",
            elvlBtnX, y0+r0off, elvlBtnW, RH0,
            g_extraLevelsVisible ? C_BTN_GREEN : C_BTN_DEF, C_TXT_W);

   //----------------------------------------------------------
   // СТРОКА STOP1/BAL1 и STOP2/BAL2 внутри блоков
   //----------------------------------------------------------
   int stopW = LBL_W + GAP + 8;  // правый край совпадает с левым краем кнопки OPEN (ox)
   int balW2 = COL_W - stopW - GAP;
   // X кнопки CLOSE: ox+BTN_W+GAP (блок1), ox2+BTN_W+GAP (блок2)
   int closeX1 = ox  + BTN_W + GAP;
   int closeX2 = ox2 + BTN_W + GAP;
   int pTxtW    = 62;  int pTxtH  = 16;
   int pDlrWb   = 9;
   int pBrdPadW = 8;
   int pBrdW    = pTxtW + pDlrWb + pBrdPadW*2;
   int pShift   = 10;
   int pBrdYTop = yS1 - 2;
   int pBrdYBot = yS1 + RH2 + 3;

   // Центр строки STOP1/2
   int s1MidY  = yS1 + RH2/2;
   int balY    = s1MidY - 6;   // fs=9 ~12px
   int profY   = s1MidY - 7;   // fs=11 ~14px
   int dlrY    = s1MidY - 6;   // fs=9 ~12px

   int balNW  = balW2;
   int bal1DX = ox + balNW;
   int bal2DX = ox2 + balNW;
   PanelBtn(g_prefix+"BTN_STOP1", "STOP 1", COL1_X, yS1,  stopW, RH2, C_BTN_DEF, C_TXT_W);
   PanelLbl(g_prefix+"LBL_BAL1",     "---", ox+20,     balY, balNW, 12, C_TXT_Y, 9);
   PanelLbl(g_prefix+"LBL_BAL1_DLR", "$",   bal1DX+20, dlrY, 9,     12, C_TXT_G, 9);
   PanelBorder(g_prefix+"LBL_PROFIT1_BRD", closeX1+pShift, pBrdYTop, pBrdW, pBrdYBot, clrWhite);
   PanelLbl(g_prefix+"LBL_PROFIT1", "---",
            closeX1+pShift+pBrdPadW,       profY, pTxtW, pTxtH, C_PROFIT, 11);
   PanelLbl(g_prefix+"LBL_PROFIT1_DLR", "$",
            closeX1+pShift+pBrdPadW+pTxtW, dlrY,  pDlrWb, 12,   C_PROFIT, 9);

   PanelBtn(g_prefix+"BTN_STOP2", "STOP 2", COL2_X, yS1,  stopW, RH2, C_BTN_DEF, C_TXT_W);
   PanelLbl(g_prefix+"LBL_BAL2",     "---", ox2+20,    balY, balNW, 12, C_TXT_Y, 9);
   PanelLbl(g_prefix+"LBL_BAL2_DLR", "$",   bal2DX+20, dlrY, 9,     12, C_TXT_G, 9);
   PanelBorder(g_prefix+"LBL_PROFIT2_BRD", closeX2+pShift, pBrdYTop, pBrdW, pBrdYBot, clrWhite);
   PanelLbl(g_prefix+"LBL_PROFIT2", "---",
            closeX2+pShift+pBrdPadW,       profY, pTxtW, pTxtH, C_PROFIT, 11);
   PanelLbl(g_prefix+"LBL_PROFIT2_DLR", "$",
            closeX2+pShift+pBrdPadW+pTxtW, dlrY,  pDlrWb, 12,   C_PROFIT, 9);

   //----------------------------------------------------------
   // СТРОКИ MAIN и SAFE (без рамок подблоков)
   //----------------------------------------------------------
   string msRows[2]; msRows[0]="MAIN"; msRows[1]="SAFE";
   int    msYs[2];   msYs[0]=yMS;      msYs[1]=yS;

   for(int i=0; i<2; i++)
   {
      string r  = msRows[i];
      int    ry = msYs[i];
      // Блок 1 - темно-синий фон + текст (не кнопка)
      PanelRect(g_prefix+"B1_"+r+"_BG", COL1_X, ry, LBL_W, RHR, C_BORDER, C'0,0,80');
      PanelLblCenter(g_prefix+"B1_"+r+"_N",   r,       COL1_X+LBL_W/2,    ry+RHR/2,  LBL_W,   RHR,   C_TXT_W,   9, "Arial Bold");
      PanelBtn(g_prefix+"B1_"+r+"_OPEN", "OPEN", ox,                ry,    BTN_W,   RHR,   C_BTN_DEF, C_TXT_W);
      PanelBtn(g_prefix+"B1_"+r+"_CLOSE","CLOSE",ox+BTN_W+GAP,      ry,    BTN_W,   RHR,   C_BTN_DEF, C_TXT_W);
      PanelLbl(g_prefix+"B1_"+r+"_BAL", "---",   ox+BTN_W*2+GAP*2,  ry+4,  BAL_W,   RHR,   C_TXT_Y,   9);
      // Блок 2 - темно-синий фон + текст (не кнопка)
      PanelRect(g_prefix+"B2_"+r+"_BG", COL2_X, ry, LBL_W, RHR, C_BORDER, C'0,0,80');
      PanelLblCenter(g_prefix+"B2_"+r+"_N",   r,       COL2_X+LBL_W/2,    ry+RHR/2,  LBL_W,   RHR,   C_TXT_W,   9, "Arial Bold");
      PanelBtn(g_prefix+"B2_"+r+"_OPEN", "OPEN", ox2,               ry,    BTN_W,   RHR,   C_BTN_DEF, C_TXT_W);
      PanelBtn(g_prefix+"B2_"+r+"_CLOSE","CLOSE",ox2+BTN_W+GAP,     ry,    BTN_W,   RHR,   C_BTN_DEF, C_TXT_W);
      PanelLbl(g_prefix+"B2_"+r+"_BAL", "---",   ox2+BTN_W*2+GAP*2, ry+4,  BAL_W,   RHR,   C_TXT_Y,   9);
   }

   //----------------------------------------------------------
   // СТРОКИ EXTRA1 / EXTRA2 / EXTRA3 (без рамок подблоков)
   //----------------------------------------------------------
   string exRows[3]; exRows[0]="EXTRA1"; exRows[1]="EXTRA2"; exRows[2]="EXTRA3";
   int    exYs[3];   exYs[0]=yEX; exYs[1]=yE2; exYs[2]=yE3;

   for(int i=0; i<3; i++)
   {
      string r  = exRows[i];
      int    ry = exYs[i];
      // Блок 1 - темно-синий фон + текст (не кнопка)
      PanelRect(g_prefix+"B1_"+r+"_BG", COL1_X, ry, LBL_W, RHR, C_BORDER, C'0,0,80');
      PanelLblCenter(g_prefix+"B1_"+r+"_N",   r,       COL1_X+LBL_W/2,    ry+RHR/2,  LBL_W,   RHR,   C_TXT_W,   9, "Arial Bold");
      PanelBtn(g_prefix+"B1_"+r+"_OPEN", "OPEN", ox,                ry,    BTN_W,   RHR,   C_BTN_DEF, C_TXT_W);
      PanelBtn(g_prefix+"B1_"+r+"_CLOSE","CLOSE",ox+BTN_W+GAP,      ry,    BTN_W,   RHR,   C_BTN_DEF, C_TXT_W);
      PanelLbl(g_prefix+"B1_"+r+"_BAL", "---",   ox+BTN_W*2+GAP*2,  ry+4,  BAL_W,   RHR,   C_TXT_Y,   9);
      // Блок 2 - темно-синий фон + текст (не кнопка)
      PanelRect(g_prefix+"B2_"+r+"_BG", COL2_X, ry, LBL_W, RHR, C_BORDER, C'0,0,80');
      PanelLblCenter(g_prefix+"B2_"+r+"_N",   r,       COL2_X+LBL_W/2,    ry+RHR/2,  LBL_W,   RHR,   C_TXT_W,   9, "Arial Bold");
      PanelBtn(g_prefix+"B2_"+r+"_OPEN", "OPEN", ox2,               ry,    BTN_W,   RHR,   C_BTN_DEF, C_TXT_W);
      PanelBtn(g_prefix+"B2_"+r+"_CLOSE","CLOSE",ox2+BTN_W+GAP,     ry,    BTN_W,   RHR,   C_BTN_DEF, C_TXT_W);
      PanelLbl(g_prefix+"B2_"+r+"_BAL", "---",   ox2+BTN_W*2+GAP*2, ry+4,  BAL_W,   RHR,   C_TXT_Y,   9);
   }

   //----------------------------------------------------------
   // СТРОКА AUTO / MANUAL
   //----------------------------------------------------------
   PanelBtn(g_prefix+"B1_EXTRA_ON",  "AUTO",   ox,           yEON, BTN_W, RHR, C_BTN_GREEN, C_TXT_W);
   PanelBtn(g_prefix+"B1_EXTRA_OFF", "MANUAL", ox+BTN_W+GAP, yEON, BTN_W, RHR, C_BTN_DEF,   C_TXT_W);
   PanelBtn(g_prefix+"B2_EXTRA_ON",  "AUTO",   ox2,          yEON, BTN_W, RHR, C_BTN_GREEN, C_TXT_W);
   PanelBtn(g_prefix+"B2_EXTRA_OFF", "MANUAL", ox2+BTN_W+GAP,yEON, BTN_W, RHR, C_BTN_DEF,   C_TXT_W);

   //----------------------------------------------------------
   // BLOCK 1 / BLOCK 2 — рисуем последними, поверх всего
   // z-order кнопок = 1, но в MT5 побеждает порядок создания
   //----------------------------------------------------------
   PanelBtn(g_prefix+"BTN_B1TOGGLE", "BLOCK 1", COL1_X, yB, btnW0, RHB, C_BTN_GREEN, C_TXT_W);
   // ALL SET — правее BLOCK1 (через GAP)
   int allSetX = COL1_X + btnW0 + GAP;
   int allSetW = 62;
   PanelBtn(g_prefix+"BTN_ALLSET", "ALL SET", allSetX, yB, allSetW, RHB, C_BTN_DEF, C_TXT_W);
   PanelBtn(g_prefix+"BTN_B2TOGGLE", "BLOCK 2", COL2_X, yB, btnW0, RHB, C_BTN_RED,   C_TXT_W);
   // A-LOT — правее BLOCK2 (через GAP)
   int aLotX = COL2_X + btnW0 + GAP;
   int aLotW = 62;
   PanelBtn(g_prefix+"BTN_ALOT", "A-LOT", aLotX, yB, aLotW, RHB, C_BTN_DEF, C_TXT_W);

   //----------------------------------------------------------
   // КНОПКИ СЕТОВ S1/S2 (блок 1) и S3/S4 (блок 2)
   // Отступ от правой рамки блока = PAD (тот же что у BLOCK от левой рамки)
   // Ширина = elvlBtnW=46, высота = RHB=30, зазор = GAP
   //----------------------------------------------------------
   int sW   = elvlBtnW;   // 46 — как кнопка ON
   int sGap = GAP;        // 4

   // Блок 1: правая рамка = b1R-LW, отступ PAD внутрь
   int s1_S2x = b1R - LW - PAD - sW;
   int s1_S1x = s1_S2x - sW - sGap;
   PanelBtn(g_prefix+"BTN_SET1", "S1", s1_S1x, yB, sW, RHB, C_BTN_DEF, C_TXT_W);
   PanelBtn(g_prefix+"BTN_SET2", "S2", s1_S2x, yB, sW, RHB, C_BTN_DEF, C_TXT_W);

   // Блок 2: правая рамка = b2R-LW, отступ PAD внутрь
   int s2_S4x = b2R - LW - PAD - sW;
   int s2_S3x = s2_S4x - sW - sGap;
   PanelBtn(g_prefix+"BTN_SET3", "S3", s2_S3x, yB, sW, RHB, C_BTN_DEF, C_TXT_W);
   PanelBtn(g_prefix+"BTN_SET4", "S4", s2_S4x, yB, sW, RHB, C_BTN_DEF, C_TXT_W);

   //----------------------------------------------------------
   // STATUS
   //----------------------------------------------------------
   PanelLbl(g_prefix+"LBL_STATUS","STATUS: STANDBY", COL1_X, yStatus, PNL_W-PAD*2, RHS, C_TXT_GRAY, 8);

   ChartRedraw();
}

//+------------------------------------------------------------------+
void UpdatePanel()
{
   // Общий баланс = сумма текущих балансов обоих блоков (не баланс счёта)
   double b1total = (g_block1.state==BLOCK_PHASE1) ?
                    GetBlockBalancePhase1(g_block1) : GetBlockBalance(g_block1);
   double b2total = (g_block2.state==BLOCK_PHASE1) ?
                    GetBlockBalancePhase1(g_block2) : GetBlockBalance(g_block2);
   double totalBal = b1total + b2total;
   ObjectSetString(0, g_prefix+"LBL_BALANCE", OBJPROP_TEXT,  DoubleToString(totalBal,2));
   ObjectSetInteger(0,g_prefix+"LBL_BALANCE", OBJPROP_COLOR, totalBal>=0 ? C_TXT_G : C_TXT_R);

   // Принудительное обновление цвета контуров блоков
   string frames[10];
   frames[0]=g_prefix+"F1_T"; frames[1]=g_prefix+"F1_B";
   frames[2]=g_prefix+"F1_L"; frames[3]=g_prefix+"F1_R";
   frames[4]=g_prefix+"F2_T"; frames[5]=g_prefix+"F2_B";
   frames[6]=g_prefix+"F2_L"; frames[7]=g_prefix+"F2_R";
   frames[8]=g_prefix+"F1_EX";frames[9]=g_prefix+"F2_EX";
   for(int i=0;i<10;i++)
   {
      ObjectSetInteger(0,frames[i],OBJPROP_BGCOLOR,     C_FRAME_BLK);
      ObjectSetInteger(0,frames[i],OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0,frames[i],OBJPROP_BORDER_COLOR,C_FRAME_BLK);
   }

   // -------------------------------------------------------
   // АЛГОРИТМ КНОПОК START / STOP / BLOCK / STOP1 / STOP2
   // -------------------------------------------------------
   bool anyEnabled = g_block1.enabled || g_block2.enabled;

   // Общий START: зелёный — EA запущен, оранжевый — EA работает но есть завершённый блок (можно перезапустить),
   //              серый — стендбай/остановлен
   bool hasDoneBlock = g_eaState==STATE_RUNNING &&
                       ((g_block1.enabled && (g_block1.state==BLOCK_DONE||g_block1.state==BLOCK_IDLE)) ||
                        (g_block2.enabled && (g_block2.state==BLOCK_DONE||g_block2.state==BLOCK_IDLE)));
   if(g_eaState == STATE_RUNNING && anyEnabled)
   {
      ObjectSetInteger(0,g_prefix+"BTN_START",OBJPROP_BGCOLOR, hasDoneBlock ? C_BTN_ORG : C_BTN_GREEN);
      ObjectSetInteger(0,g_prefix+"BTN_STOP", OBJPROP_BGCOLOR, C_BTN_DEF);
   }
   else
   {
      ObjectSetInteger(0,g_prefix+"BTN_START",OBJPROP_BGCOLOR, C_BTN_DEF);
      ObjectSetInteger(0,g_prefix+"BTN_STOP", OBJPROP_BGCOLOR, C_BTN_RED);
   }

   // Кнопка LVL — текст ON/OFF, зелёная когда видно, серая когда скрыто
   ObjectSetString(0, g_prefix+"BTN_ELVL", OBJPROP_TEXT,
      g_extraLevelsVisible ? "ON" : "OFF");
   ObjectSetInteger(0,g_prefix+"BTN_ELVL",OBJPROP_BGCOLOR,
      g_extraLevelsVisible ? C_BTN_GREEN : C_BTN_DEF);
   // Кнопка CORR — зелёная когда индикатор виден
   ObjectSetInteger(0,g_prefix+"BTN_CORR",OBJPROP_BGCOLOR,
      g_corrVisible ? C_BTN_GREEN : C_BTN_DEF);
   // Кнопка AUTO — зелёная когда автопилот включён
   ObjectSetInteger(0,g_prefix+"BTN_AUTO",OBJPROP_BGCOLOR,
      g_autoPilot ? C_BTN_GREEN : C_BTN_DEF);
   // SET-кнопки: жёлтые если выбраны и блок активен, серые если блок завершил цикл
   for(int _s=1;_s<=4;_s++) {
      string _nm = g_prefix+"BTN_SET"+(string)_s;
      bool _isB1 = (g_selSet[0]==_s);
      bool _isB2 = (g_selSet[1]==_s);
      bool _act  = _isB1 || _isB2;
      // Серый если соответствующий блок завершил цикл (нужно выбрать новый сет)
      bool _done = (_isB1 && g_block1.cycleFinished) || (_isB2 && g_block2.cycleFinished);
      ObjectSetInteger(0,_nm,OBJPROP_BGCOLOR, (_act && !_done) ? C_BTN_YEL : C_BTN_DEF);
      ObjectSetInteger(0,_nm,OBJPROP_COLOR,   (_act && !_done) ? clrBlack   : C_TXT_W);
   }

   // BLOCK1 включён (enabled=true):  BLOCK1 зелёный, STOP1 серый
   // BLOCK1 выключен (enabled=false): BLOCK1 серый,  STOP1 красный
   ObjectSetString(0,  g_prefix+"BTN_B1TOGGLE",OBJPROP_TEXT,   "BLOCK 1");
   ObjectSetInteger(0, g_prefix+"BTN_B1TOGGLE",OBJPROP_BGCOLOR, g_block1.enabled ? C_BTN_GREEN : C_BTN_DEF);
   ObjectSetInteger(0, g_prefix+"BTN_STOP1",   OBJPROP_BGCOLOR, g_block1.enabled ? C_BTN_DEF   : C_BTN_RED);

   // BLOCK 2 / STOP 2 — взаимный переключатель
   ObjectSetString(0,  g_prefix+"BTN_B2TOGGLE",OBJPROP_TEXT,   "BLOCK 2");
   ObjectSetInteger(0, g_prefix+"BTN_B2TOGGLE",OBJPROP_BGCOLOR, g_block2.enabled ? C_BTN_GREEN : C_BTN_DEF);
   // ALL SET / A-LOT подсветка
   ObjectSetInteger(0, g_prefix+"BTN_ALLSET", OBJPROP_BGCOLOR, g_allSetActive ? C_BTN_GREEN : C_BTN_DEF);
   ObjectSetInteger(0, g_prefix+"BTN_ALOT",   OBJPROP_BGCOLOR, g_aLotActive   ? C_BTN_GREEN : C_BTN_DEF);
   ObjectSetInteger(0, g_prefix+"BTN_STOP2",   OBJPROP_BGCOLOR, g_block2.enabled ? C_BTN_DEF   : C_BTN_RED);

   // Балансы блоков (b1total/b2total уже посчитаны выше)
   ObjectSetString(0,g_prefix+"LBL_BAL1",OBJPROP_TEXT,DoubleToString(b1total,2));
   ObjectSetString(0,g_prefix+"LBL_BAL2",OBJPROP_TEXT,DoubleToString(b2total,2));
   ObjectSetInteger(0,g_prefix+"LBL_BAL1",OBJPROP_COLOR, b1total>=0?C_TXT_G:C_TXT_R);
   ObjectSetInteger(0,g_prefix+"LBL_BAL2",OBJPROP_COLOR, b2total>=0?C_TXT_G:C_TXT_R);

   // Двигаем зелёные $ вплотную после числа
   {
      int PAD_ = 6, GAP_ = 4, LBL_W_ = 78, BTN_W_ = 78, BAL_W_ = 68;
      int COL_W_  = LBL_W_ + BTN_W_*2 + GAP_*2;
      int COL1_X_ = PX + PAD_;
      int COL2_X_ = COL1_X_ + COL_W_ + BAL_W_ + GAP_;
      uint tw1,th1, tw2,th2, twB,thB;
      TextSetFont("Arial",9*-10);
      TextGetSize(DoubleToString(b1total,2), tw1, th1);
      TextGetSize(DoubleToString(b2total,2), tw2, th2);
      TextSetFont("Arial",11*-10);
      TextGetSize(DoubleToString(totalBal,2), twB, thB);

      int btnW0_ = 99;
      int ox_  = COL1_X_ + LBL_W_ + GAP_ + 8;
      int ox2_ = COL2_X_ + LBL_W_ + GAP_ + 8;

      ObjectSetInteger(0,g_prefix+"LBL_BAL1_DLR",    OBJPROP_XDISTANCE, ox_ +20+(int)tw1+2);
      ObjectSetInteger(0,g_prefix+"LBL_BAL2_DLR",    OBJPROP_XDISTANCE, ox2_+20+(int)tw2+2);
      ObjectSetInteger(0,g_prefix+"LBL_BALANCE_DLR",  OBJPROP_XDISTANCE, COL1_X_+btnW0_+GAP_+20+(int)twB+2);
      ObjectSetInteger(0,g_prefix+"LBL_BAL1_DLR",    OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0,g_prefix+"LBL_BAL2_DLR",    OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0,g_prefix+"LBL_BALANCE_DLR",  OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   }

   // Прибыль блока:
   //   - PHASE1/PHASE2 (активен): takenProfit + текущий баланс позиций
   //   - DONE (завершён, идёт следующий цикл): сохранённое значение g_savedProfit
   //   - IDLE / советник остановлен: 0
   double profit1, profit2;
   if(g_block1.state == BLOCK_PHASE1)
      profit1 = g_block1.profitTaken ? g_block1.takenProfit + b1total : 0;
   else if(g_block1.state == BLOCK_PHASE2)
      profit1 = g_block1.takenProfit + b1total;
   else if(g_block1.state == BLOCK_DONE)
      profit1 = g_savedProfit1;
   else
      profit1 = 0;

   if(g_block2.state == BLOCK_PHASE1)
      profit2 = g_block2.profitTaken ? g_block2.takenProfit + b2total : 0;
   else if(g_block2.state == BLOCK_PHASE2)
      profit2 = g_block2.takenProfit + b2total;
   else if(g_block2.state == BLOCK_DONE)
      profit2 = g_savedProfit2;
   else
      profit2 = 0;

   double profitTotal = profit1 + profit2;
   color  cProfit     = clrAqua;
   ObjectSetString(0,  g_prefix+"LBL_PROFIT_TOTAL", OBJPROP_TEXT,  DoubleToString(profitTotal,2));
   ObjectSetInteger(0, g_prefix+"LBL_PROFIT_TOTAL", OBJPROP_COLOR, cProfit);
   ObjectSetString(0,  g_prefix+"LBL_PROFIT1",      OBJPROP_TEXT,  DoubleToString(profit1,2));
   ObjectSetInteger(0, g_prefix+"LBL_PROFIT1",      OBJPROP_COLOR, cProfit);
   ObjectSetString(0,  g_prefix+"LBL_PROFIT2",      OBJPROP_TEXT,  DoubleToString(profit2,2));
   ObjectSetInteger(0, g_prefix+"LBL_PROFIT2",      OBJPROP_COLOR, cProfit);

   // Статус
   string stStr = "STATUS: STANDBY";
   if(g_eaState==STATE_RUNNING)
      stStr="STATUS: RUNNING  B1:"+BlockStateStr(g_block1.state)
            +"  B2:"+BlockStateStr(g_block2.state);
   if(g_eaState==STATE_STOPPED) stStr="STATUS: STOPPED";
   ObjectSetString(0,g_prefix+"LBL_STATUS",OBJPROP_TEXT,stStr);

   // Балансы строк
   SetRowBal("B1_MAIN_BAL",
      (g_block1.state==BLOCK_PHASE1) ?
      GetPairBalance(g_block1.ticketMainBuy,g_block1.ticketMainSell) :
      GetPairBalance(g_block1.ticketMain2,g_block1.ticketCorr2));
   SetRowBal("B2_MAIN_BAL",
      (g_block2.state==BLOCK_PHASE1) ?
      GetPairBalance(g_block2.ticketMainBuy,g_block2.ticketMainSell) :
      GetPairBalance(g_block2.ticketMain2,g_block2.ticketCorr2));
   SetRowBal("B1_SAFE_BAL",   GetPairBalance(g_block1.ticketSafeMain,  g_block1.ticketSafeCorr));
   SetRowBal("B2_SAFE_BAL",   GetPairBalance(g_block2.ticketSafeMain,  g_block2.ticketSafeCorr));
   SetRowBal("B1_EXTRA1_BAL", GetPairBalance(g_block1.ticketExtra1Main,g_block1.ticketExtra1Corr));
   SetRowBal("B2_EXTRA1_BAL", GetPairBalance(g_block2.ticketExtra1Main,g_block2.ticketExtra1Corr));
   SetRowBal("B1_EXTRA2_BAL", GetPairBalance(g_block1.ticketExtra2Main,g_block1.ticketExtra2Corr));
   SetRowBal("B2_EXTRA2_BAL", GetPairBalance(g_block2.ticketExtra2Main,g_block2.ticketExtra2Corr));
   SetRowBal("B1_EXTRA3_BAL", GetPairBalance(g_block1.ticketExtra3Main,g_block1.ticketExtra3Corr));
   SetRowBal("B2_EXTRA3_BAL", GetPairBalance(g_block2.ticketExtra3Main,g_block2.ticketExtra3Corr));

   // AUTO/MANUAL подсветка кнопок EXTRA
   // AUTO (ON)   — зелёный когда активен, серый когда нет
   // MANUAL (OFF)— оранжевый когда активен, серый когда нет
   ObjectSetInteger(0,g_prefix+"B1_EXTRA_ON",  OBJPROP_BGCOLOR, g_block1.extraAlgoEnabled ? C_BTN_GREEN : C_BTN_DEF);
   ObjectSetInteger(0,g_prefix+"B1_EXTRA_OFF", OBJPROP_BGCOLOR, g_block1.extraAlgoEnabled ? C_BTN_DEF   : C_BTN_ORG);
   ObjectSetInteger(0,g_prefix+"B2_EXTRA_ON",  OBJPROP_BGCOLOR, g_block2.extraAlgoEnabled ? C_BTN_GREEN : C_BTN_DEF);
   ObjectSetInteger(0,g_prefix+"B2_EXTRA_OFF", OBJPROP_BGCOLOR, g_block2.extraAlgoEnabled ? C_BTN_DEF   : C_BTN_ORG);

   // Кнопки OPEN/CLOSE строк EXTRA: 
   // OPEN зеленая если пара открыта, серая если нет
   // CLOSE оранжевая если закрыта вручную, серая если открыта или не трогали
   // Фон названия двойки: тёмно-синий = нет позиций, малиновый = позиции открыты
   string er[3]; er[0]="EXTRA1"; er[1]="EXTRA2"; er[2]="EXTRA3";
   bool b1ex[3]; b1ex[0]=g_block1.extra1Active; b1ex[1]=g_block1.extra2Active; b1ex[2]=g_block1.extra3Active;
   bool b2ex[3]; b2ex[0]=g_block2.extra1Active; b2ex[1]=g_block2.extra2Active; b2ex[2]=g_block2.extra3Active;
   bool b1mc[3]; b1mc[0]=g_block1.extra1ManuallyClosed; b1mc[1]=g_block1.extra2ManuallyClosed; b1mc[2]=g_block1.extra3ManuallyClosed;
   bool b2mc[3]; b2mc[0]=g_block2.extra1ManuallyClosed; b2mc[1]=g_block2.extra2ManuallyClosed; b2mc[2]=g_block2.extra3ManuallyClosed;
   
   for(int i=0;i<3;i++)
   {
      // Блок 1: цвет фона названия
      ObjectSetInteger(0,g_prefix+"B1_"+er[i]+"_BG", OBJPROP_BGCOLOR, b1ex[i] ? C_LBL_ACTIVE : C'0,0,80');
      // Блок 1: кнопки
      if(g_block1.extraAlgoEnabled)
      {
         // AUTO режим: CLOSE всегда серая
         ObjectSetInteger(0,g_prefix+"B1_"+er[i]+"_OPEN",  OBJPROP_BGCOLOR, b1ex[i] ? C_BTN_GREEN : C_BTN_DEF);
         ObjectSetInteger(0,g_prefix+"B1_"+er[i]+"_CLOSE", OBJPROP_BGCOLOR, C_BTN_DEF);
      }
      else
      {
         // MANUAL режим: OPEN зеленая если открыта, CLOSE оранжевая если закрыта вручную
         ObjectSetInteger(0,g_prefix+"B1_"+er[i]+"_OPEN",  OBJPROP_BGCOLOR, b1ex[i] ? C_BTN_GREEN : C_BTN_DEF);
         ObjectSetInteger(0,g_prefix+"B1_"+er[i]+"_CLOSE", OBJPROP_BGCOLOR, b1mc[i] ? C_BTN_ORG : C_BTN_DEF);
      }
      // Блок 2: цвет фона названия
      ObjectSetInteger(0,g_prefix+"B2_"+er[i]+"_BG", OBJPROP_BGCOLOR, b2ex[i] ? C_LBL_ACTIVE : C'0,0,80');
      // Блок 2: кнопки
      if(g_block2.extraAlgoEnabled)
      {
         // AUTO режим: CLOSE всегда серая
         ObjectSetInteger(0,g_prefix+"B2_"+er[i]+"_OPEN",  OBJPROP_BGCOLOR, b2ex[i] ? C_BTN_GREEN : C_BTN_DEF);
         ObjectSetInteger(0,g_prefix+"B2_"+er[i]+"_CLOSE", OBJPROP_BGCOLOR, C_BTN_DEF);
      }
      else
      {
         // MANUAL режим: OPEN зеленая если открыта, CLOSE оранжевая если закрыта вручную
         ObjectSetInteger(0,g_prefix+"B2_"+er[i]+"_OPEN",  OBJPROP_BGCOLOR, b2ex[i] ? C_BTN_GREEN : C_BTN_DEF);
         ObjectSetInteger(0,g_prefix+"B2_"+er[i]+"_CLOSE", OBJPROP_BGCOLOR, b2mc[i] ? C_BTN_ORG : C_BTN_DEF);
      }
   }

   // MAIN и SAFE: фон названия малиновый если позиции открыты
   bool b1MainOpen = IsPositionOpen(g_block1.ticketMainBuy) || IsPositionOpen(g_block1.ticketMain2);
   bool b2MainOpen = IsPositionOpen(g_block2.ticketMainBuy) || IsPositionOpen(g_block2.ticketMain2);
   bool b1SafeOpen = IsPositionOpen(g_block1.ticketSafeMain);
   bool b2SafeOpen = IsPositionOpen(g_block2.ticketSafeMain);

   ObjectSetInteger(0,g_prefix+"B1_MAIN_BG",   OBJPROP_BGCOLOR, b1MainOpen ? C_LBL_ACTIVE : C'0,0,80');
   ObjectSetInteger(0,g_prefix+"B2_MAIN_BG",   OBJPROP_BGCOLOR, b2MainOpen ? C_LBL_ACTIVE : C'0,0,80');
   ObjectSetInteger(0,g_prefix+"B1_SAFE_BG",   OBJPROP_BGCOLOR, b1SafeOpen ? C_LBL_ACTIVE : C'0,0,80');
   ObjectSetInteger(0,g_prefix+"B2_SAFE_BG",   OBJPROP_BGCOLOR, b2SafeOpen ? C_LBL_ACTIVE : C'0,0,80');
   
   // ИСПРАВЛЕНО: Кнопки OPEN/CLOSE для MAIN и SAFE теперь обновляются автоматически
   // OPEN - зеленая если позиции открыты, CLOSE - серая
   ObjectSetInteger(0,g_prefix+"B1_MAIN_OPEN",  OBJPROP_BGCOLOR, b1MainOpen ? C_BTN_GREEN : C_BTN_DEF);
   ObjectSetInteger(0,g_prefix+"B1_MAIN_CLOSE", OBJPROP_BGCOLOR, C_BTN_DEF);
   ObjectSetInteger(0,g_prefix+"B2_MAIN_OPEN",  OBJPROP_BGCOLOR, b2MainOpen ? C_BTN_GREEN : C_BTN_DEF);
   ObjectSetInteger(0,g_prefix+"B2_MAIN_CLOSE", OBJPROP_BGCOLOR, C_BTN_DEF);
   ObjectSetInteger(0,g_prefix+"B1_SAFE_OPEN",  OBJPROP_BGCOLOR, b1SafeOpen ? C_BTN_GREEN : C_BTN_DEF);
   ObjectSetInteger(0,g_prefix+"B1_SAFE_CLOSE", OBJPROP_BGCOLOR, C_BTN_DEF);
   ObjectSetInteger(0,g_prefix+"B2_SAFE_OPEN",  OBJPROP_BGCOLOR, b2SafeOpen ? C_BTN_GREEN : C_BTN_DEF);
   ObjectSetInteger(0,g_prefix+"B2_SAFE_CLOSE", OBJPROP_BGCOLOR, C_BTN_DEF);

   // Вывод уровней EXTRA за пределами основной панели
   ShowExtraLevels(g_block1, 1);
   ShowExtraLevels(g_block2, 2);

   // Обновляем CORR панель — позиция прикреплена к правому краю советника
   // PNL_W вычисляется из тех же констант что и в CreatePanel
   {
      int PAD_  = 6, GAP_ = 4, LBL_W_= 78, BTN_W_= 78, BAL_W_= 68;
      int COL_W_= LBL_W_+BTN_W_*2+GAP_*2;
      int COL1_X_= PX+PAD_;
      int COL2_X_= COL1_X_+COL_W_+BAL_W_+GAP_;
      int PNL_W_ = COL2_X_+COL_W_+BAL_W_+PAD_-PX;
      int RH0_=34, RH0_ROW_=56, VGAP_=4, IP_=4, RH2_=26, RHR_=22, RHS_=16;
      int y0_  = PY+PAD_-4;
      int yB_  = y0_+RH0_ROW_+VGAP_+4;
      int yS1_ = yB_+RH0_+VGAP_;
      int yMS_ = yS1_+RH2_+VGAP_+IP_;
      int yS_  = yMS_+RHR_+VGAP_;
      int yMSend_ = yS_+RHR_+IP_;
      int yEX_ = yMSend_+VGAP_+IP_;
      int yE2_ = yEX_+RHR_+VGAP_;
      int yE3_ = yE2_+RHR_+VGAP_;
      int yEON_= yE3_+RHR_+VGAP_;
      int yEXend_= yEON_+RHR_+IP_;
      int yStatus_= yEXend_+VGAP_+PAD_;
      int PNL_H_= yStatus_+RHS_+PAD_-PY;
      UpdateCorrLayout(PX, PY, PNL_W_, PNL_H_);
   }

   ChartRedraw();
}

void SetRowBal(string key, double val)
{
   ObjectSetString(0,  g_prefix+key, OBJPROP_TEXT,  DoubleToString(val,2));
   ObjectSetInteger(0, g_prefix+key, OBJPROP_COLOR, val>=0?C_TXT_G:C_TXT_R);
}

//--- Вывод уровней EXTRA под соответствующим блоком
void ShowExtraLevels(SBlock &blk, int blockNum)
{
   string pfx = g_prefix + "ELVL_B" + IntegerToString(blockNum) + "_";

   // Видимость: OBJ_ALL_PERIODS = видно, OBJ_NO_PERIODS = скрыто
   long vis = g_extraLevelsVisible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;

   // Вычисляем координаты блока (те же константы что в CreatePanel)
   int PAD_  = 6;
   int GAP_  = 4;
   int LBL_W_= 78;
   int BTN_W_= 78;
   int BAL_W_= 68;
   int COL_W_= LBL_W_ + BTN_W_*2 + GAP_*2;
   int COL1_X_= PX + PAD_;
   int COL2_X_= COL1_X_ + COL_W_ + BAL_W_ + GAP_;
   int VGAP_ = 4;
   int RH0_  = 34;
   int RH2_  = 26;
   int RHR_  = 22;
   int IP_   = 4;
   int y0_   = PY + PAD_ - 4;
   int yB_   = y0_ + 56 + VGAP_ + 4;   // RH0_ROW=56 — высота строки START
   int yS1_  = yB_ + RH0_ + VGAP_;
   int yMS_  = yS1_ + RH2_ + VGAP_ + IP_;
   int yS_   = yMS_ + RHR_ + VGAP_;
   int yMSend_ = yS_ + RHR_ + IP_;
   int yEX_  = yMSend_ + VGAP_ + IP_;
   int yE2_  = yEX_ + RHR_ + VGAP_;
   int yE3_  = yE2_ + RHR_ + VGAP_;
   int yEON_ = yE3_ + RHR_ + VGAP_;
   int yEXend_= yEON_ + RHR_ + IP_;

   // Под блоком: X = левый край блока, Y = сразу под нижней рамкой
   int ex  = (blockNum == 1) ? (COL1_X_ - PAD_) : (COL2_X_ - GAP_);
   int ey  = yEXend_ + 4;  // вплотную под нижней голубой полоской рамки (LW=4)
   int lw  = COL_W_ + BAL_W_ + PAD_;  // ширина = ширина блока
   int lh  = 22;   // высота строки (было 17 — увеличено для читаемости)
   int rows= 7;    // было 6, теперь 7 (L1-L5 + L6)
   int bh  = rows * lh + 6;

   // Фон
   string bgName = pfx + "BG";
   if(ObjectFind(0, bgName) < 0)
      PanelRect(bgName, ex, ey, lw, bh, C'10,10,10', C'10,10,10');
   else
   {
      ObjectSetInteger(0,bgName,OBJPROP_XDISTANCE, ex);
      ObjectSetInteger(0,bgName,OBJPROP_YDISTANCE, ey);
      ObjectSetInteger(0,bgName,OBJPROP_XSIZE,     lw);
      ObjectSetInteger(0,bgName,OBJPROP_YSIZE,     bh);
   }
   ObjectSetInteger(0, bgName, OBJPROP_TIMEFRAMES, vis);

   // Заголовок
   string hName = pfx + "HDR";
   if(ObjectFind(0, hName) < 0)
      PanelLbl(hName, "", ex+4, ey+3, lw-8, lh, C_TXT_GRAY, 9);  // было 7
   else
   {
      ObjectSetInteger(0,hName,OBJPROP_XDISTANCE, ex+4);
      ObjectSetInteger(0,hName,OBJPROP_YDISTANCE, ey+3);
   }
   ObjectSetInteger(0, hName, OBJPROP_TIMEFRAMES, vis);

   // Строки уровней
   struct LvlInfo { string lbl; double val; bool isTech; };
   LvlInfo lvls[6];
   lvls[0].lbl="L1 [tech]"; lvls[0].val=blk.extraLevel1; lvls[0].isTech=true;
   lvls[1].lbl="L2 [work]"; lvls[1].val=blk.extraLevel2; lvls[1].isTech=false;
   lvls[2].lbl="L3 [work]"; lvls[2].val=blk.extraLevel3; lvls[2].isTech=false;
   lvls[3].lbl="L4 [work]"; lvls[3].val=blk.extraLevel4; lvls[3].isTech=false;
   lvls[4].lbl="L5 [tech]"; lvls[4].val=blk.extraLevel5; lvls[4].isTech=true;
   // L6 - порог запуска EXTRA (стоп-лосс) = -TP - TP*threshold/100
   double stopLevel = -blk.takenProfit - blk.takenProfit * blk.extraThreshold / 100.0;
   lvls[5].lbl="L6 [stop]"; lvls[5].val=stopLevel; lvls[5].isTech=true;

   if(blk.state == BLOCK_PHASE2 && blk.profitTaken)
   {
      double step   = blk.takenProfit * blk.extraDeviation / 100.0;
      double curBal = GetBlockBalance(blk);

      ObjectSetString(0, hName, OBJPROP_TEXT,
         "B"+IntegerToString(blockNum)+" TP="+DoubleToString(blk.takenProfit,2)
         +" stp="+DoubleToString(step,2));

      for(int i = 0; i < 6; i++)
      {
         string nm = pfx + IntegerToString(i+1);
         if(ObjectFind(0, nm) < 0)
            PanelLbl(nm, "", ex+4, ey+lh*(i+1)+3, lw-8, lh, C_TXT_W, 10);  // было 8
         else
         {
            ObjectSetInteger(0,nm,OBJPROP_XDISTANCE, ex+4);
            ObjectSetInteger(0,nm,OBJPROP_YDISTANCE, ey+lh*(i+1)+3);
         }
         ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, vis);

         color c = lvls[i].isTech ? C_TXT_GRAY : C_TXT_Y;
         if(curBal <= lvls[i].val) c = C_TXT_R;
         ObjectSetString(0,  nm, OBJPROP_TEXT,
            lvls[i].lbl + ": " + DoubleToString(lvls[i].val, 2) + "$");
         ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
      }
   }
   else
   {
      ObjectSetString(0, hName, OBJPROP_TEXT, "B"+IntegerToString(blockNum)+" EXTRA: ---");
      for(int i = 0; i < 6; i++)
      {
         string nm = pfx + IntegerToString(i+1);
         if(ObjectFind(0, nm) >= 0)
         {
            ObjectSetString(0,  nm, OBJPROP_TEXT, "");
            ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, vis);
         }
      }
   }
}

//============================================================
//  ОБРАБОТКА КНОПОК
//============================================================

// Вспомогательная: подсветить кнопку OPEN (зелёная) и сбросить CLOSE (серая)
void SetBtnOpen(string pfx, string row)
{
   ObjectSetInteger(0, g_prefix+pfx+row+"_OPEN",  OBJPROP_BGCOLOR, C_BTN_GREEN);
   ObjectSetInteger(0, g_prefix+pfx+row+"_CLOSE", OBJPROP_BGCOLOR, C_BTN_DEF);
}
// Вспомогательная: подсветить кнопку CLOSE (оранжевая) и сбросить OPEN (серая)
void SetBtnClose(string pfx, string row)
{
   ObjectSetInteger(0, g_prefix+pfx+row+"_OPEN",  OBJPROP_BGCOLOR, C_BTN_DEF);
   ObjectSetInteger(0, g_prefix+pfx+row+"_CLOSE", OBJPROP_BGCOLOR, C_BTN_ORG);
}
// Вспомогательная: сбросить обе кнопки в серый (по завершению блока)
void SetBtnGray(string pfx, string row)
{
   ObjectSetInteger(0, g_prefix+pfx+row+"_OPEN",  OBJPROP_BGCOLOR, C_BTN_DEF);
   ObjectSetInteger(0, g_prefix+pfx+row+"_CLOSE", OBJPROP_BGCOLOR, C_BTN_DEF);
}

// Применяет настройки выбранного сета к блоку (не трогает enabled, state, тикеты)
//============================================================
//  ВСПОМОГАТЕЛЬНАЯ: подбор лотов (A-LOT) и общие параметры (ALL SET)
//============================================================

// Округляет лот до стандартного шага 0.01
double RoundLot(double lot)
{
   return MathFloor(lot * 100.0 + 0.5) / 100.0;
}

// Рассчитывает лоты по депозиту и записывает в блок
void CalcAutoLots(SBlock &blk)
{
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double mainLot  = RoundLot(balance / InpALotDivisor);
   double safeLot  = RoundLot(mainLot / InpALotSafeDiv);

   // extra = (main - safe) / 3, округляем extra1=extra2 вниз, extra3 — компенсирует остаток
   double extraRaw = (mainLot - safeLot) / 3.0;
   double e12      = RoundLot(MathFloor(extraRaw * 100.0) / 100.0); // округл. вниз
   double e3       = RoundLot(mainLot - safeLot - e12 - e12);       // компенсация: main-safe-e1-e2

   blk.mainLot   = mainLot;
   blk.corrLot   = mainLot;
   blk.safeLot   = safeLot;
   blk.extra1Lot = e12;
   blk.extra2Lot = e12;
   blk.extra3Lot = e3;
   Print("A-LOT: баланс=", DoubleToString(balance,2),
         "$ main=", DoubleToString(mainLot,2),
         " safe=", DoubleToString(safeLot,2),
         " e1=", DoubleToString(e12,2),
         " e2=", DoubleToString(e12,2),
         " e3=", DoubleToString(e3,2),
         " (проверка main-safe-e1-e2-e3=",
         DoubleToString(mainLot-safeLot-e12-e12-e3,3), ")");
}

// Применяет общие параметры ALL SET к блоку (кроме пар и направления)
void ApplyAllSetParams(SBlock &blk)
{
   blk.tp               = InpAllTP;
   blk.sl               = InpAllSL;
   blk.extraThreshold   = InpAllExtThr;
   blk.extraDeviation   = InpAllExtDev;
   blk.extraClosePercent= InpAllExtCls;
   if(!g_aLotActive)
   {
      blk.mainLot  = InpAllMainLot;
      blk.corrLot  = InpAllMainLot;
      blk.safeLot  = InpAllSafeLot;
      blk.extra1Lot= InpAllE1Lot;
      blk.extra2Lot= InpAllE2Lot;
      blk.extra3Lot= InpAllE3Lot;
   }
}


void ApplySetToBlock(SBlock &blk, int setNum)
{
   bool wasEnabled = blk.enabled;
   ENUM_BLOCK_STATE wasState = blk.state;
   // Запоминаем все тикеты и рабочие поля
   ulong tMB=blk.ticketMainBuy, tMS=blk.ticketMainSell;
   ulong tM2=blk.ticketMain2,   tC2=blk.ticketCorr2;
   ulong tSM=blk.ticketSafeMain,tSC=blk.ticketSafeCorr;
   ulong tE1M=blk.ticketExtra1Main,tE1C=blk.ticketExtra1Corr;
   ulong tE2M=blk.ticketExtra2Main,tE2C=blk.ticketExtra2Corr;
   ulong tE3M=blk.ticketExtra3Main,tE3C=blk.ticketExtra3Corr;
   double tp=blk.takenProfit; bool pt=blk.profitTaken;
   double sb=blk.startBalance;

   // Загружаем параметры нужного сета в блок
   int prevSet = 0;
   // prevSet unused after refactor

   string pfx = "";
   if(setNum==1)      pfx="Set1";
   else if(setNum==2) pfx="Set2";
   else if(setNum==3) pfx="Set3";
   else if(setNum==4) pfx="Set4";

   // Применяем пары и направление (всегда индивидуальные)
   switch(setNum)
   {
      case 1: blk.mainPair=InpSet1MainPair; blk.corrPair=InpSet1CorrPair;
              blk.direction=InpSet1Direction; blk.correlation=InpSet1Corr; break;
      case 2: blk.mainPair=InpSet2MainPair; blk.corrPair=InpSet2CorrPair;
              blk.direction=InpSet2Direction; blk.correlation=InpSet2Corr; break;
      case 3: blk.mainPair=InpSet3MainPair; blk.corrPair=InpSet3CorrPair;
              blk.direction=InpSet3Direction; blk.correlation=InpSet3Corr; break;
      case 4: blk.mainPair=InpSet4MainPair; blk.corrPair=InpSet4CorrPair;
              blk.direction=InpSet4Direction; blk.correlation=InpSet4Corr; break;
   }
   // Числовые параметры из общего блока (ALL SET / A-LOT применяются ниже)
   blk.tp               = InpAllTP;
   blk.sl               = InpAllSL;
   blk.mainLot          = InpAllMainLot;
   blk.corrLot          = InpAllMainLot;
   blk.safeLot          = InpAllSafeLot;
   blk.extra1Lot        = InpAllE1Lot;
   blk.extra2Lot        = InpAllE2Lot;
   blk.extra3Lot        = InpAllE3Lot;
   blk.extraThreshold   = InpAllExtThr;
   blk.extraDeviation   = InpAllExtDev;
   blk.extraClosePercent= InpAllExtCls;

   // Применяем общие параметры если ALL SET активен
   if(g_allSetActive) ApplyAllSetParams(blk);
   // Применяем автолоты если A-LOT активен
   if(g_aLotActive)   CalcAutoLots(blk);

   // Восстанавливаем рабочие поля — сет меняет только параметры, не состояние
   blk.enabled=wasEnabled; blk.state=wasState;
   blk.ticketMainBuy=tMB; blk.ticketMainSell=tMS;
   blk.ticketMain2=tM2;   blk.ticketCorr2=tC2;
   blk.ticketSafeMain=tSM;blk.ticketSafeCorr=tSC;
   blk.ticketExtra1Main=tE1M;blk.ticketExtra1Corr=tE1C;
   blk.ticketExtra2Main=tE2M;blk.ticketExtra2Corr=tE2C;
   blk.ticketExtra3Main=tE3M;blk.ticketExtra3Corr=tE3C;
   blk.takenProfit=tp; blk.profitTaken=pt; blk.startBalance=sb;
   Print("Сет ", setNum, " применён к блоку.");
}

void OnButtonClick(string name)
{
   if(StringFind(name,g_prefix)!=0) return;
   string btn=StringSubstr(name,StringLen(g_prefix));

   //--- Глобальные кнопки
   if(btn=="BTN_START") {
      int enabledBlocks = (g_block1.enabled ? 1 : 0) + (g_block2.enabled ? 1 : 0);
      int selectedSets  = (g_selSet[0] > 0 ? 1 : 0) + (g_selSet[1] > 0 ? 1 : 0);

      if(enabledBlocks == 0)
      {
         Alert("Включите хотя бы один блок (BLOCK 1 или BLOCK 2)!");
         ObjectSetInteger(0,name,OBJPROP_STATE,false);
      }
      else if(selectedSets < enabledBlocks)
      {
         if(enabledBlocks == 1)
            Alert("Для запуска одного блока нужно выбрать хотя бы 1 сет!");
         else
            Alert("Для запуска двух блоков нужно выбрать 2 сета!");
         ObjectSetInteger(0,name,OBJPROP_STATE,false);
      }
      else if(g_eaState == STATE_RUNNING)
      {
         // EA работает — перезапускаем только завершённые блоки
         bool hasDone = (g_block1.enabled && (g_block1.state==BLOCK_DONE||g_block1.state==BLOCK_IDLE)) ||
                        (g_block2.enabled && (g_block2.state==BLOCK_DONE||g_block2.state==BLOCK_IDLE));
         if(hasDone)
            StartEA();
         else
            ObjectSetInteger(0,name,OBJPROP_STATE,false);
      }
      else if(g_eaState != STATE_RUNNING && (g_block1.enabled || g_block2.enabled))
      {
         bool en1 = g_block1.enabled;
         bool en2 = g_block2.enabled;
         if(g_block1.state == BLOCK_DONE || g_block1.state == BLOCK_IDLE)
         {
            g_savedProfit1 = 0;
            g_block1 = SBlock();
         }
         if(g_block2.state == BLOCK_DONE || g_block2.state == BLOCK_IDLE)
         {
            g_savedProfit2 = 0;
            g_block2 = SBlock();
         }
         LoadBlockSettings();
         g_block1.enabled = en1;
         g_block2.enabled = en2;
         StartEA();
      }
      else ObjectSetInteger(0,name,OBJPROP_STATE,false);
   }
   else if(btn=="BTN_STOP") {
      ArrayInitialize(g_selSet, 0);
      StopEA(false);
   }

   //--- STOP блоков — выключают блок (enabled=false) и останавливают
   else if(btn=="BTN_STOP1") {
      if(g_block1.state!=BLOCK_IDLE) CloseBlock(g_block1,1);
      g_block1.enabled = false;
      g_block1.cycleFinished = true;
      bool b2done = (!g_block2.enabled || g_block2.state==BLOCK_DONE || g_block2.state==BLOCK_IDLE);
      if(b2done) g_eaState = STATE_STANDBY;
   }
   else if(btn=="BTN_STOP2") {
      if(g_block2.state!=BLOCK_IDLE) CloseBlock(g_block2,2);
      g_block2.enabled = false;
      g_block2.cycleFinished = true;
      bool b1done = (!g_block1.enabled || g_block1.state==BLOCK_DONE || g_block1.state==BLOCK_IDLE);
      if(b1done) g_eaState = STATE_STANDBY;
   }

   //--- BLOCK кнопки — только ВКЛЮЧАЮТ блок в стендбай (нельзя нажать если уже включён)
   else if(btn=="BTN_B1TOGGLE") {
      int enabledAfter  = (!g_block1.enabled ? 1 : 0) + (g_block2.enabled ? 1 : 0);
      int selectedSets  = (g_selSet[0] > 0 ? 1 : 0) + (g_selSet[1] > 0 ? 1 : 0);

      if(!g_block1.enabled)
      {
         if(selectedSets < enabledAfter)
         {
            if(enabledAfter == 1)
               Alert("Для включения блока нужно выбрать хотя бы 1 сет!");
            else
               Alert("Для работы двух блоков нужно выбрать 2 сета!");
            ObjectSetInteger(0,name,OBJPROP_STATE,false);
         }
         else
            g_block1.enabled = true;
      }
      else if(g_block1.state == BLOCK_DONE)
      {
         // Блок завершён — разрешаем "переключить" в enabled для перезапуска
         // Просто оставляем enabled=true, пользователь выберет сет и нажмёт START
         ObjectSetInteger(0,name,OBJPROP_STATE,false);
      }
      else ObjectSetInteger(0,name,OBJPROP_STATE,false);
   }
   else if(btn=="BTN_ALLSET") {
      g_allSetActive = !g_allSetActive;
      Print("ALL SET: ", g_allSetActive ? "ON — общие параметры" : "OFF — индивидуальные параметры");
   }
   else if(btn=="BTN_ALOT") {
      g_aLotActive = !g_aLotActive;
      if(g_aLotActive)
         Print("A-LOT ON: депозит=", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2),
               "$ divisor=", InpALotDivisor, " safeDiv=", InpALotSafeDiv);
      else
         Print("A-LOT OFF: лоты из настроек сетов.");
   }
   else if(btn=="BTN_B2TOGGLE") {
      int enabledAfter  = (g_block1.enabled ? 1 : 0) + (!g_block2.enabled ? 1 : 0);
      int selectedSets  = (g_selSet[0] > 0 ? 1 : 0) + (g_selSet[1] > 0 ? 1 : 0);

      if(!g_block2.enabled)
      {
         if(selectedSets < enabledAfter)
         {
            if(enabledAfter == 1)
               Alert("Для включения блока нужно выбрать хотя бы 1 сет!");
            else
               Alert("Для работы двух блоков нужно выбрать 2 сета!");
            ObjectSetInteger(0,name,OBJPROP_STATE,false);
         }
         else
            g_block2.enabled = true;
      }
      else if(g_block2.state == BLOCK_DONE)
      {
         ObjectSetInteger(0,name,OBJPROP_STATE,false);
      }
      else ObjectSetInteger(0,name,OBJPROP_STATE,false);
   }

   //--- Тест-кнопки: имитация взятия профита и запуск фазы 2
   else if(btn=="BTN_CORR") {
      g_corrVisible = !g_corrVisible;
      // Немедленно скрываем/показываем DRAG_CORR (расширение полоски над CORR)
      ObjectSetInteger(0, g_prefix+"DRAG_CORR", OBJPROP_TIMEFRAMES,
         g_corrVisible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   }
   else if(btn=="BTN_AUTO") {
      g_autoPilot = !g_autoPilot;
      if(g_autoPilot)
         Print("Автопилот ВКЛЮЧЁН: советник будет запущен при жирном сигнале CORR");
      else
         Print("Автопилот ВЫКЛЮЧЕН: ручное управление");
   }
   else if(btn=="BTN_ELVL") {
      g_extraLevelsVisible = !g_extraLevelsVisible;
      if(!g_extraLevelsVisible)
      {
         // Скрываем объекты выносных панелей
         for(int bn=1; bn<=2; bn++)
         {
            string pfx = g_prefix+"ELVL_B"+IntegerToString(bn)+"_";
            ObjectSetInteger(0,pfx+"BG",  OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
            ObjectSetInteger(0,pfx+"HDR", OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
            for(int i=1;i<=5;i++)
               ObjectSetInteger(0,pfx+IntegerToString(i),OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
         }
      }
   }
   else if(btn=="B1_EXTRA_ON")  { 
      g_block1.extraAlgoEnabled=true;
      // Сбрасываем флаги ручного закрытия, чтобы AUTO алгоритм мог подхватить открытые пары
      g_block1.extra1ManuallyClosed=false;
      g_block1.extra2ManuallyClosed=false;
      g_block1.extra3ManuallyClosed=false;
   }
   else if(btn=="B1_EXTRA_OFF") { g_block1.extraAlgoEnabled=false; }
   else if(btn=="B2_EXTRA_ON")  { 
      g_block2.extraAlgoEnabled=true;
      // Сбрасываем флаги ручного закрытия, чтобы AUTO алгоритм мог подхватить открытые пары
      g_block2.extra1ManuallyClosed=false;
      g_block2.extra2ManuallyClosed=false;
      g_block2.extra3ManuallyClosed=false;
   }
   else if(btn=="B2_EXTRA_OFF") { g_block2.extraAlgoEnabled=false; }

   //--- Кнопки сетов S1..S4: любые 2 из 4
   //    Клик: если уже выбрана — снять; иначе добавить (если 2 уже есть — убрать старый [0], сдвинуть [1]→[0])
   else if(btn=="BTN_SET1"||btn=="BTN_SET2"||btn=="BTN_SET3"||btn=="BTN_SET4") {
      int sNum = (int)StringToInteger(StringSubstr(btn, StringLen("BTN_SET")));
      // Проверяем — уже выбрана?
      if(g_selSet[0] == sNum) {
         // Снимаем из слота 0, сдвигаем [1]→[0]
         g_selSet[0] = g_selSet[1];
         g_selSet[1] = 0;
      } else if(g_selSet[1] == sNum) {
         // Снимаем из слота 1
         g_selSet[1] = 0;
      } else {
         // Не выбрана — добавляем
         if(g_selSet[0] == 0) {
            g_selSet[0] = sNum;
         } else if(g_selSet[1] == 0) {
            g_selSet[1] = sNum;
         } else {
            // Оба слота заняты — убираем [0], ставим новый в [1]
            g_selSet[0] = g_selSet[1];
            g_selSet[1] = sNum;
         }
         // Применяем: первый выбранный → блок1, второй → блок2
         if(g_selSet[0] > 0) { ApplySetToBlock(g_block1, g_selSet[0]); g_block1.cycleFinished = false; }
         if(g_selSet[1] > 0) { ApplySetToBlock(g_block2, g_selSet[1]); g_block2.cycleFinished = false; }
      }
   }

   //--- MAIN: всегда активные кнопки OPEN / CLOSE
   else if(btn=="B1_MAIN_OPEN") {
      // Открываем вручную MAIN пары блока 1
      // В фазе 1: открываем buy+sell, в фазе 2: main2+corr2
      if(g_block1.state == BLOCK_PHASE1 || g_block1.state == BLOCK_IDLE)
      {
         // Открываем обе MAIN пары (BUY и SELL)
         g_block1.ticketMainBuy  = OpenOrder(g_block1.mainPair, ORDER_TYPE_BUY,  g_block1.mainLot, "CA_B1_BUY");
         g_block1.ticketMainSell = OpenOrder(g_block1.mainPair, ORDER_TYPE_SELL, g_block1.mainLot, "CA_B1_SELL");
      }
      SetBtnOpen("B1_","MAIN");
   }
   else if(btn=="B1_MAIN_CLOSE") {
      { ulong _mt[4]; _mt[0]=g_block1.ticketMainBuy; _mt[1]=g_block1.ticketMainSell; _mt[2]=g_block1.ticketMain2; _mt[3]=g_block1.ticketCorr2; CloseTickets(_mt,4); }
      SetBtnClose("B1_","MAIN");
   }
   else if(btn=="B2_MAIN_OPEN") {
      // Открываем вручную MAIN пары блока 2
      if(g_block2.state == BLOCK_PHASE1 || g_block2.state == BLOCK_IDLE)
      {
         g_block2.ticketMainBuy  = OpenOrder(g_block2.mainPair, ORDER_TYPE_BUY,  g_block2.mainLot, "CA_B2_BUY");
         g_block2.ticketMainSell = OpenOrder(g_block2.mainPair, ORDER_TYPE_SELL, g_block2.mainLot, "CA_B2_SELL");
      }
      SetBtnOpen("B2_","MAIN");
   }
   else if(btn=="B2_MAIN_CLOSE") {
      { ulong _mt[4]; _mt[0]=g_block2.ticketMainBuy; _mt[1]=g_block2.ticketMainSell; _mt[2]=g_block2.ticketMain2; _mt[3]=g_block2.ticketCorr2; CloseTickets(_mt,4); }
      SetBtnClose("B2_","MAIN");
   }

   //--- SAFE: всегда активные кнопки OPEN / CLOSE
   else if(btn=="B1_SAFE_OPEN") {
      // Открываем SAFE пары вручную
      bool remainIsSell = (g_block1.direction == DIR_BUY);
      ENUM_ORDER_TYPE safeMainDir = remainIsSell ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      ENUM_ORDER_TYPE corrDir = (g_block1.correlation == CORR_INVERSE) ? 
                                (remainIsSell ? ORDER_TYPE_SELL : ORDER_TYPE_BUY) : 
                                (remainIsSell ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      ENUM_ORDER_TYPE safeCorrDir = (corrDir == ORDER_TYPE_SELL) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      
      g_block1.ticketSafeMain = OpenOrder(g_block1.mainPair, safeMainDir, g_block1.safeLot, "CA_B1_SAFE_M");
      g_block1.ticketSafeCorr = OpenOrder(g_block1.corrPair, safeCorrDir, g_block1.safeLot, "CA_B1_SAFE_C");
      SetBtnOpen("B1_","SAFE");
   }
   else if(btn=="B1_SAFE_CLOSE") {
      { ulong _st[2]; _st[0]=g_block1.ticketSafeMain; _st[1]=g_block1.ticketSafeCorr; CloseTickets(_st,2); }
      SetBtnClose("B1_","SAFE");
   }
   else if(btn=="B2_SAFE_OPEN") {
      // Открываем SAFE пары вручную блок 2
      bool remainIsSell = (g_block2.direction == DIR_BUY);
      ENUM_ORDER_TYPE safeMainDir = remainIsSell ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      ENUM_ORDER_TYPE corrDir = (g_block2.correlation == CORR_INVERSE) ? 
                                (remainIsSell ? ORDER_TYPE_SELL : ORDER_TYPE_BUY) : 
                                (remainIsSell ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      ENUM_ORDER_TYPE safeCorrDir = (corrDir == ORDER_TYPE_SELL) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      
      g_block2.ticketSafeMain = OpenOrder(g_block2.mainPair, safeMainDir, g_block2.safeLot, "CA_B2_SAFE_M");
      g_block2.ticketSafeCorr = OpenOrder(g_block2.corrPair, safeCorrDir, g_block2.safeLot, "CA_B2_SAFE_C");
      SetBtnOpen("B2_","SAFE");
   }
   else if(btn=="B2_SAFE_CLOSE") {
      { ulong _st[2]; _st[0]=g_block2.ticketSafeMain; _st[1]=g_block2.ticketSafeCorr; CloseTickets(_st,2); }
      SetBtnClose("B2_","SAFE");
   }

   //--- EXTRA1: только при ручном управлении (!extraAlgoEnabled)
   else if(btn=="B1_EXTRA1_OPEN" && !g_block1.extraAlgoEnabled) {
      // Ручной запуск EXTRA1 блока 1
      bool remainIsSell=(g_block1.direction==DIR_BUY);
      ENUM_ORDER_TYPE eDir=remainIsSell?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      ENUM_ORDER_TYPE eCor=(g_block1.correlation==CORR_INVERSE)?eDir:(eDir==ORDER_TYPE_BUY?ORDER_TYPE_SELL:ORDER_TYPE_BUY);
      g_block1.ticketExtra1Main=OpenOrder(g_block1.mainPair,eDir,g_block1.extra1Lot,"CA_B1_E1M");
      g_block1.ticketExtra1Corr=OpenOrder(g_block1.corrPair,eCor,g_block1.extra1Lot,"CA_B1_E1C");
      g_block1.extra1Active=true;
      g_block1.extra1ManuallyClosed=false;  // Сбрасываем флаг при открытии
      SetBtnOpen("B1_","EXTRA1");
   }
   else if(btn=="B1_EXTRA1_CLOSE" && !g_block1.extraAlgoEnabled) {
      { ulong _et[2]; _et[0]=g_block1.ticketExtra1Main; _et[1]=g_block1.ticketExtra1Corr; CloseTickets(_et,2); }
      g_block1.extra1Active=false;
      g_block1.extra1ManuallyClosed=true;  // Устанавливаем флаг ручного закрытия
      SetBtnClose("B1_","EXTRA1");
   }
   else if(btn=="B2_EXTRA1_OPEN" && !g_block2.extraAlgoEnabled) {
      bool remainIsSell=(g_block2.direction==DIR_BUY);
      ENUM_ORDER_TYPE eDir=remainIsSell?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      ENUM_ORDER_TYPE eCor=(g_block2.correlation==CORR_INVERSE)?eDir:(eDir==ORDER_TYPE_BUY?ORDER_TYPE_SELL:ORDER_TYPE_BUY);
      g_block2.ticketExtra1Main=OpenOrder(g_block2.mainPair,eDir,g_block2.extra1Lot,"CA_B2_E1M");
      g_block2.ticketExtra1Corr=OpenOrder(g_block2.corrPair,eCor,g_block2.extra1Lot,"CA_B2_E1C");
      g_block2.extra1Active=true;
      g_block2.extra1ManuallyClosed=false;
      SetBtnOpen("B2_","EXTRA1");
   }
   else if(btn=="B2_EXTRA1_CLOSE" && !g_block2.extraAlgoEnabled) {
      { ulong _et[2]; _et[0]=g_block2.ticketExtra1Main; _et[1]=g_block2.ticketExtra1Corr; CloseTickets(_et,2); }
      g_block2.extra1Active=false;
      g_block2.extra1ManuallyClosed=true;
      SetBtnClose("B2_","EXTRA1");
   }

   //--- EXTRA2
   else if(btn=="B1_EXTRA2_OPEN" && !g_block1.extraAlgoEnabled) {
      bool remainIsSell=(g_block1.direction==DIR_BUY);
      ENUM_ORDER_TYPE eDir=remainIsSell?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      ENUM_ORDER_TYPE eCor=(g_block1.correlation==CORR_INVERSE)?eDir:(eDir==ORDER_TYPE_BUY?ORDER_TYPE_SELL:ORDER_TYPE_BUY);
      g_block1.ticketExtra2Main=OpenOrder(g_block1.mainPair,eDir,g_block1.extra2Lot,"CA_B1_E2M");
      g_block1.ticketExtra2Corr=OpenOrder(g_block1.corrPair,eCor,g_block1.extra2Lot,"CA_B1_E2C");
      g_block1.extra2Active=true;
      g_block1.extra2ManuallyClosed=false;
      SetBtnOpen("B1_","EXTRA2");
   }
   else if(btn=="B1_EXTRA2_CLOSE" && !g_block1.extraAlgoEnabled) {
      { ulong _et[2]; _et[0]=g_block1.ticketExtra2Main; _et[1]=g_block1.ticketExtra2Corr; CloseTickets(_et,2); }
      g_block1.extra2Active=false;
      g_block1.extra2ManuallyClosed=true;
      SetBtnClose("B1_","EXTRA2");
   }
   else if(btn=="B2_EXTRA2_OPEN" && !g_block2.extraAlgoEnabled) {
      bool remainIsSell=(g_block2.direction==DIR_BUY);
      ENUM_ORDER_TYPE eDir=remainIsSell?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      ENUM_ORDER_TYPE eCor=(g_block2.correlation==CORR_INVERSE)?eDir:(eDir==ORDER_TYPE_BUY?ORDER_TYPE_SELL:ORDER_TYPE_BUY);
      g_block2.ticketExtra2Main=OpenOrder(g_block2.mainPair,eDir,g_block2.extra2Lot,"CA_B2_E2M");
      g_block2.ticketExtra2Corr=OpenOrder(g_block2.corrPair,eCor,g_block2.extra2Lot,"CA_B2_E2C");
      g_block2.extra2Active=true;
      g_block2.extra2ManuallyClosed=false;
      SetBtnOpen("B2_","EXTRA2");
   }
   else if(btn=="B2_EXTRA2_CLOSE" && !g_block2.extraAlgoEnabled) {
      { ulong _et[2]; _et[0]=g_block2.ticketExtra2Main; _et[1]=g_block2.ticketExtra2Corr; CloseTickets(_et,2); }
      g_block2.extra2Active=false;
      g_block2.extra2ManuallyClosed=true;
      SetBtnClose("B2_","EXTRA2");
   }

   //--- EXTRA3
   else if(btn=="B1_EXTRA3_OPEN" && !g_block1.extraAlgoEnabled) {
      bool remainIsSell=(g_block1.direction==DIR_BUY);
      ENUM_ORDER_TYPE eDir=remainIsSell?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      ENUM_ORDER_TYPE eCor=(g_block1.correlation==CORR_INVERSE)?eDir:(eDir==ORDER_TYPE_BUY?ORDER_TYPE_SELL:ORDER_TYPE_BUY);
      g_block1.ticketExtra3Main=OpenOrder(g_block1.mainPair,eDir,g_block1.extra3Lot,"CA_B1_E3M");
      g_block1.ticketExtra3Corr=OpenOrder(g_block1.corrPair,eCor,g_block1.extra3Lot,"CA_B1_E3C");
      g_block1.extra3Active=true;
      g_block1.extra3ManuallyClosed=false;
      SetBtnOpen("B1_","EXTRA3");
   }
   else if(btn=="B1_EXTRA3_CLOSE" && !g_block1.extraAlgoEnabled) {
      { ulong _et[2]; _et[0]=g_block1.ticketExtra3Main; _et[1]=g_block1.ticketExtra3Corr; CloseTickets(_et,2); }
      g_block1.extra3Active=false;
      g_block1.extra3ManuallyClosed=true;
      SetBtnClose("B1_","EXTRA3");
   }
   else if(btn=="B2_EXTRA3_OPEN" && !g_block2.extraAlgoEnabled) {
      bool remainIsSell=(g_block2.direction==DIR_BUY);
      ENUM_ORDER_TYPE eDir=remainIsSell?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      ENUM_ORDER_TYPE eCor=(g_block2.correlation==CORR_INVERSE)?eDir:(eDir==ORDER_TYPE_BUY?ORDER_TYPE_SELL:ORDER_TYPE_BUY);
      g_block2.ticketExtra3Main=OpenOrder(g_block2.mainPair,eDir,g_block2.extra3Lot,"CA_B2_E3M");
      g_block2.ticketExtra3Corr=OpenOrder(g_block2.corrPair,eCor,g_block2.extra3Lot,"CA_B2_E3C");
      g_block2.extra3Active=true;
      g_block2.extra3ManuallyClosed=false;
      SetBtnOpen("B2_","EXTRA3");
   }
   else if(btn=="B2_EXTRA3_CLOSE" && !g_block2.extraAlgoEnabled) {
      { ulong _et[2]; _et[0]=g_block2.ticketExtra3Main; _et[1]=g_block2.ticketExtra3Corr; CloseTickets(_et,2); }
      g_block2.extra3Active=false;
      g_block2.extra3ManuallyClosed=true;
      SetBtnClose("B2_","EXTRA3");
   }

   UpdatePanel();
}

//============================================================
//  ПРИМИТИВЫ ПАНЕЛИ
//============================================================
// Видимая рамка из 4 залитых прямоугольников.
// yTop/yBot — точные Y верхней и нижней полосок (независимо друг от друга).
void PanelBorder(string name,int x,int yTop,int w,int yBot,color cb)
{
   int LW  = 4;
   int hSide = yBot - yTop + LW;   // высота боковых линий от верха до низа включительно
   color bg = clrDimGray;
   PanelRect(name+"_T", x,        yTop, w,    LW,    bg, bg);  // верхняя полоска
   PanelRect(name+"_B", x,        yBot, w,    LW,    bg, bg);  // нижняя полоска
   PanelRect(name+"_L", x,        yTop, LW,   hSide, bg, bg);  // левая
   PanelRect(name+"_R", x+w-LW,   yTop, LW,   hSide, bg, bg);  // правая
}

void PanelRect(string name,int x,int y,int w,int h,color cb,color cbg)
{
   ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,       w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,       h);
   ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE, BORDER_FLAT);   // сначала тип
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,cb);            // потом цвет
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,     cbg);
   ObjectSetInteger(0,name,OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_BACK,        false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,      true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,      0);
}

void PanelBtn(string name,string text,int x,int y,int w,int h,color cbg,color ct)
{
   ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,     w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,     h);
   ObjectSetString(0, name,OBJPROP_TEXT,      text);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,   cbg);
   ObjectSetInteger(0,name,OBJPROP_COLOR,     ct);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,  8);
   ObjectSetString(0, name,OBJPROP_FONT,      "Arial Bold");
   ObjectSetInteger(0,name,OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,    true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,    1);
}

void PanelLbl(string name,string text,int x,int y,int w,int h,color ct,int fs=8,string font="Arial")
{
   ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name,OBJPROP_TEXT,      text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,     ct);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,  fs);
   ObjectSetString(0, name,OBJPROP_FONT,      font);
   ObjectSetInteger(0,name,OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,    true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,    1);
}

void PanelLblCenter(string name,string text,int x,int y,int w,int h,color ct,int fs=8,string font="Arial")
{
   ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name,OBJPROP_TEXT,      text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,     ct);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,  fs);
   ObjectSetString(0, name,OBJPROP_FONT,      font);
   ObjectSetInteger(0,name,OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,    ANCHOR_CENTER);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,    true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,    1);
}

void DeletePanel()
{
   ObjectsDeleteAll(0,g_prefix);
   ChartRedraw();
}
//+------------------------------------------------------------------+
