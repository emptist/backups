util = require 'util'
say = require 'say'
{IBCode} = require './secode'
{speakout} = require './config'

# 原則: 寧可不賺,不可虧本

# Buoy 浮標,標記動態價格區間
#   由於這是object,所以可以靈活設計變量以輔助策略實施.
#   可在每次查證信號是否滿足發佈條件時,記錄有意義的價格.結合指令激發價隨觸發時價格變動,確定bor回昇或衝高回落時才買賣.
#   這一塊可以深入研究.甚至形成價格階梯,涵蓋所有可能的變動.

# 設計思路:
# 一個證券可以有多種浮標,各自可設置先決條件,例如bor指標初次回昇,以及擬委託價,例如昨收盤,或等待符合條件時,用當時價位
# 浮標條件滿足時,隨時滿足隨時加入信號之浮標組,新來barArray經過信號發放給各浮標,浮標自動變動其三價: 委託價,理想價,行動價;
# 信號再搜索符合預定條件並且達到行動價的第一個浮標,發出信號.
# 信號發出後,即記錄剛才信號,並不再接受同向信號,同時產生反向的回補信號,如此循環.
# 其中有所變動的只是原先設計中的價格追蹤部分,新設計交給浮標來完成;以及將多個信號壓縮為一個,其中帶有浮標組.其他部分不變.



# 注意: 
#   cond 不得涉及委託/行動/更佳等關鍵價格,因委託等各關鍵價格尚不確定

class Buoy # 浮標
  
  # 注意: 
  #   cond 不得涉及委託/行動/更佳等關鍵價格,因委託等各關鍵價格尚不確定
  constructor:({signal,@buoyName,@orderPrice,@tillMinute=0,@cond=(-> true)})->
    {@secCode,@facts,@bases,@customs} = signal
    # @customs 也可自行設定:
    #@customs = ldb("db/factors#{@secCode}.json", storage)

  hitPrice: (pool,tracer,tableBuoys)->
    ### 完整寫法應該是:
    if @hitPriceSpecial(pool,tracer,tableBuoys) # 1. 非常規程序
      return true
    else # 2. 常規程序
      retrun @hitPriceNormal(pool,tracer,tableBuoys) # <- 永遠 return false
    ###
    # 簡化寫法. 注意: 順序一定不能顛倒!
    return @hitPriceSpecial(pool,tracer,tableBuoys) or @hitPriceNormal(pool,tracer,tableBuoys)

  followPrice: (pool,newPrice,tableBuoys)->
    @followPriceNormal(pool,newPrice,tableBuoys)     # 1. 常規程序
    @followPriceSpecial(pool,newPrice,tableBuoys)     # 2. 非常規程序


  isTime:->
    return (@tillMinute is 0) or IBCode.timeReady(@secCode, @tillMinute)

  refineFactors: =>
    # 條件可以持續改進; 根據 委託價格與行動價格的差價,判斷是否調整 報價因子
    changed = false
    {最小容忍下單單位數,最大容忍下單單位數,最小委託下單單位數,最大委託下單單位數,最小報價因子,最大報價因子,最小容忍因子,最大容忍因子} = @bases

    #ctc = IBCode.tooClose(@secCode,@orderPrice,@betterPrice,最小容忍下單單位數,最小容忍因子)
    ctc = IBCode.tooClosePercent(@secCode,@orderPrice,@betterPrice,最小容忍因子)
    if ctc
      @facts.容忍因子 = 最小容忍因子
      util.log "容忍因子 增加到", @facts.容忍因子
      changed = true
    else
      #ctf = IBCode.tooFar(@secCode,@orderPrice,@betterPrice,最大容忍下單單位數,最大容忍因子)
      ctf = IBCode.tooFarPercent(@secCode,@orderPrice,@betterPrice,最大容忍因子)
      if ctf
        @facts.容忍因子 = 最大容忍因子
        util.log "容忍因子 縮減到", @facts.容忍因子
        changed = true

    @facts.報價因子 = Math.min(@facts.容忍因子 / 2 , @facts.報價因子)

    #atc = IBCode.tooClose(@secCode, @actionPrice, @orderPrice,最小委託下單單位數,最小報價因子)
    atc = IBCode.tooClosePercent(@secCode, @actionPrice, @orderPrice,最小報價因子)
    if atc
      @facts.報價因子 *= 1 + 5  / 100
      util.log "報價因子 增加到", @facts.報價因子
      changed = true
    else
      #atf = IBCode.tooFar(@secCode, @actionPrice, @orderPrice,最大委託下單單位數,最大報價因子)
      atf = IBCode.tooFarPercent(@secCode, @actionPrice, @orderPrice,最大報價因子)
      if atf
        @facts.報價因子 /= 1 + 5  / 100
        util.log "報價因子 縮減到", @facts.報價因子
        changed = true

    @updateFactorDb() if changed
    return changed
  
  
  copyWithout:(keys)->
    o = {}
    for key, value of this when not (key in keys)
      o[key] = value
    return o

  updateFactorDb: =>
    miniSettings =
      報價因子: @facts.報價因子
      容忍因子: @facts.容忍因子
    @customs.get('factors')
      .merge(miniSettings)
      .value()




