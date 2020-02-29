###
Crossing, 穿透(某線),用於交易策略
此法較為局限,盡量不用.以免系統變得複雜而死板.
主要用於單獨考察level或bband其中的一類關鍵界線,用於記錄穿越發生的部位.
單獨考察的意思是,當考察一個指標時,另一個最好不計算,不然就很混亂.
應用在level時,比較安全.因系統默認統計level穿刺情況.
若用於其他,則須禁止計算levels過程中統計傳統入bar,不然很混亂.

計算當前的上穿下穿所形成的波動邊界,以便上方賣出,下方買入
思路是,在上下穿被"吃掉"之前,上下穿影響都存在,即買賣根據地存在,伸縮空間由 farLine 再順延一個level來確定
###

assert = require './assert'
{BaseDataFlow} = require './dataflow'
CordonFlowBase = require './cordonflow'


class CrossingRangeBase 
  @pick:({baseUpXName,farUpXName,baseDownXName,farDownXName,cordonType,bar,contract})->
    switch cordonType
      when 'levels'
        new LevelCrossingRange({baseUpXName,farUpXName,baseDownXName,farDownXName,bar})
      when 'bband'
        new BbandCrossingRange({baseUpXName,farUpXName,baseDownXName,farDownXName,bar})
  @symbolUp: 'xUp'
  @symbolDown: 'xDown'

  constructor: ({@baseUpXName,@farUpXName,@baseDownXName,@farDownXName,@bar}) ->
    @direction = null


  updateRange:({baseUpXName,farUpXName,baseDownXName,farDownXName,bar})->
    return



class CrossingRange extends CrossingRangeBase

class LevelCrossingRange extends CrossingRange
  updateRange: ({baseUpXName,farUpXName,baseDownXName,farDownXName,bar})->
    #{@baseUpXName,@farUpXName,@baseDownXName,@farDownXName,@bar} = {baseUpXName,farUpXName,baseDownXName,farDownXName,bar}
    @bar = bar
    assert.log({@baseUpXName,@farUpXName,@baseDownXName,@farDownXName,@direction},{baseUpXName,farUpXName,baseDownXName,farDownXName})
    switch
      when (not farDownXName?) and (not farUpXName?)
        return
      when farDownXName is 'level0'
        @farUpXName = @baseUpXName = null
        @farDownXName = farDownXName
        @baseDownXName ?= baseDownXName        
        @direction = @constructor.symbolDown
      when farUpXName is 'level10'
        @farDownXName = @baseDownXName = null
        @farUpXName = farUpXName
        @baseUpXName ?= baseUpXName        
        @direction = @constructor.symbolUp
      when (not farUpXName?) and (farDownXName isnt 'level0')
        @farUpXName = CordonFlowBase.pick(farDownXName).lowerCordonName()
        @baseUpXName ?= baseUpXName ? @farUpXName   # 應僅有一種情形,baseUpXName是null,@farUpXName為0 
        @farDownXName = farDownXName
        @baseDownXName ?= baseDownXName        
        @direction = @constructor.symbolDown        
      when (not farDownXName?) and (farUpXName isnt 'level10')
        @farDownXName = CordonFlowBase.pick(farUpXName).higherCordonName()
        @baseDownXName ?= baseDownXName ? @farDownXName   # 應僅有一種情形,baseDownXName是null,@farDownXName為0 
        @farUpXName = farUpXName
        @baseUpXName ?= baseUpXName
        @direction = @constructor.symbolUp
      else
        # 先檢測方向
        switch
          when CordonFlowBase.pick(farDownXName).isLowerThan(@farDownXName)
            @direction = @constructor.symbolDown
          when CordonFlowBase.pick(farUpXName).isLowerThan(@farUpXName)
            @direction = @constructor.symbolDown
          when CordonFlowBase.pick(farDownXName).isHigherThan(@farDownXName)
            @direction = @constructor.symbolUp
          when CordonFlowBase.pick(farUpXName).isHigherThan(@farUpXName)
            @direction = @constructor.symbolUp
        # 再更新
        @baseDownXName ?= baseDownXName
        @farDownXName = farDownXName
        @baseUpXName ?= baseUpXName
        @farUpXName = farUpXName


class BbandCrossingRange extends CrossingRange


module.exports = CrossingRangeBase