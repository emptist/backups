###
  breakthrough flow 突破
  此法之各種子法識別各自對應的各種突破
  
  vs moveforward flow 前行段流
  突破與前行段的關係: 
    前行極大可能是先於突破開始的,至突破時獲得確認.
    其結束也早於下一個反向突破,至反向突破時,反向前行獲得確認.
    為了方便統計分析,也可以在 breakthrough 內使用, 以記錄突破後的一段單向行情,此時實為其中一段,而非完整的前行段.
    或者使用判斷突破的 underlyingIndicators 來判斷前行段,此時則為該定義下的完整的前行

  [20171116 補記] 
  將作如下修改,二選其一:
    1. 此法的功能並入 swimflow ,一個 swimflow 就只能固定定義 breakthrough 條件,不能隨時切換,但是免除了時差問題
    2. 顛倒一下,此法放在 swimflow 內,一個 swimflow 可以隨意設置所需要的 breakthrough, 但要重新考慮時差問題
  傾向於方案1
###
assert = require './assert'
BaseDataFlow = require './dataflow_base'
SwimFlowBase = require './swimflow_bt'
{noOPTs} = require './config'


class BreakthroughFlowBase extends BaseDataFlow
  @pick:({contractHelper, breakClass})->
    switch breakClass
      when 'fish' 
        new FishBreakthroughFlow(contractHelper)
      else
        new BreakthroughFlow(contractHelper)

  constructor:(@contractHelper)->
    super(@contractHelper)
    # 次第混放的 swimUp/Downwards
    @swimForwards = []
    @swimUpwards = []
    @swimDownwards = []
    # 持續單向行進
    @swim = null
    @trend = null
    
    ### 切莫增加下行! 不應如此設計,極大不便,時空混亂,檢查之前單向運動的各項屬性非常困難,極為複雜
    #@previousSwim = null
    ###



  comingBar:(aBar,pool)->
    super(aBar,pool)
    @swim?.comingBar(aBar,pool)

    ### 切莫增加以下三行! 不應如此設計,會造成後續他方判斷突破狀態時,憑據難定,時空混亂,增加複雜性,必須等下次賦值時,swim 所指才改變
    if @swim?.stageCeased()
      @previousSwim = @swim
      @swim = null
    ###


  ### beforePushPreviousBar 須謹慎使用,因會造成時空狀況複雜難懂易錯.
  # 此法會在 nextBar 之前執行, 執行後, 所在的 comingBar() 會令 @bar = bar, 然後執行 nextBar
  # 大部分情況或可避免使用,而改在 nextBar 中引用 previousBar 的狀態
  # 此處實質代碼已經過審閱,未發現問題. 
  # 檢查日期:(後續檢查應同樣記錄日期)
  #   [20171107] 未發現問題.
  ###
  beforePushPreviousBar:(pool)-> 
    @_checkForBreaking(pool)
  
  # 在參數不加 bar 的情形下, 若放在 nextBar 則判斷當時(未定), 若放在 beforePushPreviousBar 則判斷既成
  _checkForBreaking:(pool)->
    switch 
      when @_breakup(pool)
        switch
          when (not @swim?) or @swim.isDownward() or @swim.stageCeased()
            @_breakupSettings(pool)
          when not @swim.stageAdvancedAgain()
            @_breakupAgainSettings(pool)
      when @_breakdown(pool)
        switch
          when (not @swim?) or @swim.isUpward() or @swim.stageCeased()
            @_breakdownSettings(pool)
          when not @swim.stageAdvancedAgain()
            @_breakdownAgainSettings(pool)
  
  _breakup:(pool) ->
    assert.subJob()
  _breakdown:(pool) ->
    assert.subJob()

  # 以下諸法使用 swim 時,直接傳遞 @bar,以免時空混亂
  # 注意, 之所以將 swim 設置放置於 _callOperations 是因順序不可隨意改變,防止不小心改錯
  _breakupSettings:(pool)->
    if @_uselessBreak(pool)
      return
    @swim = @_callOperations(pool)  
    @swim.comingBar(@bar) # @swim 必須後於我接受新 @bar, 然而,此時新開若無 firstBar 則以下設置無法實施
    @swim.setAsAdvanced(@bar)
    @swimForwards.push(@swim)
    @swimUpwards.push(@swim)
    @trend.setTrendSymbolAs(pool,@bar,'bull')

  # 注意順序不可隨意改變
  _callOperations:(pool)->
    swim = SwimFlowBase.pick({@contractHelper,direction:'up',hostName:@constructor.name})
    swim.trend = @trend
    # 對於除了期權牛熊證等衍生品之外的基礎證券,其中如果有 @callOperator , 則:
    if @callOperator?
      @putOperator.emitForcedOPTCloseMessage(pool,@bar)
      if @_callSuitable(pool)
        @callOperator.emitForcedOPTOpenMessage(pool,@bar)
      # 將由彼法觸發關閉消息
      swim.callOperator = @callOperator
    # 無論有無 @callOperator, 皆須回復 swim
    return swim
  
  _breakupAgainSettings:(pool)->            
    if @_uselessBreak(pool)
      return
    @swim.setAsAdvancedAgain(@bar)
    @trend.setTrendSymbolAs(pool,@bar,'bull')    

  # 以下諸法使用 swim 時,直接傳遞 @bar,以免時空混亂
  # 注意, 之所以將 swim 設置放置於 _putOperations 是因順序不可隨意改變,防止不小心改錯
  _breakdownSettings:(pool)->
    if @_uselessBreak(pool)
      return
    @swim = @_putOperations(pool)
    @swim.comingBar(@bar) # @swim 必須後於我接受新 @bar, 然而,此時新開若無 firstBar 則以下設置無法實施    
    @swim.setAsAdvanced(@bar)
    @swimForwards.push(@swim)
    @swimDownwards.push(@swim)
    @trend.setTrendSymbolAs(pool,@bar,'bear')

  # 注意順序不可隨意改變
  _putOperations:(pool)->
    swim = SwimFlowBase.pick({@contractHelper,direction:'down',hostName:@constructor.name})
    swim.trend = @trend
    # 對於除了期權牛熊證等衍生品之外的基礎證券,其中如果有 @putOperator,則:
    if @putOperator? 
      @callOperator.emitForcedOPTCloseMessage(pool,@bar)
      if @_putSuitable(pool)
        @putOperator.emitForcedOPTOpenMessage(pool,@bar)
      # 將由彼法觸發關閉期權消息
      swim.putOperator = @putOperator
    # 無論有無 @putOperator 皆須回復 swim
    return swim

  _breakdownAgainSettings:(pool)->
    if @_uselessBreak(pool)
      return
    @swim.setAsAdvancedAgain(@bar)
    @trend.setTrendSymbolAs(pool,@bar,'bear')

  ###
  注意: 僅限本法內使用,僅用於排除大行情起始之突破,行情中間之停歇和復始不適用 
  ###
  _uselessBreak:(pool)->
    @bar.closeVari > pool.bband.varianceLowLevel

  _callSuitable:(pool)->
    earlyN = 15
    (pool.yangfishx.size < earlyN) and @bar.lowBelowLine(pool.bband.highHalfBandName)
  _putSuitable:(pool)->
    earlyN = 15
    (pool.yinfishx.size < earlyN) and @bar.highUponLine(pool.bband.lowHalfBandName)



