assert = require './assert'
BaseDataFlow = require './dataflow_base'
{NewBuoyFlow} = require './buoyflow'
{dev,rush,lowRiskStrike,useOverlock} = require './config'
{fix} = require './fix'
IBSignal = require './tradesignal'
moment = require 'moment-timezone'
OPTOperatorBase = require './optOperator' 


# todo 早期買入賣出

class SwimFlowBase extends BaseDataFlow
  @pick:({contractHelper,fishName,upOrDown})->
    switch upOrDown
      when 'up'
        switch  # 凡 switch 其中 when 之順序皆不可輕易更改
          when contractHelper.contract.isOPT() then new OPTSwimUpFlow({contractHelper,fishName,upOrDown})
          when contractHelper.contract.isIOPT() then new IOPTSwimUpFlow({contractHelper,fishName,upOrDown})
          else new GradualSwimUpFlow({contractHelper,fishName,upOrDown})
      when 'down'
        switch  # 凡 switch 其中 when 之順序皆不可輕易更改
          when contractHelper.contract.isOPT() then new OPTSwimDownFlow({contractHelper,fishName,upOrDown})
          when contractHelper.contract.isIOPT() then new IOPTSwimDownFlow({contractHelper,fishName,upOrDown})
          else new GradualSwimDownFlow({contractHelper,fishName,upOrDown}) 

  

  # SwimFlowBase
  constructor:({@contractHelper,@fishName,upOrDown})->
    super(@contractHelper)
    @_fishArrayName = "#{@fishName}Array"
    @_direction = upOrDown
    {@isUsStock} = @contractHelper
    @messageSymbol = '穿行信號'
    @grade = []
    if false
      @gradeArray = [] # 若需要可以此記錄所有 grade 與 @barArray 一一對應,方便查詢
    # 提示信號類型.與其他變量不同,在沒有 @_stageBar 時已經必須有信號提示,故使用本變量記錄之
    @_initSignalTypeSuggestion = null

    _optOperator = OPTOperatorBase.pickFor(this)
    if _optOperator
      @_optOperator = _optOperator
      @_optsOpened = false
    
    # 以下屬性存在兩種時態,完成時,進行時,以變量記錄的是完成時,進行時則記錄於 @bar
    # 須用 function 來提取綜合兩種時態的狀態
    #成住壞滅
    @_stageBar = null
    @_advanceBar = null
    @_pauseBar = null
    @_retractBar = null
    @_ceaseBar = null
    # cease 並非 end,故仍可重新突破,切記

  
    


  # ------------------------------  constructor end  ------------------------------
  # 主要用於 SPY 期權.
  # 其他證券亦可使用, 但須在 contractHelper 幫助下根據 timescale 和品種屬性設置.
  # 此處臨時設置
  _highGradeRatio: 5
  _extremeGradeRatio: 15


  # SwimFlowBase
  isUpward:->
    false
  isDownward:->
    false

  # SwimFlowBase
  # 此法是在 beforePushPreviousBar 之後緊接著執行的
  _pushPreviousBar:(pool)->
    super(pool)
    @_recordPastValue(pool)
  # SwimFlowBase
  _recordPastValue:(pool)->
    @earlierGrade = @previousGrade
    @previousGrade = @grade
    @gradeArray?.push(@grade)

  ### beforePushPreviousBar 須謹慎使用,因會造成時空狀況複雜難懂易錯.
  # 此法會在 nextBar 之前執行, 執行後, 所在的 comingBar() 會令 @bar = bar, 然後執行 nextBar
  # 大部分情況或可避免使用,而改在 nextBar 中引用 previousBar 的狀態
  # 此處實質代碼已經過審閱,未發現問題. 
  # 檢查日期:(後續檢查應同樣記錄日期)
  #   [20171107] 未發現問題.
  ###
  # SwimFlowBase
  beforePushPreviousBar:(pool)->
    if @_changedCorner(pool)
      @_gradeScore(pool)
    @_stageCheck(pool) # <-- 理論上應該不再需要,但測試結果仍然不對,故代碼仍有缺漏,導致必須再次使用這些function
    if @_barHasStage()
      # 一行代碼將所有的狀態記錄於本法
      @_stageBar = @bar
      @_stageBarChanged(@bar)
    #assert(@bar.chartTrend?,'error beforePushPreviousBar no chart trend mark') #<<< 結果是大量沒有的
    #@_setChartSignalValue(pool) # <-- 經測試本行已經可以刪除而無影響

  _barHasStage: ->
    @_barStageAnyAdvanced() or @bar.stageCeased() or @bar.stagePaused() or @bar.stageRetracted()

  # SwimFlowBase
  # we can do something here
  _stageBarChanged:(bar)->
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      # 再突破仍是突破,不另外命名可能方便後續比較高低等等檢測    
      when @_barStageAnyAdvanced() then @_advanceBar = bar
      when bar.stageCeased() then @_ceaseBar = bar
      when bar.stagePaused() then @_pauseBar = bar
      when bar.stageRetracted() then @_retractBar = bar
      else
        assert.log("[debug] _barStageAnyAdvanced>> ",@_barStageAnyAdvanced(),@bar._stage,@_barHasStage()) 
        throw 'Wrong stage'

    
  # SwimFlowBase
  # 自身亦有高低開收
  firstBar:(pool)->
    {@open, @high, @low, @close} = @bar
    @_lowBar = @_highBar = @bar
    @_gradeScore(pool)
    @_setChartSignalValue(pool)

  # SwimFlowBase
  nextBar:(pool)->
    if @_changedCorner(pool)
      @_gradeScore(pool)
    @_stageCheck(pool)
    @_setChartSignalValue(pool)


  _stageCheck:(pool)->
    switch  # 凡 switch 其中 when 之順序皆不可輕易更改
      when @_break(pool)
        switch  # 凡 switch 其中 when 之順序皆不可輕易更改
          when @stageAdvanced() then null
          when @stageAdvancedAgain() then null # <-曾因此行發現他處bug導致注釋本行才免遺漏行情,現似已糾正,可再嘗試比較
          when @everAdvanced() then @_breakAgainSettings(pool)
          else @_breakSettings(pool)
      # 以下皆須已經突破方有必要設置故此檢測
      when not @everAdvanced() then return null
      when @_paused(pool) 
        switch  # 凡 switch 其中 when 之順序皆不可輕易更改
          when @_retracted(pool) then @_retractedSettings(pool)
          when @_ceased(pool) and not @stageCeased() then @_ceasedSettings(pool)
          else @_pausedSettings(pool)
      #when @stageCeased() then return null 
      #when @_ceased(pool) then @_ceasedSettings(pool)
     
  # SwimFlowBase
  # break 突破是非常稀少的,屬於大段行情的起點,甚至有可能是轉勢的初始起點,故條件苛刻,出現在大段 swim 靠近起始點的地方;
  # 依此可以過濾掉小的 swim, 篩選出最佳的行情段,提供效率,降低風險
  _break:(pool)->
    assert.subJob()

  # SwimFlowBase
  _retracted:(pool)->
    switch  # 凡 switch 其中 when 之順序皆不可輕易更改
      when not @everPausedAferCorner() then false
      when @everRetractedAfterCorner() then false
      when @stageRetracted() then false
      else @_secondPoint(pool)
  
  # SwimFlowBase
  _paused:(pool)->
    assert.subJob()
  # 停歇但仍有可能重新啟動,故不是 end, 切記
  #_ceased:(pool)->
  #  assert.subJob()



  # SwimFlowBase
  _setChartSignalValue:(pool)->
    {signalSwim} = pool
    if (not signalSwim?) or @_isNowSignalSwim(pool)
      # 僅作為提議,可用於繪圖,但勿用以提取當前 signal 類別,實際信號可以迥異
      @bar.chartTrend = @_chartSignal[@signalTypeSuggestion()]
      @bar.chartGradeRatio = @_gradeRatio
      #assert(@bar.chartTrend?,'error no chart trend mark')


  # SwimFlowBase
  _breakSettings:(pool)->
    # signalSwim 非常關鍵,記錄當前起作用的 swim 及其類別故.今後若有改動,先須仔細檢查其作用,慎勿輕易刪除
    @_setAsSignalSwim(pool)
    if not @stageAdvanced()
      # 同一時刻僅有一個主 swim
      # signalSwim 非常關鍵,記錄當前起作用的 swim 及其類別故.今後若有改動,先須仔細檢查其作用,慎勿輕易刪除
      @_setBarAsAdvanced(@bar)

  # SwimFlowBase
  _breakAgainSettings:(pool)->
    # signalSwim 非常關鍵,記錄當前起作用的 swim 及其類別故.今後若有改動,先須仔細檢查其作用,慎勿輕易刪除
    @_setAsSignalSwim(pool)
    if not @stageAnyAdvanced()
      @_setBarAsAdvancedAgain(@bar)

  # SwimFlowBase
  _pausedSettings:(pool)->
    @bar.setStage('_paused')
    @bar.chartPauseMove = "p#{@_direction[0]}"

  # SwimFlowBase
  # 壞,滅之先兆
  _retractedSettings:(pool)->
    @bar.setStage('_retract')
    @bar.chartRetractMove = "R#{@_direction[0].toUpperCase()}"

  # SwimFlowBase
  # 並非end,故仍可重新突破,切記
  _ceasedSettings:(pool) ->
    @bar.setStage('_ceased')
    @bar.chartCeaseMove = "C#{@_direction[0].toUpperCase()}"

  # 慎用此法!
  # 注意,此法取得的僅僅是同名的魚,可能是後出現的,而非原先自己所寄居的魚
  currentSwimOfMyClass:(pool)->
    @_currentFishOfMyClass(pool).swim
  _currentFishOfMyClass:(pool)->
    pool[@fishName]

  # 繪圖用
  _chartSignal:
    longOpen: 1
    shortOpen: -1
    longClose: 0.5
    shortClose: -0.5

  # 以此獲得跨時態的結果.注意可以是null
  advanceBar:->
    if @_barStageAnyAdvanced() then @bar else @_advanceBar
  pauseBar:->
    if @bar.stagePaused() then @bar else @_pauseBar
  retractBar:->
    if @bar.stageRetracted() then @bar else @_retractBar
  ceaseBar:->
    if @bar.stageCeased() then @bar else @_ceaseBar
  
  # SwimFlowBase
  # 以下諸法,檢查有無相應的 bar,確定是否有過某狀態,但不表示目前處在相應狀態
  justAdvanced:->
    if @_barStageAnyAdvanced()
      return true
    avb = @_advanceBar
    avb? and ((@previousBar is avb) or (@earlierBar is avb))
  # SwimFlowBase
  everAdvanced:->
    @advanceBar()?
  everPaused:->
    @pauseBar()?
  everRetracted:->
    @retractBar()?
  everCeased:->
    @ceaseBar()?

  # 轉折之後的才有意義,之前的已經過去了
  everPausedAferCorner:->
    @everPaused() and @pauseBar().momentAfter(@cornerBar(),@timescale)
  everRetractedAfterCorner:->
    @everRetracted() and @retractBar().momentAfter(@cornerBar(),@timescale)
  everCeasedAfterCorner:->
    @everCeased() and @ceaseBar().momentAfter(@cornerBar(),@timescale)


  # 成住壞滅
  
  # SwimFlowBase
  # 以下諸法,檢查當前狀態
  # 此法兼顧久暫;若需知道已經確定的狀態則可用 @_stageBar?.stageAnyAdvanced() 等等
  stageAnyAdvanced:->
    @stageAdvancedAgain() or @stageAdvanced()
  stagePaused:->
    @_stageIs('_paused')
  stageRetracted:->
    @_stageIs('_retract')
  stageCeased:->
    @_stageIs('_ceased')
  _stageIs:(aStage)->
    @_stageBar?.stage is aStage or @bar.stage is aStage


  # SwimFlowBase
  _gradeScore:(pool,geometric=true) ->
    if geometric then @_gradeScoreGeometric(pool) else @_gradeScoreMath(pool)
    @_resetGradeRatio()

  # SwimFlowBase
  # 注意: 指標標號是有意義的! 順序對應指標數值從小到大! 相關代碼用到此特性,不要隨意更改!
  _gradeScoreGeometric:(pool) ->
    g = Math.pow(@high / @low, 1/10)
    for idx in [0..10]
      @grade[idx] = fix(@low * g ** idx)

  # SwimFlowBase
  # 注意: 指標標號是有意義的! 順序對應指標數值從小到大! 相關代碼用到此特性,不要隨意更改!
  _gradeScoreMath:(pool) ->
    for idx in [0..10]
      @grade[idx] = fix((idx*@high + (10-idx)*@low) / 10)


      
  
  _resetGradeRatio: ->
    gradeRatio = fix(100*@grade[10]/@grade[0] - 100)
    @maxGradeRatio ?= gradeRatio
    if @_gradeRatio < gradeRatio
      @maxGradeRatio = gradeRatio
    @_gradeRatio = gradeRatio

  # SwimFlowBase
  gradeRatio:->
    @_gradeRatio 



  # SwimFlowBase
  ###
  注意: 僅限 swim class 內使用,用於識別行情中繼停歇後小突破,以便篩選出大行情起始之大突破 
  ###
  _recurringBreak:(pool)->
    @bar.closeVari > pool.bband.varianceLowLevel





