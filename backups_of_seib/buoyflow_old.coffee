# New Grade Based Buoy System
###
  [20180303] price forward 順價交易思路
  
  要領:
    在上漲過程中賣出,下跌過程中買入,這樣可以確保成交,並且屬於止盈操作模式
  
  方法:
    1. 先產生一個操作意向,根據是:
      a. 現有的 actionPrice 逆行預警機制,表明單向運行可能結束
      b. 新增背離機制,待研究開發,重點是,尚未出現回撤逆行,但是氣勢已減,形之於 rsi, closeVari 等指標
    
    2. 反復檢查是否順價 @_priceShiftForward 根據是:
      a. @bar.close is @betterPrice
      b. @bar.highUponLine(bband.yinfish.tbaName)

  歷史:
    之前就有過類似的設計, 但後來被擱置了,並且當時的思路也不清晰.
###


moment = require 'moment-timezone'
BaseDataFlow = require './dataflow_base'
{IBCode} = require './codemanager'
{fartherPrice,testingIOPT,ioptBuyEndTime} = require './config'
{fix,goldenPoint} = require './fix'
_assert = require './devAssert'
BuoyFlowBase = require './buoyflow_base'

farther = fartherPrice

class BuoyFlowPicker
  # ------------------------------ class functions ---------------------------- 
  # 以下的選擇functions 如果需要的話,在各自文件中需要拷貝粘貼以下.
  # 為了避免多處重複維護不便,可獨立放置於buoyflow.coffee文件,但是需要exports中存放所有的 class 名以便引用.

  @pick: (buoySwim)->
    # 上游賣出, 下游買入, 相反相成
    switch  # 凡此 when 順序皆不可隨意變更
      when buoySwim.preferSelling then @pickSell(buoySwim)
      when buoySwim.preferBuying then @pickBuy(buoySwim)
      else throw "wrong swim #{buoySwim}"

  @pickBuy: (buoySwim)->
    {contractHelper:{contract}} = buoySwim
    switch  # 凡此 when 順序皆不可隨意變更
      when contract.secType is 'OPT'
        new OPTBuyBuoy({buoySwim})
      when contract.secType is 'IOPT'
        new HKIOPTBuyBuoy({buoySwim})
      else
        new BuyBuoy({buoySwim})

  @pickSell:(buoySwim)->
    {contractHelper:{contract}} = buoySwim
    switch  # 凡此 when 順序皆不可隨意變更
      when contract.secType is 'OPT'
        new OPTSellBuoy({buoySwim})
      when contract.secType is 'IOPT'
        new HKIOPTSellBuoy({buoySwim})
      else
        new SellBuoy({buoySwim})

  # ------------------------------ 以上均為class functions ----------------------------

