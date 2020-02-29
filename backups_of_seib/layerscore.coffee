###
BaseDataFlow
|- Pool
|- Ratio
|- Ma 
|- Tracer
    |- Explorer: 策略交易信號系統
    |- Guardian: 賬戶級別的止盈止損系統


  對不同品種,可以設置不同的子法,但是看來不需要,目前是通過系統設置,直接根據代碼給予不同的尺度
###
###
  根本:
    多頭和空頭獲利都依賴開倉後價格有利變動.
    

    可以設定一個時間函數,比如多頭倉位,每一個@bar要求x%的增幅,累積計算到@lastBar 這根 @bar,一旦達不到預計,即平倉.
    如此則形成對於速率合格片斷的擷取.
    此為投資本質.一切工具以此為根本進行開發.
    如果以幾何學來比擬,就好像在行情曲線中,截取切線斜率優於設定斜率的片斷.如此形成高單利,高復利,低風險(平倉先於轉勢).
###
# 由於注釋影響觀瞻,故大幅注釋移動到文件末尾,可參閱

# 提煉 Explorer/Guardian 共同需要的部分
path = require 'path' # 參閱 pool 如何設置路徑
assert = require './assert'
moment = require 'moment-timezone'
BaseDataFlow = require './dataflow_base'
{TopBotFlow} = require './topbotindex'

{Flow:{pureYinYang,scoreIntoBar,layerIntoBar,levelIntoBar}} = require './config'
{IBCode} = require './secode'
{fix,fixAll} = require './fix'


# 初始設計時,考慮繪圖方便,所以採用 label 命名各個層級,而沒有用 array. 
# 有空應改為使用 array 參閱 swimflow.grade[]
class LayerScore extends BaseDataFlow
  constructor:(@contractHelper,@secCode,@timescale,@contract,@pureYinYang=pureYinYang,@recordInBar=false)->
    super(@contractHelper)
      
  # 首日不做,所以不用計算那些實時策略判斷所需要的變量
  firstBar:(pool)->
    super(pool)
    isFirstBar = true
    @score({pool,isFirstBar})

  nextBar:(pool)->
    super(pool)
    @score({pool})

  # 還可以記錄上次穿透的情況,哪根線,向上向下,記錄在bar 然後可以檢查 if previousBar.cross({type,level})
  # 穿透的定義是,前一bar 或今bar 之低點在某level 之下,今bar close 在該level 之上,或相反,前一或本身high 在level 之上,收在其下
  score:({pool,geometric=true,isFirstBar=false})=>
    {maxta,minba} = @maxmin(pool,isFirstBar) # [bug] sometimes maxta and minba is 0
    unless maxta? and minba?
      return
    intoBar = if @recordInBar then @bar else null
    if geometric 
      g = Math.pow(maxta / minba, 1/10)
    # 注意:
    # 指標標號是有意義的! 順序對應指標數值從小到大! 相關代碼用到此特性,不要隨意更改!
    for idx in [0..10]
      label = @label(idx)
      if geometric 
        @[label] = fix(minba * g ** idx)
      else # minba * x ^ 10 = maxta => x^10 = maxta/minba => x = Math.pow(maxta/minba, 1/10)
        @[label] = fix((idx*maxta + (10-idx)*minba) / 10)

      indicator = @[label]
      intoBar?[label] = indicator # 注意不能合併上句為一句,那樣,到不了 @[label] 就結束了      
      @ohlcScore(indicator, idx, pool)
    @ratioRecord?()
    @hkGradeRecord?()

    # 因出現遺漏情況,在此檢測是否有遺漏
    ['high','low','open','close'].map (what)=>
      unless @bar["#{what}#{@indicatorName}"]?
        debugger
      else if isNaN(@bar["#{what}#{@indicatorName}"])
        debugger
      assert(@bar["#{what}#{@indicatorName}"]?, "#{@bar.date}: #{what}#{@indicatorName} missing")
      assert.not(isNaN(@bar["#{what}#{@indicatorName}"]), "#{@bar.day}: #{what}#{@indicatorName} isNaN")


  label:(idx)->
    label = "#{@indicatorName}#{idx}" # 用不同的指標名,來區分兩類不同算法,例如 layer0 ~ layer10, score0 ~ score10


  ohlcScore:(indicatorValue,idx,pool)->
    indicator = indicatorValue
    {high,low,open,close} = @bar
    fixed = fixAll({high,low,open,close,indicator})
    for ohlc in ['high','low','close','open']
      if fixed.indicator > fixed[ohlc] >= fix((@[@label(idx - 1)] ? 0))
        @bar["#{ohlc}#{@indicatorName}"] = idx
      else if (idx is 10) and (fixed[ohlc] >= fixed.indicator)
        @bar["#{ohlc}#{@indicatorName}"] = 11 

      

  # 以下兩線為看圖故放在 bar, 開發完成,可僅放在 this,減少內存需要
  # 制譜. 帶參數 bar 則算入其中,否則置於本法內
  # @indicatorName 應為 'score' 或 'layer', 計算方法不同,指標名稱各異,故亦可同時存在
  # 算法 1 score
  # 優點: 邏輯清晰,天地之間,對半為分界,兩邊再分,各通道有其含義,例如,熊在下半邊走,牛在上半邊走,很少逾越,等等.且收放自如,隨行情而變.自然非雕琢.
  # 缺點: 間距千變萬化,不直接反應漲跌幅度空間大小,同一通道,邏輯意義前後一致,比例關係前後不同.
  # 算法 2 layer
  # 此算法優點是層次之間幅度關係清晰不變,是常量,易於理解其實質;缺點是需要更多層次,例如從頂到10%頂(假定最多下跌90%),中間分10層,然後每層再分10層
  # LayerScore
  maxmin:(pool, isFirstBar)->
    {bar:{ba,bay,ta,tay}} = pool
    assert(ba and ta and bay and tay, 'ba or ta is not ready')

    if pureYinYang
      maxta: ta
      minba: ba
    else
      maxta: Math.max(ta,tay)
      minba: Math.min(ba,bay)






