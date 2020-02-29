###
DataFlow
|- Pool
|- Ratio
|- Ma 
|- Tracer
    |- Explorer: 策略交易信號系統
    |- Guardian: 賬戶級別的止盈止損系統


  對不同品種,可以設置不同的子法,但是看來不需要,目前是通過系統設置,直接根據代碼給予不同的尺度
###
###
  根本:
    多頭和空頭獲利都依賴開倉後價格有利變動.
    

    可以設定一個時間函數,比如多頭倉位,每一個@bar要求x%的增幅,累積計算到@lastBar 這根 @bar,一旦達不到預計,即平倉.
    如此則形成對於速率合格片斷的擷取.
    此為投資本質.一切工具以此為根本進行開發.
    如果以幾何學來比擬,就好像在行情曲線中,截取切線斜率優於設定斜率的片斷.如此形成高單利,高復利,低風險(平倉先於轉勢).
###
# 由於注釋影響觀瞻,故大幅注釋移動到文件末尾,可參閱

# 提煉 Explorer/Guardian 共同需要的部分
_ = require 'lodash'
path = require 'path' # 參閱 pool 如何設置路徑
say = require 'say'
moment = require 'moment'
assert= require './assert'
DataFlow = require './dataflow'
{IBCode} = require './secode'
{fix} = require './fix'
{IOPTLongOpen,IOPTLongClose,IOPTLongReOpen,IOPTLongSKClose,IBLongOpen,IBShortOpen,IBLongOpenManual,IBShortOpenManual,IBLongReOpen,IBShortReOpen,IBLongClose,IBShortClose,IBLongSKClose,IBShortSKClose} = require './signal'
{previousBarMode,testingIOPT,research,Flow:{pureYinYang,scoreIntoBar,layerIntoBar,skLimit,zeroLevel,maTolerableDays,rewarmConfirmDays,longMaUpConfirmDays,shortMaUpConfirmDays},factors,baseFactors,FundAccount:{mayReOpen}} = require './config'

ldb = require('lowdb')
storage = require('lowdb/lib/file-async')
lsdb = ldb "db/dbLiveSignals.json", storage
lsdb.defaults({liveSignals:[]}).value() unless lsdb.has('liveSignals').value()

### too slow to use,太慢,不能用
# 此db非內存db
# ldb = require 'lowdb'
# storage = require('lowdb/lib/file-async')
###

# 對不同品種,可以設置不同的子法,但是看來不需要,目前是通過系統設置,直接根據代碼給予不同的尺度
# 交易諸要事: buy/sell
# Explorer: 
#   開倉, entry
#   追倉, continue
#   退倉, redraw
#   平倉  close
# Guardian:
#   止復倉, reOpen stop-lose keep-profit
#     止多/止空
#     復多/復空
#   砍倉, cut
#   手工賣出
class Tracer extends DataFlow
  constructor: (@secCode,@timescale,@contract) ->
    super(@secCode,@timescale,@contract)
    @onDuty = false
    @liveSignals = {} # 交易用,非歷史回測,用以限制反復發出相同的信號,以signalTag為key
    @signalDictionary = {IBBuyOrder:[],IBSellOrder:[]} # 僅供研究之用. 本擬改成lowdb,節省內存,可惜lowdb反復讀寫太慢了
    @tempSameDaySignals = {} # for research only

  # -------------------- Tracer constructor end  -----------------------------------  
  # Tracer
  nowOnDuty:(aBoolean)->
    @onDuty = aBoolean
    @guardian?.nowOnDuty(aBoolean)
    for k, v of @liveSignals
      v.nowOnDuty(aBoolean)

  # Tracer
  prepareSignal: (pool,signalClass,sigOpt,buoyOpt)->
    sig = null
    signalTag = signalClass.name
    #sigOpt.day ?= @bar.day
    assert(sigOpt.day?,'sigOpt.day should not be undefined')
    sigOpt.timescale ?= @timescale
    if buoyOpt.genCond? and not buoyOpt.genCond(pool, this)
      return
    unless @currentBar or (/manual/i.test signalTag) # 歷史信號純用於研究開發
      @addHistory(@newHistorySignal(signalClass,sigOpt,buoyOpt))
      
    else  # 盤中信號,用於交易
      if @lastSignal? and signalTag is @lastSignal.signalTag
        #assert.log "同類信號,不再生成"
        return

      sameSignal = @liveSignals[signalTag]
      if sameSignal? # 若已有該信號,則可能增加跟價浮標
        sameSignal.addBuoy(buoyOpt)
        #assert.log "is same signal with signalTag:",signalTag
      else # 新信號處理
        sig = @newLiveSignal(signalClass,sigOpt,pool)
        @liveSignals[signalTag] = sig #當天以前發佈的信號被覆蓋
        sig.addBuoy(buoyOpt)
        #assert.log "new signal: ", @secCode, sig.signalTag


  newLiveSignal:(signalClass,sigOpt,pool)->
    # 舊的對應信號需要先刪除,然後再自動生成新的
    sig = new signalClass(sigOpt)
    for key, signal of @liveSignals when key in sig.removeSignals
      delete(@liveSignals[key]) unless @liveSignals[key].emittedTimes >= signal.timesLimit # 已發出指令不刪除,待有新指令發出時才刪除,以免在等待成交期間,在此產生相同指令
    #令 signal 知道 secCode,timescale等等
    sig.setLive(this,pool)
    return sig


  # Tracer
  beforePushPreviousBar: (bar,pool)->
    @clearOldSignals(bar,pool)
    
  clearOldSignals:(bar,pool) ->
    notToday = (signal)-> 
      not (moment().utc().isSame(signal.ariseTime,'day') or moment().isSame(signal.ariseTime,'day')) 
    for key, signal of @liveSignals when notToday(signal) # 如果系統連續運行,僅當天的信號有效
      delete @liveSignals[key] # 系統連續運行不關機情況下,刪除昨日信號
    #@liveSignals = {}
  
  # Tracer
  # 臨時注釋: detect 是後起之法,用以取代之前的 preSettings 等錯誤機制
  # detect 將嚴格遵照 oop 原則,將工作分配到最末端,各就各位去完成,
  # 待detect 完成之後,prpreCalc 內的計算均已部署到合理的地方,目前大片代碼腫瘤也就自動消失了.
  firstBar:(pool)->
    @currentBar = pool.currentBar
    @preSettings(pool)
    @detect(pool)
  
  # Tracer
  nextBar: (pool)->
    @currentBar = pool.currentBar
    @preSettings(pool)
    @detect(pool)
    return this
  
  # Tracer
  newHistorySignal: (signalClass,sigOpt,buoyOpt)->
    signal = new signalClass(sigOpt)
    signal.orderPrice = buoyOpt.orderPrice
    signal.signalTag = signal.buoyName = buoyOpt.buoyName
    return signal

  # Tracer
  addHistory:(signal)->
    # 歷史信號目前僅作研究開發之用,不影響交易.發行版可注釋此行
    {orderClassName} = signal
    similar = @tempSameDaySignals[orderClassName]
    if similar? and moment(similar.day).isSame(signal.day,@timescale)
      similar.privateCombine(signal)
    else if signal.isValidHistoricTime()
      @tempSameDaySignals[orderClassName] = signal
      @signalDictionary[orderClassName].push(signal)
    
    if @currentBar
      simplified = signal.copyWithout(['tradePrice','buoys','addTime','timesLimit','emittedTimes','customs','bases','isStopKeepSignal','isOpenSignal','isCloseSignal','isLongSignal','isShortSignal','isReOpenSignal'])
      @emit('liveSignalsEmerged',simplified)
  
    # Tracer
    # 主要用於分時策略歷史效果數據測試
    isValidTime:->
      true # 各自為政. 例如 iopt 在一個交易日內,有買入點時間限制

  # Tracer
  emitSignal:(pool,sig)->
    {signalTag} = sig
    for key, signal of @liveSignals when signal.emittedTimes >= signal.timesLimit
      delete(@liveSignals[key]) # 清除已經過期的指令,此時已經不擔心重複指令問題
    assert.log @constructor.name, " >> emitted signal: ", signalTag
    if true # 可添加限制條件
      @emit(@messageSymbol, sig)
    @lastSignal = sig
    @addHistory(sig)
      
  # Tracer
  closeInsteadOfLow: =>
    {open,close,high,low} = @bar
    p = if @currentBar then close else low
    return p / (1+@facts.容忍因子)
  
  closeInsteadOfHigh: =>
    {open,close,high,low} = @bar
    p = if @currentBar then close else high
    return p * (1+@facts.容忍因子)
  
  # Tracer
  # 支持人工買賣, 如果指定價格執行,name 用大寫字母 'SET'
  bsBoarder:(bp,sp,pool,name,percent=1)->
    @buy(bp,pool,name,percent)
    @sell(sp,pool,name,percent)
  
  buy:(price,pool,name,percent=1,vol=null)->
    {day,close,high} = @bar
    buoyOpt =  
      buoyName: "開多:手工#{name ? 'SET'}"
      orderPrice: (price ? close)
    @prepareSignal(pool,IBLongOpenManual,{day:day,plannedPosition:percent,vol:vol},buoyOpt)
    assert.log("注意: 已準備委託. 目前非多頭態勢") if @isBear
  sell:(price,pool,name,percent=1,vol=null)->
    {day,close} = @bar
    
    buoyOpt =  
      buoyName: "開空:手工#{name ? 'SET'}"
      orderPrice: (price ? close)
    @prepareSignal(pool,IBShortOpenManual,{day:day,plannedPosition:percent,vol:vol},buoyOpt) 
    assert.log("注意: 已準備委託. 目前非空頭態勢") if @isBull


  # 記錄 orderId, 用於後續更新成交狀況對號入座
  sentSignal:(signal, orderId)->
    @liveSignals[signal.signalTag].orderId = orderId 
    # [TODO] 若此時已不在 liveSignals, 則在 @signalDictionary 查找?

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Tracer End ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~