# ---------------------------------- Base ---------------------------------------
# base 可以直接使用,只會去掉一些擴充功能

class BuyBuoyBase extends Buoy
  # BuyBuoyBase
  # 折返成交機制: 
  #   價格可以再考慮,比如取 0.5*(@betterPrice+@orderPrice),等等
  #   優點: 價格更優
  #   缺點: 可能錯過,無法成交
  # 兩種情況:  
  #   1. 正常情況,已經有 betterPrice 出現 
  #   2. 緊急情況,已經穿過actionPrice,無論怎樣也要委託;

  # BuyBuoyBase
  hitPriceSpecial: (pool,tracer,tableBuoys)->
    # 1. 非常規程序
    {容忍因子,報價因子} = @facts
    {lastBar,bar,bar:{close}} = tracer
    if (not @betterPrice?)  
      if @actionPrice? and @touchPrice?
        if @isTime() and @cond(pool,tracer)
          triggerPrice = @actionPrice #@orderPrice # @orderPrice 更嚴格,更難觸發指令
          if close > triggerPrice and not @tradePrice?
            @tradePrice = @actionPrice * (1 + @facts.報價因子 * 0.5)  #0.5*(@touchPrice + @actionPrice) #* (1 + @facts.報價因子)  # 折返成交機制
            tableBuoys?()
            return true
  
  # BuyBuoyBase
  # 永遠 return false
  hitPriceNormal: (pool,tracer,tableBuoys)->
    # 2. 常規程序
    {容忍因子,報價因子} = @facts
    {lastBar,bar,bar:{close}} = tracer
    if @betterPrice? and @actionPrice?
      if close > @actionPrice > @betterPrice 
        if @isTime() and @cond(pool,tracer)
          @touchPrice = @betterPrice # 折返報價,由擴充程序完成交易
          #@actionPrice = @betterPrice * (1+報價因子)
          @orderPrice = @actionPrice * (1+報價因子)  #@touchPrice * (1+報價因子)
          @actionPrice = null
          @betterPrice = null
          if /^止|^復/.test @buoyName
            util.log "#{@constructor.name} better price 觸發策略條件:",close
          tableBuoys?()
          say.speak("#{pool.secCode}#{@buoyName}: 觸發交易",'sin-ji') if speakout and pool.onDuty
    @followPrice(pool,close,tableBuoys)
    return false # 永遠 return false

  # BuyBuoyBase
  followPriceNormal: (pool,newPrice,tableBuoys)->
    {容忍因子,報價因子} = @facts
    # 1. 常規程序
    if newPrice < (@betterPrice ? (@orderPrice / (1+容忍因子)))
      @betterPrice = newPrice
      @actionPrice ?= @orderPrice / (1+報價因子)
      
      bp = @betterPrice * (1+容忍因子)

      if bp < @actionPrice
        #@actionPrice = bp # 方法 1
        if (/^止|^復/.test @buoyName)
          @actionPrice = Math.max(@betterPrice * (1+容忍因子), 0.5*(@betterPrice + @orderPrice)) # 保持等距離
          #@orderPrice = @actionPrice * (1+報價因子) # <- 注釋掉,欲強調保持不變
        else
          @actionPrice = @betterPrice * (1+報價因子) # 方法 2
          @orderPrice = @actionPrice * (1+報價因子)
        say.speak("#{pool.secCode}#{@buoyName}: 作價 #{@actionPrice.toFixed(3)} ",'sin-ji') if speakout  and pool.onDuty
        @refineFactors()
      tableBuoys?() # 純粹研究開發工具,非交易所需
      return
  
  # BuyBuoyBase
  followPriceSpecial: (pool,newPrice,tableBuoys)->
    # 2. 非常規程序
    # 原則: 寧可不賺,不可虧本
    #注意: 此處不得修改 @orderPrice! 留給上方常規程序處理    
    {容忍因子,報價因子} = @facts
    unless @betterPrice?
      # 以下/止空買:.*本價/ 則包含 成本價 和 保本價, 若只需其中之一,則寫明,如 /復多:.*保本價/
      #if (/開多|平空|復多:.*本價|止空買:.*autoPrice|止空買:.*本價|止空買:.*止損價/.test @buoyName)
      #special = /^開多|^平空|^復多:.*保本價|^止空買:.*保本價|^止空買:.*止損價|^止空買:.*截斷價/.test(@buoyName)
      special = /^開多|^平空|^復多:.*保本價|^止空買:.*保本價/.test(@buoyName)
      if @touchPrice? or special
        @actionPrice ?= @orderPrice / (1+報價因子)
        if newPrice < (@touchPrice ? @actionPrice)
          @touchPrice = newPrice
          # 除非止損或恢復倉位,其他指令則actionPrice 跟價
          unless /^止|^復/.test(@buoyName)
            @actionPrice = @touchPrice * (1+報價因子)
          tableBuoys?() # 純粹研究開發工具,非交易所需
          return    
          #注意: 此處不得修改 @orderPrice! 留給常規程序處理
    
  # BuyBuoyBase
  laterPrice:(laterPrice,tableBuoys)->
    if laterPrice < @orderPrice
      @orderPrice = laterPrice
      tableBuoys?()