class SignalSwimFlow extends SwimFlowBase

  # SignalSwimFlow
  _isNowSignalSwim:(pool)->
    {signalSwim} = pool
    # !!! 此時可能是由於 fish 跳轉而剛生成的新一段, 故不可以用 if @everAdvanced() 替代以下 if
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      # 就是
      when this is pool.signalSwim then true
      # 同類,待同步
      when signalSwim? and signalSwim.constructor.name is @constructor.name
        @_setAsSignalSwim(pool)
        true
      # 是,但不知為何未能及時設置,現設置
      when @stageAnyAdvanced()
        @_setAsSignalSwim(pool)
        true
      # 不是
      else false

  # SignalSwimFlow
  _setAsSignalSwim:(pool)->
    pool.setSignalSwim(this)

  # SignalSwimFlow
  _setSignalTypeAs:(signalType)->
    # 僅作為提議,可用於繪圖,但勿用以提取當前 signal 類別,實際信號可以迥異
    
    臨時 = true
    # 本想將狀態盡量放進 bar 以便令自身自由,但初步測試有問題,暫時先過渡一下,有空再研究能否將此狀態也放入 bar
    if 臨時 
      @_signalTypeSuggestion = signalType

    # 可能設置完之後,進行中的 @bar 變了,信號就丟失了,於是跟 @_signalTypeSuggestion 不一樣了
    @bar.setSignalTypeSuggestion(signalType)
    # 本法與其他變量不同,在沒有 @_stageBar 時已經必須有信號提示,故使用本變量記錄之
    @_initSignalTypeSuggestion ?= signalType
    # 在 pick 過程中處理各種複雜情形,例如強制平倉並關閉窗口等等
    @signal = IBSignal.pick(this)
  
  # SignalSwimFlow
  # 僅作為提議,可用於繪圖,但勿用以提取當前 signal 類別,實際信號可以迥異
  signalTypeSuggestion:->
    臨時 = true
    if 臨時
      if @_barHasStage() and not @bar.stagePaused() then assert(@bar.signalTypeSuggestion()?, "#{@bar.day}#{@bar._stage}#{@bar._signalTypeSuggestion} has no signal suggestion")
      if @_stageBar? and not @_stageBar.stagePaused() then assert(@_stageBar.signalTypeSuggestion()?, 'stage bar has no signal suggestion')
      @_signalTypeSuggestion
    else
      # [TODO] 經測試以下代碼無法等價替換 @_signalTypeSuggestion 原因未知,待有空繼續研究,先採用 @_signalTypeSuggestion
      @bar.signalTypeSuggestion() ? @_stageBar?.signalTypeSuggestion() ? @_initSignalTypeSuggestion

  ### 
  這是住在pool.crosses 中的 cordonBuoys 中的某個buoy通過 pool.signalSwim 轉發至此的消息
  
  轉一圈發過來的原因:
    1. buoy和signal非一一對應關係,buoy有可能在signal中,
    2. buoy再記憶此signal,會造成circular關係,js處理不好;
    3. 又,buoy可能先後出現在不同的signal中,故buoy不方便記憶所在的signal
    4. 但是為何 signal 要記憶buoys? 有必要嗎? 可以從 pool 中查找,但不方便,故記憶當時的 buoys 備查

  要點:
    1. 此時已知此 bar 已經觸發進出操作入口 (已經在 buoyflow 中 _recordHistChartEntry 存入 bar 用於後續繪圖研究)
    2. 此 buoy 此時未必有合適之 signal, 故可能被拒絕
  ###
  # SignalSwimFlow
  entryBuoy:(pool,buoy,msg)->
    assert.log("[debug]entryBuoy >> #{@signal?.constructor.name} entry: a buoy", buoy.buoyName)
    @signal?.readyToEmit(buoy,msg,(signal,order)=>
      if signal?
        # 不能用 @emit 自行 emit, 原因是此法變動不居, 在 wbv_pool 中無法定位
        pool.emit(@messageSymbol,{signal,order})
        @_postEmitSignal(pool,buoy,{signal,order})
      else
        assert.log("[debug]entryBuoy >> #{@signal?.constructor.name} rejected a buoy", buoy.buoyName)
    )
    
  # SignalSwimFlow
  recordHistChartSig: (pool,buoy)->
    {buoySwim:{latestCrossBar},actionType} = buoy
    # 限制只記錄一次
    if @signal?.justified(buoy) and (actionType isnt @_recordedActionType)
      @_recordedActionType = actionType
      @_recordChartSig(pool,buoy,true)

  # SignalSwimFlow
  # 此法必須用兩次, 其中一次是歷史行情之偽信號, 用於繪圖研究
  _recordChartSig: (pool,buoy,fake)->
    x= if fake then pool.bar.day else @signal.emitTime # or emitTimestamp? 為可讀日期
    title = if @isUpward() then '多' else '空'
    text = "#{if fake then buoy.buoyName else @signal.orderPrice}@#{@signal.signalTag}"
    buoy.helpRecordChartSig({x,title,text})

  # SignalSwimFlow
  _postEmitSignal:(pool,buoy,{signal,order}) ->
    {buoyName,signalTag,buoyStamp} = signal
    @_recordChartSig(pool,buoy)
    # 用 buoy.sentBuoyEntry(), 其中 sentObj 製作一個copy, 見 todo.md
    @contractHelper.sentBuoy(buoyStamp, buoy.sentBuoyEntry())
    msg = "[_postEmitSignal]#{@contractHelper.secCode}: #{@constructor.name} #{buoyStamp} #{@messageSymbol}"
    assert.log(msg)
    # 歷史信號目前僅作研究開發之用,不影響交易.發行版可注釋此行
    @_addHistory(pool)
  
  # SignalSwimFlow
  #有必要嗎?
  _addHistory:(pool)->
    unless dev
      return
    @tempSameDaySignals ?= {} # for research only
    {orderClassName,buoyName} = @signal
    similar = @tempSameDaySignals[orderClassName]
    if similar? and moment(similar.buoys[similar.buoyName].day).isSame(@signal.buoys[buoyName].day,@timescale)
      similar.privateCombine(@signal)
    else if @signal.isValidHistoricTime()
      @tempSameDaySignals[orderClassName] = @signal
    
    if @isCurrentBar()
      # 不能用 @emit 自行 emit, 原因是此法變動不居, 在 wbv_pool 中無法定位
      pool.emit('liveSignalEmerged',@signal.historyRec())
    return

  # SignalSwimFlow
  # 或許需根據當前價位訂製,先按照最差情形設置,因 buoy 擇優更新故
  _setFakeCordonGradeIndex:->
    if @_fakeCordonGradeIndex then return
    @_fakeCordonGradeIndex = @_gradeBorderIndice(@bar.close, @_fakeIndex)
    @cordonGradeIndex = @_fakeCordonGradeIndex    
    assert.log("[debug]_setFakeCordonGradeIndex",@fishName,@cordonGradeIndex)

  # SignalSwimFlow
  _gradeBorderIndice:(price,n)->
    len = @grade.length - 1
    assert(len > 1, "#{@secCode} no grade in #{@buoyNamePrefix}")
    if @grade[0] is @grade[len]
      assert(@bar.high is @bar.low,"[bug?]#{@fishName} @grade border is: #{@grade[0]},#{@grade[len]}, @bar: #{@bar.high},#{@bar.low} ")
      return if n is 0 then 0 else len 
    @grade.indexOf(@_gradeBorder(price,@gade)[n])

  # SignalSwimFlow
  # recursively
  _gradeBorder:(price,g=@grade)->
    min = g[0]
    max = g[g.length - 1]
    #unless min < max
    #  throw "must be in a <= b order"
    assert(min < max, "must be in a <= b order")
    unless min <= price <= max
      throw "#{price} out of #{g}"
    ng = g
    lower = g[1]
    if price >= lower then ng = ng[1..]
    upper = ng[ng.length - 2]
    if price <= upper then ng = ng[..-2]
    if ng.length is 2
      return ng
    else 
      return @_gradeBorder(price,ng)


  # SignalSwimFlow
  whyNoSignal:->
    aBug = @signal?
    if @isDownward()
      unless @contractHelper.isShortable()
        aBug = false
    assert.log('sometimes there should not be a signal, and is this one a bug? ', aBug)

  _onFitSignalCross:(pool)->
    @latestCrossBar = @bar
    # 不能移走
    @_setBuoy(pool)






