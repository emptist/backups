DataFlow = require './dataflow'
{Flow:{zeroLevel,traceItem,bullLength}} = require './config'
{fix} = require './fix'
divisionPoint = 0 #zeroLevel

# 採用 DataFlow 重新設計的 魚
# 特點:
# barArray 是本魚的bars(若是最末一條,則還需加上 @lastBar)
# @startBar 為頭, @previousBar 為尾
# 最後一條魚 @lastBar 為不確定,一旦確定,就已經成為 @previousBar 而 @lastBar 為下一魚頭
# 


# 新版本沒有 協均 部分, 需要時可單列之作為新法
class FishFlow extends DataFlow
  ### 生成魚時需提供 @頭: {序:n,數:x} 數據
  ###
  constructor: (@options={})-> # @secCode, @週期名 非必須
    {
      @secCode
      @週期名
      @fishName = @constructor.name.toLowerCase() # 可以重設,且與原有系統無衝突
      @tbaName = null # 在燭線中記錄天地均值所用名,若為null,則不計算均值;但 fishZ 定義為默認計算均值,無論是否提供此參數
      @rawName = null # 用於計算天地線所依據原始數據名,如 高低,長短均線等等
      @cornerName = null # 計算 cornerBar 
    } = @options
    @cornerName ?= @rawName
    @cornerBar = null # 拐點或稱之為極點
    @endBar = null
    @formerEndBar = null # 前魚之魚尾 bar
    @retrograde = false # 若有退位,則會更改
    @forward = false # 創新記錄之新魚,非退化魚

    super(@secCode,@週期名) 


  firstBar:(pool) ->
    @cornerBar = @bar
    if @tbaName?
      @bar[@tbaName] = fix(@bar[@rawName])
      @anyCrossed(@tbaName)
  
  nextBar:(pool) ->
    if @anotherFish(pool)
      # 此處設計與舊版魚重大差異,舊版的魚Array最後一條魚是最新的,此處必須是已經完成的,即前一條成型的魚.新版更合理
      # 注意此處有玄機.
      # 根據 DataFlow 之定義,至此,我必有 @previousBar , 否則仍在 firstBar(pool) 中. 但隨後我即消失不可見,
      # 故實際上此 @previousBar 僅僅過渡,對後續計算來說,亦不可見.故不存在問題.
      if @previousBar isnt @startBar
        @endBar = @previousBar
        pool["#{@fishName}Array"]?.push this

      f = @newSelf()
      f.retrograde = @retrograded(@bar[@rawName], @startBar[@rawName])
      f.forward = not f.retrograde
      f.formerEndBar = @previousBar ? @startBar # 我自己可能才開始便結束
      f.comingBar(@bar,pool)
      pool[@fishName] = f
    else
      # cornerBar 走向與魚生滅方向相反,且初成即決定,故不必顧慮 @bar 完成與否
      @forward = false
      @recordCorner(pool)
      if @tbaName?
        {length} = @barArray
        delta = @bar[@rawName] / (length+1)
        @bar[@tbaName] = fix(delta + (@previousBar[@tbaName] * length / (length + 1)))
        @anyCrossed(@tbaName)


  beforePushPreviousBar:(pool)->
    super(pool)

  retrograded:(nowValue,formerValue)->
    return false

  newSelf:()->
    Fish = @constructor
    新 = new Fish(@options)

    list = [
      'fishName', 
      'rawName',
      'tbaName',
      '回幅',
      '轉勢臨界幅度',
      '協價名',
      '協權',
      '協均前燭',
      '協均基數'
    ] 

    新[某名] = this[某名] for 某名 in list when this[某名]?
      
    return 新


  cornerDistance:->
    #@barArray.length - @barArray.indexOf(@cornerBar)
    @barArray.indexOf(@previousBar) - @barArray.indexOf(@cornerBar)
  
  startedUpon:(indicatorName) ->
    @startBar[@tbaName] > @startBar[indicatorName]
  startedBelow:(indicatorName)->
    @startBar[@tbaName] < @startBar[indicatorName]
  
    

  # 已經驗證正確
  _isCorrect:->
    a = @barArray[-1..][0][@tbaName]
    b = 0
    b += bar[@rawName] for bar in @barArray
    console.log "should equal:", a, b / @barArray.length

