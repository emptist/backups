###
  前行,單向行情.
  開發深入,乃知此法有多態.有始終,亦有停歇.停歇之後,終結之前,同向突破,名為復始;終結之後,同向突破,名為開始.正合趨勢之四象.
  相應英文名: start(Bar) --- pause(Bar) --- restart(Bar) --- end(Bar)
  配以方向之上落 up/down 形成趨勢: 
  ---> bull(up start) --- bullish(up pause) --- bull(up restart) --- bearish(up end) ---> 牛熊兩種可能
  ---> bear(down start) --- bearish(down pause) --- bear(down restart) --- bullish(down end) ---> 牛熊兩種可能
  其中對應 最佳開倉點 --- 止盈平倉點 --- 重返開倉點 --- 止盈平倉點 --- .... --- 最佳清倉點

  若無特殊需要,判斷各種價格關係盡量使用close,並且在即將設置為前 bar 時判斷,故沒有未來數據.實際是對前收盤進行判斷.

  各大 flow 均可用我.
  @underlyingIndicatorName 記錄所跟蹤的指標,或 rawdata high,low, etc.
  
  # forward vs forwards:
  While only used as an adverb, forwards means the same. So we stick to 'forward'.

  [20171111補記]
  # 後來發現,此法其實是真正的魚,或游魚 swimming/moving fish,,或 fishBody, upwardFishBody downwardFishBody 
  由於聚焦其動向,改名 swimflow 命名更切當.
  [20171114補記]
  不但此法是魚,且breakthrough 一法亦此法之一分,似無須另立
  start 應改名 advance, 突破
###

assert = require './assert'
BaseDataFlow = require './dataflow_base'
{fix} = require './fix'


