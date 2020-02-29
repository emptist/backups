assert = require './assert'
{TradeDataFlow} = require './dataflow'
{IBCode} = require './secode'

# 設計意圖:
# 將牛熊策略分開處理
# 盡量簡化此法(目前思路不清晰,待開發中逐步完善)
class TrendFlow extends TradeDataFlow
  @pick:(pool,type)->
    #選擇合適的子系,生成object並回復. 細分子系,可參照 Tracer
    {secCode,timescale,contract} = pool
    switch type
      when 'bull'
        if IBCode.isForex(secCode)
          aTrend = new ForexBullFlow(secCode, timescale, contract)
        else if IBCode.isHKIOPT(secCode)
          aTrend = new HKSecBullFlow(secCode, timescale, contract)        
        else if IBCode.isHK(secCode)
          aTrend = new HKSecBullFlow(secCode, timescale, contract)         
        else if IBCode.isABC(secCode)
          aTrend = new USSecBullFlow(secCode, timescale, contract)
        else
          aTrend = new BullFlow(secCode,timescale,contract)
      when 'bear'
        if IBCode.isForex(secCode)
          aTrend = new ForexBearFlow(secCode, timescale, contract)
        else if IBCode.isHKIOPT(secCode)
          aTrend = new HKSecBearFlow(secCode, timescale, contract)        
        else if IBCode.isHK(secCode)
          aTrend = new HKSecBearFlow(secCode, timescale, contract)         
        else if IBCode.isABC(secCode)
          aTrend = new USSecBearFlow(secCode, timescale, contract)
        else
          aTrend = new BearFlow(secCode,timescale,contract)
      when 'undecided'
        if IBCode.isForex(secCode)
          aTrend = new ForexUndecidedFlow(secCode, timescale, contract)
        else if IBCode.isHKIOPT(secCode)
          aTrend = new HKSecUndecidedFlow(secCode, timescale, contract)        
        else if IBCode.isHK(secCode)
          aTrend = new HKSecUndecidedFlow(secCode, timescale, contract)         
        else if IBCode.isABC(secCode)
          aTrend = new USSecUndecidedFlow(secCode, timescale, contract)
        else
          aTrend = new UndecidedFlow(secCode,timescale,contract)
    

    
    if false #pool.trend?
      aTrend.buyXBar = pool.trend.buyXBar
      aTrend.sellXBar = pool.trend.sellXBar
    # 以下兩行或許需要,先測試一下看看
    if false #pool.lastBar?
      aTrend.bar = pool.bar
      aTrend.lastBar = pool.lastBar
      aTrend.startBar = pool.bar
    
    return aTrend


  constructor: (@secCode,@timescale,@contract) ->
    super(@secCode,@timescale,@contract)
    #@endBar = null
  
  beforePushPreviousBar:(bar,pool)->
    @endBar = @bar
    #@collectXIO(pool)
    @setIOXBar(pool)
  comingBarDoFinal:(pool)->
    @setEntryPrice(pool)

  foundSellX:(pool)=>
    pool.downXBar? and @downXPriceDown(pool)

  foundBuyX: (options) =>
    pool.downXBar? and @downXPriceUp()
  
  setIOXEntry:(pool)->
    super(pool)

# [正在改寫]
# 以下代碼臨時從 dataflow 拷貝而來,待在此定制為漲跌盤三種不同的方式,並可再細分成各類不同品種的定制模式
class UndecidedFlow extends TrendFlow

class BullFlow extends TrendFlow

class BearFlow extends TrendFlow