class YinFish extends FishFlow
  constructor: (@options={})->
    super(@options)

  anotherFish:(pool)->
    @bar[@rawName] > @startBar[@rawName]
  
  recordCorner: (pool)->
    # 極值,在yinfish為極低的數值
    if @cornerBar[@cornerName] > @bar[@cornerName]
      @cornerBar = @bar

  retrograded:(nowValue,formerValue)->
    nowValue < formerValue
  
  
  # 重要思路,試過有用,在找到其他醫用方式之前,保留勿刪!!!
  有用備考_longFilteredEntry:(pool)->
    limit = 3
    host = pool[@homeName ? 'yangfish'] # 陰魚 yinfish 沒有 @homeName
    bearEnd = (@size * 2) > host.size > limit    
    ready = bearEnd #or bull
    return ready and @bar.upXName?
  

  # 舊代碼. 新方法見pool bullish bearish
  isBull:(len=bullLength)->
    (not @retrograde) and (@barArray.length < len)
  isBear:(len)->
    not @isBull(len)
  
  # 本身是第一天,故previousBar 不存在
  fake:(previousBar)->
    {close,level0,level5,level6} = @bar
    if previousBar? and not @previousBar?  #假突破 注意必須配合上行
      pre = previousBar
      level0 < pre.level0 and (close <= level6 or close <= pre.level6)
    else if not @earlierBar? and @previousBar? #次日即跌. 需要特殊處理的原因是,此時,tay 不可能高於 ta 故會被忽略
      pre = @previousBar
      @bar.close < pre.low < pre.level8
    else
      false
  
  downCrossedHigh: ->
    @tbaName in @bar.downCrosses and (@startBar.outOfHighBand() or @startBar.higherThan('level9') or @bar.higherThan('ema_price20'))
    

class YangFish extends FishFlow
  constructor: (@options={})->
    super(@options)

  anotherFish:(pool)->
    @bar[@rawName] < @startBar[@rawName]

  recordCorner: (pool)->
    # 極值,在yangfish為極高的數值
    if @cornerBar[@cornerName] < @bar[@cornerName]
      @cornerBar = @bar
  
  retrograded:(nowValue, formerValue)->
    nowValue > formerValue

  maDown:(maName)->
    @startBar[maName] > @bar[maName] or (not @earlierBar? or (@earlierBar[maName] > @bar[maName]))
  

# 對應於舊版yinfishx/yangfishx, 注意設計好變量名,以便保護原有引用代碼
class YinFishX extends YinFish
  constructor: (@options={})->
    super(@options)
    {@回幅} = @options

  firstBar:(pool)->
    super(pool)
    @bar.hirx = 0
  nextBar:(pool)->
    super(pool)
    @bar.hirx = fix((@bar[@rawName] / @startBar[@rawName])*100 - 100)

  anotherFish:(pool)->
    belowTa = (not @tbaName?) or (@bar[@rawName] < @previousBar[@tbaName])
    super(pool) or (belowTa and (@bar[@rawName] > @cornerBar[@rawName]*(1+@回幅)))
  
  # 這裡有個潛在bug,即,只能用 tax / ta 兩個名字
  realBull:(len)->
    @isBull(len) and (@bar.tax > @bar.ta) 
    
