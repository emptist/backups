# New Grade Based Buoy System
# 舊注釋詳見文末

moment = require 'moment-timezone'
BaseDataFlow = require './dataflow_base'
{IBCode} = require './secode'
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
      when buoySwim.isUpward() then @pickSell(buoySwim)
      when buoySwim.isDownward() then @pickBuy(buoySwim)
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

class BuoyFlow extends BuoyFlowBase

  # BuoyFlow
  _backwardPrice:()->
    if @priceBackward
      fix(0.8618*@bar.close + 0.1382*@actionPrice)  
    else
      @bar.close
      #@actionPrice 絕對不可以,因為很可能是很遠的止損線,目前已經無此價位 



  _detectEntryPoint:(pool)->
    # 先後順序不可改動
    @hitPriceFinal(pool) or @hitPriceAgent(pool)   



  # 此法捕捉有策略價值的穿刺點.可將各種策略揀擇置於此法
  _strategyFilter:(pool)->
    super(pool)



  emitEntry:(pool, msg=@buoyMessage)->
    # 暫時沿用之前的發佈方式和內容
    super(pool,msg)



  # 純粹研究開發工具,非交易所需
  tableThisBuoy: ->
    display ={
      @tradePrice
      @buoyName
      #@size
      basePrice: @_basePrice()
      bestPrice: @_bestPrice()
      worstPrice: @_worstPrice()
      @betterPrice
      @touchPrice
      @actionPrice
    }
    o = {} 
    o[k] = v for k, v of display when v?
    o.close = @bar.close
    console.table([o])



  atPriceNow:(pool)->
    {close} = @bar
    @_$IsTime = @isTime()
    switch # 凡此 when 順序皆不可隨意變更   
      when not @_confirmTrigger(@actionPrice) then false
      when not @_priceShiftBackward() then false
      when not @_$IsTime then false
      else
        # @priceBackward 即等待落入價格區間之後又略微回頭,此時即刻發出以前一價位交易的指令
        # 如此設計之後,此@tradePrice不需要再改動,也不需要等待更好價位才發送交易指令
        @tradePrice = @_backwardPrice()
        @tableThisBuoy()
        #_assert.log("#{@contractHelper.secCode}: #{@constructor.name} #{@buoyName} 觸發交易")
        return true


  hitPriceFinal:(pool) ->
    if (not @betterPrice) and @actionPrice and @touchPrice and @atPriceNow(pool) # 不加問號, 為0 則 false
      true
    else
      false

  # 原始設計永遠 return false;後來機制損壞,改為就地成交
  hitPriceAgent:(pool)->
    # @betterActionPrice() 已經不必要? 總是耽誤操作
    #if @betterPrice and @actionPrice and @atPriceNow(pool) and @betterAction(pool) # 不加問號, 為0 則 false
    if @betterPrice and @actionPrice and @atPriceNow(pool) # 不加問號, 為0 則 false
      return true
    else
      # 先後順序不可改動!!
      @followBetterPrice(pool) or @followTouchPrice(pool)
      return false # 原始設計永遠 return false;後來機制損壞,改為就地成交
    
  #BuoyFlow
  # return @betterPrice 數字, 以便作後續邏輯判斷, 若不存在則進一步 follow touch price
  # 此功能在價格變動達到預定幅度之後起作用,會跟蹤每一個更好的價位,但是僅對有預定跨度的變動作出反應,推進行動警戒線
  # 此法的用途是過濾掉紊波,忽略"細小"的波動,其幅度由isBetterPrice來定義
  followBetterPrice: (pool)->
    switch 
      when @isBetterPrice()
        @touchPrice = null
        @betterPrice = @bar.close
        @resetActionPrice(pool, @betterSuggestedActionPrice())
      when @betterPrice and not @actionPrice   # 不加問號, 為0 則 false
        @resetActionPrice(pool, @betterSuggestedActionPrice())
    return @betterPrice    #等同 @betterPrice isnt 0 and not isNaN(@betterPrice)


  #BuoyFlow
  followTouchPrice: (pool)->
    if @betterPrice  # 不加問號, 為 0 亦答 false
      return
    switch
      when @isTouchPrice()
        @touchPrice = @bar.close
        # 根據報價因子/差價,略作緩衝:
        @resetActionPrice(pool, @touchSuggestedActionPrice())
      when @touchPrice and not @actionPrice  # 不加問號, 為 0 亦答 false
        @resetActionPrice(pool, @touchSuggestedActionPrice())



  resetActionPrice:(pool, suggestedActionPrice)->
    if suggestedActionPrice isnt @actionPrice
      #_assert.log({debug: 'resetActionPrice',@actionPrice,suggestedActionPrice})
      @actionPrice = suggestedActionPrice
      @tableThisBuoy() 




  #BuoyFlow
  # 用於設置收盤前 n 分鐘 (@finalMinutes) 才開始監控及操作的特殊情形
  isTime:->
    return (@finalMinutes is 0) or IBCode.marketWillCloseIn({@finalMinutes, @contract})


  copyWithout:(keys)->
    o = {}
    for key, value of this when not (key in keys)
      o[key] = value
    return o



  





