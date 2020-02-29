### XFlow(X for Cross) 一物一用
定義: 
  X 是指穿透.此法跟蹤指定目標的穿透情況,主要是被股價穿透.亦可擴展為跟蹤線線互相穿透.

工作:
  維護變量 baseUpXName, farUpXName, baseDownXName, farDownXName

意義:
  根據以上四個變量,即可生成,變更,以及清理維護買賣信號
  ----- @bar[@baseDownXName] ------   bestPrice for selling
  - - - - - - - - - - - - - - -
  ----- @bar[@farDownXName] ------
  - - - - - - - - - - - - - - - - -   worstPrice for selling
  ----- @bar[...] ------
  - - - - - - - - - - - - - - -
  ----- @bar[...] ------
  - - - - - - - - - - - - - - - - -   worstPrice for buying  
  ----- @bar[@farUpXName] ------
  - - - - - - - - - - - - - - -
  ----- @bar[@baseUpXName]   ------   bestPrice for buying

協作:
  可協同 CordonFlowBase 完成工作


# events
穿透發生時,所在法類已經跟蹤並捕捉到,只需emit(aCrossingEvent)即可,何須此法延後搜集?
主要是代碼似乎可以簡化並且集中,易懂易於維護.另外,對於穿透發生的燭線,是已經完成的,還是過程中的,如果用emit的方式,檢測起來可能
比較繁瑣.此法則利用dataflow的一個特性,處理剛剛完成的燭線的穿透很容易.
亦可用此法記錄既成穿透,而用emit實時報告正在發生的穿透,結合使用,則此法僅需記錄歷史穿透,不必記憶即時的穿透現象.但由於涉及時間
先後可能造成的混亂,故乾脆都在本法中處理.

# 歷史沿革:
之前穿越跟蹤嵌入於 dataflow _ basex, 應該獨立為一個flow,然後在各法中引用即可
優點:
   代碼集中,容易理解,容易維護管理
   各線回歸單一的功能,穿透屬於可以自立門戶的功能,分離出來,簡化系統
缺點(或有):
   若保留諸線各自能力,則須將此法嵌入各線,需要改動現有系統,待有空再做
   若不保留各線能力,則更簡潔,但似乎有越俎代庖的嫌疑?
放置:  
  本法本應放置於 tracer, 可惜目前 Explorer 和 Guardian 的關係沒擺好,既非繼承亦非主從,故為令兩者皆可使用,只好放置於pool
  其他flow之後, tracer兩法之前
後續清理:
  本法用到的 @bar.detectUpCross(lineName, formerBar) 之前僅在 dataflow_basex中用到,在bar中記錄下穿透,故此,有本法之後,
  原有的dataflow_basex 以及之下的 dataflow_ trade 皆可不用,有空可清理

###

assert = require './assert'
{BaseDataFlow} = require './dataflow'
Crossing = require './crossing'
CrossingRangeBase = require './_crossingRange_'
{levelNames,cordonNames,recordCordonHistory} = require './config'
XFlowBase = require './xflow'


class XFlowRanges extends XFlowBase

  # 注意用了 {} 作為參數
  constructor:({@contractHelper,@cordonNames,@symbolUp,@symbolDown,@cordonType,@recordInBar})->
    super({@contractHelper,@cordonNames,@symbolUp,@symbolDown,@cordonType,@recordInBar})
    @cordonRanges = null
    # 這些數據在bar中都有,所以屬於冗餘記憶,單純為了研究方便,研究完就可以不用了.只需要注釋即可:  
    @cordonHistory = []

  firstBar:(pool)->
    super(pool)
    @initRanges()

  initCordons:->
    @cordons = CordonFlowBase.pickAllLevel(@contractHelper)

  initRanges:->
    {baseUpXName,farUpXName} = @bar.knownUpXLineNames()
    {baseDownXName,farDownXName} = @bar.knownDownXLineNames()
    @cordonRanges = CrossingRangeBase.pick({baseUpXName,farUpXName,baseDownXName,farDownXName,@bar,@cordonType,@contract})

    
  # 這裡可以寫想在bar確認完成之後做的額外的事情,例如更新數據庫等等
  # 注意: 在不同的Objects組合工作的情況下,previousBar 會出現異步, 例如經常引用 pool.previousBar 需要謹慎小心,盡力避免
  # 尤其是在以下beforePushPreviousBar function內部,引用外部的previousBar 結果會出乎意料
  # 此時必有 @previousBar
  beforePushPreviousBar:(bar,pool)-> 
    super(bar,pool)
    {baseUpXName,farUpXName} = @bar.knownUpXLineNames()
    {baseDownXName,farDownXName} = @bar.knownDownXLineNames()
    @_addHistory({baseUpXName,farUpXName},{baseDownXName,farDownXName},bar)
    @cordonRanges?.updateRange({baseUpXName,farUpXName,baseDownXName,farDownXName,@bar})

  # 這些數據在bar中都有,所以屬於冗餘記憶,單純為了研究方便,研究完就可以不用了.只需要注釋constructor中的@cordonHistory=[]即可
  _addHistory:({baseUpXName,farUpXName},{baseDownXName,farDownXName},bar)->
    @cordonHistory?.push({baseUpXName,farUpXName,baseDownXName,farDownXName,day:bar.day})