class HKSecTrendFlow extends TrendFlow
  #[臨時待整理] 以下各項function 皆原樣拷貝自 HKIOPTExplorer
  # HKIOPTExplorer
  foundBuyX:(pool)->
    pool.upXBar? and (pool.upXBar.low > pool.preUpXBar?.low or pool.upXBar.ema_price20 > pool.preUpXBar?.ema_price20)
  
  # HKIOPTExplorer
  # todo:
  # 若有大行情,策略平倉,如何及時跟進
  foundSellX:(pool)=>
    pool.downXBar? and @downXPriceDown(pool)
  
  downXPriceDown:(pool)->
    pool.downXBar.high <= pool.preDownXBar?.high or (pool.downXBar.ema_price20 < pool.preDownXBar?.ema_price20) or (pool.downXBar.isAfter(pool.upXBar?) and pool.downXBar.high <= pool.upXBar?.high)

  
  setIOXPrice:(pool) ->
    @sellXPrice = pool.downXBar?.downXPrice()
    @buyXPrice = pool.upXBar?.upXPrice()
  


  # HKIOPTExplorer
  sellXFilter:(pool)=>
    @sellXBullFilter(pool) or @sellXBearFilter(pool)
  sellXBullFilter:(pool)->
    pool.isBull and (pool.downXBar.highlevel > 7) and pool.downXBar.high > pool.downXBar.bbta #pool.downXBar.hkPriceGradesUpto('close','bbta',2)
  sellXBearFilter:(pool)->
    pool.isBear and (pool.downXBar.highlevel > 1) and pool.downXBar.high > pool.downXBar.ema_price20
  
  # HKIOPTExplorer
  # 箱體小於36格不入手,雖然會錯過一些機會,但機會太多了.只須考慮排除風險.
  buyXFilter:(pool)=>
    x = 36
    y = 9
    if pool.isBear or pool.bar.hkCurrentVerticalGrade() < x or pool.yinfish.hkCurrentDepthGrade() < y or pool.bar.closeHigherThanAny(['closeHighHalfBand','score9','ta','bbta','level9'])
      return false
    @buyXBullFilter(pool) or @buyXBearFilter(pool)
  
  buyXBullFilter:(pool)->
    pool.isBull and (pool.upXBar.lowBelowLine(pool.bband20.highHalfBandName) or pool.upXBar.closeBelowLine('level4'))  #('level1') 
  buyXBearFilter:(pool)->
    pool.isBear and pool.upXBar.lowBelowLine(pool.bband20.lowHalfBandName) #or @bar.closeBelowLine('level1')  #('level1') 

  

class HKSecUndecidedFlow extends HKSecTrendFlow

class HKSecBullFlow extends HKSecTrendFlow

class HKSecBearFlow extends HKSecTrendFlow


class USSecTrendFlow extends TrendFlow

class USSecUndecidedFlow extends USSecTrendFlow

class USSecBullFlow extends USSecTrendFlow

class USSecBearFlow extends USSecTrendFlow


class ForexTrendFlow extends TrendFlow
  # ForexExplorer
  foundSellX:(pool)=>
    pool.downXBar? and @downXPriceDown(pool)
  downXPriceDown:(pool)->
    pool.downXBar.high <= pool.preDownXBar?.high or (pool.downXBar.ema_price20 < pool.preDownXBar?.ema_price20) or (pool.downXBar.isAfter(pool.upXBar?) and pool.downXBar.high <= pool.upXBar?.high)
  foundBuyX:(pool)->
    pool.upXBar? and (pool.upXBar.low > pool.preUpXBar?.low or pool.upXBar.ema_price20 > pool.preUpXBar?.ema_price20)
  setIOXPrice:(pool) ->
    @sellXPrice = pool.downXBar?.downXPrice()
    @buyXPrice = pool.upXBar?.upXPrice()

  # ForexExplorer
  sellXFilter:(pool)=>
    @sellXBullFilter(pool) or @sellXBearFilter(pool)
  sellXBullFilter:(pool)->
    pool.isBull and (pool.downXBar.highlevel > 7) and pool.downXBar.high > pool.downXBar.bbta
  sellXBearFilter:(pool)->
    pool.isBear and (pool.downXBar.highlevel > 1) and pool.downXBar.high > pool.downXBar.ema_price20
  
  buyXFilter:(pool)=>
    @buyXBullFilter(pool) or @buyXBearFilter(pool)
  buyXBullFilter:(pool)->
    pool.isBull and pool.upXBar.lowBelowLine(pool.bband20.maName) #('level1') 
  buyXBearFilter:(pool)->
    pool.isBear and pool.upXBar.lowBelowLine(pool.bband20.lowHalfBandName) #('level1') 

class ForexUndecidedFlow extends ForexTrendFlow

class ForexBullFlow extends ForexTrendFlow

class ForexBearFlow extends ForexTrendFlow



module.exports = TrendFlow