class CordonicSwimFlow extends SignalSwimFlow
  _currentOnDuty:(pool)->
    pool.onDuty and @isCurrentBar()

  # 此時沒有 @previousBar
  firstBar:(pool)->
    super(pool)
    if @_currentOnDuty(pool)
      @_detectCrosses()
      @_reviewBuoySettings(pool)

  # 此時必有 @previousBar
  nextBar:(pool)->
    super(pool)
    # 無論是否合乎當前 signal 都要預作檢測,以便及時切換
    if @_currentOnDuty(pool)
      @_detectCrosses()
      @_reviewBuoySettings(pool)

  # beforePushPreviousBar 須謹慎使用,因會造成時空狀況複雜難懂易錯.
  beforePushPreviousBar:(pool)->
    super(pool)
    if @_currentOnDuty(pool)
      @_reviewBuoySettings(pool)
  
  _reviewBuoySettings:(pool)->
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      when not @_currentOnDuty(pool) then return
      when @_fitSignal(pool) then @_setGradeBuoyOnFitSignal(pool)
      when @_isNowBuoySwimClass(pool) then pool.setGradeBuoy(null)
        

  # 天地線憑空內斂反跳回來(正常是向創新低新高方向外擴跳開,反跳收回則可由fishy定義而致)
  _jumpingBack:(pool)->
    @size is 0 and @retrograded

  # 一個 swim cordonGradeIndex 對應一個 buoy, buoy 生於穿透故
  # 用於類型轉換以及價格線替換,其中價格線替換是否需要,有待觀察
  _setBuoy:(pool)->
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      when not @_isNowBuoySwimClass(pool) 
        @_setAsBuoySwim(pool)
      when @_inBetterGrade(pool)
        assert.log(@buoyNamePrefix,"debug _inBetterGrade",@cordonGradeIndex)
        @_setAsBuoySwim(pool)
  # 僅用於反跳情形
  _resetBuoy:(pool)->
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      when not @_isNowBuoySwim(pool) 
        @_setAsBuoySwim(pool)
      #when @cordonGradeIndex isnt pool.gradeBuoy?.cordonGradeIndex
      #  @_setAsBuoySwim(pool)

  # SwimFlowBase
  # 以此限制 buoy 跟蹤過程
  _isNowBuoySwimClass:(pool)->
    @constructor.name is pool.buoySwim?.constructor.name
  _isNowBuoySwim:(pool)->
    this is pool.buoySwim

  # SwimFlowBase
  # 在本 swim 非 signalSwim 且經既成 bar 確認出現穿刺的情形之下,會使用本法,更新設置
  _setAsBuoySwim:(pool)->
    assert(@cordonGradeIndex >=0 , "#{@constructor.name} #{@startBar.day} has no cordonGradeIndex")
    pool.setGradeBuoy(NewBuoyFlow.pick(this))