class SellBuoyBase extends Buoy
  # SellBuoyBase
  hitPriceSpecial:(pool,tracer,tableBuoys)->
    # 非常規程序
    {容忍因子,報價因子} = @facts
    {lastBar,bar,bar:{close}} = tracer    
    if not @betterPrice?
      if @actionPrice? and @touchPrice?
        if @isTime() and @cond(pool,tracer)
          triggerPrice = @actionPrice #@orderPrice # @orderPrice 更嚴格,更難觸發指令
          if triggerPrice > close and not @tradePrice?
            @tradePrice = @actionPrice / (1 + @facts.報價因子 * 0.5) # 0.5*(@touchPrice + @actionPrice) # #* (1 + @facts.報價因子)  # 折返成交機制
            tableBuoys?()
            return true
  
  # SellBuoyBase
  # 永遠 return false
  hitPriceNormal:(pool,tracer,tableBuoys)->
    # 常規程序
    {容忍因子,報價因子} = @facts
    {lastBar,bar,bar:{close}} = tracer    
    if @betterPrice? and @actionPrice?
      if @betterPrice > @actionPrice > close
        if @isTime() and @cond(pool,tracer)
          @touchPrice = @betterPrice # 折返報價,由擴充程序完成交易
          #@actionPrice = @betterPrice / (1+報價因子) #@orderPrice = @touchPrice / (1+報價因子)
          @orderPrice = @actionPrice / (1+報價因子)  
          @actionPrice = null
          @betterPrice = null
          #return false # 不需要
          if /^止|^復/.test @buoyName
            util.log "#{@constructor.name} better price 觸發策略條件:",close
          tableBuoys?()
          say.speak("#{pool.secCode}#{@buoyName}: 觸發交易",'sin-ji') if speakout and pool.onDuty
    @followPrice(pool,close,tableBuoys)
    return false # 永遠 return false

  # SellBuoyBase
  followPriceNormal: (pool,newPrice,tableBuoys)->
    # 常規情形
    {容忍因子,報價因子} = @facts
    if newPrice > (@betterPrice ? (@orderPrice * (1+容忍因子)))
      @betterPrice = newPrice
      @actionPrice ?= @orderPrice * (1+報價因子)
      bp = @betterPrice / (1+容忍因子)
      if bp > @actionPrice
        #@actionPrice = bp # 方法 1
        if (/^止|^復/.test @buoyName)
          @actionPrice = Math.min(@betterPrice / (1+容忍因子), 0.5*(@betterPrice + @orderPrice)) # 保持等距離
          #@orderPrice = @actionPrice / (1+報價因子) # <- 注釋掉欲保持不變
        else
          @actionPrice = @betterPrice / (1+報價因子) # 方法 2
          @orderPrice = @actionPrice / (1+報價因子)
        say.speak("#{pool.secCode}#{@buoyName}: 作價 #{@actionPrice.toFixed(3)} ",'sin-ji') if speakout and pool.onDuty
        @refineFactors()
      tableBuoys?() # 純粹研究開發工具,非交易所需
      return
  
  # SellBuoyBase
  followPriceSpecial: (pool,newPrice,tableBuoys)->
    # 非常規情形
    # 原則: 寧可不賺,不可虧本
    {容忍因子,報價因子} = @facts    
    unless @betterPrice?
      # 以下/止多賣:.*本價/ 則包含 成本價 和 保本價, 若只需其中之一,則寫明,如 /復空:.*保本價/
      #if (/開空|平多|復空:.*本價|止多賣:.*autoPrice|止多賣:.*本價|止多賣:.*止損價/.test @buoyName)
      #special = /^開空|^平多|^復空:.*保本價|^止多賣:.*保本價|^止多賣:.*止損價|^止多賣:.*截斷價/.test(@buoyName)
      special = /^開空|^平多|^復空:.*保本價|^止多賣:.*保本價/.test(@buoyName)      
      if @touchPrice? or special
        @actionPrice ?= @orderPrice * (1+報價因子)
        if newPrice > (@touchPrice ? @actionPrice)
          @touchPrice = newPrice
          # 除非止損或恢復倉位,其他指令則actionPrice 跟價
          unless (/^止|^復/.test @buoyName)
            @actionPrice = @touchPrice / (1+報價因子)          
          tableBuoys?() # 純粹研究開發工具,非交易所需
          return
          #注意: 此處不得修改 @orderPrice! 留給常規程序處理

  # SellBuoyBase
  laterPrice:(laterPrice,tableBuoys)->
    if laterPrice > @orderPrice
      @orderPrice = laterPrice
      tableBuoys?()




