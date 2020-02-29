# 原始的設計思路,備考
class TestTDataFlow extends BaseTDataFlow 

  obsolescent__setIOXPrice: ->
    @sellXPrice = @downXBar?.downXPrice()
    @buyXPrice = @upXBar?.upXPrice()


  defineUpX: ->
    p = @upXBar?.upXPrice()
    @upXBar?.isAfter(@downXBar) and ((p > @preUpXBar?.upXPrice()) or (p > @downXBar?.downXPrice()))
  defineDownX: ->
    p = @downXBar?.downXPrice()
    @downXBar?.isAfter(@upXBar) and ((p < @preDownXBar?.downXPrice()) or (p < @upXBar?.upXPrice()))



  # -------------------------- API --------------------------
  listAPI: ->
    'checkBuyX, checkSellX, sellXFilter, buyXFilter'
  
  
  # 過濾所發現可作為買賣點的bar
  sellXFilter:(pool,sellBandNames)->
    for sellBandName in sellBandNames
      if @barBefore(@downXBar)?.high >= @downXBar[sellBandName]  #sellXPrice > @downXBar[sellBandNames]
        return true
    return false
  buyXFilter:(pool,buyBandNames)->
    for buyBandName in buyBandNames
      if @barBefore(@upXBar)?.low < @upXBar[buyBandName] #buyXPrice < @upXBar[buyBandNames]
        return true
    return false


  


module.exports = TestTDataFlow