# 逆對應於 SellBuoy, fits sell signals
class SwimUpFlowBase extends CordonicSwimFlow
  _barStageAnyAdvanced: ->
    @bar.stageAnyOpenLong()
  stageAdvanced:->
    @_stageIs('_openLong')
  stageAdvancedAgain:->
    @_stageIs('_openLongAgain')

  # SwimUpFlowBase
  _fakeIndex: if rush then 1 else 0

  # SwimUpFlowBase
  isUpward:->
    true
  cornerBar:->
    @_highBar
  _changedCorner:(pool)->
    return @_changedHighBar(pool)

  # SwimUpFlowBase
  # 不等下次更新機會直接重設(此時@contractHelper已經完成設置)
  forceClosePosition:->
    @_setSignalTypeAs('longClose')

  # SwimUpFlowBase
  firstBar:(pool)->
    if @bar.closeBelowLine(pool.bband.maName)
      @_setSignalTypeAs('longClose')
    else 
      @_setSignalTypeAs('longOpen')
    super(pool)



  # SwimUpFlowBase
  _break:(pool)->
    @_breakup(pool)

  # SwimUpFlowBase
  _breakSettings:(pool)->
    @_setSignalTypeAs('longOpen')
    super(pool)
    
  # SwimUpFlowBase
  _breakAgainSettings:(pool)->
    @_setSignalTypeAs('longOpen')
    super(pool)


  # SwimUpFlowBase
  # 僅能使用 bar 數據判斷,而若不想增加太多數據,以下方法是目前能想到的,雖然會有少數例外(恰好相等,並非新高)
  _breakup:(pool)->
    {bband,yinfish,yinfishx,yinfishy} = pool
    pb = pool.barBefore(@bar)
    switch  # 凡 switch 其中 when 之順序皆不可輕易更改
      when @bar.yin() then false
      when @bar.closeBelowLine(bband.maName) and @bar.closeBelowLine(bband.yinfishx.tbaName) then false
      when @_pureBear(pool) then false
      when @bar.highIs(yinfish.tbaName) then true
      when @bar.highIs(yinfishy.tbaName)
        switch  # 凡 switch 其中 when 之順序皆不可輕易更改
          when not @bar.indicatorRise(yinfishy.tbaName,pb) then false
          when @bar.indicatorRise(bband.maName,pb) then @bar.closeUponLine(bband.maName)
          when @bar.closeBelowLine(yinfish.tbaName) then true
          when pb?.closeUponLine(yinfish.tbaName) then true
          when @bar.close > @bar[bband.highHalfBandName] > pb?[bband.highHalfBandName] then true
          #when @_rsiUp(pool) then true 
          else false
      #when @_rsiUp(pool) then false
      # 以下均需 rsi 上漲為條件
      #when @bar.floatedUponLine(pool.yinfishx.tbaName) then true
      #when @bar.closeUpCross(pool.bband.maName,pool.barBefore(@bar)) then true
      #when @bar.closeUpCross(pool.bband.highHalfBandName,pool.barBefore(@bar)) then true
      #when @bar.closeUpCross(pool.bband.lowHalfBandName,pool.barBefore(@bar)) then true
      else false
  
  # SwimUpFlowBase
  _pureBear:(pool)->
    {bband,yinfish,yinfishx,yinfishy} = pool
    pb = pool.barBefore(@bar)
    if @bar.indicatorRise(bband.maName,pb) and @bar.closeUponLine(bband.maName)
      return false
    @bar[yinfishy.tbaName] < @bar[yinfishx.tbaName] < @bar[yinfish.tbaName] < @bar[bband.yinfishx.tbaName]
  
  # SwimUpFlowBase
  _rsiUp:(pool)->
    unless pool.barBefore(@bar)?
      return true
    (67 > @bar.rsi >= pool.barBefore(@bar)?.rsi)

  

  # SwimUpFlowBase
  _setBarAsAdvanced:(aBar)->
    @bar.setStage('_openLong')
    aBar.chartBreakUp = true
  # SwimUpFlowBase
  _setBarAsAdvancedAgain:(aBar)->
    @bar.setStage('_openLongAgain')
    aBar.chartUpAgain = true

  # SwimUpFlowBase
  _retractedSettings:(pool)->
    super(pool)
    @_setSignalTypeAs('longClose')

  # SwimUpFlowBase
  _ceasedSettings:(pool) ->
    super(pool)
    @_setSignalTypeAs('longClose')
    @_optOperator?.emitForcedOPTCloseMessage(pool,@bar)


  # SwimUpFlowBase
  # 這不是一個 function; 是一個變量而已
  _ceasedGrade: {
    month: 9
    week: 9
    day: 8
    DAY: 8
    hour: 6
  }

  # SwimUpFlowBase
  # 次日不拉回收盤則壞
  _secondPoint:(pool)->
    switch  # 凡 switch 其中 when 之順序皆不可輕易更改
      when @_pauseBar is @previousBar
        @bar.close < @_pauseBar.close
      else 
        @_pauseBar?.momentBefore(@previousBar,@timescale)

  # SwimUpFlowBase
  _ceased:(pool)->
    {yinfishy,bband,bband:{highHalfBandName}} = pool
    switch  # 凡 switch 其中 when 之順序皆不可輕易更改
      when @stageCeased() then false
      when @everCeasedAfterCorner() then false

      # gradeRatio 登極(小於前yinfish)而價格橫走
      when @_stopAfterBigWave(pool) then true #<<< 位置可能需要調整,是否亦須先 paused?

      when (@bar.low < @_advanceBar?.low) then true
      when @bar.low < @startBar.low then true      
      when not @everPausedAferCorner() then false
      when @bar.yang() and @bar.highIs(yinfishy.tbaName) then false
      when @bar.indicatorDrop(bband.yinfishx.tbaName, pool.barBefore(@bar)) then true
      when not @bar.equal(highHalfBandName, bband.yinfishx.tbaName) then true
      else false


  # SwimUpFlowBase
  _paused:(pool)->
    if true
      @bar.closeBelowLine(pool.bband.maName)
    else 
      @bar.closeBelowLine(pool.bband.highHalfBandName)

  # SwimUpFlowBase
  # 止盈技術
  _stopAfterBigWave:(pool)->
    {bband,bband:{highHalfBandName,maName}} = pool
    pb = pool.barBefore(@bar)
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      # 思路: 1. 幅度大 2. 回調先兆出現: a. 股價停滯 b. 峰值遞減
      when @_gradeRatio < @_highGradeRatio then false
      when @maxGradeRatio isnt @_gradeRatio then false 
      #when @bar.closeBelowLine(highHalfBandName) then false
      when @bar.closeBelowLine(maName) then false
      when not (@bar.equal(highHalfBandName, bband.yinfishx.tbaName) ) then false
      when not @bar.indicatorRise('high',pb) then true
      when pool.formerObject(@_fishArrayName)?.swim.maxGradeRatio > @maxGradeRatio > @_highGradeRatio then true
      when @bar.yin() and (@_gradeRatio > @_extremeGradeRatio) then true
      else false


  # --------------------------- cordonic -------------------------------
  # 相反相成
  # SwimUpFlowBase
  _fitSignal:(pool)->
    pool.signalSwim?.signal?.isSellSignal

  # SwimUpFlowBase
  # 無意義,純用於 SellBuoy 命名
  buoyNamePrefix: 'xDown'

  # SwimUpFlowBase
  # 此時不確定,故僅存信息於變動之 @bar
  _detectCrosses:->
    # 必須按邏輯順序檢測,即下跌是從高到低,以便後續處理  bar.baseDownXIndex
    for x in [10..0] when @_closeDownCrossGrade(x)
      @bar.recordDownXGrade(x)
    if @bar.baseDownXIndex  
      @cordonGradeIndex = @bar.baseDownXIndex

  # SwimUpFlowBase
  _closeDownCrossGrade:(anIndex)->
    if not @previousBar?
      return false

    {high, low, close} = @previousBar
    line = @previousGrade?[anIndex]
    #{high,low,close,line} = fixAll({high,low,close,line})
    switch  # 凡 switch 其中 when 之順序皆不可輕易更改
      #dn1
      when @bar.close < line <= close then true
      when @bar.close < line < @bar.high then true
      #dn2
      #when (high > line >= close) and (@close < line) then true
      #dn3
      # 昨日上穿前日之線,而不高於自身之線,且以上代碼均檢測不到下穿:
      #when @bar.yin() and (close > @earlierGrade?[anIndex]) and (close <= line) and (@close < line) then true
      else false

  # SwimUpFlowBase
  # 天地線憑空內斂反跳回來(正常是向創新低新高方向外擴跳開,反跳收回則可由fishy定義而致)
  _onFitSignalJumpBack:(pool)->
    if @bar.low > pool.barBefore(@bar)?.low
      # 此時尚未檢測到穿透,模擬一個假穿刺
      @latestCrossBar = @bar  
      @_setFakeCordonGradeIndex() 
      # 不能移走
      @_resetBuoy(pool)

  # SwimUpFlowBase
  # 應放在 beforePushPreviousBar 內以便檢測既成事實.
  _setGradeBuoyOnFitSignal:(pool)->
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      when @bar.baseDownXIndex then @_onFitSignalCross(pool)
      when @_jumpingBack(pool) then @_onFitSignalJumpBack(pool)
      when not @_isNowBuoySwimClass(pool)
        # 此時尚未檢測到穿透,模擬一個假穿刺
        @_setFakeCordonGradeIndex() 
        @_onFitSignalCross(pool)
      
  
  # SwimUpFlowBase
  _inBetterGrade:(pool)->
    {gradeBuoy,gradeBuoy:{buoySwim,cordonGradeIndex}} = pool
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      when not gradeBuoy? then false 
      when @cordonGradeIndex <= cordonGradeIndex then false
      when @grade[@cordonGradeIndex] <= buoySwim.grade[cordonGradeIndex] then false
      else true