# Explorer 跟 Guardian 策略寫法不一樣,不用強求一致.因止盈止損重點是價位,邏輯簡單很多.而此法則反之.

class Explorer extends Tracer
  # 為方便iopt 等特殊法故如此設置
  @longOpenSigClass: IBLongOpen
  @longCloseSigClass: IBLongClose


  @pick:(secCode,timescale,contract)->
    if IBCode.isForex(secCode)
      return new ForexExplorer(secCode, timescale, contract)
    else if /HSI/i.test(secCode)
      return new HSIExplorer(secCode, timescale, contract)
    else if IBCode.isHKIOPT(secCode)
      return new HKIOPTExplorer(secCode, timescale, contract)        
    else if IBCode.isHK(secCode)
      return new HKStkExplorer(secCode, timescale, contract)         
    else if IBCode.isABC(secCode)
      return new USStkExplorer(secCode, timescale, contract)
    else
      return new Explorer(secCode, timescale, contract)

  constructor:(@secCode,@timescale,@contract) ->
    super(@secCode,@timescale,@contract)
    @messageSymbol = '策略信號'
    
    # 若尚無自適應因子,則取基本設置,待系統學習生成各品種因子
    @customs = ldb("db/factors#{@secCode}.json", storage)
    @customs.defaults({factors:factors}).value()
    # 使用@facts 指代各因子,而不直接取變量,是為了跟signal等共同使用, object 唯一故,否則要增加代碼來同步.
    @facts = @customs.get('factors').value()
    @bases = new IBCode(@secCode).parameters(baseFactors)
    @facts.容忍因子 = Math.max(@bases.最小容忍因子, @facts.容忍因子)
    @facts.保本因子 = Math.max(@bases.最小保本因子, @facts.保本因子)
    if @facts.報價因子 < @bases.最小報價因子
      @facts.報價因子 = @bases.最小報價因子
    else if @facts.報價因子 > @bases.最大報價因子
      @facts.報價因子 = @bases.最大報價因子

    if true #@timescale is 'day' # 沒有 guardian 就會沒有信號,現在我很疲憊昏沉,尚未找到出錯原因,待明天再說
      @guardian = new Guardian(@secCode, @timescale, @contract)
      [@guardian.bases, @guardian.customs, @guardian.facts] = [@bases, @customs, @facts]

  # -------------------- Explorer constructor end  -----------------------------------
  #nowOnDuty:(aBoolean)->
  #  super(aBoolean)
  #  guardian?.nowOnDuty(aBoolean)
  
  ### [收盤迷霧]

    某法在歷史行情中會出現誤差,原因是@bar.close已經收盤矣
    注意: 盡量採用固定價格作為觸發事件,和設定執行價位,例如ta值等等,避免使用 .close

  ###

  comingBar:(bar,pool) ->
    super(bar,pool)
    #if @timescale is 'day'
    @guardian?.comingBar(bar,pool)
  


  # 首日不做,所以不用計算那些實時策略判斷所需要的變量
  firstBar:(pool)->
    super(pool)

  #Explorer
  nextBar:(pool)->
    super(pool)
    # 為了簡化代碼, 以下均需要 earlierBar
    unless @earlierBar?
      return
    @inspect(pool)
    if pool.currentBar
      unless @cautionPrice?
        assert.log "[debug] now setCautionInterval"
        @setCautionInterval()
      @makeCaution()  # 語音播報行情變動
  
  # 語音播報行情變動
  setCautionInterval:(@cautionPrice, @cautionInterval)->
    @cautionPrice ?= @bar.closeHighBand
    #assert.log "debug: makeCaution:", @cautionInterval

  warnOn: (price)->
    if close > price >= @lastBar.close
      say.speak("#{@secCode},上#{close}",'sin-ji')
      #assert.log("#{@secCode},上漲突破#{price}")
    else if close < price <= @lastBar.close
      say.speak("#{@secCode}, 落#{close}",'sin-ji')
      #assert.log("#{@secCode}, 下跌跌破#{price}")
  
  makeCaution: ->
    {close} = @bar    
    if @cautionPrice?
      @warnOn(@cautionPrice)
    if @cautionInterval? # 設置此變量前已經檢測 speakout 選項,故以下不必再測
      unless @cautionPrices? and @bar.closescore is @lastBar.closescore
        high = @bar["score#{@bar.closescore}"] 
        low = @bar["score#{@bar.closescore - 1}"]
        @cautionPrices = (x for x in [low..high] by @cautionInterval)
      for price in @cautionPrices
        @warnOn(price)
  
  # 放置於pool似乎亦可.但目前設計,pool 必須設置不同的subclass 應對不同的行情來源,不方便根據品種類型設置subclass
  # explorer
  detect:(pool) ->
    @collectXIO(pool)

  sellXFilter:(pool) ->
    return true
  buyXFilter:(pool) ->
    return true

  # 此處應該選擇最小概率的高確定性策略,然後在各個子系可以根據各自特點放寬
  # explorer
  ____NOTUSED__detectBuyEntry:(pool)->
    @bar.buyEntry

  ____NOTUSED__detectSellEntry:(pool)->
    @bar.sellEntry    
  
  ###
  ____NOTUSED__detectBuyEntry:(pool)->
    if pool.ema20.barUpCrossing() 
      @bar.buyPrice = @bar.ema_price20
    else if pool.bband20.barUpCrossing('closeLowBand') 
      @bar.buyPrice = @bar.closeLowBand
    else
      @bar.buyPrice = null
    @bar.buyEntry = @bar is pool.buyXBar
    
    #or @bar.upXBelow('ema_price20')
  
  ____NOTUSED__detectSellEntry:(pool)->
    if pool.ema20.barDownCrossing() 
      @bar.sellPrice = @bar.ema_price20
    else
      @bar.sellPrice = null
    @bar.sellEntry = @bar is pool.sellXBar
    #pool.bband20.barDownCrossing('closeHighBand') or pool.yinfish.downCrossedHigh()
  ###    

  ____NOTUSED__detectBuyWithdraw: (pool)->
    if pool.ema20.barDownCrossing() 
      @bar.sellPrice = @bar.ema_price20
    @bar.buyWithdraw = @bar.sellPrice?

  ____NOTUSED__detectSellWithdraw: (pool)->
    @bar.sellWithdraw = false
  
  
  
  # 開發工具
  showXLine:(lineName,crossName)->
    (bar for bar in @barArray when bar[crossName]? and (lineName in bar["#{crossName[...-5]}Crosses"]))
  

  preSettings: (pool)->    
    # 先分牛熊,後定進出;牛熊宜寬,進出須嚴
    #   陰短陽長,名之為牛
    #   越於常軌,而有進出
    pool.secPosition.facts = @facts
    @isBull = pool.bullish()
    @isBear = not @isBull #pool.bearish()
    
    return this


  # Explorer
  # 此處設計,至少需要三根@bar才能開始inspect操作
  inspect:(pool)->
    if @isBear
      if @previousBar.isBull # 注意,現在設計,bar.isBull 是0或1
        @longClose(pool)
      @shortOpen?(pool)
      @shortClose?(pool)
    else if @isBull
      @longOpen(pool)    
      @longClose(pool)
      if not @previousBar?.isBull # 注意,現在設計,bar.isBull 是0或1
        @shortClose?(pool)
      

    # 信號發佈
    (each for key, each of @liveSignals).map (sig) =>
      {ariseTime,signalTag} = sig
      if sig.outdated(pool, this)
        assert.log("deleting outdated #{signalTag},#{ariseTime} ")        
        delete(@liveSignals[signalTag])
      else if sig.fire(pool,this)
        assert.not(sig.isShortOpenSignal and @isBull, 'short when bull')
        assert.not(sig.isLongOpenSignal and @isBear, 'long when not bull')
        @emitSignal(pool,sig)
        sig.emittedTimes++
      
    


  # Explorer
  longFor:(pool)->
    @longOpen(pool)    
    @longClose(pool)






  # 多頭開倉
  # Explorer
  # 原則
  #   開倉條件須嚴格,能不做就不做,避免魚目混珠,資金留給真正出現良機的品種.機會無限.
  #   不怕錯過一萬,就怕碰到萬一.故此,凡遇若想占全機會則需複雜條件者,一律放棄
  longOpen:(pool)->
    {容忍因子,報價因子} = @facts
    unless research
      cond = (pool,tracer) -> tracer.buyable()
      if @bar.buyEntry and cond(pool,this)
        arr = pool.scores.estimates()[..8]
        # 以上方法為舊設計,現臨時湊合,但加穿透位,以後再修改
        xPrice = @buyXPrice
        arr.push(xPrice)
        levels = ({buoyName: "開多:均速#{i}",orderPrice: fix(p),cond: cond} for p,i in arr when p <= xPrice * (1 + 報價因子)) # 
        levels.map (buoyOpt)=>
          {close,high,low,day} = @bar
          if (buoyOpt.orderPrice <= @closeInsteadOfHigh()) # 而不用 < high 是要求已經上衝到委託價,然後尋求回落下來再回昇到行動價的機會,如此自動追價機制才能正常運作
            sigOpt = 
              day:day
              plannedPosition:1
            @prepareSignal(pool,@constructor.longOpenSigClass,sigOpt,buoyOpt) 
    else
      @bor多頭開倉(pool)
      @bor回昇多頭開倉(pool)

  # 多頭平倉
  # Explorer
  longCloseGetCost:(pool)=>
    if @currentBar then pool.secPosition.成本價 * (1+@facts.保本因子) else 0
  # Explorer
  longClose:(pool)->
    {容忍因子} = @facts
    unless research
      cond = (pool,tracer)-> tracer.sellable() # 發令條件而非執行條件,無論牛熊皆可平倉(對不對?)
      if @bar.sellEntry and cond(pool,this)
        #cost = @longCloseGetCost(pool)
        arr = pool.scores.estimates()[-5..]
        # 以上方法為舊設計,現臨時湊合,但加穿透位,以後再修改
        xPrice = @sellXPrice
        arr.push(xPrice)
        levels = ({buoyName: "平多:均速#{i}",orderPrice: fix(p),cond:-> true} for p,i in arr when p >= xPrice / (1 + 容忍因子))
        levels.map (buoyOpt)=>
          {close,high,low,day} = @bar
          if (@closeInsteadOfLow() <= buoyOpt.orderPrice) # 而不是 low < 是要求已經下探到委託價,然後尋求反彈上來再下行到行動價的機會,如此自動追價機制才能正常運作
            sigOpt = 
              day: day
              plannedPosition: 0 / 100
            @prepareSignal(pool,@constructor.longCloseSigClass,sigOpt,buoyOpt)

    else
      @防跌破前收多頭平倉(pool)
      @跌破動天前收之高者賣出(pool)
      @跌破均線反彈賣出(pool)
      @跌破前yinfishy賣出(pool)
      @跌破動天高空賣出(pool)



  
  
  
  # ==============================================================================
  
  # 為了兼容舊代碼而作的簡單備份方法,舊法要用到最下面的若干變量故先須運行此function
  extraCalc: ->      
    {bor,deltar,open,low,close,ma_price10,ma_price150} = @bar
    {ratioTBF:{yangfishz},yangfishy} = pool
    pre = @previousBar
    ear = @earlierBar
    predlt = pre.deltar
    uponMa = close > ma_price10 > low*0.994 or close > ma_price150 > low*0.994
    @notNewLow = ((yangfishy.size > 1) and (yangfishz.size > 1)) or (close > open) or uponMa
    dropEnd = @notNewLow or ratioMaUp or (deltar > 0)
    @longPointBor雙底 = (0 > bor) and (pre.bor > bor > ear.bor) and dropEnd

  # ---------------------------- Explorer 多頭開倉 ---------------------------------

  # 價格創新低,bor值則回昇,形成底背離
  # Explorer
  bor多頭開倉:(pool)->
    name = "開多:#{pool.timescale}bor"
    if (@bar.low < @previousBar.low < @earlierBar.low) or ((@bar.low < @previousBar.close < @earlierBar.close) and @bar.low < Math.min(@previousBar.low,@earlierBar.low))
      if @bor值初回昇(pool) or @longPointBor雙底 or @幅度差回零上(pool)
        {open,close,low} = @previousBar
        price = 0.5 * (@bar.low + Math.min(close, open)) # let signal itself to approve the price later
        buoyOpt = buoyName:name,orderPrice:price
        @prepareLongOpenSignal(pool,buoyOpt)

  # 不必須創新低,其他同上
  # Explorer
  # 此方案須在尾盤半小時或十五分鐘內開始探測
  bor回昇多頭開倉:(pool)->
    name = "開多:#{pool.timescale}bor回昇"
    if @bor值初回昇(pool) or @幅度差回零上(pool)
      if @previousBar.low < @bar.low < Math.max(@earlierBar.low,@earlierBar.close) # @earlierBar.low
        if @bar.low < @earlierBar.close #Math.max(@previousBar.close, @earlierBar.close) #@previousBar.close < @earlierBar.close
          # 底部回昇買入,不應出現跳空高開向上的情形,一旦出現防止高開暴跌,故不買
          price = Math.min((@previousBar.low + @previousBar.high) / 2, (@previousBar.close * (1+@facts.保本因子)))
          buoyOpt = buoyName:name,orderPrice:price,tillMinute:-15
          @prepareLongOpenSignal(pool,buoyOpt)







  # ----------------------------  Explorer 多頭平倉 ---------------------------------

    

  三線止盈:(pool)->
    if (@bar.close < @bar.duePrice) or (@bar.deltar < 0 < @previousBar.deltar)
      orderPrice = Math.min(@bar.duePrice,@previousBar.high)
      @prepareLongCloseSignal(pool,{buoyName:"平多:三線止盈",orderPrice:orderPrice})

  # Explorer
  天上新天:(pool)->
    (@bar.high is @bar.tay) and @bar.tay >= @bar.ta

  # [收盤迷霧] 此法在歷史行情中會出現誤差,原因是@bar.close已經收盤矣
  # Explorer
  防跌破前收多頭平倉:(pool)->
    name = "平多:#{pool.timescale}:防跌破前收"
    if pool.yangfishy.loryTurnedDown or @天上新天(pool)
      orderPrice = @previousBar.close * (1+@facts.容忍因子)
      buoyOpt = buoyName:name,orderPrice:orderPrice
      @prepareLongCloseSignal(pool,buoyOpt)



  # Explorer
  跌破動天前收之高者賣出:(pool)->
    name = "平多:#{pool.timescale} 跌破動天前收之高者"
    if pool.yangfishy.loryTurnedDown
      if @bar.high > @bar.tay
        價位 = Math.max(@previousBar.close,@bar.tay)
        buoyOpt = buoyName:name,orderPrice:價位
        @prepareLongCloseSignal(pool,buoyOpt)


  # [開發 待複查(困先睡了)]
  # Explorer
  跌破均線反彈賣出:(pool)->
    name = "平多:#{pool.timescale} 跌破均線反彈"
    均值 = switch @timescale
      when 'day' then @bar.ma_price10
      when 'week' then @bar.ma_price05
      when 'month' then @bar.ma_price05
      else
        @bar.ma_price30

    buoyOpt = buoyName:name,orderPrice:均值
    @prepareLongCloseSignal(pool,buoyOpt)


  # Explorer
  跌破前yinfish賣出:(pool)->
    name = "平多:#{pool.timescale}跌破前yinfish"
    價位 = pool.求前魚('yinfishArray').startBar.high
    buoyOpt = buoyName:name,orderPrice:價位
    @prepareLongCloseSignal(pool,buoyOpt)

  # Explorer
  跌破前yinfishy賣出:(pool)->
    name = "平多:#{pool.timescale}跌破前yinfishy"
    價位 = pool.求前魚('yinfishyArray').startBar.high
    buoyOpt = buoyName:name,orderPrice:價位
    @prepareLongCloseSignal(pool,buoyOpt)


  # 1. 在天均之上 2. 跌破tay
  # Explorer
  跌破動天高空賣出:(pool)->
    name = "平多:#{pool.timescale}跌破動天"
    if pool.yangfishy.loryTurnedDown
      價位 = @bar.tay
      buoyOpt = buoyName:name,orderPrice:價位
      @prepareLongCloseSignal(pool,buoyOpt)








  # ---------------------------- Explorer 空頭開倉 ---------------------------------


  幅度差回零上:(pool)->
    @bar.deltar > 0 > @previousBar.deltar

  # Explorer
  bor值初回昇:(pool)->
    {bor} = @bar
    @lineBottomUp('bor',0,5/100)

  

  # Explorer


  # 以下生成多空策略,可使用pool各種屬性,以及@bar(lastBar行情),@previousBar,@earlierBar這三個便利變量

  # Explorer
  # [在改] name將簡化為 開多,開空,平多,平空,止多,止空,復多,復空 八種.
  prepareLongOpenSignal:(pool,buoyOpt)->
    {close,high,low,day,tay,lory} = @bar
    if @notNewLow
      if @closeInsteadOfHigh() >= buoyOpt.orderPrice > low # close: 預設價格已出現
        if high <= tay and lory < 15 #true # @previousBar.deltar <=0 and @bar.deltar > 0 # 可能會有未來數據,不輕易使用
          if (@earlierBar.bor < 0) or (@previousBar.bor < 0) or (@lastBar.bor < 0) or (@bar.bor < 0)
            #buoyOpt.cond = (p,tracer)-> tracer.previousBar.deltar <=0 and tracer.bar.deltar > 0
            @prepareSignal(pool,IBLongOpen,{day:day,plannedPosition:100 / 100},buoyOpt)



  # Explorer
  prepareLongCloseSignal:(pool,buoyOpt)->
    {close,high,low,day} = @bar
    # 以下條件不能通用,須納入的適用的條件內
    unless @bor值初回昇(pool) or @幅度差回零上(pool) #  or @longPointBor雙底
      if high > buoyOpt.orderPrice >= @closeInsteadOfLow() #> low # 預設價格已出現,故不用low而用close,現價
        if true #@bar.deltar < 0 # pool.yangfishy.loryTurnedDown
          @prepareSignal(pool,IBLongClose,{day:day,plannedPosition:0 / 100},buoyOpt)


  # Explorer
  prepareShortOpenSignal:(pool,buoyOpt)->
    unless @bor值初回昇(pool) or @longPointBor雙底 or @幅度差回零上(pool)
      if @bar.deltar < 0 < @previousBar.deltar
        {high,low,close,day} = @bar
        if high > buoyOpt.orderPrice >= @closeInsteadOfLow() #> low # 預設價格已出現,故不用low而用close,現價
          sigOpt = day:day,plannedPosition:100 / 100
          @prepareSignal(pool,IBShortOpen,sigOpt,buoyOpt)

  # Explorer
  prepareShortCloseSignal:(pool,buoyOpt)->
    if @bar.deltar > 0 > @previousBar.deltar
      {high,low,close,day} = @bar
      if low < buoyOpt.orderPrice <= @closeInsteadOfHigh() #< high # close: 買入價已出現
        sigOpt = day:day,plannedPosition:0 / 100
        @prepareSignal(pool,IBShortClose,sigOpt,buoyOpt)




# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Explorer End ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
class HKSecExplorer extends Explorer

  #[臨時待整理] 以下各項function 皆原樣拷貝自 HKIOPTExplorer
  # HKIOPTExplorer
  foundBuyX:(pool)->
    @upXBar? and (@upXBar.low > @preUpXBar?.low or @upXBar.ema_price20 > @preUpXBar?.ema_price20)
  
  # HKIOPTExplorer
  # todo:
  # 若有大行情,策略平倉,如何及時跟進
  foundSellX:(pool)->
    (@downXBar? and @downXPriceDown(pool)) 
  
  downXPriceDown:(pool)->
    @downXBar.high <= @preDownXBar?.high or (@downXBar.ema_price20 < @preDownXBar?.ema_price20) or (@downXBar.isAfter(@upXBar?) and @downXBar.high <= @upXBar?.high)

  
  setIOXPrice: ->
    @sellXPrice = @downXBar?.downXPrice()
    @buyXPrice = @upXBar?.upXPrice()
  


  # HKIOPTExplorer
  sellXFilter:(pool)->
    @sellXBullFilter(pool) or @sellXBearFilter(pool)
  sellXBullFilter:(pool)->
    @isBull and (@downXBar.highlevel > 7) and @downXBar.high > @downXBar.bbta #@downXBar.hkPriceGradesUpto('close','bbta',2)
  sellXBearFilter:(pool)->
    @isBear and (@downXBar.highlevel > 1) and @downXBar.high > @downXBar.ema_price20
  
  # HKIOPTExplorer
  # 箱體小於15格不入手,雖然會錯過一些機會,但機會太多了.只須考慮排除風險.
  buyXFilter:(pool)->
    x = 16
    y = 9
    if @isBear or pool.bar.hkCurrentVerticalGrade() < x or pool.yinfish.hkCurrentDepthGrade() < y or pool.bar.closeHigherThanAny(['closeHighHalfBand','score9','ta','bbta','level9'])
      return false
    @buyXBullFilter(pool) or @buyXBearFilter(pool)
  
  buyXBullFilter:(pool)->
    @isBull and (@upXBar.lowBelowLine(pool.bband20.highHalfBandName) or @upXBar.closeBelowLine('level4'))  #('level1') 
  buyXBearFilter:(pool)->
    @isBear and @upXBar.lowBelowLine(pool.bband20.lowHalfBandName) #or @bar.closeBelowLine('level1')  #('level1') 

    
  
  # HKIOPTExplorer
  longOpen:(pool)->
    cond = (pool, tracer)-> tracer.buyable() and (tracer.bar.volume > 10000)
    if @bar.buyEntry and cond(pool,this)
      arr = pool.scores.estimates()[..4]
      # 以上方法為舊設計,現臨時湊合,但加穿透位,以後再修改
      xPrice = @buyXPrice
      assert(xPrice, 'no buyXPrice')
      arr.push(xPrice)
      levels = ({buoyName: "開多:均速#{i}",orderPrice: fix(p),cond: cond} for p,i in arr when p <= xPrice)
      assert(levels.length > 0, 'arr should not be empty')
      levels.map (buoyOpt)=>
        {close,high,low,day} = @bar
        sigOpt = 
          day:day
          plannedPosition:1
        @prepareSignal(pool,@constructor.longOpenSigClass,sigOpt,buoyOpt) 

  
  # HKIOPTExplorer
  longClose:(pool)->
    cond = (pool,tracer) -> tracer.sellable()
    if @bar.sellEntry and cond(pool,this)
      #cost = @longCloseGetCost(pool)
      arr = pool.scores.estimates()[-5..]
      # 以上方法為舊設計,現臨時湊合,但加穿透位,以後再修改
      xPrice = @sellXPrice
      arr.push(xPrice)
      levels = ({buoyName: "平多:均速#{i}",orderPrice:fix(p),cond:cond} for p,i in arr when p >= 0.998 * xPrice)
      levels.map (buoyOpt)=>
        {close,high,low,day} = @bar
        sigOpt = 
          day: day
          plannedPosition: 0 / 100
        @prepareSignal(pool,@constructor.longCloseSigClass,sigOpt,buoyOpt)