# --------------------------------- extends  ---------------------------------
# 可在此定制特殊程序
class BuyBuoy extends BuyBuoyBase

class SellBuoy extends SellBuoyBase





# -------------------------------------- 備考: Special Example  -------------------------------------
# 備考.
class BuyBuoySpecialExample extends BuyBuoyBase
  # BuyBuoySpecialExample
  # 擴充: 非常規情形
  # 此處 super 必須後置
  hitPrice: (pool,tracer,tableBuoys)->
    {容忍因子,報價因子} = @facts
    {lastBar,bar,bar:{close}} = tracer
    if (not @betterPrice?)  
      if @actionPrice? and @touchPrice?
        if @isTime() and @cond(pool,tracer)
          triggerPrice = @actionPrice #@orderPrice # @orderPrice 更嚴格,更難觸發指令
          if close > triggerPrice and not @tradePrice?
            @tradePrice = @actionPrice * (1 + @facts.報價因子 * 0.5)  #0.5*(@touchPrice + @actionPrice) #* (1 + @facts.報價因子)  # 折返成交機制
            tableBuoys?()
            return true
    # 此處 super 必須後置
    return super(pool,tracer,tableBuoys)
  # BuyBuoySpecialExample
  # 擴充: 非常規情形
  # 此處 super 適宜前置
  followPrice: (pool,newPrice,tableBuoys)->
    # 此處 super 適宜前置
    super(pool,newPrice,tableBuoys)
    # 非常規情形
    # 原則: 寧可不賺,不可虧本
    {容忍因子,報價因子} = @facts
    unless @betterPrice?
      # 以下/止空買:.*本價/ 則包含 成本價 和 保本價, 若只需其中之一,則寫明,如 /復多:.*保本價/
      #if (/開多|平空|復多:.*本價|止空買:.*autoPrice|止空買:.*本價|止空買:.*止損價/.test @buoyName)
      #special = /^開多|^平空|^復多:.*保本價|^止空買:.*保本價|^止空買:.*止損價|^止空買:.*截斷價/.test(@buoyName)
      special = /^開多|^平空|^復多:.*保本價|^止空買:.*保本價/.test(@buoyName)
      if @touchPrice? or special
        @actionPrice ?= @orderPrice / (1+報價因子)
        if newPrice < (@touchPrice ? @actionPrice)
          @touchPrice = newPrice
          # 除非止損或恢復倉位,其他指令則actionPrice 跟價
          unless /^止|^復/.test(@buoyName)
            @actionPrice = @touchPrice * (1+報價因子)
          tableBuoys?() # 純粹研究開發工具,非交易所需
          return    
          #注意: 此處不得修改 @orderPrice! 留給常規程序處理