class ScoreFlow extends LayerScore
  constructor:(@contractHelper,@secCode,@timescale,@contract,@pureYinYang=pureYinYang,@recordInBar=scoreIntoBar)->
    super(@contractHelper,@secCode,@timescale,@contract,@pureYinYang,@recordInBar)

  indicatorName: 'score'


class YScoreFlow extends ScoreFlow
  # YScoreFlow
  maxmin:(pool,isFirstBar)->
    {bar:{ba,bay,ta,tay}} = pool
    assert(ba and ta and bay and tay, 'ba or ta is not ready')
    
    if pureYinYang
      maxta: tay
      minba: bay
    else
      maxta: Math.max(ta,tay)
      minba: Math.min(ba,bay)


class LayerFlow extends LayerScore
  constructor:(@contractHelper,@secCode,@timescale,@contract,@pureYinYang=pureYinYang,@recordInBar=layerIntoBar)->
    super(@contractHelper,@secCode,@timescale,@contract,@pureYinYang,@recordInBar)

  indicatorName:'layer'

  # LayerFlow
  maxmin:(pool)->
    {bar:{ba,bay,ta,tay}} = pool
    assert(ba and ta and tay and bay, 'ba or ta is not ready')
    
    if pureYinYang
      maxta: ta
      minba: 0.5 * ta
    else
      maxta = Math.max(ta,tay)
      # return object:
      maxta: maxta
      minba: 0.5 * maxta  #(ba + ta)