class HKIOPTExplorer extends HKSecExplorer # 不從 HKStkExplorer, 諸多不同故
  @longOpenSigClass: IOPTLongOpen
  @longCloseSigClass: IOPTLongClose

  constructor:(@secCode,@timescale,@contract) ->
    super(@secCode,@timescale,@contract)
    @facts.容忍格數 = Math.max(@bases.最小容忍格數, @facts.容忍格數 ? 0)
    @facts.保本格數 = Math.max(@bases.最小保本格數, @facts.保本格數 ? 0)
    @isHKIOPT = true

    if true #@timescale is 'day' # 沒有 guardian 就會沒有信號,現在我很疲憊昏沉,尚未找到出錯原因,待明天再說
      @guardian = new HKIOPTGuardian(@secCode, @timescale, @contract)
      [@guardian.bases, @guardian.customs, @guardian.facts] = [@bases, @customs, @facts]
  
  # HKIOPTExplorer
  preSettings:(pool)->
    @renewKeyPrices()
    # 注意順序
    super(pool)

  # HKIOPTExplorer
  renewKeyPrices:->
    @facts.priceGrade = @bar.hkPriceGrade()
    @facts.容忍差價 = @facts.容忍格數 * @facts.priceGrade
    @facts.保本差價 = @facts.保本格數 * @facts.priceGrade
    @facts.報價差價 = @facts.priceGrade



  # HKIOPTExplorer
  foundBuyX:(pool)->
    @upXBar? and (@upXBar.low > @preUpXBar?.low or @upXBar.ema_price20 > @preUpXBar?.ema_price20)
  
  # HKIOPTExplorer
  # todo:
  # 若有大行情,策略平倉,如何及時跟進
  foundSellX:(pool)->
    (@downXBar? and @downXPriceDown(pool)) 
  
  downXPriceDown:(pool)->
    @downXBar.high <= @preDownXBar?.high or (@downXBar.ema_price20 < @preDownXBar?.ema_price20) or (@downXBar.isAfter(@upXBar?) and @downXBar.high <= @upXBar?.high)

  
  setIOXPrice: ->
    @sellXPrice = @downXBar?.downXPrice()
    @buyXPrice = @upXBar?.upXPrice()
  


  # HKIOPTExplorer
  sellXFilter:(pool)->
    @sellXBullFilter(pool) or @sellXBearFilter(pool)
  sellXBullFilter:(pool)->
    @isBull and (@downXBar.highlevel > 7) and @downXBar.high > @downXBar.bbta #@downXBar.hkPriceGradesUpto('close','bbta',2)
  sellXBearFilter:(pool)->
    @isBear and (@downXBar.highlevel > 1) and @downXBar.high > @downXBar.ema_price20
  
  # HKIOPTExplorer
  # 箱體小於15格不入手,雖然會錯過一些機會,但機會太多了.只須考慮排除風險.
  buyXFilter:(pool)->
    x = 16
    y = 9
    if @isBear or pool.bar.hkCurrentVerticalGrade() < x or pool.yinfish.hkCurrentDepthGrade() < y or pool.bar.closeHigherThanAny(['closeHighHalfBand','score9','ta','bbta','level9'])
      return false
    @buyXBullFilter(pool) or @buyXBearFilter(pool)
  
  buyXBullFilter:(pool)->
    @isBull and (@upXBar.lowBelowLine(pool.bband20.highHalfBandName) or @upXBar.closeBelowLine('level4'))  #('level1') 
  buyXBearFilter:(pool)->
    @isBear and @upXBar.lowBelowLine(pool.bband20.lowHalfBandName) #or @bar.closeBelowLine('level1')  #('level1') 

    
  
  # HKIOPTExplorer
  longOpen:(pool)->
    cond = (pool, tracer)-> tracer.buyable() and (tracer.bar.volume > 10000)
    if @bar.buyEntry and cond(pool,this)
      arr = pool.scores.estimates()[..4]
      # 以上方法為舊設計,現臨時湊合,但加穿透位,以後再修改
      xPrice = @buyXPrice
      assert(xPrice, 'no buyXPrice')
      arr.push(xPrice)
      levels = ({buoyName: "開多:均速#{i}",orderPrice: fix(p),cond: cond} for p,i in arr when p <= xPrice)
      assert(levels.length > 0, 'arr should not be empty')
      levels.map (buoyOpt)=>
        {close,high,low,day} = @bar
        sigOpt = 
          day:day
          plannedPosition:1
        @prepareSignal(pool,@constructor.longOpenSigClass,sigOpt,buoyOpt) 

  
  # HKIOPTExplorer
  longClose:(pool)->
    cond = (pool,tracer) -> tracer.sellable()
    if @bar.sellEntry and cond(pool,this)
      #cost = @longCloseGetCost(pool)
      arr = pool.scores.estimates()[-5..]
      # 以上方法為舊設計,現臨時湊合,但加穿透位,以後再修改
      xPrice = @sellXPrice
      arr.push(xPrice)
      levels = ({buoyName: "平多:均速#{i}",orderPrice:fix(p),cond:cond} for p,i in arr when p >= 0.998 * xPrice)
      levels.map (buoyOpt)=>
        {close,high,low,day} = @bar
        sigOpt = 
          day: day
          plannedPosition: 0 / 100
        @prepareSignal(pool,@constructor.longCloseSigClass,sigOpt,buoyOpt)

  ###
  # HKIOPTExplorer
  ____NOTUSED__detectBuyEntry:(pool)->
    if pool.ema20.barUpCrossing() and (@timescale in ['minute'] or not @bar.openUpOver('closeHighBand',@previousBar)) 
      @bar.buyPrice = @bar.ema_price20
    else if pool.bband20.hkJumpUp()
      @bar.buyPrice = @bar.closeHighBand
    else 
      super(pool)
    @bar.buyEntry = @bar is pool.buyXBar

  # HKIOPTExplorer
  ____NOTUSED__detectSellEntry:(pool)->
    if pool.bband20.barDownCrossing('closeHighBand')
      @bar.sellPrice = @bar.closeHighBand
    else if pool.yinfish.downCrossedHigh()
      @bar.sellPrice = @bar.tay
    else
      super(pool)
    @bar.sellEntry = @bar is pool.sellXBar
  ###

  # 接收到正股發出的操作信號,如何操作?
  # HKIOPTExplorer
  rootSecSignal: (pool, direction)=>
    # direction is 'buy' or 'sell' so:
    assert.log "from sec: #{direction}FromRootSec"
    @["#{direction}FromRootSec"](pool)
  rootSecEntryPoint: (pool,direction,obj)=>
    _.assign(@bar,obj)
  
  buyFromRootSec:(pool)->
    @bar.buyPrice = @bar.close
    @bar.buyEntry = true
  sellFromRootSec:(pool)->
    @bar.sellPrice = @bar.close
    @bar.sellEntry = true


  closeInsteadOfLow: =>
    {open,close,high,low} = @bar
    p = if @currentBar then close else low
    return p - @facts.容忍差價

  closeInsteadOfHigh: =>
    {open,close,high,low} = @bar
    p = if @currentBar then close else high
    return p + @facts.容忍差價

  longCloseGetCost: (pool)=>
    if @currentBar then pool.secPosition.成本價 + @facts.保本差價 else 0
  

