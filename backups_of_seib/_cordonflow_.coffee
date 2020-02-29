# extends BaseDataFlow 之後,我覺得弄複雜了.
# 保留此文件備考,另開一個簡單的simpleCordon.coffee
### CordonFlow 關鍵臨界線
  用於 Buoy 方便根據追蹤關鍵臨界線的穿越的結果確定交易時間和價格(best/worst)
  上下檔:
    定義次第排序的 [],相鄰兩項互為上下
    買賣的次第或可相反或應相同,總之需要方便使用,不易出錯.
  合適的結構有:
    levels: 相鄰為上下,兩端為[level0, level10]
    bband: 相鄰為上下,兩極為[closeLowBand,closeHighBand]
    [yinfishy/yangfishy: 比較欠缺]
###

assert = require './assert'
BaseDataFlow = require './dataflow_base'
SecTypeHelper = require './secTypeHelper'

class CordonFlowBase extends BaseDataFlow
  @pick: ({secCode,timescale,cordonName,contract,tradeType})->
    typeHelper = SecTypeHelper.pick(secCode,timescale,contract)
    if /level/i.test(cordonName)
      if tradeType is 'buy'
        new LevelBuyCordonFlow({secCode,timescale,cordonName,typeHelper})
      else
        new LevelSellCordonFlow({secCode,timescale,cordonName,typeHelper})
    else if /bband/i.test(cordonName)
      if tradeType is 'buy'
        new BBandBuyCordonFlow({secCode,timescale,cordonName,typeHelper})
      else
        new BBandSellCordonFlow({secCode,timescale,cordonName,typeHelper})

  constructor:({@secCode,@timescale,@cordonName,@typeHelper})->
    super(@secCode,@timescale)

  firstBar: (pool)->
    super(pool)
    @typeHelper.withBar(@bar)

  nextBar: (pool)->
    super(pool)
    @typeHelper.withBar(@bar)


    
class CordonFlow extends CordonFlowBase
  @levelOrder:[
    'level0'
    'level1'
    'level2'
    'level3'
    'level4'
    'level5'
    'level6'
    'level7'
    'level8'
    'level9'
    'level10'
  ]

  @bbandOrder:[
    'closeLowBand'
    'closeLowHalfBand'
    'bbandma'
    'closeHighHalfBand'
    'closeHighBand'
  ]



# ================================== buy ===================================

class BuyCordonFlow extends CordonFlow
  bestLine:->

# 最方便故最主要的cordon
class LevelBuyCordonFlow extends BuyCordonFlow
  @cordonOrder: @levelOrder

class BBandBuyCordonFlow extends BuyCordonFlow
  @cordonOrder: @bbandOrder


# less important
#class YangFishyBuyCordonFlow extends BuyCordonFlow







# ================================== sell ===================================

class SellCordonFlow extends CordonFlow

class LevelSellCordonFlow extends SellCordonFlow

class BBandSellCordonFlow extends SellCordonFlow

# less important
#class YinFishySellCordonFlow extends SellCordonFlow



module.exports = CordonFlowBase