# 備考.
class SellBuoySpecialExample extends SellBuoyBase
  # SellBuoySpecialExample
  # 擴充: 非常規情形
  # 此處 super 必須後置
  hitPrice: (pool,tracer,tableBuoys)->
    {容忍因子,報價因子} = @facts
    {lastBar,bar,bar:{close}} = tracer    
    if (not @betterPrice?)
      if @actionPrice? and @touchPrice?
        if @isTime() and @cond(pool,tracer)
          triggerPrice = @actionPrice #@orderPrice # @orderPrice 更嚴格,更難觸發指令
          if triggerPrice > close and not @tradePrice?
            @tradePrice = @actionPrice / (1 + @facts.報價因子 * 0.5) # 0.5*(@touchPrice + @actionPrice) # #* (1 + @facts.報價因子)  # 折返成交機制
            tableBuoys?()
            return true
    # 此處 super 必須後置
    return super(pool,tracer,tableBuoys)

  # SellBuoySpecialExample
  # 擴充: 非常規情形
  # 此處 super 適宜前置
  followPrice: (pool,newPrice,tableBuoys)->
    # 此處 super 適宜前置
    super(pool,newPrice,tableBuoys)

    # 非常規情形
    # 原則: 寧可不賺,不可虧本
    {容忍因子,報價因子} = @facts
    unless @betterPrice?
      # 以下/止多賣:.*本價/ 則包含 成本價 和 保本價, 若只需其中之一,則寫明,如 /復空:.*保本價/
      #if (/開空|平多|復空:.*本價|止多賣:.*autoPrice|止多賣:.*本價|止多賣:.*止損價/.test @buoyName)
      #special = /^開空|^平多|^復空:.*保本價|^止多賣:.*保本價|^止多賣:.*止損價|^止多賣:.*截斷價/.test(@buoyName)
      special = /^開空|^平多|^復空:.*保本價|^止多賣:.*保本價/.test(@buoyName)      
      if @touchPrice? or special
        @actionPrice ?= @orderPrice * (1+報價因子)
        if newPrice > (@touchPrice ? @actionPrice)
          @touchPrice = newPrice
          # 除非止損或恢復倉位,其他指令則actionPrice 跟價
          unless (/^止|^復/.test @buoyName)
            @actionPrice = @touchPrice / (1+報價因子)          
          tableBuoys?() # 純粹研究開發工具,非交易所需
          return
          #注意: 此處不得修改 @orderPrice! 留給常規程序處理







# 試過把這部分放到上方,結果出錯,不要再嘗試
module.exports = {BuyBuoy, SellBuoy}