class SwimFlowBase extends BaseDataFlow
  @pick:({contractHelper,direction,hostName})->
    switch direction
      when 'up'
        switch 
          # 臨時訂製,待完成陰陽魚之 swim 再移至彼 class 或一以貫之
          when contractHelper.contract.secType is 'OPT' then new OPTSwimUpFlowBT({contractHelper,hostName})
          when contractHelper.contract.secType is 'IOPT' then new IOPTSwimUpFlowBT({contractHelper,hostName})
          else new SwimUpFlowBT({contractHelper,hostName})
      when 'down'
        new SwimDownFlowBT({contractHelper,hostName})


  constructor:({@contractHelper,@hostName})->
    super(@contractHelper)
    # 這樣的寫法,@grade[0]...@grade[10] 比起 level0...level10 這樣好用多了,但當時設計的時候,考慮的是繪圖方便.不智.
    @grade = []

    # one of ['_advanced','_ceased','_advancedAgain','_paused']
    # 其中, _advanced and _advancedAgain 由他法判定設置,他法例如 breakthrough; _paused and _ceased 系自省而得,故在此處定義
    @_stage = null

    #成
    @_advancedBar = null
    #住 
    @_pauseBar = null
    #住 
    # 再突破仍是突破,不另外命名可能方便後續比較高低等等檢測
    #@_advancedAgainBar = null

    #壞
    #退轉點,特指可能成為結束信號者; retreat 含義相近,但是有股票下跌的意思,不合適.需要多空皆宜
    @_retractBar = null
    #滅
    @_ceaseBar = null


  isUpward:->
    @_direction is 'up'
  isDownward:->
    @_direction is 'down'

  #成
  stageAdvanced:->
    @_stage is '_advanced'
  #住
  stagePaused:->
    @_stage is '_paused'
  #住
  stageAdvancedAgain:->
    @_stage is '_advancedAgain'
  #壞
  stageRetracted:->
    @_stage is '_retract'
  #滅
  stageCeased:->
    @_stage is '_ceased'

  setAsAdvanced: (aBar)->
    # caller 在 BreakthroughFlow 不同文件,為便於理解維護,故在此過濾重複設置
    if @stageAdvanced()
      return
    @_stage = '_advanced'
    @_advancedBar = aBar
    # chart 標誌由下級各自設定
    @_labelBarAsAdvanced(aBar)

  setAsAdvancedAgain: (aBar) ->
    # caller 在 BreakthroughFlow 不同文件,為便於理解維護,故在此過濾重複設置
    if @stageAdvancedAgain() or @stageAdvanced()
      return
    @_stage = '_advancedAgain'
    #@_advancedAgainBar = aBar
    # 再突破仍是突破,不另外命名可能方便後續比較高低等等檢測
    @_advancedBar = aBar
    # bar chart 標誌由下級各自設定
    @_labelBarAsAdvancedAgain(aBar)

  _setAsPaused:(pool)->
    @_stage = '_paused'
    @_pauseBar = @bar
    @bar.chartPauseMove = true

  # 壞,滅之先兆
  _setAsRetracted:(pool)->
    #assert.log("_setAsRetracted @_stage is ",@_stage)
    @_stage = '_retract'
    @_retractBar = @bar
    @bar.chartRetractMove = true

  _setAsCeased:(pool) ->
    #assert.log("_setAsCeased @_stage is ",@_stage)
    @_stage = '_ceased'
    @_ceaseBar = @bar
    @bar.chartCeaseMove = true



  comingBar:(aBar,pool)->
    # 似乎不妥:
    #if @_ceaseBar? then return
    super(aBar,pool)

   
  ### beforePushPreviousBar 須謹慎使用,因會造成時空狀況複雜難懂易錯.
  # 此法會在 nextBar 之前執行, 執行後, 所在的 comingBar() 會令 @bar = bar, 然後執行 nextBar
  # 大部分情況或可避免使用,而改在 nextBar 中引用 previousBar 的狀態
  # 此處實質代碼已經過審閱,未發現問題. 
  # 檢查日期:(後續檢查應同樣記錄日期)
  #   [20171107] 未發現問題.
  ###
  beforePushPreviousBar:(pool)->
    @_checkPauseOrCeased(pool)

  # 若放在 nextBar 則判斷當時(未定), 若放在 beforePushPreviousBar 則判斷既成
  # 由於此二種狀態,非突破所攝,故由自身判斷,不涉及 breakthrough 一法
  _checkPauseOrCeased:(pool)->
    switch
      #when @_retracted(pool) and not (@stageRetracted(pool) or @stageCeased(pool)) 
      #  @_setAsRetracted(pool)
      when @_ceased(pool) and not @stageCeased(pool)
        @_setAsCeased(pool)
      when @_paused(pool) and not (@stagePaused(pool) or @stageCeased(pool)) 
        @_setAsPaused(pool)
 

  # 若放在 nextBar 則判斷當時(未定), 若放在 beforePushPreviousBar 則判斷既成
  _paused:(pool)->
    assert.subJob()

  _retracted:(pool)->
    assert.subJob()
  # 若放在 nextBar 則判斷當時(未定), 若放在 beforePushPreviousBar 則判斷既成
  _ceased:(pool)->
    assert.subJob()


  # 自身亦有高低開收
  firstBar:(pool)->
    {@open, @high, @low, @close} = @bar
    @score()
    ###
    if @bar[@hostName]?
      @bar[@hostName].grade = @grade
    else
      @bar[@hostName] = {@grade}
    ###

  nextBar:(pool)->
    changed = false
    {@close,high,low} = @bar
    if high > @high
      changed = true
      @high = high
    if low < @low 
      changed = true
      @low = low
    if changed
      @score()
    ###
    if @bar[@hostName]?
      @bar[@hostName].grade = @grade
    else
      @bar[@hostName] = {@grade}
    ###

  # 此處其實可以應用 layerscore object, 但有些殺雞用牛刀的感覺
  # 以下代碼是從 layerscore.coffee 拷貝過來再稍加調整的; 有空進一步推敲,以便形成通法
  score:(geometric=true) ->
    if geometric 
      g = Math.pow(@high / @low, 1/10)
    # 注意:
    # 指標標號是有意義的! 順序對應指標數值從小到大! 相關代碼用到此特性,不要隨意更改!
    for idx in [0..10]
      if geometric 
        @grade[idx] = fix(@low * g ** idx)
      else
        @grade[idx] = fix((idx*@high + (10-idx)*@low) / 10)
    
  closeBelowGrade:(n)->
    @close < @grade[n]
  closeAtGrade:(n)->
    @close is @grade[n]
  closeUponGrade:(n)->
    @close > @grade[n]

