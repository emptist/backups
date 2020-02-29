# 一物一用
# 討論: cordon buoy 是不是一個法?需要分開嗎?
# 結論: 不是一法,應該分開. 一物一性一用
# Cordon 可比喻為刻度線,相對靜,直到再度穿刺.一個刻度線,只跟線的類型有關.而浮標則根據上穿下穿而有兩種.
# Buoy 則是在刻度線上上下移動的浮標,浮標的用途是找到介入點.跟現實浮標不同,此處一浮標對應一刻度線.有多少刻度有多少浮標.
# 某刻度發生向上穿刺之後,買入時機可能來臨,浮標開始跟蹤價格波動,穿刺之後回調時,不斷降低準備出手買入的價格線,直到價格不再回調,
# 並上穿設定的行動線,此時即刻發出訊號,以便下單買入
# Buoy是隨著穿刺而生成,下次穿刺發生時自動被新Buoy取代,故其生命週期可長可短,只要未發生反向穿刺,就一直生存,落在有效區間時,才
# 尋找操作機會,因此一旦脫離有效區間,應重新設置行動線等變量(或構思出更好的object不需要人為設置者)


{BuoyFlowPicker} = require './buoyflow'


# 此法是為了避免 Cordon <-> Buoy 形成 Circular reference
# 配對之後,僅buoy中有cordon,而cordon中無buoy
class PairCordonBuoyBase
  constructor:({@cordon,@buoy})->
  
  comingBar:(bar,pool)->
    @cordon.comingBar(bar,pool)
    # @buoy 待穿刺之後才會有
    @buoy?.comingBar(bar,pool)

  # @buoy 隨穿刺而更生
  resetBuoy: ->
    @buoy = BuoyFlowPicker.pickFor(@cordon)


class PairCordonBuoy extends PairCordonBuoyBase



module.exports = PairCordonBuoy