# base 亦可以直接使用,但用子法可靈活擴充功能
# ---------------------------------- Base ---------------------------------------


# 系統禁止做空,故此即開倉 open long position
class BuyBuoyBase extends BuoyFlow

  constructor:({@buoySwim,@finalMinutes=0})->
    super({@buoySwim,@finalMinutes})  
    @actionType = 'buy'



  # BuyBuoyBase
  _bestPrice:->
    bp = @_downPrice()
    unless @cost
      bp
    else
      Math.min(bp,@contractHelper.向下容忍價(@cost))

    #按照舊代碼直譯(但覺得欠妥故已改):
    #Math.min(@_downPrice(),@contractHelper.向下報價(@cost ? @actionPrice))



  # BuyBuoyBase
  _worstPrice:->
    wp = @bar.closeHighBand 
    unless @cost
      wp
    else
      Math.max(wp, @contractHelper.向上極限價(@cost))

    #按照舊代碼直譯(但覺得欠妥故已改):
    #Math.max(@_upPrice(), @contractHelper.向上極限價(@cost ? @actionPrice))








  # BuyBuoyBase
  ### 
    此時須設置 actionPrice 為小於等於 @cost
  ### 
  _costPriceChanged:->
    super()
    switch
      when not (@bar? and @contractHelper.secPosition.hasShortPosition()) then this
      when @actionPrice and @actionPrice <= @cost then this
      else
        if @cost
          # 此時,經過以上兩個條件篩選,必然符合 @actionPrice > @cost, 故須更改
          # 若現價高於 cost 將導致立即交易止損
          #_assert.log({debug:'_costPriceChanged',@actionType,@actionPrice,@cost})
          @actionPrice = @cost
          @tableThisBuoy()



  # BuyBuoyBase
  _coveringPrice:->
    @_bestPrice() <= @bar.close <= @_worstPrice()



  # BuyBuoyBase
  _confirmTrigger:(triggerPrice)->
    {close} = @bar
    @_$RightTriggerPrice = close >= triggerPrice
    @_$ConfirmTriggerPrice = @_worstPrice() > close >= triggerPrice
    switch
      when @_$ConfirmTriggerPrice then true
      else false



  # BuyBuoyBase
  _priceShiftBackward: -> 
    {close} = @bar
    switch  # 凡此 when 順序皆不可隨意變更
      when @priceBackward
        @_$FitLastPrice = (close <= @lastBar?.close) or (close <= @previousBar?.close) 
      else
        true 



  # BuyBuoyBase
  betterAction:(pool)->
    #@actionPrice > @betterPrice
    @actionPrice >= @betterPrice


  # BuyBuoyBase
  isBetterPrice: ->
    @bar.close < (@betterPrice ? @firstBetterPrice())



  firstBetterPrice:->
    @contractHelper.向下容忍價(@_worstPrice())



  # BuyBuoyBase
  isTouchPrice: ->
    @bar.close < (@touchPrice ? @_worstPrice())
  


  # BuyBuoyBase
  betterSuggestedActionPrice: ->
    aprice = @_gradeBetterPrice()
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      when @contractHelper.secPosition.hasShortPosition() and @cost and @bar?.close < @cost  # @cost 不加問號, 為0 則 false
        Math.min(aprice, @cost) 
      else
        aprice




  # BuyBuoyBase
  _gradeBetterPrice:->
    
    p = goldenPoint(@betterPrice, Math.min(@_upPrice(),@contractHelper.向上容忍價(@betterPrice)), farther)
    # 一旦 < @betterPrice 則意味著人為滿足交易條件,即刻發生交易,故不可
    Math.max(p, @contractHelper.向上報價(@betterPrice))



  # BuyBuoyBase
  touchSuggestedActionPrice: ->
    aprice = @_gradeTouchPrice()
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      when @contractHelper.secPosition.hasShortPosition() and @cost and @bar?.close < @cost   # @cost 不加問號, 為0 則 false
        Math.min(aprice, @cost) 
      when @actionPrice  # 不加問號, 為 0 亦答 false
        aprice
      else 
        @_oneGradeUpPrice



  # BuyBuoyBase
  _gradeTouchPrice:->
    
    p = goldenPoint(@touchPrice, Math.min(@_upPrice(), @contractHelper.向上報價(@touchPrice)), farther)
    # 一旦 < @touchPrice 則意味著人為滿足交易條件,即刻發生交易,故不可
    Math.max(p, @contractHelper.向上報價(@touchPrice))






  helpRecordChartSig:(obj)->
    @bar.chartBuySig = obj









