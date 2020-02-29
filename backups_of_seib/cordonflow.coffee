### CordonFlowBase 關鍵臨界線
  用於 BuoyFlow 方便根據追蹤關鍵臨界線的穿越的結果確定交易時間和價格(best/worst)
  上下檔:
    定義次第排序的 [],相鄰兩項互為上下
    買賣的次第或可相反或應相同,總之需要方便使用,不易出錯.
  合適的結構有:
    levels: 相鄰為上下,兩端為[level0, level10]
  為了簡化,使用時,就不分買賣兩種情形吧
###

assert = require './assert'
PairCordonBuoy = require './pair_cordonbuoy'
BaseDataFlow = require './dataflow_base'
{fix} = require './fix'
{useOverlock, cordonLimits:{levelLimit, bbandLimit}} = require './config'



class CordonFlowBase extends BaseDataFlow
  @pickAllLevel:(contractHelper,obj={}) ->
    # cordonIndex 從 @cordonOrder 提取
    for cordonIndex in @cordonOrder
      cordon = new LevelCordonFlow({contractHelper,cordonIndex})
      obj[cordonIndex] = new PairCordonBuoy({cordon})
    return obj

  # 按照當前設計,上下兩端的指標分別僅適合賣出,買入
  @cordonOrder:[
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

  # 按照當前設計,上下兩端的指標分別僅適合賣出,買入
  @bbandOrder:[
    'closeLowBand'
    'closeLowHalfBand'
    'bbandma'
    'closeHighHalfBand'
    'closeHighBand'
  ]
  
  @symbolUp: 'up'
  @symbolDown: 'down'



  constructor:({@contractHelper,@cordonIndex})->
    # 此變量可用於存儲最近的已確定穿越狀態標誌,以便操作決策
    super(@contractHelper)
    @buoyNamePrefix = null
    @latestCrossBar = null
  

  # 此時沒有 @previousBar
  firstBar:(pool)->
    super(pool)
    @updateCordonState(pool,true)

  # 此時必有 @previousBar
  nextBar:(pool)->
    super(pool) 
    @updateCordonState(pool)  

  # 此時可能是由尚未完成的 @bar 所造成的臨時狀態
  updateCordonState:(pool,firstBar=false)->
    former = if firstBar then null else pool.barBefore(@bar)
    @bar.detectCrosses(@cordonIndex, former)


  ### beforePushPreviousBar 須謹慎使用,因會造成時空狀況複雜難懂易錯.
  # 此法會在 nextBar 之前執行, 執行後, 所在的 comingBar() 會令 @bar = bar, 然後執行 nextBar
  # 大部分情況或可避免使用,而改在 nextBar 中引用 previousBar 的狀態
  # 此處實質代碼已經過審閱,未發現問題. 
  # 檢查日期:(後續檢查應同樣記錄日期)
  #   [20171107] 未發現問題.
  ###
  beforePushPreviousBar:(pool)->
    super(pool)
    @_dealWithCross(pool)

  # 應放在 beforePushPreviousBar 內以便檢測既成事實.
  _dealWithCross:(pool)->
    cordon = this
    finishedBar = @bar
    switch
      when finishedBar.knownUpCross(@cordonIndex)
        @resetCordonBeforePushPreviousBar(@constructor.symbolUp, pool)
      when finishedBar.knownDownCross(@cordonIndex)
        @resetCordonBeforePushPreviousBar(@constructor.symbolDown, pool)


  # @edgePrice 不動的; 發現有時候太近,以至於不斷跳級但始終無法成交,故須放大到隔層, 命名為 @overlockPrice
  resetCordonBeforePushPreviousBar:(@buoyNamePrefix,pool)->
    finishedBar = @bar
    @latestCrossBar = finishedBar
    assert(finishedBar?, 'no bar error occured in reset Cordon Before Push Previous Bar')
    @basePrice = finishedBar[@cordonIndex]
    switch @buoyNamePrefix
      when @constructor.symbolUp
        @overlockPrice = @_evenHigherOrSelfCordonPrice(finishedBar)
        @edgePrice = @_higherOrSelfCordonPrice(finishedBar)
        # 一度發現無 edgePrice 問題,經查是由源數據錯誤 bar 內各項為0造成的,已經在源數據模塊修正此錯誤,以下檢測或可保留
        assert(@edgePrice, "證券代碼 #{@secCode}:#{finishedBar['level9']},#{finishedBar[@_higherOrSelfCordonName()]} no edgePrice, cordon name:#{@cordonIndex}, higher cordonIndex:#{@_higherOrSelfCordonName()}")        
      when @constructor.symbolDown
        @overlockPrice = @_evenLowerOrSelfCordonPrice(finishedBar)
        @edgePrice = @_lowerOrSelfCordonPrice(finishedBar)
        # 一度發現無 edgePrice 問題,經查是由源數據錯誤 bar 內各項為0造成的,已經在源數據模塊修正此錯誤,以下檢測或可保留
        assert(@edgePrice, "證券代碼 #{@secCode}:#{finishedBar['level1']},#{finishedBar[@_lowerOrSelfCordonName()]} no edgePrice, cordon name:#{@cordonIndex}, lower cordonIndex:#{@_lowerOrSelfCordonName()}")
      else
        # 因首日起均檢查穿透情況,當準備記錄此 bar 為 previuosBar 時,若仍無 @buoyNamePrefix 記錄上次上穿下穿,則必有錯誤
        assert.fail("#{@buoyNamePrefix},size:#{@size} ")
    pool.crosses.cordonBuoys[@cordonIndex].resetBuoy()


  _orderIndex:(cordonIndex=@cordonIndex) -> 
    @constructor.cordonOrder.indexOf(cordonIndex)
  
  # 因應買賣方向選擇部分的cordon作為操作依據;理論上似乎可行,實際效果不佳,故備考
  __suitableFor__: (buoy)->
    assert.subJob()

  # 不需移植  
  xUpLatest:->
    assert(@buoyNamePrefix?,'wrong, no latest cross')
    @buoyNamePrefix is @constructor.symbolUp

  # 不需移植  
  xDownLatest:->
    assert(@buoyNamePrefix?,'wrong, no latest cross')  
    @buoyNamePrefix is @constructor.symbolDown

  # 此處使用的價格基準必須和 buoyflow 一致
  # 差異: 
  # edgePrice 出現單一的 buoy, 跟蹤交易區間就是一層樓; 樓層空間有時候不夠高,因此會出現跳級卻不成交情形
  # overlockPrice 可能同時出現兩個 buoy, 區間放寬到臨近的兩層樓,因此兩個 buoy 有一層重疊,這樣其中一個成交的機會增加
  arround: (aBar)->
    {close} = aBar
    endPrice = if useOverlock then @overlockPrice else @edgePrice
    switch @buoyNamePrefix
      when @constructor.symbolUp
        @basePrice <= close <= endPrice
      when @constructor.symbolDown
        @basePrice >= close >= endPrice

  isHigherThan: (cordonIndex) ->
    @cordonIndex? and cordonIndex? and (@_orderIndex() > @_orderIndex(cordonIndex))
  isLowerThan: (cordonIndex) ->
    @cordonIndex? and cordonIndex? and (@_orderIndex() < @_orderIndex(cordonIndex))

  # 上極則自薦
  _higherOrSelfCordonName: -> 
    @constructor.cordonOrder[@_orderIndex() + 1] ? @cordonIndex
  # 下極則自薦
  _lowerOrSelfCordonName: -> 
    @constructor.cordonOrder[@_orderIndex() - 1] ? @cordonIndex
  # 上極則自薦
  _evenHigherOrSelfCordonName: -> 
    {cordonOrder} = @constructor
    cordonOrder[@_orderIndex() + 2] ? cordonOrder[cordonOrder.length-1]
  # 下極則自薦
  _evenLowerOrSelfCordonName: ->
    {cordonOrder} = @constructor   
    cordonOrder[@_orderIndex() - 2] ? cordonOrder[0]
  
  _higherOrSelfCordonPrice: (bar)->
    bar[@_higherOrSelfCordonName()]
  _lowerOrSelfCordonPrice: (bar)->
    bar[@_lowerOrSelfCordonName()]
  _evenHigherOrSelfCordonPrice: (bar)->
    bar[@_evenHigherOrSelfCordonName()]
  _evenLowerOrSelfCordonPrice: (bar)->
    bar[@_evenLowerOrSelfCordonName()]



class LevelCordonFlow extends CordonFlowBase

 




module.exports = CordonFlowBase