# 逆對應於 BuyBuoy, fits buy signals
class SwimDownFlowBase extends CordonicSwimFlow
  _barStageAnyAdvanced:->
    @bar.stageAnyOpenShort()
  stageAdvanced:->
    @_stageIs('_openShort')
  stageAdvancedAgain:->
    @_stageIs('_openShortAgain')

  # SwimDownFlowBase
  _fakeIndex: if rush then 0 else 1

  # SwimDownFlowBase
  isDownward:->
    true

  cornerBar:->
    @_lowBar
  _changedCorner:(pool)->
    return @_changedLowBar(pool)

  # SwimDownFlowBase
  # 不等下次更新機會直接重設(此時@contractHelper已經完成設置)
  forceClosePosition:->
    @_setSignalTypeAs('shortClose')

  # SwimDownFlowBase
  firstBar:(pool)->
    # 無論是否可空品種,都一樣
    if @bar.closeUponLine(pool.bband.maName)
      @_setSignalTypeAs('shortClose')
    else
      @_setSignalTypeAs('shortOpen')
    super(pool)


  # SwimDownFlowBase
  _break:(pool)->
    @_breakdown(pool)

  # SwimDownFlowBase
  _breakSettings:(pool)->
    @_setSignalTypeAs('shortOpen')
    super(pool)

  # SwimDownFlowBase
  _breakAgainSettings:(pool)->
    @_setSignalTypeAs('shortOpen')
    super(pool)

  # SwimDownFlowBase
  _breakdown:(pool)->
    {bband,bband:{highHalfBandName},yangfishx,yangfishy,yangfish} = pool
    # 凡 switch 其中 when 之順序皆不可輕易更改
    switch  # 凡 switch 其中 when 之順序皆不可輕易更改
      when @bar.yang() then false
      when @bar.closeUponLine(bband.lowHalfBandName) then false
      when @bar.indicatorRise(bband.maName,pool.barBefore(@bar)) then false
      when @bar.equal(highHalfBandName,bband.yinfishx.tbaName) then false
      # 不用retrograded, 否則會遺漏突破點
      #when yangfishx.retrograded then false
      #when yangfishy.retrograded then false
      when @bar.lowIs(yangfishx.tbaName) then true
      when @bar.lowIs(yangfishy.tbaName) then true
      when @bar.lowIs(yangfish.tbaName) then true 
      when @bar.settledBelowLine(yangfishx.tbaName) then true
      when @bar.settledBelowLine(yangfishy.tbaName) then true
      else false



  # SwimDownFlowBase
  _setBarAsAdvanced:(aBar)->
    @bar.setStage('_openShort')
    aBar.chartBreakDown = true
  # SwimDownFlowBase
  _setBarAsAdvancedAgain:(aBar)->
    @bar.setStage('_openShortAgain')
    aBar.chartDownAgain = true

  
  # SwimDownFlowBase
  _retractedSettings:(pool)->
    super(pool)
    @_setSignalTypeAs('shortClose')
    
  # SwimDownFlowBase
  _ceasedSettings:(pool)->
    super(pool)
    @_setSignalTypeAs('shortClose')
    @_optOperator?.emitForcedOPTCloseMessage(pool,@bar)
    # 已放到 @_optOperations
    #buoySwim = pool.getCurrentBuoySwim()
    #buoySwim?.shortCloseSuggestedCallOpen?(pool)

  # SwimDownFlowBase
  _secondPoint:(pool)->
    # 凡 switch 其中 when 之順序皆不可輕易更改  
    switch  # 凡 switch 其中 when 之順序皆不可輕易更改
      when @_pauseBar is @previousBar
        @bar.close > @_pauseBar.close
      else 
        @_pauseBar?.momentBefore(@previousBar,@timescale)

  # SwimDownFlowBase
  _ceased:(pool)->
    x = 5
    {bband,yangfishy} = pool
    switch  # 凡 switch 其中 when 之順序皆不可輕易更改
      when @stageCeased() then false
      when @everCeasedAfterCorner() then false
      
      when @_stopAfterBigWave(pool) then true #<<< 位置可能需要調整,是否亦須先 paused?

      when @bar.high > @_advanceBar?.high then true
      when @bar.high > @startBar.high then true
      when not @everPausedAferCorner() then false
      when @bar.yin() and @bar.lowIs(yangfishy.tbaName) then false
      when @bar.indicatorRise(bband.lowHalfBandName, pool.barBefore(@bar)) then true
      when @bar.floatedUponLine(bband.maName) then true
      #when (@size > x and @bar.close > @grade[4]) then true 
      else false

  # SwimDownFlowBase
  _paused:(pool)->
    if true
      @bar.closeUponLine(pool.bband.maName)
    else 
      @bar.closeUponLine(pool.bband.lowHalfBandName)


  # SwimDownFlowBase
  # 止盈技術
  _stopAfterBigWave:(pool)->
    {bband,bband:{lowHalfBandName}} = pool
    pb = pool.barBefore(@bar)
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      # 思路: 1. 幅度大 2. 回調先兆出現: a. 股價停滯 b. 峰值遞減
      # [bug] 似乎沒有起作用,待 debug
      when (@_gradeRatio < @_highGradeRatio) or (@maxGradeRatio isnt @_gradeRatio) then false 
      when not (@bar.indicatorDrop(lowHalfBandName, pb) or @bar.closeBelowLine(lowHalfBandName)) then false
      when @bar.yang() and (@_gradeRatio > @_extremeGradeRatio) then true
      when not @bar.indicatorDrop('low',pb) then true
      when not @bar.indicatorDrop('close',pb) then true
      when pool.formerObject(@_fishArrayName)?.swim.maxGradeRatio > @maxGradeRatio > @_highGradeRatio then true
      else false

  # --------------------------- cordonic -------------------------------
  # SwimDownFlowBase
  # 相反相成
  _fitSignal:(pool)->
    pool.signalSwim?.signal?.isBuySignal
 
  # SwimDownFlowBase
  # 無意義,純用於 BuyBuoy 命名
  buoyNamePrefix: 'xUp'

  # SwimDownFlowBase
  _detectCrosses: ->
    # 必須按邏輯順序檢測,即上漲是從低到高,以便後續處理 baseUpXIndex
    for x in [0..10] when @_closeUpCrossGrade(x)
      # 此時不確定,故僅存信息於變動之 @bar
      @bar.recordUpXGrade(x)
    if @bar.baseUpXIndex
      @cordonGradeIndex = @bar.baseUpXIndex
      
  # SwimDownFlowBase
  _closeUpCrossGrade: (anIndex)->
    if not @previousBar?
      return false
    {high, low, close} = @previousBar
    line = @previousGrade?[anIndex]
    #{high,low,close,line} = fixAll({high,low,close,line})
    switch  # 凡 switch 其中 when 之順序皆不可輕易更改
      #up1 
      when @bar.close > line >= close then true
      when @bar.close > line > @bar.low then true
      #up2 
      #when (low < line <= close) and (@close > line) then true
      #up3, 昨日下穿前日之線,而不低於自身之線,且以上代碼均檢測不到上穿:
      #when @bar.yang() and (@earlierGrade?[anIndex] > close) and (close >= line) and (@close > line) then true
      else false

    
  # SwimDownFlowBase
  # 應放在 beforePushPreviousBar 內以便檢測既成事實.
  _setGradeBuoyOnFitSignal:(pool)->
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      when @bar.baseUpXIndex then @_onFitSignalCross(pool)
      when @_jumpingBack(pool) then @_onFitSignalJumpBack(pool)
      when not @_isNowBuoySwimClass(pool) 
        # 此時尚未檢測到穿透,模擬一個假穿刺
        @_setFakeCordonGradeIndex() 
        @_onFitSignalCross(pool)
            

  # SwimDownFlowBase
  # 天地線憑空內斂反跳回來(正常是向創新低新高方向外擴跳開,反跳收回則可由fishy定義而致)
  _onFitSignalJumpBack:(pool)->
    if @bar.high < pool.barBefore(@bar)?.high
      # 此時尚未檢測到穿透,模擬一個假穿刺
      @latestCrossBar = @bar
      @_setFakeCordonGradeIndex() 
      # 不能移走
      @_resetBuoy(pool)


  # SwimDownFlowBase
  _inBetterGrade:(pool)->
    {gradeBuoy,gradeBuoy:{buoySwim,cordonGradeIndex}} = pool  
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      when not pool.gradeBuoy? then false
      when @cordonGradeIndex >= cordonGradeIndex then false
      when @grade[@cordonGradeIndex] >= buoySwim.grade[cordonGradeIndex] then false
      else true