# 系統禁止做空,故此即平倉 close long position
class SellBuoyBase extends BuoyFlow
  constructor:({@buoySwim,@finalMinutes=0})->
    super({@buoySwim,@finalMinutes})  
    @actionType = 'sell'

  


  # SellBuoyBase
  _bestPrice:->
    # 因系統禁止做空,故此賣出即專指平倉也,故價格上限為上半軌,軌道之上則考慮持倉
    bp = @_upPrice()
    unless @cost
      bp
    else
      Math.max(bp, @contractHelper.向上容忍價(@cost))

    #按照舊代碼直譯(但覺得欠妥故已改):
    #Math.max(@_upPrice(), @contractHelper.向上報價(@cost ? @actionPrice))


  
  # SellBuoyBase
  _worstPrice:->
    wp = @bar.closeLowHalfBand
    unless @cost
      wp
    else
      Math.min(wp,@contractHelper.向下極限價(@cost))

    #按照舊代碼直譯(但覺得欠妥故已改):
    #Math.min(@_downPrice(),@contractHelper.向下極限價(@cost ? @actionPrice))






  ### 
    此時須設置 actionPrice 為高於等於 @cost
  ###
  _costPriceChanged:->
    super()
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      when not (@bar? and @contractHelper.secPosition.hasLongPosition())
        this
      when @actionPrice and @actionPrice >= @cost  # 不加問號, 為0 則 false
        this
      else 
        if @cost
          # 此時,經過以上兩個條件篩選,必然符合 @actionPrice < @cost, 故須更改
          # 若現價低於 cost 將導致立即交易止損
          #_assert.log({debug:'_costPriceChanged',@actionType,@actionPrice,@cost})
          @actionPrice = @cost
          @tableThisBuoy()



  # SellBuoyBase
  _coveringPrice:->
    @_bestPrice() >= @bar.close >= @_worstPrice()



  # SellBuoyBase
  # 以下兩個互有增減,其實一回事,用在兩個function內,將來設法合併,以免費解
  _confirmTrigger:(triggerPrice)->
    {close} = @bar
    @_$RightTriggerPrice = triggerPrice >= close
    @_$ConfirmTriggerPrice = triggerPrice >= close > @_worstPrice()
    switch
      when @_$ConfirmTriggerPrice then true
      else false 



  # SellBuoyBase
  _priceShiftBackward: ->
    {close} = @bar
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      when @priceBackward
        @_$FitLastPrice = (close >= @lastBar?.close) or (close >= @previousBar?.close)
      else
        true 
        #@_$FitLastPrice = close <= @lastBar?.close




  # SellBuoyBase
  betterAction:(pool)->
    #@actionPrice < @betterPrice
    @actionPrice <= @betterPrice



  # SellBuoyBase
  isTouchPrice: ->
    @bar.close > (@touchPrice ? @_worstPrice())



  # SellBuoyBase
  isBetterPrice: ->
    @bar.close > (@betterPrice ? @firstBetterPrice())



  firstBetterPrice:->
    @contractHelper.向上容忍價(@_worstPrice())



  # SellBuoyBase
  betterSuggestedActionPrice: ->
    aprice = @_gradeBetterPrice()
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      #若有多頭倉位,成本低於現價,多頭尚有盈利
      when @contractHelper.secPosition.hasLongPosition() and @cost and @bar?.close > @cost  # @cost 不加問號, 為0 則 false
        Math.max(aprice, @cost)
      else
        aprice



  # SellBuoyBase
  _gradeBetterPrice:->
    
    p = goldenPoint(@betterPrice, Math.max(@_downPrice(), @contractHelper.向下容忍價(@betterPrice)), farther)
    # 一旦 > @betterPrice 則意味著人為滿足交易條件,即刻發生交易,故不可    
    Math.min(p, @contractHelper.向下報價(@betterPrice))


  # SellBuoyBase
  touchSuggestedActionPrice: ->
    aprice = @_gradeTouchPrice()
    switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      #若有多頭倉位,成本低於現價,多頭尚有盈利
      when @contractHelper.secPosition.hasLongPosition() and @cost and @bar?.close > @cost  # @cost 不加問號, 為0 則 false
        Math.max(aprice, @cost)
      when @actionPrice  # 不加問號, 為 0 亦答 false
        aprice
      else
        @_downPrice()
  


  _gradeTouchPrice:->
    
    p = goldenPoint(@touchPrice, Math.max(@_downPrice(), @contractHelper.向下報價(@touchPrice)),farther)
    # 一旦 > @touchPrice 則意味著人為滿足交易條件,即刻發生交易,故不可    
    Math.min(p, @contractHelper.向下報價(@touchPrice))







  helpRecordChartSig:(obj)->
    @bar.chartSellSig = obj



 