class HKStkExplorer extends HKSecExplorer
  ____NOTUSED__detectBuyEntry:(pool)->
    if pool.ema20.barUpCrossing() and (@timescale in ['minute'] or not @bar.openUpOver('closeHighBand',@previousBar)) # or @bar.upXBelow('ema_price20'))
      @bar.buyPrice = @bar.ema_price20
    else if pool.bband20.hkJumpUp()
      @bar.buyPrice = @bar.closeHighBand
    else
      @bar.buyPrice = null
    @bar.buyEntry = @bar.buyPrice?
  ____NOTUSED__detectSellEntry:(pool)->
    if pool.bband20.barDownCrossing('closeHighBand')
      @bar.sellPrice = @bar.closeHighBand
    #else if pool.yinfish.downCrossedHigh()
    #  @bar.sellPrice = @bar.ta
    else
      @bar.sellPrice = null
    @bar.sellEntry = @bar.sellPrice?
    

class HKRootSecExplorer extends HKStkExplorer
  constructor:(@secCode,@timescale,@contract) ->
    super(@secCode,@timescale,@contract)
    @messageSymbol = '牛熊證正股信號'
    @stateSymbol = '牛熊證正股買賣點'
    @state =
      buyEntry: false
      sellEntry: false
      buyWithdraw: false
      sellWithdraw: false

  emitRootSecChanged:(pool, obj)->
    unless pool.currentBar then return
    @emit(@stateSymbol, obj)

class HSIExplorer extends HKRootSecExplorer
  ###  
  ____NOTUSED__detectBuyEntry:(pool)->
    if pool.ema20.barUpCrossing() and (@timescale in ['minute'] or not @bar.openUpOver('closeHighBand',@previousBar))  # or @bar.upXBelow('ema_price20'))
      @bar.buyPrice = @bar.ema_price20
    else if pool.bband20.hkJumpUp()
      @bar.buyPrice = @bar.closeHighBand
    else
      @bar.buyPrice = null
    @bar.buyEntry = @bar is pool.buyXBar
      
    if @bar.buyEntry
      unless @state.buyEntry
        @emitRootSecChanged(pool, buyEntry:true)
        @state.buyEntry = true
    else 
      if @state.buyEntry
        @emitRootSecChanged(pool, buyEntry:false)
        @state.buyEntry = false

  ____NOTUSED__detectBuyWithdraw:(pool)->
    super(pool)
    if @bar.buyWithdraw
      unless @state.buyWithdraw
        @emitRootSecChanged(buyWithdraw:true)
        @state.buyWithdraw = true
    else 
      if @state.buyWithdraw
        @emitRootSecChanged(buyWithdraw:false)
        @state.buyWithdraw = false
    
  ____NOTUSED__detectSellEntry:(pool)->
    if pool.bband20.barDownCrossing('closeHighBand') 
      @bar.sellPrice = @bar.closeHighBand
    #else if pool.yinfish.downCrossedHigh()
    #  @bar.sellPrice = @bar.ta
    else
      @bar.sellPrice = null
    @bar.sellEntry = @bar is pool.sellXBar

    if @bar.sellEntry and not @state.sellEntry
      @emitRootSecChanged(sellEntry:true)
      @state.sellEntry = true
    else 
      if @state.sellEntry
        @emitRootSecChanged(sellEntry:false)
        @state.sellEntry = false
  ###
  
  ____NOTUSED__detectSellWithdraw:(pool)->
    super(pool)
    if @bar.sellWithdraw and not @state.sellWithdraw
      @emitRootSecChanged(sellWithdraw:true)
      @state.sellWithdraw = true
    else 
      if @state.sellWithdraw
        @emitRootSecChanged(sellWithdraw:false)
        @state.sellWithdraw = false
  

class USStkExplorer extends Explorer
  ###
  ____NOTUSED__detectBuyEntry:(pool)->
    if pool.ema20.barUpCrossing()
      @bar.buyPrice = @bar.ema_price20
    else if pool.bband20.barUpCrossing('closeLowBand')
      @bar.buyPrice = @bar.closeLowBand
    else if @bar.upXBelow('ema_price20')
      @bar.buyPrice = @bar.ema_price20
    else
      @bar.buyPrice = null
    @bar.buyEntry = @bar is pool.buyXBar

  ____NOTUSED__detectSellEntry:(pool)->
    if pool.bband20.barDownCrossing('closeHighBand')
      @bar.sellPrice = @bar.closeHighBand
    else if pool.yinfish.downCrossedHigh()
      @bar.sellPrice = @bar.ta
    else
      @bar.sellPrice = null
    @bar.sellEntry = @bar is pool.sellXBar    
  ###











# 止損,本質是考慮日內以及行情整體波動的標準差,反向波動幅度超出常規則退出
# 委託價應該往不利的方向設置,從而在現價位就有可能滿足條件
# 防守比進攻重要.防守必須牢不可破.多重防守為:止盈,成本,折本,砍倉.
# 尤其折本區必須確保清倉,不擴大虧損.砍倉則是對於極端行情預留的逃生設計.

# TODO 
# 設計價格階梯的梯度,將梯度放大到多數交易日內幅度達不到的梯度即可.

