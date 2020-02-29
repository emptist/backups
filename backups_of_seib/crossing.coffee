# Crossing, 穿透(某線),用於交易策略

assert = require './assert'
{BaseDataFlow} = require './dataflow'



class Crossing
  @pickRange:(xtype,baseLineName,farLineName,bar,contract)->
    if xtype is @symbolUp
      UpCrossingBase.pickRange(baseLineName,farLineName,bar,contract)
    else
      DownCrossingBase.pickRange(baseLineName,farLineName,bar,contract)

  @pick:(xtype,lineName,bar,contract)->
    if xtype is @symbolUp
      UpCrossingBase.pick(lineName,bar,contract)
      #new UpCrossing(lineName,bar)
    else
      DownCrossingBase.pick(lineName,bar,contract)
      #new DownCrossing(lineName,bar)

  @symbolUp: 'xUp'
  @symbolDown: 'xDown'

  constructor: (@lineName, @bar) ->

  # dosn't work as expected?
  toString: ->
    "#{@constructor.name}@#{@bar.day.toString()}"

  updateRange: (@bar, obj)->
    # 更新上下限
    # [待完成代碼:]
    assert.log('[known names]', @bar.day, obj)




class UpCrossingBase extends Crossing
  @pickRange: (baseLineName,farLineName,bar,contract)->
    new UpCrossingRange(baseLineName,farLineName,bar)
  
  @pick: (lineName,bar,contract)->
    # 可根據contract再選  
    new UpCrossing(lineName,bar)

  @xtype: @symbolUp

  updateRange: (@bar, obj)->
    super(obj)
    # 更新上下限
    # [待完成代碼:]
    {baseUpXName, farUpXName} = obj    
    @baseLineName = baseUpXName
    @farLineName = farUpXName




class DownCrossingBase extends Crossing
  @pickRange: (baseLineName,farLineName,bar,contract)->
    new DownCrossingRange(baseLineName,farLineName,bar)

  @pick: (lineName,bar,contract)->
    # 可根據contract再選
    new DownCrossing(lineName,bar)
  
  @xtype: @symbolDown

  updateRange: (@bar, obj)->
    super(@bar,obj)
    # 更新上下限
    # [待完成代碼:]
    {baseDownXName, farDownXName} = obj
    @baseLineName = baseDownXName
    @farLineName = farDownXName



class UpCrossing extends UpCrossingBase

  
class DownCrossing extends DownCrossingBase



class CrossingRange 
  @pick:(xtype,baseLineName,farLineName,bar,contract)->
    if xtype is @symbolUp
      UpCrossingBase.pickRange(baseLineName,farLineName,bar,contract)
    else
      DownCrossingBase.pickRange(baseLineName,farLineName,bar,contract)
  @symbolUp: 'xUp'
  @symbolDown: 'xDown'

  constructor: (@baseLineName, @farLineName, @bar) ->


class UpCrossingRange extends CrossingRange

  
class DownCrossingRange extends DownCrossingBase





module.exports = Crossing