class XFlowBaseAlien extends XFlowBase

  # 注意用了 {} 作為參數
  constructor:({@contractHelper,@cordonNames,@symbolUp,@symbolDown,@cordonType,@recordInBar})->
    super({@contractHelper,@cordonNames,@symbolUp,@symbolDown,@cordonType,@recordInBar})
    # 另須記憶 baseUpXName/baseDownXName(may not from lastest bar), farUpXName/farDownXName(from latest bar)
    # 太困明天再思考如何做

    # 追蹤最近結果,
    # 注意: 對象可能是尚未完成的bar 
    # {cdname:{xtype: lableUp/symbolDown, bar}}
    @cordonState = {}
    # 以下兩個變量必須在 beforePushPreviousBar() 內更新, 以記錄已經收盤的確定狀態
    # 追蹤最近結果,
    # 注意: 對象限於已完成的bar 
    # {cdname:{xtype: lableUp/symbolDown, bar}}
    @cordonStateVerified = {}
    @cordonStateVerifiedFormer = {}
    # history, if needed.
    # {cdname:[{xtype,bar}]}

    # 若bar記錄crosses,則此數據可以從 @barArray 中抽取,無須另外存儲記憶
    # 若bar不欲記錄,則此法可以保留歷史數據;若欲更快檢索,亦可保留此法
    if recordCordonHistory
      @cordonHistory = {}

  # -------------   constructor end   -------------

  # 這裡可以寫想在bar確認完成之後做的額外的事情,例如更新數據庫等等
  # 注意: 在不同的Objects組合工作的情況下,previousBar 會出現異步, 例如經常引用 pool.previousBar 需要謹慎小心,盡力避免
  # 尤其是在以下beforePushPreviousBar function內部,引用外部的previousBar 結果會出乎意料
  # 此時必有 @previousBar
  beforePushPreviousBar:(bar,pool)-> 
    super(bar,pool)

    # 此時@bar是準@previousBar, 記錄已經確定的既往狀態
    for lineName in @cordonNames
      xtype = @verifiedXType(pool,lineName)
      if xtype?
        former = @cordonStateVerified[lineName]
        if former? then @cordonStateVerifiedFormer[lineName] = former  
        
        @cordonStateVerified[lineName] = Crossing.pick(xtype,lineName,@bar,@contract)
        if recordCordonHistory
          @cordonHistory[lineName] ?= []
          @cordonHistory[lineName].push(@cordonStateVerified[lineName])


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
    for lineName in @cordonNames
      xtype = @detectXType(pool, lineName, firstBar)
      if xtype?
        @cordonState[lineName] = Crossing.pick(xtype,lineName,@bar,@contract)


  # 存在並無上穿或下穿的情況,此時xtype為null
  detectXType: (pool,lineName,firstBar=false)-> 
    xtype = null
    # 避免使用 pool.previousBar (潛存異步風險), 故使用 pool.barBefore(@bar)
    formerBar = if firstBar then null else pool.barBefore(@bar)
    if @bar.detectUpCross(lineName, formerBar)
      xtype = @symbolUp
    else if @bar.detectDownCross(lineName, formerBar)
      xtype = @symbolDown
    # 由於bar可能正在交易尚未完成,故會出現重複報告相對於已經完成的previousBar的穿透情形,且應記錄在@bar內,
    # 因活動@bar流失僅存最後結果故; 但此時不必log為新發現:
    #assert.log('[detect X] ',@bar.day,xtype,lineName,@bar[lineName], @bar.close) if xtype? and (@bar.date > @lastBar?.date or @bar.close isnt @lastBar?.close)   
    return xtype
  
  # 已經getXType標記過,只需提取
  verifiedXType:(pool,lineName,firstBar=false)-> 
    xtype = null
    if @bar.knownUpCross(lineName)
      xtype = @symbolUp
    else if @bar.knownDownCross(lineName)
      xtype = @symbolDown
    #assert.log('[verified X] ',@bar.day,xtype,lineName,@bar[lineName], @bar.close) if xtype? #and false
    return xtype







module.exports = XFlowBaseAlien