# 此法中的 pool, 是指證券,其中亦有 secPosition, 與 EDPool 接口一致,故保留此命名
class Guardian extends Tracer
  @longReOpenSigClass: IBLongReOpen
  @longSKCloseSigClass: IBLongSKClose

  constructor:(@secCode,@timescale,@contract)->
    super(@secCode,@timescale,@contract) # 已定義:
    @messageSymbol = '保本信號'
    @skTimes = 0
    @reOpen = null

    #@liveSignals = {}
  # --------------------------- Guardian constructor end  ------------------------------

  # TODO:
  #  [@guardian?.bases, @guardian?.customs, @guardian?.facts] = [@bases, @customs, @facts]

  # Guardian
  detect:(pool)->
    # 不可以同時在explorer和Guardian中使用此方法,會造成混亂
    # @collectXIO(pool)
    return

  longEscape:(pool)->
    return
  # Guardian 與 Tracer 差異大
  inspectPosition:(pool)->
    unless @onDuty
      return null

    {secPosition} = pool
    
    # 生成信號
    if @reOpen?
      {operation,contraSignal} = @reOpen
      @[operation](pool,contraSignal)
    else if secPosition.bigShortPosition()
      @shortSKClose?(pool)
    else if secPosition.bigLongPosition()
      @longEscape(pool)
      @longSKClose(pool)
      
    
    # 發佈信號
    (each for key, each of @liveSignals).map (sig) =>
      {signalTag, ariseTime} = sig
      # 暫限當日信號
      if sig.outdated(pool,this)
        assert.log( "(Guardian)deleting outdated #{signalTag},#{ariseTime} ")
        delete(@liveSignals[signalTag])
      else 
        if sig.fire(pool,this)
          @emitSignal(pool,sig)
          sig.emittedTimes++




  # 以下生成多空策略,可使用pool各種屬性,以及@bar(lastBar行情),@previousBar,@earlierBar這三個便利變量



  # Guardian
  longSKCutPrice:(pool)=>
    pool.bar.close * 0.9382
  longSKCloseKeepCostOrderPrice:(pool) =>
    pool.secPosition.成本價 * (1+@facts.報價因子)
  longSKCloseAutoPrice:(pool)=>
    {close,high} = @bar
    if close <= pool.secPosition.截斷價()
      close / (1+@facts.容忍因子)
    else
      Math.max(pool.secPosition.保本價() * (1+@facts.保本因子) * (1+@facts.容忍因子), high / (1+@facts.容忍因子))
  
  # Guardian
  longSKCloseBuoys:(pool,forced)->
    {secPosition} = pool
    return [
      {
        buoyName: "止多賣:成本價"
        orderPrice: @longSKCloseKeepCostOrderPrice(pool)
        cond:(pool,tracer)-> pool.mayCloseLong #and not pool.secPosition.boughtToday()
      }# / (1 + @facts.報價因子)} # 行動價比成本價稍微賺一點,實際成交可能略微虧損,但避免了跟不上行情而大虧
      {
        buoyName:"止多賣:autoPrice"
        orderPrice:@longSKCloseAutoPrice(pool)
        cond:(pool,tracer)-> pool.mayCloseLong
      } # autoPrice 已經考慮了成交縫隙,故無須再調整
      {
        buoyName:"止多賣:保本價", 
        orderPrice: secPosition.保本價()
        cond:(pool,tracer)-> pool.mayCloseLong #and not pool.secPosition.boughtToday()
      }
      {
        buoyName:"止多賣:截斷價", 
        orderPrice:secPosition.截斷價()
        cond:(pool,tracer)-> pool.mayCloseLong # and not pool.secPosition.boughtToday())
      }
      {
        buoyName:"止多賣:止損價", 
        orderPrice:secPosition.止損價(),
        cond:(pool,tracer)-> pool.mayCloseLong #and not pool.secPosition.boughtToday()
      }
    ]

  #Guardian
  longSKClose:(pool,forced=false)->
    @longSKCloseBuoys(pool,forced).map (buoyOpt)=>
      {high,low,close,day} = @bar
 
      #if (low <= buoyOpt.orderPrice) # 實測不好,會提前止盈止損,而破壞止盈止損機制
      #if (@closeInsteadOfLow() <= buoyOpt.orderPrice < high) # 而不是 low < 是要求已經下探到委託價,然後尋求反彈上來再下行到行動價的機會,如此自動追價機制才能正常運作
      if forced or (@closeInsteadOfLow() <= buoyOpt.orderPrice) # 而不是 low < 是要求已經下探到委託價,然後尋求反彈上來再下行到行動價的機會,如此自動追價機制才能正常運作  
        sigOpt = 
          day:day
          plannedPosition:0 / 100
        if buoyOpt.cond(pool,this)
          @prepareSignal(pool,@constructor.longSKCloseSigClass,sigOpt,buoyOpt)
  
  # Guardian
  longReOpenKeepCostPrice:(orderPrice)=>
    orderPrice / (1+@facts.保本因子)
  longReOpenAtCostPrice:(orderPrice)=>
    orderPrice / (1+@facts.報價因子)
  longReOpen: (pool, contraSignal)->
    {buoyName,orderPrice,originVol,signalTag} = contraSignal
    {actionPrice,betterPrice} = contraSignal.buoys[buoyName]#.betterPrice #.actionPrice
    cond = (pool,tracer)-> not pool.explorer.liveSignals.IBLongClose?
    levels = [
      {
        buoyName:"復多:保本價", 
        orderPrice: @longReOpenKeepCostPrice(orderPrice)
        cond:->true
      }
      {
        buoyName:"復多:成本價", 
        orderPrice: @longReOpenAtCostPrice(orderPrice)
        cond:cond
      }
      #{buoyName:"復多:止損價", orderPrice: orderPrice * (1+@facts.保本因子), cond:cond} # @facts.保本因子 > 0; 追高買入,回補多頭倉位
    ]

    levels.map (buoyOpt)=>
      {day, low} = @bar
      if (@closeInsteadOfHigh() >= buoyOpt.orderPrice) # 而不用 < high 是要求已經上衝到委託價,然後尋求回落下來再回昇到行動價的機會,如此自動追價機制才能正常運作
        sigOpt = 
          day:day
          vol:originVol
        if buoyOpt.cond(pool,this)
          @prepareSignal(pool,@constructor.longReOpenSigClass,sigOpt,buoyOpt)
          @reOpen = null 
 
  
  # 保本因子似乎不必調整,而應調整 容忍因子,但此法保留不要刪除,將來可能從其他角度加以調整
  refineSK: =>  
    # 條件可以持續改進; 另可根據 委託價格與行動價格的差價,判斷是否縮減 報價因子
    # 最簡化的條件: 止損超過 3 次, 即開始調整,每出新一次新止損上調百分之一
    # assert.log "[debug] 成本價,保本價,@skTimes:",成本價,保本價,@skTimes

    # 容忍因子,即可容忍日內波動幅度,應該通過日內行情移動平均標準差或其他統計指標來動態估算,再作調整
    # [以下僅為臨時代碼]
    if @skTimes > 3
      if @facts.容忍因子 < @bases.最大容忍因子
        @facts.容忍因子 = Math.min((@facts.容忍因子 * 1 + 5 / 100), @bases.最大容忍因子)
    
    ###
    # 保本因子,應該是根據一段行情幅度特徵來確定,約 > lory 95%分佈數值,再作調整
    # [以下僅為臨時代碼]
    condition = (@facts.保本因子 < (9.10 / 100)) and (@skTimes > 3)
    if condition or IBCode.tooClosePercent(@secCode, 保本價, 成本價, @bases.最小保本因子) # 小於2個報價單位且小於 1 + 2*9.10 / 100
      @facts.保本因子 *= 1 + 5 / 100
      @updateFactorDb(成本價,保本價)
    else if IBCode.tooFarPercent(@secCode, 保本價, 成本價, @bases.最大保本因子) # 大於 n 個報價單位 或大於 1 + n*9.10 / 100
      @facts.保本因子 /= 1 + 5 / 100
      @updateFactorDb(成本價,保本價)
    ###

  # Guardian
  updateFactorDb:(成本價,保本價) =>
    miniSettings =
      保本因子: @facts.保本因子
    assert.log "#{@secCode}:保本因子,保本價,skTimes >>> ",@facts.保本因子, 成本價, 保本價, @skTimes
    @customs.get('factors')
      .merge(miniSettings)
      .value()
  
  # Guardian
  emitSignal:(pool,sig) ->
    {contraOperation,isReOpenSignal,isStopKeepSignal,signalTag} = sig
    for key, exSig of @liveSignals when exSig.emittedTimes >= exSig.timesLimit
      delete(@liveSignals[key])
    if isReOpenSignal
      if signalTag in exSig.removeSignals for key, exSig of pool.explorer.liveSignals
        assert.log "存在平倉指令,重開倉?",signalTag
        @emit(@messageSymbol, sig)
      else
        @emit(@messageSymbol, sig)
    else if isStopKeepSignal
      if @skTimes <= skLimit
        @emit(@messageSymbol, sig)
      @skTimes++
      # 部分指令有對應的回補指令,非皆有,故加問號
      if mayReOpen
        this.reOpen =
          operation:contraOperation
          contraSignal:sig
      #this[contraOperation]?(pool,sig) if mayReOpen  #contraOperation means longReOpen() / shortReOpen()
      @refineSK()

    super(pool,sig)
  
  # guardian
  nextBar:(pool)->
    super(pool)
    @currentBar = pool.currentBar
    # 為了簡化代碼, 以下均需要 earlierBar    
    unless @earlierBar?
      return
    if @currentBar
      @inspectPosition(pool)

  # 注意: 既要減少冗餘操作,又要確保止損操作在特殊情況下可以有效保護資產,因此可能要比 explorer 的操作條件放寬
  # 以下[臨時]先照抄 explorer 的條件
  # guardian
  preSettings:(pool)->
    @isBull = pool.bullish()
    @isBear = not @isBull # pool.bearish()

    @shouldSKCloseLong = @isBear #and @bar.sellEntry
    @shouldSKCloseShort = @isBull #and @bar.buyEntry