class GradualSwimUpFlow extends SwimUpFlowBase

  # GradualSwimUpFlow
  nextBar:(pool)->
    super(pool)
    if @_isNowSignalSwim(pool)
      @_optOperations(pool)
      #assert.log("debug GradualSwimUpFlow nextBar here")
      


  # GradualSwimUpFlow
  _breakSettings:(pool)->
    super(pool)
    @_optOperations(pool)

  # GradualSwimUpFlow
  _breakAgainSettings:(pool)->
    super(pool)
    @_optOperations(pool)

  shortCloseSuggestedCallOpen:(pool)->
    @_optOperations(pool)

  # GradualSwimUpFlow
  # 注意順序不可隨意改變
  _optOperations:(pool)->
    if @_optOperator?
      if @_isOptChance(pool)
        strike = @_strike(pool)
        @_optOperator.emitForcedOPTOpenMessage(pool,@bar,strike)
        assert.log('_optOperations open calls at lowRiskStrike:',lowRiskStrike,strike)
        @_optsOpened = true

  # GradualSwimUpFlow
  _isOptChance:(pool)->
    if not @isCurrentBar()
      return false
    earlyN = 15
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      when @_optsOpened
        #assert.log('not a chance since already opened')
        false 
      when @stageCeased()
        #assert.log('not a chance since stage ceased')      
        false
      when @_recurringBreak(pool)
        #assert.log('not a chance since break is recurring')
        false
      when not @bar.lowBelowLine(pool.bband.highBandName)
        #assert.log('not a chance since not under high band')
        false
      # 本身非 signalSwim 由 signalSwim shortClose 引發開啟 call options
      when not @_isNowSignalSwim(pool) then true
      when not @justAdvanced()
        #assert.log('not a chance since not just advanced')
        false
      when (pool.yangfishy.size > earlyN)
        #assert.log('not a chance since yangfishy.size > ',earlyN)
        false
      else 
        true
    
  _strike:(pool)->
    if lowRiskStrike
      #Math.floor(@bar.low - 0.5) 
      Math.ceil(@bar.high)
    else 
      Math.max(@high, pool.bband.potentialHigherPrice())