class YangFishX extends YangFish
  constructor: (@options={})->
    super(@options)
    {@回幅} = @options

  firstBar:(pool)->
    super(pool)
    @bar.lorx = 0
    @lorxTurnedDown = false
  
  nextBar:(pool)->
    super(pool)
    @bar.lorx = fix((@bar[@rawName] / @startBar[@rawName])*100 - 100)
    
    # 當前lorx有升轉跌,跌幅過1/100.由於動魚受到參數影響,故盡量不用此指標.
    # a?.x > b?.y 經測試可以如此寫,勿懷疑慮,若不存在,則答false
    @lorxTurnedDown = (@earlierBar?.lorx > 0 or @previousBar?.lorx > 0) and @lineTurnedDown('lorx', 1 / 100)

  anotherFish:(pool)->
    onBa = (not @tbaName?) or (@bar[@rawName] > @previousBar[@tbaName])
    super(pool) or (onBa and (@bar[@rawName] < @cornerBar[@rawName]*(1-@回幅)))


class YinFishZ extends YinFish
  constructor: (@options={})->
    super(@options)
    @tbaName ?= 'taz'

  anotherFish:(pool)->
    super(pool) or (@previousBar[@rawName] >= divisionPoint > @bar[@rawName] and @startBar[@rawName] > zeroLevel) 

class YangFishZ extends YangFish
  constructor: (@options={})->
    super(@options)
    @tbaName ?= 'baz'
  
  anotherFish:(pool)->
    super(pool) or (@previousBar[@rawName] >= divisionPoint  > @bar[@rawName] and (@cornerBar[@rawName] > zeroLevel)) 


# 若要嘗試變更條件,可用以下class 實驗
class YinFishZZ extends YinFishZ
  anotherFish:(pool)->
    super(pool) or (@previousBar.high >= @previousBar[traceItem] > @bar.high and @startBar[@rawName] > zeroLevel)
class YangFishZZ extends YangFishZ
  anotherFish:(pool)->
    super(pool) or ((@previousBar.low >= @previousBar[traceItem] > @bar.low) and (@cornerBar[@rawName] > zeroLevel))


# 陰陽魚可以有另一種寫法,即,創新低之後或創新高之後,都開始新陰魚,由於我們系統以做多為主,故常用的是 YangFishY
# 同樣的效果,可以不用創建新的class, 用在陰魚中,存放陽魚,每段陰魚即成為pool,這種方式也可以實現,但是涉及到嵌套
# 下面都嘗試一下看哪種方式更靈活方便
class YangFishY extends YangFish
  # 需要在 homeFish 之後計算,並且知道 homeName
  constructor:(@options={})->
    super(@options)
    {@homeName} = @options

  anotherFish:(pool)->
    super(pool) or (pool[@homeName].startBar is @bar)
  
  firstBar:(pool)->
    super(pool)
    @bar.lory = 0
    @lorxTurnedDown = false
  
  nextBar:(pool)->
    super(pool)
    @bar.lory = fix((@bar[@rawName] / @startBar[@rawName]) * 100 - 100)
    
    # 當前lory有升轉跌,跌幅過1/100.由於動魚受到參數影響,故盡量不用此指標.
    # a?.x > b?.y 經測試可以如此寫,勿懷疑慮,若不存在,則答false
    @lorxTurnedDown = (@earlierBar?.lory > 0 or @previousBar?.lory > 0) and @lineTurnedDown('lory', 1 / 100)



class YinFishY extends YinFish
  # 需要在目標(宿主) homeFish 之後計算,並且知道 homeName
  constructor:(@options={})->
    super(@options)
    {@homeName} = @options

  anotherFish:(pool)->
    super(pool) or (pool[@homeName].startBar is @bar)
  
  firstBar:(pool)->
    super(pool)
    @bar.hiry = 0
  nextBar:(pool)->
    super(pool)
    @bar.hiry = fix((@bar[@rawName] / @startBar[@rawName]) * 100 - 100)


module.exports = 
  FishFlow:FishFlow
  
  YinFish:YinFish
  YinFishX:YinFishX
  YinFishY:YinFishY
  YinFishZ:YinFishZ
  YinFishZZ:YinFishZZ

  YangFish:YangFish
  YangFishX:YangFishX
  YangFishY:YangFishY
  YangFishZ:YangFishZ
  YangFishZZ:YangFishZZ