class HKIOPTGuardian extends Guardian
  @longReOpenSigClass: IOPTLongReOpen
  @longSKCloseSigClass: IOPTLongSKClose

  constructor:(@secCode,@timescale,@contract)->
    super(@secCode,@timescale,@contract) # 已定義:
    @isHKIOPT = true
  
  # HKIOPTGuardian
  longSKCloseBuoys:(pool,forced)->
    origin = super(pool,forced)
    #origin.map (each)-> each.cond = (pool,tracer)-> not pool.previousBar.buyEntry
    #assert.log "longSKCloseBuoys adjusted each cond"
    return origin.concat [
      {
        buoyName: "止多賣:砍倉價SET"
        orderPrice: @longSKCutPrice(pool)
        cond:(pool,tracer)-> forced and pool.mayCloseLong
      }
      {
        buoyName: "止多賣:新高止盈價"
        orderPrice: pool.levels.level10
        cond:(pool,tracer)-> 
          not pool.previousBar.buyEntry
        genCond:(pool,tracer)-> 
          pool.levels.isNewHigh()
      }
      {
        buoyName: "止多賣:高位止盈價"
        orderPrice: @bar.close
        cond:(pool,tracer)-> 
          not pool.previousBar.buyEntry
        genCond:(pool,tracer)->
          (tracer.previousBarIs('upXBar') and (tracer.previousBar.hkVerticalGrade() < 15) and tracer.bar.hkCurrentVerticalGrade() < 3)
      }
    ]

  # HKIOPTGuardian
  longSKClose:(pool,forced=false)->
    @longSKCloseBuoys(pool,forced).map (buoyOpt)=>
      {high,low,close,day} = @bar
      # @closeInsteadOfLow()而不是low 是要求已經下探到委託價,然後尋求反彈上來再下行到行動價的機會,如此自動追價機制才能正常運作  
      buoyOpt.genCond ?= (pool,tracer)-> 
        (forced or (tracer.closeInsteadOfLow() <= buoyOpt.orderPrice)) and buoyOpt.cond(pool,tracer)
      sigOpt = 
        day:day
        plannedPosition: 0 / 100
      @prepareSignal(pool,@constructor.longSKCloseSigClass,sigOpt,buoyOpt)

  # HKIOPTGuardian
  longSKCloseAutoPrice:(pool)=>
    {close} = @bar
    if close < pool.secPosition.止損價() or close < 0.016 < pool.secPosition.成本價 or close < 0.012
      p = Math.max(0.011, close - 2 * @facts.priceGrade) # 少報以便即刻跟蹤
      return p
    else
      Math.max(pool.secPosition.保本價() + @facts.保本差價 + @facts.容忍差價, @bar.high - @facts.容忍差價)
  # HKIOPTGuardian
  longSKCutPrice:(pool)=>
    pool.bar.close - @facts.priceGrade
  longSKCloseKeepCostOrderPrice: (pool) => 
    pool.secPosition.成本價 + @facts.priceGrade
  longReOpenKeepCostPrice:(orderPrice)=>
    orderPrice - @facts.保本差價
  longReOpenAtCostPrice:(orderPrice)=>
    orderPrice - @facts.priceGrade
  
  refineSK: ->  
    return
  
  dayEnd:(pool) -> # 牛熊證絕不過夜,此為最後砍倉賣出. 在此之前應該盡量用其他常規方法出售
    pool.currentBar and moment().hour() is 15 and moment().minute() > 50 

  longEscape:(pool)->
    if @dayEnd(pool)
      @escape(pool)

  # [未完善] 仍需補充 成交之後才關閉窗口否則撤單重新委託直至成交機制
  # 收盤前賣出也適宜改用此法
  escape:(pool)->
    # 清倉逃跑
    # 先確定有倉位,然後立刻賣出
    forced = true
    assert.log "debug: now escape!",forced
    @longSKClose(pool,forced)









class ShortableExplorer extends Explorer





class ForexExplorer extends ShortableExplorer
  constructor:(@secCode,@timescale,@contract) ->
    super(@secCode,@timescale,@contract)
    if true #@timescale is 'day' # 沒有 guardian 就會沒有信號,現在我很疲憊昏沉,尚未找到出錯原因,待明天再說
      @guardian = new ForexGuardian(@secCode, @timescale, @contract)
      [@guardian.bases, @guardian.customs, @guardian.facts] = [@bases, @customs, @facts]
  
  # ForexExplorer
  foundSellX:(pool)->
    @downXBar? and @downXPriceDown(pool)
  downXPriceDown:(pool)->
    @downXBar.high <= @preDownXBar?.high or (@downXBar.ema_price20 < @preDownXBar?.ema_price20) or (@downXBar.isAfter(@upXBar?) and @downXBar.high <= @upXBar?.high)
  foundBuyX:(pool)->
    @upXBar? and (@upXBar.low > @preUpXBar?.low or @upXBar.ema_price20 > @preUpXBar?.ema_price20)
  setIOXPrice: ->
    @sellXPrice = @downXBar?.downXPrice()
    @buyXPrice = @upXBar?.upXPrice()

  # ForexExplorer
  sellXFilter:(pool)->
    @sellXBullFilter(pool) or @sellXBearFilter(pool)
  sellXBullFilter:(pool)->
    @isBull and (@downXBar.highlevel > 7) and @downXBar.high > @downXBar.bbta
  sellXBearFilter:(pool)->
    @isBear and (@downXBar.highlevel > 1) and @downXBar.high > @downXBar.ema_price20
  
  buyXFilter:(pool)->
    @buyXBullFilter(pool) or @buyXBearFilter(pool)
  buyXBullFilter:(pool)->
    @isBull and @upXBar.lowBelowLine(pool.bband20.maName) #('level1') 
  buyXBearFilter:(pool)->
    @isBear and @upXBar.lowBelowLine(pool.bband20.lowHalfBandName) #('level1') 

  ###
  ____NOTUSED__detectBuyEntry:(pool)->
    @bar.buyEntry = @bar is pool.buyXBar
    tracer.buyable()
      buyPrice = @buyXPrice
      if (buyPrice <= pool.bar.level1) or (buyPrice <= pool.bar.closeLowBand)
        @bar.buyPrice = buyPrice
    else if not @____NOTUSED__detectSellEntry(pool)
      if @lastBar?.buyX
        @bar.buyPrice = @lastBar.buyPrice
      else if @previousBar?.buyX
        @bar.buyPrice = @previousBar.buyPrice
    @bar.buyEntry = @bar is pool.buyXBar
    @bar.buyEntry
  
  ____NOTUSED__detectSellEntry:(pool)->
    
      
    @bar.sellEntry = @bar is pool.sellXBar   
    @bar.sellEntry
  ###
    
  ____NOTUSED__detectBuyWithdraw: (pool)->
    if pool.ema20.barDownCrossing() 
      @bar.sellPrice = @bar.ema_price20
    @bar.buyWithdraw = @bar.sellPrice?

  ____NOTUSED__detectSellWithdraw: (pool)->
    @bar.sellWithdraw = false  
  
  # ForexExplorer
  shortFor:(pool)->
    @shortOpen(pool)
    @shortClose(pool)
  
  # 空頭開倉
  # ForexExplorer
  shortOpen:(pool)->
    {容忍因子,報價因子} = @facts
    unless research
      cond = (pool,tracer)-> tracer.sellable() # and pool.strongBear() # and pool.sellFilter()
      arr = pool.scores.estimates()[-5..]
      # 以上方法為舊設計,現臨時湊合,但加穿透位,以後再修改
      xPrice = @sellXPrice 
      arr.push(xPrice)
      levels = ({buoyName: "開空:均速#{i}", orderPrice:fix(p), cond: cond} for p,i in arr when p >= xPrice / (1 + 報價因子))
      levels.map (buoyOpt)=>
        {close,high,low,day} = @bar
        if (@closeInsteadOfLow() <= buoyOpt.orderPrice) # 而不是 low < 是要求已經下探到委託價,然後尋求反彈上來再下行到行動價的機會,如此自動追價機制才能正常運作
          sigOpt = 
            day:day
            plannedPosition:1
          if @bar.sellEntry and buoyOpt.cond(pool,this)
            @prepareSignal(pool,IBShortOpen,sigOpt,buoyOpt) 
          
    else
      levels = [
        {buoyName:"開空:#{pool.timescale}跌破前魚頭", orderPrice:pool.求前魚('yinfishArray').startBar.high}
        {buoyName:"開空:#{pool.timescale}跌破前動魚頭", orderPrice:pool.求前魚('yinfishyArray').startBar.high}
        {buoyName:"開空:#{pool.timescale}跌破tay", orderPrice:@bar.tay}
        {buoyName:"開空:#{pool.timescale}跌破ma_price05", orderPrice:@bar.ma_price05}
      ]
      levels.map (buoyOpt)=>
        @prepareShortOpenSignal(pool,buoyOpt)

  # 空頭平倉
  # ForexExplorer
  shortCloseGetCost: (pool) =>
    if @currentBar then pool.secPosition.成本價 / (1+@facts.保本因子)**2 else @bar.high * 2
  shortClose:(pool)->
    {容忍因子} = @facts
    if pool.mayCloseShort
      unless research
        cond = (pool,tracer)-> tracer.buyable() # 發令條件而非執行條件,任何情況都可平倉(對不對?)
        arr = pool.scores.estimates()[..4]
        # 以上方法為舊設計,現臨時湊合,但加穿透位,以後再修改
        xPrice = @buyXPrice
        arr.push(xPrice)
        levels = ({buoyName:"平空:均速#{i}",orderPrice:fix(p),cond: -> true} for p,i in arr when p <= xPrice * (1 + 容忍因子))
        levels.map (buoyOpt)=>
          {high,low,close,day} = @bar
          if (buoyOpt.orderPrice <= @closeInsteadOfHigh()) # 而不用 < high 是要求已經上衝到委託價,然後尋求回落下來再回昇到行動價的機會,如此自動追價機制才能正常運作    
            sigOpt = 
              day:day
              plannedPosition: 0 / 100
            if @bar.buyEntry and cond(pool,this)
              @prepareSignal(pool,IBShortClose,sigOpt,buoyOpt)
          
      else
        levels = [
          #{buoyName:"平空:#{pool.timescale}上穿前魚頭", orderPrice:pool.求前魚('yinfishArray').startBar.low}
          #{buoyName:"平空:#{pool.timescale}上穿前動魚頭", orderPrice:pool.求前魚('yinfishyArray').startBar.low}
          #{buoyName:"平空:#{pool.timescale}上穿bay", orderPrice:@bar.bay}
          #{buoyName:"平空:#{pool.timescale}上穿ma_price10", orderPrice:@bar.ma_price10}
        ]

        levels.map (buoyOpt)=>
          @prepareShortCloseSignal(pool,buoyOpt)