class GradualSwimDownFlow extends SwimDownFlowBase
  # GradualSwimDownFlow
  nextBar:(pool)->
    super(pool)
    if @_isNowSignalSwim(pool)
      @_optOperations(pool)
      #assert.log("debug GradualSwimDownFlow nextBar here")

  # GradualSwimDownFlow
  _breakSettings:(pool)->
    super(pool)
    @_optOperations(pool)

  # GradualSwimDownFlow
  _breakAgainSettings:(pool)->
    super(pool)
    @_optOperations(pool)


  # GradualSwimDownFlow
  # 注意順序不可隨意改變
  _optOperations:(pool)->
    if @_optOperator? 
      if /shortClose/i.test(@signalTypeSuggestion())
        buoySwim = pool.getCurrentBuoySwim()
        assert.log('debug _optOperations >> buoySwim:',buoySwim?)
        if buoySwim?
          buoySwim.shortCloseSuggestedCallOpen(pool)
          assert.log('debug _optOperations3')

      if @_isOptChance(pool)
        strike = @_strike(pool)
        @_optOperator.emitForcedOPTOpenMessage(pool,@bar,strike)
        assert.log('_optOperations open puts at lowRiskStrike:',lowRiskStrike,strike)        
        @_optsOpened = true
        

  # GradualSwimDownFlow
  _isOptChance:(pool)->
    if not @isCurrentBar()
      return false
    earlyN = 15
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      when @_optsOpened
        #assert.log('not a chance since already opened')
        false 
      when @stageCeased()
        #assert.log('not a chance since stage ceased')      
        false
      when @_recurringBreak(pool)
        #assert.log('not a chance since break is recurring')
        false
      when not @justAdvanced()
        #assert.log('not a chance since not just advanced')
        false
      when (pool.yinfishx.size > earlyN)
        #assert.log('not a chance since yinfishx size > ',earlyN)
        false
      when not @bar.highUponLine(pool.bband.lowBandName)
        #assert.log('not a chance since below low band')
        false
      else
        true

  # GradualSwimDownFlow
  _strike:(pool)->
    if lowRiskStrike
      #Math.ceil(@bar.high + 0.5)
      Math.floor(@bar.low)
    else
      Math.min(@low, pool.bband.potentialLowerPrice())



class QuickSwimUpFlow extends SwimUpFlowBase
  _highGradeRatio: 10
  _extremeGradeRatio: 100

  # QuickSwimUpFlow
  # 高風險品種專用.波動特別巨大,適合及時止盈止損,故須注重保全成果.
  # 注意: 所有引用必須基於 bar 不得直接引用他法狀態,以免時空錯亂  
  _paused:(pool)->
    return super(pool)

    # 暫時不用以下代碼,觀察效果如何
    {bband:{maName}} = pool
    if @size < 2
      return false
    x = 5
    switch  # 凡 switch 其中 when 之順序皆不可輕易更改
      when super(pool) then true
      when @bar.close < @grade[3] < @previousBar?.close then true
      when @bar.closeBelowLine(maName) then true
      when @size > x and @bar.close < @grade[8] < @previousBar?.close then true
      else false


  # QuickSwimUpFlow
  _ceased:(pool)->
    {bband:{maName},yinfish} = pool
    pb = pool.barBefore(@bar) 
    switch  # 凡 switch 其中 when 之順序皆不可輕易更改
      when super(pool) then true
      # 似乎無須以下複雜條件
      #when @bar.closeBelowLine(maName) and @bar.closeBelowLine('tay') and @_dropToCeasedGrade(pool) then true
      #when @bar.settledBelowLine(maName) and @bar.closeBelowLine('tay') and @_dropToCeasedGrade(pool) then true
      #when @_triDroping(pool) then true
      # 以下思路很好,唯尚需尋找克制過早終結之法以佐之
      #when @bar.yang() and Math.max(60,@bar.rsi) < pb?.rsi then true
      #when (@bar.rsi > 68) and (@bar.close < @grade[9]) then true
      #when @bar.tay < @bar.ta and (@bar.rsi < pb?.rsi) and yinfish.size < 10
      #  switch  # 凡 switch 其中 when 之順序皆不可輕易更改
      #    when @bar.tay < pb?.tay and @bar.closeBelowLine('tay') then true
      #    when @bar.tay is pb?.tay and @bar.close is pb?.close then true
      #    else false 
      else false
  


  # QuickSwimUpFlow
  _dropToCeasedGrade:(pool)->
    @bar.yin() and @bar.low < @grade[@_ceasedGrade[@timescale]]
  _triDroping:(pool)->
    unless @bar.highBelowLine(pool.bband.highHalfBandName)
      return false
    pb = pool.barBefore(@bar)   
    (@bar.tay < pb?.tay) and (@bar.bbtax < pb?.bbtax) and (@bar.bbta < pb?.bbta) and (@bar.rsi < pb?.rsi)