class SwimFlow extends SwimFlowBase

# 暫時用於訂製魚類 swim, 以便開發測試,且不影響操作,將來應歸一不二
class SwimUpFlowBase extends SwimFlow
  _direction: 'up'

  # 用於繪圖
  _labelBarAsAdvanced:(aBar)->
    aBar.chartBreakUp = true

  # 用於繪圖
  _labelBarAsAdvancedAgain:(aBar)->
    aBar.chartUpAgain = true

  _setAsPaused:(pool)->
    super(pool)
    #if /OPT|WAR/.test(@contractHelper.contract.secType)
    #  @trend?.setTrendSymbolAs(pool,@bar,'bullish')

  _setAsRetracted:(pool)->
    super(pool)
    # _retract 跟 _ceased trendSymbol 一樣
    @trend?.setTrendSymbolAs(pool,@bar,'bearish')

  _setAsCeased:(pool) ->
    super(pool)
    # _retract 跟 _ceased trendSymbol 一樣
    @trend?.setTrendSymbolAs(pool,@bar,'bearish')
    @callOperator?.emitForcedOPTCloseMessage(pool,@bar)

  # 這不是一個 function; 是一個變量而已
  _ceasedGrade: {
    month: 9
    week: 9
    day: 8
    DAY: 8
    hour: 6
  }

  _paused:(pool)->
    false
  _retracted:(pool)->
    @_dropToRetractGrade(pool,8)

  #[bug] 對照圖形,數據不對,不知是否錯位一個 bar 造成的[補記:是. grade須存入bar 或者都在 beforePushPreviousBar 時計算]
  _dropToRetractGrade:(pool,x)->
    @bar.yin() and @bar.low < @grade[x] < pool.barBefore(@bar)?.low

  _ceased:(pool)->
    false

# 暫時用於訂製魚類 swim, 以便開發測試,且不影響操作,將來應歸一不二
class SwimDownFlowBase extends SwimFlow

  _direction: 'down'

  # 用於繪圖
  _labelBarAsAdvanced:(aBar)->
    aBar.chartBreakDown = true

  # 用於繪圖
  _labelBarAsAdvancedAgain:(aBar)->
    aBar.chartDownAgain = true

  _setAsPaused:(pool) ->
    super(pool)
    #if /OPT|WAR/.test(@contractHelper.contract.secType)
    #  @trend?.setTrendSymbolAs(pool,@bar,'bearish')
  
  _setAsRetracted:(pool)->
    super(pool)
    # _retract 跟 _ceased trendSymbol 一樣
    @trend?.setTrendSymbolAs(pool,@bar,'bullish') 
    
  _setAsCeased:(pool) ->
    super(pool)
    # _retract 跟 _ceased trendSymbol 一樣
    @trend?.setTrendSymbolAs(pool,@bar,'bullish')
    @putOperator?.emitForcedOPTCloseMessage(pool,@bar)

  
  _retracted:(pool)->
    @_riseToRetractGrade(pool,2)
  #[bug] 對照圖形,數據不對,不知是否錯位一個 bar 造成的
  _riseToRetractGrade:(pool,x)->
    @bar.yang() and (@bar.high > @grade[x] > pool.barBefore(@bar)?.high)

  _ceased:(pool)->
    false
  _paused:(pool)->
    false