class ShortableGuardian extends Guardian

class ForexGuardian extends ShortableGuardian
  # ForexGuardian
  shortSKCloseKeepCostPrice:(pool)=> pool.secPosition.成本價 / (1+@facts.報價因子)
  shortSKCloseAutoPrice:(pool)=>
    Math.min(pool.secPosition.保本價() / (1+@facts.保本因子) / (1+@facts.容忍因子), @bar.low * (1+@facts.容忍因子))
  shortSKClose:(pool)->
    {secPosition:{成本價},secPosition} = pool
    autoPrice = @shortSKCloseAutoPrice(pool)
    levels = [
      {
        buoyName:"止空買:成本價", 
        orderPrice: @shortSKCloseKeepCostPrice(pool)
        cond:(pool,tracer)-> pool.mayCloseShort
      }# * (1 + @facts.報價因子)} # 行動價比成本價稍微賺一點,實際成交可能略微虧損,但避免了跟不上行情而大虧
      {
        buoyName:"止空買:autoPrice", 
        orderPrice:autoPrice,
        cond:(pool,tracer)-> pool.mayCloseShort
      } # autoPrice 已經考慮了成交縫隙,故無須再調整
      {
        buoyName:"止空買:保本價"
        orderPrice: secPosition.保本價()
        cond:(pool,tracer)-> pool.mayCloseShort
      }
      {
        buoyName:"止空買:截斷價"
        orderPrice: secPosition.截斷價()
        cond:(pool,tracer)-> pool.mayCloseShort
      }
      {
        buoyName:"止空買:止損價", 
        orderPrice:secPosition.止損價(),
        cond:(pool,tracer)-> pool.mayCloseShort #and not pool.secPosition.soldToday() 
      }
    ]


    levels.map (buoyOpt)=>
      {high,low,close,day} = @bar
      #if (low < buoyOpt.orderPrice < high) # 實測不好,會提前止盈止損,而破壞止盈止損機制
      #if (low < buoyOpt.orderPrice <= @closeInsteadOfHigh()) # 而不用 < high 是要求已經上衝到委託價,然後尋求回落下來再回昇到行動價的機會,如此自動追價機制才能正常運作
      if (@closeInsteadOfHigh() >= buoyOpt.orderPrice) # 而不用 < high 是要求已經上衝到委託價,然後尋求回落下來再回昇到行動價的機會,如此自動追價機制才能正常運作
        sigOpt = 
          day:day
          plannedPosition:0 / 100        
        if buoyOpt.cond(pool,this)
          @prepareSignal(pool,IBShortSKClose,sigOpt,buoyOpt) 

  # ForexGuardian
  shortReOpenKeepCostPrice:(orderPrice)=>
    fix(orderPrice * (1+@facts.保本因子))
  shortReOpenAtCostPrice:(orderPrice)=>
    fix(orderPrice * (1+@facts.報價因子))
  
  shortReOpen:(pool,contraSignal)->
    {buoyName,orderPrice,originVol,signalTag} = contraSignal
    {actionPrice,betterPrice} = contraSignal.buoys[buoyName]#.betterPrice #.actionPrice
    cond = (pool,tracer)-> not pool.explorer.liveSignals.IBShortClose?
    levels = [
      {
        buoyName:"復空:保本價", 
        orderPrice:@shortReOpenKeepCostPrice(orderPrice)
        cond:->true
      }
      {
        buoyName:"復空:成本價", 
        orderPrice:@shortReOpenAtCostPrice(orderPrice)
        cond:cond
      }#{buoyName:"復空:止損價",orderPrice: actionPrice / (1+@facts.保本因子),cond:cond} #(1+@facts.保本因子) > 1,殺跌賣空回補空頭倉位
    ]

    levels.map (buoyOpt) =>
      {day,high} = @bar
      #if (@closeInsteadOfLow() <= buoyOpt.orderPrice < high) # 而不是 low < 是要求已經下探到委託價,然後尋求反彈上來再下行到行動價的機會,如此自動追價機制才能正常運作
      if (@closeInsteadOfLow() <= buoyOpt.orderPrice) # 而不是 low < 是要求已經下探到委託價,然後尋求反彈上來再下行到行動價的機會,如此自動追價機制才能正常運作
        sigOpt = 
          day:day
          vol:originVol
        if buoyOpt.cond(pool,this)
          @prepareSignal(pool,IBShortReOpen,sigOpt,buoyOpt)
          @reOpen = null

  




module.exports = {Explorer,Guardian}


















### Tracer
###

### 設計改進
  本法將嘗試不考慮速度/內存等限制,而採用最佳的設計邏輯.
  即,自帶barArray(將來整個程序都依據本法改進為同樣設計時,可去掉而直接用pool.barArray),在本法中不記錄應由
  barArray記住的指標.因此動態的barArray的處理就隨之簡化.
###

### [收盤迷霧]
  某法在歷史行情中會出現誤差,原因是@bar.close已經收盤矣
  注意: 盡量採用固定價格作為觸發事件,和設定執行價位,例如ta值等等,避免使用 .close
###

### Explorer

  以下與策略有關的代碼都僅僅是佔位,需要完善.
###

###
瞭望者(哨兵)
  仿照峰谷
  用於任何barArray行情的分析操作
  為了便於使用,以barArray為數據表達方式
  計算
    每根@bar(含當日未定barArray變動過程)之多空低風險倉位(secPosition),
    及觸發建平增減倉位的時機(event)

  由證券決定如何利用這些結果.不同週期barArray(分鐘/日/週/月/年等等)皆可計算故.

如峰谷,本法巧妙之處,完全可以不改動@bar,但又可以應需設置@bar的指定屬性,且僅僅掃描一次.
類似的事務,可以仿照此法編寫.

###

### 設計改進
  本法將嘗試不考慮速度/內存等限制,而採用最佳的設計邏輯.
  即,自帶barArray(將來整個程序都依據本法改進為同樣設計時,可去掉而直接用pool.barArray),在本法中不記錄應由
  barArray記住的指標.因此動態的barArray的處理就隨之簡化.
###

### 瞭望者
  場景:
    輸入: @bar,各項指標已經計算好
    輸出: @bar,增加交易方面的指標,如,多空部位判斷,倉位計劃,交易觸發條件,策略信號
  即時:
    @bar用於存儲剛剛收到并分析計算好的即時barArray,@bar到來時,計算完畢取代之,若此二@bar不同時,則previousBar入 barArray.
    如此則記錄下歷史判斷數據.
  實效:
    如果@bar之時長足夠短,則當作一次單向判斷,因不存在變位可能故.
    但在日線週線月線等情形,barArray記錄下的其實是最後一次判斷,中間可能多次反復.
    據此,最好是以分鐘以下級別的數據作為依據
    由於x分鐘線從網上能取得的數據比較短,需要建設本地數據庫,目前可以採用lowdb來做,除非出現更好
    的庫.
    又,雖然barArray只能是一根,但中間過程可以通過指令組來記錄,只要是不可逆過程,均可記錄,因後不改前
    故.

  進益:
    既然上穿下破某價位是通用條件,即可設置一組價格線,從優到劣排序,一次嘗試即可:
      [prices.....].map(通用踩點function)
    而這一組價格可以來自seyy各種指標,也可以是歷史價位分佈中有意義其他的部分,只需逐個發掘即可
    這一點上,與保盈止損可以異中見同,一以貫之.
    投資的秘密不過如此而已.
  多空:
    那麼還需要辨別多空做什麼?只需價格線高拋低吸,有差價即可.
    小利確實如此,但撿了芝麻丟了西瓜,因小失大.順勢者大.取最佳品種,順豐楊帆可以乘風破浪.非謂
    扁舟無帆不可以渡河.謂借勢勝過蠻力.
    性空緣起,性空不可妄執,故,緣起不可輕忽.
###

### Guardian 護院家丁 :)
  區別:
    最大區別是,這個是家丁,完全了解賬戶各項操作歷史信息.可以自由應用這些資料.並且僅針對自家.
    Explorer則是公共勘察家,找到機會就廣播,但不掌握任何賬戶和操作歷史資料.僅根據行情決策.
  關鍵:
    止盈止損操作不改變結構,僅僅在日內降低成本(無論空頭或多頭).
    經過止盈止損之後,倉位至少應不減少.原因是當天出現差價才加回.
    所有工具圍繞此一關鍵進行設計,設計思路就清晰明瞭.
  對應:
    本法所用的工具,與 Explorer 對照, 盡量保持一致的api.
    Explorer  Guardian
    barArray(@bar線)  barArray(存positions)
    歷史@bar     歷史positions
    .....
    尚需進一步研究.
    本法應該用到(經過專門定制的) 歷史倉位,歷史指令,普通行情@bar
    在必要時,給不具備@bar要素的 倉位,指令 增加 ohlc, 以便像@bar一樣使用
  場景:
    輸入: @bar,各項指標已經計算好
    輸出: 保本信號
  思路:

    Every buying/selling has a price and we can set a point near that price to stop lose and keep profit.
    So, plan to close secPosition at some point to keep our profit according to trading signalDictionary database.
    That's all.

    依此止盈止損
    並不要求十分精確.
    非常簡單,先不要複雜.機制驗證無誤,再逐步增強功能.
    比如可以根據最有利的開倉價設置autoPrice.例如,查openOrders數據庫,得知本輪次最高的買入價100,可設為101,等等.
    這樣無須複雜的邏輯,僅需根據實際數據設置最樸實的平倉價位即可保盈止損.

###