class BuoyFlowByPrice extends BuoyFlowBase

  # BuoyFlowByPrice
  _forwardPrice: (pool) ->
    return @bar.close
    

  ###

    @_$ConfirmActionTriggerPrice 充當 
  
      1. 重新檢測 @_confirmActionTriggerPrice function 的開關
          因折返交易策略,在折返前後,以上 function 檢測結果是相反的,故此時不可重新檢測
          但發送了 _detectEntryPoint 通過檢測之後,即應恢復此變量,以便下一輪開始重新檢測各項價格關係
  
      2. 繼續檢測其他價格關係的前提
  
  ###
  interruptible: ->
    # 此變量三種狀態:
    # 1. null 說明尚未檢測,不妨以新換舊 2. false 檢測不符合,繼續檢測不要中斷 3. true 通過檢測,觸發"伺機交易"
    return not  @_$ConfirmActionTriggerPrice?

    # 本想在導入歷史 bar 的時候,就先更新 buoy, 記錄下盤前應有的買賣狀態,但試過不行,不知何處有誤,buoy 始終是開盤後新生的
    switch
      when @hostSwim?.size then false  
      when @_$ConfirmActionTriggerPrice? then false
      else true


  _detectEntryPoint:(pool)->
    switch
      when @_detectEntryPointByPrice(pool)
        @_$ConfirmActionTriggerPrice = null  # 必須是 null 不能用 false, 以便用 ?= 判斷是否需要重新運行檢測 _confirmActionTriggerPrice
        @_outermostIn = null  # 此變量用於記錄行情折返路徑,濾除非折返性質的噪音,以免買賣於剛展開不久.思路不周全,暫用
        @actionPrice = null   #+++ 嘗試新增此行,以觀察能否正確更新
        _assert.log({info:'_detectEntryPoint reset @_$ConfirmActionTriggerPrice', @_$ConfirmActionTriggerPrice})
        true
      when @_detectEntryPointByVariance(pool)
        true
      else false




  _detectEntryPointByPrice:(pool)->
    # 先後順序不可改動
    @_checkOutermostIn() # 避免低位盤整區賣出.此設計思路不周全,在想出更好的方法前暫用
    @hitPriceFinal(pool) or @hitPriceAgent(pool)   




  # 指標背離
  _detectEntryPointByVariance: (pool) ->
    false



  # 此法捕捉有策略價值的穿刺點.可將各種策略揀擇置於此法
  _strategyFilter:(pool)->
    super(pool)



  emitEntry:(pool, msg=@buoyMessage)->
    # 暫時沿用之前的發佈方式和內容
    super(pool,msg)



  # 純粹研究開發工具,非交易所需
  tableThisBuoy: (pool) ->
    display ={
      @suggestedTradePrice  # suggestedTradePrice 變量單純傳價,不要用於任何其他用途,不要以其是否存在作為任何判斷的前提條件
      @buoyName
      #@size
      bestPrice: @_bestPrice(pool)
      worstPrice: @_worstPrice(pool)
      @betterPrice
      @touchPrice
      actionPrice: @_actionPrice(pool)
    }
    o = {} 
    o[k] = v for k, v of display when v?
    o.close = @bar.close
    console.table([o])




  ### 
    注意: 
      
      suggestedTradePrice 變量單純傳價,不要用於任何其他用途,不要以其是否存在作為任何判斷的前提條件
      例如:
        不要用於判斷是否符合發出信號條件等等

  ### 
  _atPriceNow:(pool)->
    {close} = @bar
    
    @_$IsTime = (pool.poolOptions.paperTrading and @contract.isIOPT()) or @isTime(pool)

    switch # 凡此 when 順序皆不可隨意變更
      # 首次確認之後,就不再重複確認,因等待折返, _priceShiftForward 之後適合交易的價格將不再滿足確認條件   
      when not @_confirmActionTriggerPrice(pool, @_actionPrice(pool))
        #_assert.log({debug:'_atPriceNow', @_$ConfirmActionTriggerPrice, close})
        false
      
      # 不要提前到上一句之前,不要改變順序
      when @stopLoss() and @stopLossFirst  # 即刻止損,不等價格折返
        _assert.log({debug:'_atPriceNow',info:'stop loss', @cost, @suggestedTradePrice})
        @_setPriceAndReturnTrue(pool)

      when @priceForward and not @_priceShiftForward(pool)  # 若非 @priceForward 則此 when 通過,即回到破位追隨的舊模式
        #_assert.log({debug:'not _priceShiftForward', close})
        false
      when not @_$IsTime
        _assert.log({debug:'_atPriceNow', @_$IsTime, close})        
        false

      # 不要設法提前,不要改變順序
      else
        @_setPriceAndReturnTrue(pool)



  # 僅為兼容舊代碼,新代碼見 ~ByBand 部分
  _actionPrice: (pool) ->
    @actionPrice




  _setPriceAndReturnTrue:(pool)->
    @suggestedTradePrice = @_forwardPrice(pool)  # suggestedTradePrice 變量單純傳價,不要用於任何其他用途,不要以其是否存在作為任何判斷的前提條件
    @tableThisBuoy(pool)
    return true




  hitPriceFinal:(pool) ->
    if (not @betterPrice) and @touchPrice and @_atPriceNow(pool) # 不加問號, 為0 則 false
      # 先後順序不可改動!!
      @followBetterPrice(pool) or @followTouchPrice(pool)  #+++ 新增此行以便持續更新,但須觀察是否與其他代碼衝突
      true
    else
      false

  # 原始設計永遠 return false;後來機制損壞,改為就地成交
  hitPriceAgent:(pool)->
    if @betterPrice and @_atPriceNow(pool) # 不加問號, 為0 則 false
      # 先後順序不可改動!!
      @followBetterPrice(pool) or @followTouchPrice(pool)  #+++ 新增此行以便持續更新,但須觀察是否與其他代碼衝突
      return true
    else
      # 先後順序不可改動!!
      @followBetterPrice(pool) or @followTouchPrice(pool)
      return false # 原始設計永遠 return false;後來機制損壞,改為就地成交


  #BuoyFlowByPrice
  # return @betterPrice 數字, 以便作後續邏輯判斷, 若不存在則進一步 follow touch price
  # 此功能在價格變動達到預定幅度之後起作用,會跟蹤每一個更好的價位,但是僅對有預定跨度的變動作出反應,推進行動警戒線
  # 此法的用途是過濾掉紊波,忽略"細小"的波動,其幅度由isBetterPrice來定義
  followBetterPrice: (pool)->
    switch 
      when @isBetterPrice()
        @touchPrice = null
        @betterPrice = @bar.close
        @resetActionPrice(pool, @betterSuggestedActionPrice(pool))
      when @betterPrice and not @actionPrice   # 不加問號, 為0 則 false
        @resetActionPrice(pool, @betterSuggestedActionPrice(pool))
    return @betterPrice    #等同 @betterPrice isnt 0 and not isNaN(@betterPrice)


  #BuoyFlowByPrice
  followTouchPrice: (pool)->
    if @betterPrice  # 不加問號, 為 0 亦答 false
      return
    switch
      when @isTouchPrice()
        @touchPrice = @bar.close
        # 根據報價因子/差價,略作緩衝:
        @resetActionPrice(pool, @touchSuggestedActionPrice(pool))
      when @touchPrice and not @actionPrice  # 不加問號, 為 0 亦答 false
        @resetActionPrice(pool, @touchSuggestedActionPrice(pool))



  resetActionPrice:(pool, suggestedActionPrice)->
    if suggestedActionPrice isnt @actionPrice
      @actionPrice = suggestedActionPrice




  #BuoyFlowByPrice
  # 用於設置收盤前 n 分鐘 (@finalMinutes) 才開始監控及操作的特殊情形
  isTime: (pool) ->
    return (@finalMinutes is 0) or IBCode.marketWillCloseIn({@finalMinutes, @contract})


  copyWithout:(keys)->
    o = {}
    for key, value of this when not (key in keys)
      o[key] = value
    return o



  