# ---------------------------------   OPTs   ---------------------------------
class OPTBuyBuoy extends BuyBuoyBase

  _backwardPrice:()->
    # 務必成交,否則損失很大
    @contractHelper.略向上報價(@bar.close)


class OPTSellBuoy extends SellBuoyBase

  _backwardPrice:()->
    # 務必成交,否則損失很大
    @contractHelper.略向下報價(@bar.close)








# ---------------------------------   hk iopt   ---------------------------------
# [todo] iopt 大部分參數之容忍差價宜以priceGrade替換?


# 第一輪修改僅僅作簡單替換,不深究理路. 其中排除 iopt 各句均保留備考
# 由於牛熊證的特點,有可能需要將基於比率的系統,改為基於差額的系統,故先全部複製,然後逐步嘗試更改
# 牛熊證單向做多,此法對應於多頭開倉操作
class HKIOPTBuyBuoyBase extends BuyBuoyBase

  
  # 牛熊證僅能做多,故買入即是新開倉,賣出即是平倉.開盤5分鐘內不得新開倉
  isTime: ->
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
class HKIOPTSellBuoyBase extends SellBuoyBase



class HKIOPTBuyBuoy extends HKIOPTBuyBuoyBase

  




class HKIOPTSellBuoy extends HKIOPTSellBuoyBase

  _backwardPrice:()->
    # 務必成交,否則損失很大
    @contractHelper.向下報價(@bar.close)
    





# --------------------------------- normal security  ---------------------------------
# 可在此定制特殊程序
class BuyBuoy extends BuyBuoyBase



class SellBuoy extends SellBuoyBase









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