# 以下 _paused 之定義都尚未完善,仍在修葺之中
class SwimUpFlowBT extends SwimUpFlowBase
  # SwimUpFlowBT
  # 對於低風險品種,主要是減少操作,善始善終,降低交易成本故此法適合簡潔明快
  # 不僅此法可以終止前行段,向下突破條件滿足,也會終止.特點是此法終止過度到 bullish, 而被突破終止,則直接到 bear
  # 注意: 向下突破方法涉及 yangfishx, 此法在月線週線日線上,很難滿足向下突破條件,故須增加 grade[] 條件
  # 注意: 所有引用必須基於 bar 不得直接引用他法狀態,以免時空錯亂
  _ceased:(pool)->
    if @contractHelper.forceLongClose and not @stageCeased(pool)
      # 以便設置為 'bearish'
      return true
    {bband:{maName}} = pool
    pb = pool.barBefore(@bar) 
    switch
      when @bar.closeBelowLine(maName) and @bar.closeBelowLine('tay') and @_dropToCeasedGrade(pool) then true
      when @bar.settledBelowLine(maName) and @bar.closeBelowLine('tay') and @_dropToCeasedGrade(pool) then true
      #when @_triDroping(pool) then true
      # 以下思路很好,唯尚需尋找克制過早終結之法以佐之
      #when @bar.yang() and Math.max(60,@bar.rsi) < pb?.rsi then true
      #when (@bar.rsi > 68) and (@bar.close < @grade[9]) then true
      else false

  _dropToCeasedGrade:(pool)->
    @bar.yin() and @bar.low < @grade[@_ceasedGrade[@timescale]]
  
  _triDroping:(pool)->
    unless @bar.highBelowLine(pool.bband.highHalfBandName)
      return false
    pb = pool.barBefore(@bar)   
    (@bar.tay < pb?.tay) and (@bar.bbtax < pb?.bbtax) and (@bar.bbta < pb?.bbta) and (@bar.rsi < pb?.rsi)

  # 高風險品種專用.波動特別巨大,適合及時止盈止損,故須注重保全成果.
  # 注意: 所有引用必須基於 bar 不得直接引用他法狀態,以免時空錯亂  
  _paused:(pool)->
    if @contractHelper.forceLongClose
      # 以免設置為 'bullish'
      return false
  
    {bband:{maName}} = pool
    if @size < 2
      return false
    x = 5
    switch
      when @bar.close < @grade[3] < @previousBar?.close then true
      when @bar.closeBelowLine(maName) then true
      #when Math.min(pool.yinfishx.size, pool.yinfish.size) > 5 then true
      when @size > x and @bar.close < @grade[8] < @previousBar?.close then true
      else false

class OPTSwimUpFlowBT extends SwimUpFlowBT
  _ceased:(pool)->
    if super(pool)
      return true
    {bband:{maName}} = pool
    pb = pool.barBefore(@bar) 
    switch
      when @bar.tay < @bar.ta and (@bar.rsi < pb?.rsi) 
        switch 
          when @bar.tay < pb?.tay and @bar.closeBelowLine('tay') then true
          when @bar.tay is pb?.tay and @bar.close is pb?.close then true
          when @_triDroping(pool) then true
          else false 
      else false

class IOPTSwimUpFlowBT extends OPTSwimUpFlowBT


class SwimDownFlowBT extends SwimDownFlowBase
  _ceased:(pool)->
    if @contractHelper.forceLongClose
      #以免設置狀態為 'bullish'
      return false
    x = 5
    {bband:{maName}} = pool
    switch 
      when (@bar.high > @_advancedBar.high) then true
      when (@size > x and @bar.close > @grade[4]) then true 
      when @bar.floatedUponLine(maName) then true
      else false


  _paused:(pool)->
    if @contractHelper.forceLongClose and @stageCeased()
      # 以便設置相位為 'bearish'
      return true

    x = 3
    {bband:{maName}} = pool
    switch
      when (@bar.close > @grade[8] > @previousBar?.close) then true
      when (@bar.floatedUponLine(maName)) then true
      when (@bar.low > @earlierBar?.low) then true
      when (@bar.close > @grade[2] > @previousBar?.close and @size > x) then true
      else false

    #@bar.low > @earlierBar?.high 這就是暴漲了
    #@bar.low > @earlierBar?.close
  







module.exports = SwimFlowBase