# 在此再增加一層,根據布林線5條線進行優化
# 設計文檔: md_branch/buoy02.md.coffee
class BuoyFlowByBband extends BuoyFlowByPrice

  ### 
  新版可採用統一建議執行價
    注意: 
      此價運用之前,先檢測成本價,以便屏蔽此價,執行止盈止損操作  
  ###
  _monoSuggestedActionPrice: (pool) ->
    @bar[pool.bband.maName]













# 緩衝層,可以選擇 extends 之層次
class BuoyFlow extends BuoyFlowByBband








# base 亦可以直接使用,但用子法可靈活擴充功能
# ---------------------------------- Base ---------------------------------------


class BuyBuoyByPrice extends BuoyFlow

  constructor:({buoySwim,@finalMinutes=0})->
    super({buoySwim,@finalMinutes})  
    @actionType = 'buy'

  


  fitSignal:(signal)->
    signal?.isBuySignal



  # BuyBuoyByPrice
  _bestPrice: (pool) ->
    bp = @_bareBestPrice(pool)
    unless @cost
      bp
    else
      Math.min(bp,@contractHelper.向下容忍價(@cost))



  # BuyBuoyByPrice
  # 僅根據行情
  _bareBestPrice: (pool) ->
    @contractHelper.向下報價(@bar.closeLowBand)




  # BuyBuoyByPrice
  _worstPrice: (pool) ->
    wp = @_bareWorstPrice(pool) 
    unless @cost
      wp
    else
      Math.max(wp, @contractHelper.向上極限價(@cost))



  # BuyBuoyByPrice
  # 僅根據行情
  _bareWorstPrice: (pool) ->
    @bar.closeHighBand




  # BuyBuoyByPrice
  ### 
    此時須設置 actionPrice 為小於等於 @cost
  ### 
  _costPriceChanged: (pool) ->
    super()
    switch
      when not (@bar? and @contractHelper.secPosition.hasShortPosition())
        this
      when @_losslessActionPrice()
        this
      else
        if @cost
          # 若現價高於 cost 將導致立即交易止損
          @actionPrice = @cost
          _assert.log({debug: 'resetActionPrice', @actionPrice, @cost})


  
  _losslessActionPrice: (pool) ->
    @cost and @actionPrice and @actionPrice <= @cost

  
  
  # BuyBuoyByPrice
  _coveringPrice:(pool)->
    @_bestPrice(pool) <= @bar.close <= @_worstPrice(pool)



  # BuyBuoyByPrice
  _confirmActionTriggerPrice:(pool, triggerPrice)->
    {high} = @bar  # 由於系統可能接收到的是間隔數據,在收到數據並分析前,可能已經沖高回落,故用high
    
    @_$RightTriggerPrice = high >= triggerPrice  # 本行僅僅用於開發時程序檢測

    # 首次確認之後,就不再重複確認,因等待折返, _priceShiftForward 之後適合交易的價格將不再滿足確認條件       
    if @_$ConfirmActionTriggerPrice
      return true

    noMoreLog = @_$ConfirmActionTriggerPrice? # 檢測是否存在. 若原本不存在,則下文 log,否則不重複
    @_$ConfirmActionTriggerPrice = @_worstPrice(pool) > high > triggerPrice
    unless noMoreLog then _assert.log({
      info: '_confirmActionTriggerPrice', 
      at: @constructor.name, 
      state: '...伺機買入...'
      time: @bar.lday()
    })
    return @_$ConfirmActionTriggerPrice
    



  # BuyBuoyByPrice
  _priceShiftForward: (pool) ->
    @_priceShiftForwardByPrice(pool)




  _priceShiftForwardByPrice: (pool) -> 
    unless @priceForward   # 若非 @priceForward 則通過,即回到破位追隨的舊模式,自帶此行以免誤用
      _assert.log({info:'_priceShiftForward approved since profitable', @cost})
      return @_profitable()

    {low,bax} = @bar # 由於系統可能接收到的是間隔數據,在收到數據並分析前,可能已經反抽
    switch  # 凡此 when 順序皆不可隨意變更
      # 標記交易點之後,就不再跟蹤關鍵價位,而僅用原先價位判斷是否時機成熟
      when low < @actionPrice <= @betterPrice then true
      when low < @actionPrice <= @touchPrice and not @betterPrice then true
      #when low <= @betterPrice then true
      #when low <= @touchPrice and not @betterPrice then true
      # 以下兩條尚不嚴謹,待增加 and 過濾條件
      when low is bax then true
      when @bar.lowBelowLine('closeLowBandB') then true
      else false 





  # BuyBuoyByPrice
  isBetterPrice: (pool) ->
    @bar.close < (@betterPrice ? @firstBetterPrice())



  firstBetterPrice: (pool) ->
    @contractHelper.向下容忍價(@_worstPrice(pool))



  # BuyBuoyByPrice
  isTouchPrice: (pool) ->
    @bar.close < (@touchPrice ? @_worstPrice(pool))
  


  # BuyBuoyByPrice
  betterSuggestedActionPrice: (pool) ->
    aprice = @_gradeBetterPrice(pool)
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      when @cost and @_profitable()  # @cost and 必須要有; 不加問號, 為0 則 false
        Math.min(aprice, @cost) 
      else
        aprice




  # BuyBuoyByPrice
  _gradeBetterPrice: (pool) ->
    p = goldenPoint(@betterPrice, Math.min(@_upPrice(),@contractHelper.向上容忍價(@betterPrice)), farther)
    # 一旦 < @betterPrice 則意味著人為滿足交易條件,即刻發生交易,故不可
    Math.max(p, @contractHelper.向上報價(@betterPrice))



  # BuyBuoyByPrice
  touchSuggestedActionPrice: (pool) ->
    aprice = @_gradeTouchPrice(pool)
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      when @cost and @_profitable()   # @cost 不加問號, 為0 則 false
        Math.min(aprice, @cost) 
      when @actionPrice  # 不加問號, 為 0 亦答 false
        aprice
      else 
        @_oneGradeUpPrice



  # BuyBuoyByPrice
  _gradeTouchPrice: (pool) ->
    p = goldenPoint(@touchPrice, Math.min(@_upPrice(), @contractHelper.向上報價(@touchPrice)), farther)
    # 一旦 < @touchPrice 則意味著人為滿足交易條件,即刻發生交易,故不可
    Math.max(p, @contractHelper.向上報價(@touchPrice))



  _profitable: ->
    switch
      when @cost then @contractHelper.hasEarningShortPosition()
      else true



  helpRecordChartSig:(obj)->
    @bar.chartBuySig = obj









