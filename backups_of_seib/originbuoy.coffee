

util = require 'util'
{IBCode} = require './secode'


# ------------------------------------------- 舊版存檔 --------------------------------------------


class BuyBuoy_ extends Buoy

  # BuyBuoy
  # 思路: 動態價格階梯,實現智能化的操作.機制合理,各級之間幅度關係則可以逐步尋找最佳關係,甚至以人工智能方式因券而異自我學習.
  # 階梯為 @betterPrice(之前低點價) < @actionPrice <= close(現價) < @orderPrice(委託賣出價),幅度為:
  # @betterPrice/@orderPrice 即 1/(1+@facts.容忍因子)
  # @orderPrice/close 即 1/(1+@facts.報價因子)
  # 當價格探底回升漲至價格階梯中接近計劃買入委託價時觸發機關
  hitPrice: (pool,tracer,tableBuoys)->
    {bar} = tracer
    {close} = bar
    # 必須有過更好價位,且計劃買入價位僅比現價高一點點
    #if @betterPrice? and ((if /成本價/.test @buoyName then Math.min(@actionPrice,@betterPrice) else @actionPrice) <= close < @orderPrice)
    
    # 下行有小問題,行情快時,可能越過區間,而發不出消息
    #if @betterPrice? and (@actionPrice <= close < @orderPrice)
    if @betterPrice? and (@betterPrice < @actionPrice <= close) # < @orderPrice)
      if @isTime()
        if @cond(pool,tracer)
          @orderPrice = 0.5*(@actionPrice+@orderPrice) 
          # util.log "[#{@secCode}#{@constructor.name}] hitPrice >> fit: #{@buoyName},#{bar.day}, #{@actionPrice} <= close #{close} < #{@orderPrice}"
          return true
    else
      @followPrice(pool,close,tableBuoys)
    return false

  # BuyBuoy, 實際委託價會高於迄今最優價,中間的價差,我們想用來驗證趨勢的轉變,而不是中繼形態
  # @betterPrice < actionPrice < orderPrice,中間的差距最小是一個報價單位,最大是不超過9.09  / 100(0.012/0.011)
  followPrice: (pool,newPrice,tableBuoys)->
    {容忍因子,報價因子} = @facts
    # version 1
    lower = newPrice < (@betterPrice ? (@orderPrice / (0.99999+容忍因子))) # 報價因子
    # version 2
    # lower = newPrice < (@betterPrice ? (@orderPrice) / (0.99999+報價因子))) # 報價因子 間斷變動
    if lower
      #util.log("[#{@secCode}:#{@constructor.name}#{@buoyName}] betterPrice #{@betterPrice} >>>> ",newPrice)
      @betterPrice = newPrice
      bo = @betterPrice * (1+容忍因子)
      if bo < @orderPrice  # 假如 bo 價更低
        @orderPrice = bo
        @refineFactors()
      # version 1 止損思路
      @actionPrice = @orderPrice / (1+報價因子) # 較少止盈止損操作,但不能避免,感覺這種方式吃虧了.先在盤中對比一下再抉擇
      # version 2 止盈思路, reopen 如何解決
      #@actionPrice = @betterPrice * (1+報價因子)
      tableBuoys?() # 純粹研究開發工具,非交易所需


class SellBuoy_ extends Buoy
  # SellBuoy_
  # 思路: 動態價格階梯,實現個智能化的操作.機制合理,各級之間幅度關係則可以逐步尋找最佳關係,甚至以人工智能方式因券而異自我學習.
  # 階梯為 @betterPrice(之前高點價) > @actionPrice >= close(現價) > @orderPrice(委託賣出價),幅度為:
  # @betterPrice/@orderPrice >> (1+@facts.容忍因子)
  # @orderPrice/close >> (1+@facts.報價因子)
  # 當價格衝高回落跌至價格階梯中接近計劃賣出委託價時觸發機關
  hitPrice: (pool,tracer,tableBuoys)->
    {bar} = tracer
    {close} = bar
    # 必須有過更好價位,且計劃賣出委託價僅比現價低一點
    #if @betterPrice? and ((if /成本價/.test @buoyName then Math.max(@actionPrice,@betterPrice) else @actionPrice) >= close > @orderPrice)
    
    # 行情太快可能越過區間,故改之,以期回頭時成交
    #if @betterPrice? and (@actionPrice >= close > @orderPrice)
    if @betterPrice? and (@betterPrice > @actionPrice >= close) # > @orderPrice)
      if @isTime()
        if @cond(pool,tracer)
          @orderPrice = 0.5*(@actionPrice+@orderPrice)
          # util.log "[#{@secCode}#{@constructor.name}] hitPrice >> fit: #{@buoyName},#{bar.day}, #{@actionPrice} >= close #{close} > #{@orderPrice}"
          return true
    else
      @followPrice(pool,close,tableBuoys)
    return false

  # SellBuoy_, 實際賣出價會低於迄今最優價,中間的價差,我們想用來驗證趨勢的轉變,而不是中繼形態
  # @betterPrice > actionPrice > orderPrice,中間的差距最小是一個報價單位,最大是不超過1+9.1  / 100(0.012/0.011)
  followPrice: (pool,newPrice,tableBuoys)->
    {容忍因子,報價因子} = @facts
    # version 1
    higher =  newPrice > (@betterPrice ? (@orderPrice * (1.0001+容忍因子))) # 報價因子
    # version 2
    #higher =  newPrice > (@betterPrice ? (@orderPrice) * (1.0001+報價因子))) # 報價因子 間斷變動
    if higher
      #util.log("[#{@secCode}:#{@constructor.name}#{@buoyName}] betterPrice #{@betterPrice} >>>> ",newPrice)
      @betterPrice = newPrice  
      bo = @betterPrice / (1+容忍因子) # 注意不要用 * (1-容忍因子), 兩者數值差距甚大,會令系統混亂
      if bo > @orderPrice # 如果 bo 價更高
        @orderPrice = bo
        @refineFactors()
      # version 1  
      @actionPrice = @orderPrice * (1+報價因子) # 較少止盈止損操作,但不能避免,感覺這種方式吃虧了.先在盤中對比一下再抉擇
      # version 2
      #@actionPrice = @betterPrice / (1+報價因子)
      tableBuoys?() # 純粹研究開發工具,非交易所需








# 試過把這部分放到上方,結果出錯,不要再嘗試
module.exports = 
  BuyBuoy: BuyBuoy_
  SellBuoy: SellBuoy_