class QuickSwimDownFlow extends SwimDownFlowBase
  _highGradeRatio: 10
  _extremeGradeRatio: 100

  # QuickSwimDownFlow
  _breakdown:(pool)->
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      when super(pool) then true
      #when @bar.closeBelowLine(pool.bband.yinfishx.tbaName) then true 
      else false

  # QuickSwimDownFlow
  _paused:(pool)->
    x = 3
    {bband:{maName}} = pool
    switch  # 凡 switch 其中 when 之順序皆不可輕易更改
      when super(pool) then true
      #when (@bar.close > @grade[8] > @previousBar?.close) then true
      #when (@bar.floatedUponLine(maName)) then true
      #when (@bar.low > @earlierBar?.low) then true
      #when (@bar.close > @grade[2] > @previousBar?.close and @size > x) then true
      else false





class OPTSwimUpFlow extends QuickSwimUpFlow
class IOPTSwimUpFlow extends QuickSwimUpFlow

class OPTSwimDownFlow extends QuickSwimDownFlow
class IOPTSwimDownFlow extends QuickSwimDownFlow







module.exports = SwimFlowBase


###
  [20171222補記]
  1. 試圖整理簡化過程中,出現奇怪的現象,說明本法存在隱蔽機理.
  2. 已知上下游會競爭成為 pool.signalSwim
  3. 比較繞人的是 beforePushPreviousBar 以及 nextBar 影響不同.為了消除歧義方便簡化,必須先將本法記憶的某些狀態轉移至 @bar
  4. swim 可以放置於任意 fish 內,但對交易的影響是,grade 尺寸不一樣,久暫也不一樣.
    就期權而言,因行情長度短,故差別不大.對其他品種來說,目前試用 yinfish/yinfishx 對應 yangfishx 比較合適
  5. 待找出潛藏機理之後,可研究如何提早進入平倉期,以便 buoy 跟價止盈
  [20171218補記]
  1.應該用行情週期降級來解決的問題,則不應用改變策略邏輯來解決.
    例如突破成立之後,再做相應操作,如果發現已經走了一大段,此時不應單單因為走了一大段覺得可惜而去改變邏輯,除非存在著更好的邏輯.
    如果別樣的緣起的不存在,就應該通過降低週期級別來減少耽誤的行情.這一點非常重要.
  2.在假設 buoy 生於已經確定完成的 bar 而非當下變動中的 bar 這一前提合理且無須改進的前提下,需要解決以下問題,以前沒有注意到.
    a. @bar 創新高或新低,不再落在 buoy 出生時所在的 grade 框架內了,如何處理.
    b. @bar 雖然仍在之前 grade 範圍內,但是由於 grade 太窄,導致層級間距太小,不斷出生新 buoy 卻一直上下都出界,故無法滿足
    成交條件,如何處理
    c. fishx/fishy 反跳機制 
  3.解決方案, 這兩個問題都在 buoy 中解決.方案寫入 buoy 文檔內.

  [20171216補記]
  用 swim 作為 cordon.將原先設計的多 cordon 多 buoy (實際無用)改為 swim buoy 一對一, 並存放於 pool
  詳見 CordonicSwimFlow
  [20171206補記]
  本系統將變動點和交易點分開:
    變動點: 由分層價格線 grade[n] 和上下穿透自然形成.
    交易點: 通過陰陽魚上游下游 swim 之起止自然形成過濾條件.
  本法為過濾變動點形成交易點而設計. swim 分為上下兩種.每種包含4~5個 stage. start,advance,pause/retract,cease. 
  1. 用 advance 過濾掉不該多頭建倉或空頭建倉的部分.
    任何一小段行情都會形成 swim 但 swim 未進入 advance 階段前則僅平倉不開倉.部分 swim 可能始終不突破.此為第一層過濾.
    swim:
      up: 
        # if started at a lower price 
        start: LongClose
        advance: LongOpen
        pause/retract: LongClose/LongOpen # 持倉則可平倉,空倉亦可建倉,未終結故
        cease: LongClose
      down:
        # if started at a higher price
        start: ShortClose
        advance: ShortOpen
        pause/retract: ShortClose/ShortOpen # 持倉則可平倉,空倉亦可建倉,未終結故
        cease: ShortClose
  
  2. 使用 swim 配信號分值, 將不同的信號用[n]繪製出來
  
  3. swim up/down 自然形成各自的 grade[], 此 grade 作為 buoy 的 cordon (關鍵界線),注意買賣所對應的上下游方向: 
    swim:
      up: SellBuoy
      down: BuyBuoy
  
  [20171114補記]
  不但此法是魚,且breakthrough 一法亦此法之一分,似無須另立
  start 應改名 advance, 突破

  這邊是新思路, breakthrough 收攝於此, 趨勢入於魚,開新分支來改寫並測試
  [20171111補記]
  # 後來發現,此法其實是真正的魚,或游魚 signalSwim/moving fish,,或 fishBody, upwardFishBody downwardFishBody 
  由於聚焦其動向,改名 swimflow 命名更切當.
  
  [原始說明]
  前行,單向行情.
  開發深入,乃知此法有多態.有始終,亦有停歇.停歇之後,終結之前,同向突破,名為復始;終結之後,同向突破,名為開始.正合趨勢之四象.
  相應英文名: start(Bar) --- pause(Bar) --- advancedAgain(Bar) --- end(Bar)
  配以方向之上落 up/down 形成趨勢: 
  ---> bull(up start) --- bullish(up pause) --- bull(up advancedAgain) --- bearish(up end) ---> 牛熊兩種可能
  ---> bear(down start) --- bearish(down pause) --- bear(down advancedAgain) --- bullish(down end) ---> 牛熊兩種可能
  其中對應 最佳開倉點 --- 止盈平倉點 --- 重返開倉點 --- 止盈平倉點 --- .... --- 最佳清倉點

  若無特殊需要,判斷各種價格關係盡量使用close,並且在即將設置為前 bar 時判斷,故沒有未來數據.實際是對前收盤進行判斷.

  各大 flow 均可用我.
  #@underlyingIndicatorName 記錄所跟蹤的指標,或 rawdata high,low, etc.

###

### 上穿下穿判別條件:
# copied from databar
1. 首日無穿透,無前可比故
2. 翌日穿透前日某線價位,昨日收於另一側,算穿透
3. 複雜情形:
  1.昨日低低於昨日某線價位,昨日收於該價位之上,今日收高於昨日某線當時價位,算今日上穿(確認昨日之穿透),
    若今日收於昨日某線之下,算今日下穿,以符合2故
  2.昨日高高於昨日某線價位,昨日收於該價位之下,今日收低於昨日某線當時價位,算今日下穿(確認昨日之穿透),
    若今日收高於昨日某線當時價位,算今日上穿,以符合2故.
  3.昨日今日收在同側,但
    昨日記錄為上穿,今日/昨日均收於線下,蓋昨日上穿前日之線,而低於昨日之線,今日算下穿(確認昨日之下穿);
    昨日記錄為下穿,今日/昨日均收於線下,蓋昨日下穿前日之線,而高於昨日之線,今日算上穿(追認昨日之上穿)
  以上或可避免當天線的位置上行下行,且破昨日位,又回抽破今日線移動後所在位,此時出現當天上穿下穿同名線(位置不同了)的混亂情形
###