class SellBuoyByPrice extends BuoyFlow
  constructor:({buoySwim,@finalMinutes=0})->
    super({buoySwim,@finalMinutes})  
    @actionType = 'sell'




  fitSignal:(signal)->
    signal?.isSellSignal



  # SellBuoyByPrice
  _bestPrice: (pool) ->
    bp = @_bareBestPrice(pool)
    unless @cost
      bp
    else
      Math.max(bp, @contractHelper.向上容忍價(@cost))



  # SellBuoyByPrice
  _bareBestPrice: (pool) ->
    @contractHelper.向上報價(@bar.closeHighBand)



  # SellBuoyByPrice
  _worstPrice: (pool) ->
    wp = @_bareWorstPrice(pool)
    unless @cost
      wp
    else
      Math.min(wp,@contractHelper.向下極限價(@cost))




  # SellBuoyByPrice
  _bareWorstPrice: (pool) ->
    @bar.closeLowBandB



  ### 
    此時須設置 actionPrice 為高於等於 @cost
  ###
  _costPriceChanged: (pool) ->
    super()
    @_setActionPriceReferringCost(pool)



  _setActionPriceReferringCost:(pool)->
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      when not (@bar? and @contractHelper.secPosition.hasLongPosition())
        this
      when @_losslessActionPrice()
        this
      else 
        if @cost
          # 此時,經過以上兩個條件篩選,必然符合 @actionPrice < @cost, 故須更改
          # 若現價低於 cost 將導致立即交易止損
          @actionPrice = @cost
          _assert.log({debug:'_costPriceChanged', @actionPrice, @cost})



  _losslessActionPrice: (pool) ->
    @cost and @actionPrice and @actionPrice >= @cost  # 不加問號, 為0 則 false



  # SellBuoyByPrice
  _coveringPrice:(pool)->
    @_bestPrice(pool) >= @bar.close >= @_worstPrice(pool)



  # SellBuoyByPrice
  # 以下兩個互有增減,其實一回事,用在兩個function內,將來設法合併,以免費解
  _confirmActionTriggerPrice:(pool, triggerPrice)->
    {low} = @bar  # 由於系統可能接收到的是間隔數據,在收到數據並分析前,可能已經反抽

    @_$RightTriggerPrice = triggerPrice >= low # 本行僅僅用於程序開發時自我檢測
    # 首次確認之後,就不再重複確認,因等待折返, _priceShiftForward 之後適合交易的價格將不再滿足確認條件           
    if @_$ConfirmActionTriggerPrice
      return true
      
    noMoreLog = @_$ConfirmActionTriggerPrice? # 檢測是否存在,僅當原本不存在時,下文才需要log
    @_$ConfirmActionTriggerPrice = triggerPrice > low > @_worstPrice(pool)
    unless noMoreLog then _assert.log({
      info: '_confirmActionTriggerPrice', 
      at: @constructor.name, 
      state: '...伺機賣出...'
      time: @bar.lday()
    })
    return @_$ConfirmActionTriggerPrice
    
    ### 為提示追蹤狀態故這樣寫:
    if @_$ConfirmActionTriggerPrice?
      return @_$ConfirmActionTriggerPrice
    else
      @_$ConfirmActionTriggerPrice = triggerPrice >= low > @_worstPrice(pool)  # 檢測時價格或已折返,故用 low
      if @_$ConfirmActionTriggerPrice then _assert.log({info:'_confirmActionTriggerPrice', at:@constructor.name, state:'...伺機賣出...'})
      return @_$ConfirmActionTriggerPrice
    ###



  # SellBuoyByPrice
  _priceShiftForward: (pool) ->
    @_priceShiftForwardByPrice(pool)



  _priceShiftForwardByPrice: (pool) ->
    unless @priceForward   # 若非 @priceForward 則通過,即回到破位追隨的舊模式,自帶此行以免誤用
      _assert.log({info:'_priceShiftForward approved since profitable', @cost, @actionPrice})
      return @_profitable() 

    {high} = @bar # 由於系統可能接收到的是間隔數據,在收到數據並分析前,可能已經反抽
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      # 標記交易點之後,就不再跟蹤關鍵價位,而僅用原先價位判斷是否時機成熟    
      when high > @actionPrice >= @betterPrice then true   #when high >= @betterPrice then true
      when high > @actionPrice >= @touchPrice and not @betterPrice then true   #when high >= @touchPrice and not @betterPrice then true
      when @bar.highUponLine('bbta') then true
      else false




  # SellBuoyByPrice
  isTouchPrice: (pool) ->
    @bar.close > (@touchPrice ? @_worstPrice(pool))



  # SellBuoyByPrice
  isBetterPrice: (pool) ->
    @bar.close > (@betterPrice ? @firstBetterPrice())



  firstBetterPrice: (pool) ->
    @contractHelper.向上容忍價(@_worstPrice(pool))



  # SellBuoyByPrice
  betterSuggestedActionPrice: (pool) ->
    aprice = @_gradeBetterPrice(pool)
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      #若有多頭倉位,成本低於現價,多頭尚有盈利
      when @cost and @_profitable()  # @cost 必須要有,不可去掉; 不加問號, 為0 則 false
        Math.max(aprice, @cost)
      else
        aprice



  # SellBuoyByPrice
  _gradeBetterPrice: (pool) ->
    p = goldenPoint(@betterPrice, Math.max(@_downPrice(), @contractHelper.向下容忍價(@betterPrice)), farther)
    # 一旦 > @betterPrice 則意味著人為滿足交易條件,即刻發生交易,故不可    
    Math.min(p, @contractHelper.向下報價(@betterPrice))



  # SellBuoyByPrice
  touchSuggestedActionPrice: (pool) ->
    aprice = @_gradeTouchPrice(pool)
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      #若有多頭倉位,成本低於現價,多頭尚有盈利
      when @cost and @_profitable()  # @cost 不加問號, 為0 則 false
        Math.max(aprice, @cost)
      when @actionPrice  # 不加問號, 為 0 亦答 false
        aprice
      else
        @_downPrice()
  


  _gradeTouchPrice: (pool) ->
    p = goldenPoint(@touchPrice, Math.max(@_downPrice(), @contractHelper.向下報價(@touchPrice)),farther)
    # 一旦 > @touchPrice 則意味著人為滿足交易條件,即刻發生交易,故不可    
    Math.min(p, @contractHelper.向下報價(@touchPrice))




  _profitable: ->
    switch
      when @cost then @contractHelper.hasEarningLongPosition()
      else true



  helpRecordChartSig:(obj)->
    @bar.chartSellSig = obj



 