### 
    
  在完成檢測時,仍將有一次過濾 (uselessBreak)
  _breakupSettings:(pool)->
  _breakdownSettings:(pool)->
  
  在打開 call/put 窗口前,亦將有一次過濾, 
  _callSuitable
  _putSuitable
  
  故此處定義無須顧慮那些,可將所有的突破都找出來

###
class BreakthroughFlow extends BreakthroughFlowBase

class FishBreakthroughFlow extends BreakthroughFlow

  # 僅能使用 bar 數據判斷,而若不想增加太多數據,以下方法是目前能想到的,雖然會有少數例外(恰好相等,並非新高)
  _breakup:(pool)->
    # 配合強制多頭平倉,不可設置為向上突破
    if @contractHelper.forceLongClose 
      return false
    if @bar.yin() #or not @_yang(pool)
      return false
    switch
      when @bar.highIs('ta') then true #@_rsiUp(pool) and 
      when @_rsiUp(pool) and @bar.highIs('tax') then true 
      when @_rsiUp(pool) and @bar.floatedUponLine('tax') then true
      when @_yang(pool) and @bar.closeUpCross(pool.bband.maName,pool.barBefore(@bar)) then true
      when @_yang(pool) and @bar.closeUpCross(pool.bband.highHalfBandName,pool.barBefore(@bar)) then true
      when @_yang(pool) and @bar.closeUpCross(pool.bband.lowHalfBandName,pool.barBefore(@bar)) then true
      else false
  
  # [bug] 此處有潛在bug, 即, 當下 fishx 出現時差,所比較者,是本地未來時間的fish,出現機會不多,但需要解決
  _yang:(pool)->
    {yinfishx,yangfishx,yinfish,yangfish} = pool
    unless @_rsiUp(pool) then return false
    switch
      when yangfish.size >= yinfish.size then true
      when @bar.floatedUponLine(pool.yinfish.tbaName) and yangfishx.retrograded then true
      when @bar.floatedUponLine(pool.yinfish.tbaName) and (yangfishx.size > yinfishx.size) then true
      else false
  
  _rsiUp:(pool)->
    unless pool.barBefore(@bar)?
      return true
    (67 > @bar.rsi >= pool.barBefore(@bar)?.rsi)

  # 注意: 向下突破方法涉及 yangfishx, 此法在月線週線日線上,很難滿足向下突破條件,故須增加條件
  _breakdown:(pool)->
    if @contractHelper.forceLongClose
      # 配合強制多頭平倉,設置為向下突破
      return true
    if @bar.yang() #or @bar.lowUponLine('bbandma')
      return false
    switch
      when @bar.lowIs('bax') then true
      when @bar.lowIs('ba') then true 
      when @bar.settledBelowLine('bax') then true
      when @bar.settledBelowLine('bbandma') and @bar.settledBelowLine('bay') then true
      else false

  


module.exports = BreakthroughFlowBase



  
### 
  # ~~~~~ 以下方式不行(系統中其他各處亦須如此檢查) ~~~~~~
  
  # 不能引用前端法狀態! 故不能這樣寫:
  breakup_:(pool)->
    x = 15
    {yinfish,yinfishx,yangfishx} = pool
    (yinfish.size is 0 or yinfishx.size is 0) #and (yangfishx.size < x)
    @bar is yinfish.startBar or @bar is yinfishx.startBar

  breakdown_:(pool)->
    x = 5
    {yangfish,yangfishx,yinfishx,yinfish,bband} = pool
    switch
      when (yinfish.size > x) and (yinfishx.size > yangfishx.size) 
        if (bband.yinfish.size > x) and @bar.settledBelowLine('bax')
          # 同樣不可引用前端法狀態, 以上幾行引用大小,大於 x 尚可容忍,以下不行:
          #if (yangfish.size is 0 or (yangfishx.size is 0 and (not yangfishx.retrograded)))
          if (@bar.lowIs('ba') or (@bar.lowIs('bax'))) 
            return true
      else
        false
  # ~~~~~~~~~~~~~~~~   以上錯誤代碼   ~~~~~~~~~~~~~~~~~~
###