# 等高線,從最高價到最低價劃線
# 討論:
#   設計之初沒有意識到,這是陰魚和陽魚都有的屬性,但是陽魚的levels僅僅適合做空,否則上下邊越來距離越遠,失去效果.
#   由於我們以做多為主,時間也比較緊張,暫時不增補陽魚的台階.以後若有空做,須注意命名level為yin/yang level,並小心有些代碼中level所指為其他與此無關的事項
class LevelFlow extends LayerScore
  @pick: (contractHelper,secCode,timescale,contract)->
    if IBCode.isForex(secCode)
      return new ForexLevelFlow(contractHelper,secCode,timescale,contract)
    else if IBCode.isOPT(contractHelper,secCode)
      return new USOPTLevelFlow(contractHelper,secCode,timescale,contract)
    else if IBCode.isABC(secCode)
      return new USStkLevelFlow(contractHelper,secCode,timescale,contract)
    else if /HSI/i.test(secCode)
      return new HSILevelFlow(contractHelper,secCode,timescale,contract)
    else if IBCode.isHKIOPT(secCode)
      return new IOPTLevelFlow(contractHelper,secCode,timescale,contract)
    else if IBCode.isHK(secCode)
      return new HKStkLevelFlow(contractHelper,secCode,timescale,contract)      
    else
      return new LevelFlow(contractHelper,secCode,timescale,contract)

  constructor:(@contractHelper,@secCode,@timescale,@contract,@pureYinYang=pureYinYang,@recordInBar=levelIntoBar)->
    super(@contractHelper,@secCode,@timescale,@contract,@pureYinYang,@recordInBar)
    statsTag = 'closelevelTopBot'
    sampleDataName = 'closelevel' # 注意,closelevel 全部是小寫字母
    @levelTopBot = new TopBotFlow(@contractHelper, @secCode, @timescale, statsTag, sampleDataName) # 先完成topbot的refactoring

  indicatorName:'level'

  # LevelFlow
  maxmin:(pool,isFirstBar)->
    assert(pool.yinfish.startBar.date <= pool.yinfish.cornerBar.date, 'start bar not before corner bar')
    h = pool.yinfish.startBar.high
    l = pool.yinfish.cornerBar.low
    # 之前在個別牛熊證品種上發現此bug造成出錯,先定位,再找原因
    #assert(h and l and h >= l, "bug located: h or l is 0 or NaN, or high less low, first bar: #{isFirstBar}, pool size: #{pool.size}")
    unless h and l and (h >= l)
      return {maxta:null,minba:null}
    # return an object:
    maxta: h
    minba: l
    #minba: pool.yangfish.startBar.low
    #minba: pool.yangfishy.startBar.low
  
  
  verticalRatio: ->
    top = @["#{@indicatorName}10"]
    bot = @["#{@indicatorName}0"]
    assert(top >= bot, "#{@constructor.name} data error, #{@indicatorName}10 #{top} < #{@indicatorName}0 #{bot}")
    if top is bot
      0
    else
      fix(100 * top / bot - 100)
  
  # level的特點是最小0,最大10,不會超過底線頂線,故沒有11級,故計算略有調整
  ohlcScore:(indicatorValue,idx,pool)->
    indicator = indicatorValue
    {high,low,open,close} = @bar
    fixed = fixAll({high,low,open,close,indicator})
    for ohlc in ['high','low','close','open']
      if fixed.indicator > fixed[ohlc] >= fix((@[@label(idx - 1)] ? 0))
        @bar["#{ohlc}#{@indicatorName}"] = idx - 1
      else if (idx is 10) and (fixed[ohlc] >= fixed.indicator)
        @bar["#{ohlc}#{@indicatorName}"] = idx
    @levelTopBot?.comingBar(@bar,pool)
    

  isNewHigh:(pool,aBar=@bar) ->
    aBar.level10 > pool.barBefore(aBar)?.level10

  # high > scoren 用於過濾偏低的價格
  top:->
    {ta, tay,tay1,high,close,score8,score7} = @bar
    high > score7 and tay1 >= ta and (tay >= ta or true) # true 應替換為可以取代 tay > ta 的限制條件
  
  # 本身是第一天,故fish.previousBar 不存在
  yinfishFake:(pool)->
    {yinfish,yinfish:{previousBar,earlierBar}} = pool
    {close,level0,level5,level6} = @bar
    if @previousBar? and not previousBar?  #假突破 注意必須配合上行
      pre = @previousBar
      level0 < pre.level0 and (close <= level6 or close <= pre.level6)
    else if (not earlierBar?) and previousBar? #次日即跌. 需要特殊處理的原因是,此時,tay 不可能高於 ta 故會被忽略
      pre = @previousBar
      @bar.close < pre.low < pre.level8
    else
      false









    
# 特殊處理的買賣策略,放在特別的LevelFlow 中定義
class ForexLevelFlow extends LevelFlow



class HKSecLevelFlow extends LevelFlow
  constructor:(@contractHelper,@secCode,@timescale,@contract,@pureYinYang=pureYinYang,@recordInBar=levelIntoBar)->
    super(@contractHelper,@secCode,@timescale,@contract,@pureYinYang,@recordInBar)
    @maxVerticalGrade = null
    @nowVerticalGrade = null
    @gradeHistory = [] # 那些創紀錄的bar

  hkGradeRecord:->  
    @nowVerticalGrade = @hkVerticalGrade()
    @maxVerticalGrade ?= @nowVerticalGrade
    if @nowVerticalGrade > @maxVerticalGrade
      if @nowVerticalGrade > 0.006
        @gradeHistory.push(@bar)
      @maxVerticalGrade = @nowVerticalGrade

  hkVerticalGrade:->
    top = @["#{@indicatorName}10"]
    bot = @["#{@indicatorName}0"]
    if top is bot
      0
    else
      fix(top - bot)
  
class HKStkLevelFlow extends HKSecLevelFlow

# 港股集中做恆指牛熊證等衍生產品
class HSILevelFlow extends HKSecLevelFlow

class IOPTLevelFlow extends HKSecLevelFlow


# 美國股市是超級強勢多頭市場,故策略簡單直接,但未必適用於其他市場
class USStkLevelFlow extends LevelFlow
  top: ->
    @bar.high > @level9 #@["#{@indicatorName}9"]

class USOPTLevelFlow extends USStkLevelFlow 

module.exports = {ScoreFlow,YScoreFlow,LayerFlow,LevelFlow}