# ---------------------------------   OPTs   ---------------------------------
# 可選 extends BuyBuoyByPrice
class OPTBuyBuoy extends BuyBuoyByPrice








# 可選 extends SellBuoyByPrice
class OPTSellBuoy extends SellBuoyByPrice

 







# ---------------------------------   hk iopt   ---------------------------------
# [todo] iopt 大部分參數之容忍差價宜以priceGrade替換?


# 第一輪修改僅僅作簡單替換,不深究理路. 其中排除 iopt 各句均保留備考
# 由於牛熊證的特點,有可能需要將基於比率的系統,改為基於差額的系統,故先全部複製,然後逐步嘗試更改
# 牛熊證單向做多,此法對應於多頭開倉操作
#class HKIOPTBuyBuoy extends BuyBuoyByPrice
class HKIOPTBuyBuoy extends BuyBuoyByPrice
  
  # 牛熊證僅能做多,故買入即是新開倉,賣出即是平倉.開盤5分鐘內不得新開倉
  isTime: (pool) ->
    mmnt = moment().tz('Asia/Shanghai')
    hour = mmnt.hour()
    minute = mmnt.minute() 
    switch
      when ioptBuyEndTime > hour > 9 then true 
      when hour is 9 and minute > 30 then true
      when testingIOPT then true
      else false





# 由於牛熊證的特點,有可能需要將基於比率的系統,改為基於差額的系統,故先全部複製,然後逐步嘗試更改
# 牛熊證單向做多,故此對應於平倉操作    
#class HKIOPTSellBuoy extends SellBuoyByPrice
class HKIOPTSellBuoy extends SellBuoyByPrice
    





# --------------------------------- normal security  ---------------------------------
# 可在此定制特殊程序
class BuyBuoy extends BuyBuoyByPrice



class SellBuoy extends SellBuoyByPrice









module.exports = BuoyFlowPicker



### 思路探討
# 折返成交機制: 
#   價格可以再考慮
#   優點: 價格更優
#   缺點: 可能錯過,無法成交
# 兩種情況:  
#   1. 正常情況,已經有 betterPrice 出現 
#   2. 緊急情況,已經穿過 actionPrice,無論怎樣也要委託;
###