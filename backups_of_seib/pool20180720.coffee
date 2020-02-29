_ = require 'lodash'
path = require 'path'
moment = require 'moment-timezone'
_assert = require path.join __dirname,'..','..','devAssert'

{fix} = require path.join __dirname,'..','..','fix'
{hists} = require path.join __dirname,'..','..','sedata'
{IBCode} = require path.join __dirname,'..','..','codemanager'
{MaFlow,EMaFlow,EMaFishFlow} = require path.join __dirname,'..','..','maflow'
{BBandFlow,BBandFishFlow} = require path.join __dirname,'..','..','bbandflow'
BaseDataFlow = require path.join __dirname,'..','..','dataflow_base'

{CCEFlowGgXt,CCEFlowBxbtXt,CCEFlowAxatXt,CCEFlowFfXt,CCEFlowAxatFf,CCEFlowBxbtFf} = require path.join __dirname,'..','..', 'exchangecrossflow'

LearnFlow = require path.join __dirname,'..','..','learnflow'
{NewBuoyFlow} = require path.join __dirname,'..','..', 'buoyflow'

OPTOperatorBase = require path.join __dirname,'..','..', 'optOperator' 

RatioFlow = require path.join __dirname,'..','..','ratioflow'
RSIFlowBase = require path.join __dirname,'..','..','rsiflow'
ContractHelperBase = require path.join __dirname,'..','..', 'contractHelper'
{SimpleListDB} = require path.join __dirname,'..','..', 'e_db', 'dbmanager'
{YinSemiCycleFlow} = require path.join __dirname,'..','..', 'semicycleflow_base'

{
  availableSecTypes,dev,doCloseWindow,barsLeadFishShift,optCloseOpposites,forbidInsteadOfConvert,markPut
  ioptRoots,optBuoySelectSignal,optOpenByAny,optOpenCloseStrictly,optRoots,optSetAllOperators,optsOnly,
  research,signalNotFollowBuoy,strongGradeIndex,swimOnFishNames,buoyStrategyDone,
  takeRiskSimplyLong,tighter,topFishY,myFavorites,no_auto
  Flow: {zeroLevel, rmaArg, pureYinYang}
} = require path.join __dirname,'..','..','config'

{YinFish,YangFish,YinFishB,YangFishB,YangFishF,YangFishT,YinFishF,YinFishX,YinFishY,YangFishY,YangFishX} = require path.join __dirname,'..','..','fishflow'
{TopBotProbabs} = require './topbotflow'
{UpLasting} = require path.join __dirname,'..','..','lasting'

simple = true

### 池 以游魚
定義:
  就是讀取時序ObsoleteBArray數列(最為關鍵的是高低兩邊數據)求頂底指標(tor線/低)以及陰陽魚(天yangfishArray)
套疊:
  可以隨機取樣,算法不變.任何一組ObsoleteBArray數據都可以求池/魚.
  這將極度簡化天地頂底的套疊計算.
輸入:
  注意讀入的是ObsoleteBArray,而非ticks中的一筆成交.
  ticks乃至各級ObsoleteBArray(積聚),另外做接口接進來.
###

### 區間 有起止,其中起點預知,止住點未知
  若有sampleDataName,則高低皆取此單值計算陰陽魚等指標
  例如 ma_price10
###

# 起止無用,因僅僅需要對endIndex求內池


# 例如: new Pool({統計參數:{僅限最近:20}})
class Pool extends BaseDataFlow

  # 以 object 作為參數,寫法有些不同,注意需要另行設置默認值:
  constructor:(@poolOptions={})->
    # 高效的寫法是 {@某某=默認, @某甲, @某乙} = @poolOptions
    {
      @contract
      @forex
      @secCode
      @timescale
      statsTag # 默認為 'bor峰值統計'
      統計參數
      @selecting
    } = @poolOptions
    @forex ?= 'wallstreetcn'
    
    # contractHelper 將集中處理目前分散在各處的各種有關的計算,一物一用原則.
    @contractHelper = ContractHelperBase.pick({@contract, @timescale, @secCode})
    super(@contractHelper)

    @onDutyWithHistData = false

    # 注意以下設置的變量必須始終如一的,即常量,若需要不斷變動,就不適宜;彼時需要用 function 而非變量
    @_initAvailableForTrading()
    @refineSettings()

    @_initRSI()
    @_initMA()    
    @_initFishes()
    @initSemiCycles()
    @_initAliases()
    @_initOperators()
    @initStatistics()
    @initResearchMode()
    @initComplexMode()


  


  _initAvailableForTrading: ->
    # 以下不變
    {noOrdering, paperTrading} = @poolOptions
    {contract:{secType}} = @contractHelper
    
    # 一些證券不操作
    aimedAt = optsOnly and @contract.isAimedSec() 
    @availableForTrading = switch
      when not aimedAt then false
      when noOrdering then false
      when dev and secType is 'IOPT' then true  # for dev
      #when not @contractHelper.momentTrading() then false # 不可加此行,否則 buoy 在歷史數據注入階段不更新
      when paperTrading then true
      when @secCode in no_auto then false
      when not availableSecTypes[secType] then false
      else true
    



  refineSettings:->
    @bbandArg = 20 # 不同週期可以定制 
    @underlyingIndicator = 'ma_price150' # 各週期可定制

    # A股不能做期權,故採用新高才賣出方式,主要就是根據週線做納指100ETF 513100
    # false 牛市新高才賣出; true 牛熊兼顧,高點賣出.
    @coverBearAndBull = not @contract.isCHINA()  




  _initRSI:->
    n = 14
    @rsi = RSIFlowBase.pick({@contractHelper,n})


  # 注意以下的命名必須始終如一的,即常量,若需要不斷變動,就不適宜;彼時需要用 function 而非變量
  _initMA:->
    # 採用補充計算方法,如果源數據已有均值則不會重複計算
    @ema20 = new EMaFlow(@contractHelper, @secCode, @timescale,'bbandma','close', @bbandArg) 
    @bbma = @ema20
    @bband = new BBandFishFlow(@contractHelper, @secCode, @timescale,'bbandma','close', @bbandArg) # 亦可使用 ma_price20    
    @_initLineNames()



  # 注意以下的命名必須始終如一的,即常量,若需要不斷變動,就不適宜;彼時需要用 function 而非變量
  # 設置各處使用的上下邊際線線名,其結果為 'closeHighBand' 等等,隨後即可用 @bar[線名] 獲得指標數值
  _initLineNames: ->
    {highBandCName,highBandAName,highBandBName,lowBandCName,lowBandAName,lowBandBName, maName} = @bband
    @highestLineName = highBandCName
    @midLineName = maName
    @lowestLineName = lowBandCName
    if @contract.isCHINA() #or @contract.isCASH() or @contract.isIOPT()
      @lowerLineName = lowBandCName
      @lowLineName = lowBandBName
      @higherLineName = highBandCName
      @highLineName = highBandBName
    else
      @lowerLineName = lowBandBName
      @lowLineName = lowBandAName
      @higherLineName = highBandBName
      @highLineName = highBandAName      

    _assert.log({
      at: '_initLineNames'
      @lowerLineName
      @lowLineName
      @higherLineName
      @highLineName
    })



  # 注意以下的命名必須始終如一的,即常量,若需要不斷變動,就不適宜;彼時需要用 function 而非變量
  _initFishes:->  
    # 默認的 fishName 是 constructor.name.toLowerCase
    #@swimOnFishNames = swimOnFishNames # only set for debugging
    #swimOnFishNames = if @contract.isOPTIOPT() then ['yinfish','yangfish'] else swimOnFishNames
    # @signalFishName 跟 @buoyFishName 可以是同一個. 
    @signalFishName = null
    @buoyFishName = null
    
    # 亦可據 @timescale 因時制宜. theClass = if @timescale is 'minute' then XYZ else JKL

    # 凡與 class 名不同者,皆應明確指定

    # 難求完美,以下魚類幾經反復,測試結果互有得失,除非奇思妙想,勿再蹉跎歲月.勿求面面俱到,能抓住確定性機會即可
    @mayinfish = new YinFish({@contractHelper,fishName:'mayinfish',tbaName:'mata',rawDataName:'bbandma',cornerName:'bbandma'})
    @mayinfishArray = []    
    @mayinfishx = new YinFishX({@contractHelper,fishName:'mayinfishx',tbaName:'matax',rawDataName:'bbandma',cornerName:'bbandma'})
    @mayinfishxArray = []
    @mayangfishx = new YangFishX({@contractHelper,fishName:'mayangfishx',tbaName:'mabax',rawDataName:'bbandma',cornerName:'bbandma'})
    @mayangfishxArray = []
    
    @mayinfishb = new YinFishB({@contractHelper,fishName:'mayinfishb',tbaName:'matab',rawDataName:'bbandma',cornerName:'bbandma'})
    @mayinfishbArray = []
    @mayangfishb = new YangFishB({@contractHelper,fishName:'mayangfishb',tbaName:'mabab',rawDataName:'bbandma',cornerName:'bbandma'})
    @mayangfishbArray = []
  
    
    # 以上, 不依賴以下 fishes
    # 天地線之中間線命名為 mda, 無重名
    @yinfish = new YinFish({swimOnFishNames, @contractHelper,tbaName:'ta',rawDataName:'high',cornerName:'low'}) #,ratioName:'hir'
    
    @yangfisht = new YangFishT({@contractHelper,tbaName:'bat',rawDataName:'low',cornerName:'high',homeName:'yinfish'})
  
    @yangfishf = new YangFishF({@contractHelper,tbaName:'baf',rawDataName:'low',cornerName:'high',homeName:'yinfish'})
    @yinfishf = new YinFishF({@contractHelper,tbaName:'taf',rawDataName:'high',cornerName:'low',homeName:'yangfish'})
  
    # 兩者之中間線取名 mdx, 無重名
    @yinfishx = new YinFishX({swimOnFishNames, @contractHelper,tbaName:'tax',rawDataName:'high',cornerName:'low'})
    @yangfishx = new YangFishX({swimOnFishNames, @contractHelper,tbaName:'bax',rawDataName:'low',cornerName:'high'})
    
    @yangfish = new YangFish({swimOnFishNames, @contractHelper,tbaName:'ba',rawDataName:'low',cornerName:'high'})

    ### yinfishArray存yinfish,yangfishArray存yangfish,並非必須.
      若需要則去掉注釋,代碼無須改變.
      初始即放置,因yinfish yangfish設計,不會冗餘第一魚故

      魚Array中保存下來的魚,除了尚未完形的,都是長度大於1的
      找到最近長度大於某數值的魚,比較其尾.序與末魚之頭.序,可知單邊行情走了多久
    ###
    
    @yinfishArray = []
    @yangfishArray = []

    @yangfishfArray = []
    @yangfishtArray = []
    @yinfishxArray = []
    @yangfishxArray = []

    




  initSemiCycles: ->
    # 前綴表示 fish type, 順序為先陰後陽. g 指 @yinfish / @yangfish
    @semiCycleNames = ['ggCycle', 'ffCycle', 'gxCycle', 'xtCycle','xbtCycle']

    @ggCycle = new YinSemiCycleFlow({@contractHelper,cycleName:'ggCycle',cycleYinfish:@yinfish,cycleYangfish:@yangfish})
    @ggCycleArray = []

    @gxCycle = new YinSemiCycleFlow({@contractHelper,cycleName:'gxCycle',cycleYinfish:@yinfish,cycleYangfish:@yangfishx})
    @gxCycleArray = []

    @xtCycle = new YinSemiCycleFlow({@contractHelper,cycleName:'xtCycle',cycleYinfish:@yinfishx,cycleYangfish:@yangfisht})
    @xtCycleArray = []

    @ffCycle = new YinSemiCycleFlow({@contractHelper,cycleName:'ffCycle',cycleYinfish:@yinfishf,cycleYangfish:@yangfishf})
    @ffCycleArray = []

    # 嘗試混合組合
    # 必須使用 cycleHosts 告知相應的魚,以便更新時通知我們
    @xbtCycle = new YinSemiCycleFlow({@contractHelper,cycleName:'xbtCycle',cycleYinfish:@yinfishx,cycleYangfish:@bband.bbbyangfisht.addCycleHost(this)})
    @xbtCycleArray = []

    @cceNames = [
      'cceBgbgXt'
      'cceBgbgFf'
      'cceGgFf'
      'cceGgXt'
      'cceBxbtFf'
      'cceAxatFf'

      # 交易頻繁
      'cceFfXt'
      'cceBxbtXt'
      'cceAxatXt'
    ]

    # 靜態最外層
    cceName = 'cceBgbgXt'
    @[cceName] = new CCEFlowBxbtFf({@contractHelper,cceName,steadyCycle:@bband.bgbgCycle,shakyCycle:@xtCycle})

    # 靜態最外層
    cceName = 'cceBgbgFf'
    @[cceName] = new CCEFlowBxbtFf({@contractHelper,cceName,steadyCycle:@bband.bgbgCycle,shakyCycle:@ffCycle})

    # 靜態最外層
    cceName = 'cceGgFf'
    @[cceName] = new CCEFlowGgXt({@contractHelper,cceName,steadyCycle:@ggCycle,shakyCycle:@ffCycle})

    cceName = 'cceGgXt'
    @[cceName] = new CCEFlowGgXt({@contractHelper,cceName,steadyCycle:@ggCycle,shakyCycle:@xtCycle})

    # 動態最外層
    cceName = 'cceBxbtFf'
    @[cceName] = new CCEFlowBxbtFf({@contractHelper,cceName,steadyCycle:@bband.bxbtCycle,shakyCycle:@ffCycle})

    cceName = 'cceAxatFf'
    @[cceName] = new CCEFlowAxatFf({@contractHelper,cceName,steadyCycle:@bband.axatCycle,shakyCycle:@ffCycle})

    cceName = 'cceFfXt'
    @[cceName] = new CCEFlowFfXt({@contractHelper,cceName,steadyCycle:@ffCycle,shakyCycle:@xtCycle})

    cceName = 'cceBxbtXt'
    @[cceName] = new CCEFlowBxbtXt({@contractHelper,cceName,steadyCycle:@bband.bxbtCycle,shakyCycle:@xtCycle})

    cceName = 'cceAxatXt'
    @[cceName] = new CCEFlowAxatXt({@contractHelper,cceName,steadyCycle:@bband.axatCycle,shakyCycle:@xtCycle})





  # 注意以下的命名必須始終如一的,即常量,若需要不斷變動,就不適宜;彼時需要用 function 而非變量
  _initAliases: ->  
    @_buoys = {}  # key: fishName 
    
    for fname in swimOnFishNames
      # 先標記 @sellBuoyFishName / @buyBuoyFishName 等,
      if /^yin/i.test(fname)
        @putFishName = @shortSignalFishName = @buyBuoyFishName = fname
      else
        @callFishName = @longSignalFishName = @sellBuoyFishName = fname

      # init buoys
      #   特別注意: 
      #     當前設計, buoy 一經生成一直延續,否則以下命名就需要隨時更新
      
      # pick 依賴以上全部的 fishName 命名,故順序必須如此,不能分別插入 if...else... 條目之下
      @_buoys[fname] = NewBuoyFlow.pick(this, fname)  #(@[fname].swim)
      
      # pick 依賴以上全部的 fishName 命名,故順序必須如此,不能分別插入 if...else... 條目之下      
      @sellBuoy = @_buoys[@sellBuoyFishName]
      @buyBuoy = @_buoys[@buyBuoyFishName]






  otherBuoy:(buoy) ->
    if buoy is @buyBuoy then @sellBuoy else @buyBuoy






  _initBuoy: (fname) ->







  _initOperators:->
    ops = OPTOperatorBase.pick(@contractHelper)
    if ops?
      @optOperators = ops




  # dev tool
  dbSaveMe: ->
    db = new SimpleListDB({
      dbName: 'pool'
      dbFileName: 'db/pools.json'
      objectName: 'pools'
    }) 
    # 注意文件非常大
    db.addObj(this)





  # 取得非 signalFishName
  restFishName: ->
    for fname in swimOnFishNames when fname isnt @signalFishName
      return fname
  




  callSwim: -> 
    @[@callFishName].swim
  




  putSwim: -> 
    @[@putFishName].swim





  isLongPeriod: ->
    @isCallPeriod()




  isCallPeriod: ->
    @longSignalFishName is @signalFishName




  isShortPeriod: ->
    @isPutPeriod()




  isPutPeriod: ->
    @shortSignalFishName is @signalFishName





  # 按定義為開倉期; 有或沒有這些 fishName 的情形皆可支持
  isOpenPeriod: ->
    switch @signalFishName
      when @shortSignalFishName then switch
        when optOpenCloseStrictly then @buoyFishName is @sellBuoyFishName
        else @buoyFishName isnt @buyBuoyFishName
      when @longSignalFishName then switch
        when optOpenCloseStrictly then @buoyFishName is @buyBuoyFishName
        else @buoyFishName isnt @sellBuoyFishName
      else false
  




  # 按定義為平倉期; 有或沒有這些 fishName 的情形皆可支持
  isClosePeriod: ->
    switch @signalFishName
      when @shortSignalFishName then @buoyFishName is @buyBuoyFishName
      when @longSignalFishName then @buoyFishName is @sellBuoyFishName
      else false





  bbyangfishEarly: ->
    @bband.bbyangfish.startBefore(@bband.yinfish)




  bbandYinfishEarly: ->
    @bband.yinfish.startBefore(@bband.bbyangfish)




  mayangfishbEarly: ->
    @mayangfishb.startBefore(@mayinfishb)



  mayinfishbEarly: ->
    @mayinfishb.startBefore(@mayangfishb)


  mayangfishbAtCorner: ->
    (@mayangfishb.size > 0) and @mayangfishb.barIsCurrent(@mayangfishb.cornerBar)




  mayinfishbAtCorner: ->
    (@mayinfishb.size > 0) and @mayinfishb.barIsCurrent(@mayinfishb.cornerBar)


      

  mayinfishxEarly: ->
    @mayinfishx.startBefore(@mayangfishb)




  # 順序不可更改
  _renewSignalSwim:(fishName)->
    if fishName?
      @signalFishName = fishName
    else
      @_rootSecSignalFishName()    
    sswim = @_decideSignalSwim()
    @_setSignalSwim(sswim)



  _renewBuoySwim:(aName=null)->
    @_decideBuoyFishName(aName)
    @_setBuoySwim()
    @_renewSignalBuoy()




  _renewSignalBuoy: ->
    # 隨即生成及設置相應 objects
    
    if @_signalOrBuoyFishNameChanged()
      #_assert(@signalSwim?, 'no signal swim yet')
      @signalSwim?.defineSignalBuoy(this)
      @formerBuoyFishName = @buoyFishName
      @formerSignalFishName = @signalFishName

    # root sec signalSwim 未變,但抑或行情更新 strike 可能變化,抑或將發出強行平倉信號,故此重新選擇 opts
    @_reviewOptOperations()
    @_setChartSignalValue()




  _reviewOptOperations: ->
    if optOpenByAny 
      # 嘗試一下任意指定非當值 pool 看行不行,測試結果,不知何處有限制,導致@contractHelper.expiryArray 始終是null,待查
      if @timescale is 'hour' 
        @optSwim?.optSwimOperations(this) 
    else
      # @onDutyWithHistData 意味著已經接收完了歷史行情數據,所以好過 @isCurrentData() (盤後測試就比較麻煩)
      if @onDutyWithHistData and @timescale in ['minute','hour','day'] 
        @optSwim?.optSwimOperations(this) 
    



  _signalOrBuoyFishNameChanged: ->
    @signalFishName isnt @formerSignalFishName or @buoyFishName isnt @formerBuoyFishName




  _setChartSignalValue: ->
    # 此時 this 必定是 signalSwim, 或沒有 signalSwim 
    suggest = if @signalSwim? then @signalSwim._signalTypeSuggest(@buoySwim) else @_defaultType()
    @_setBarChartTrade()
    @_setBarChartTrendAs(suggest)
    @_debugSuggest(suggest)




  _defaultType:->
    'zeroKeep'




  # 繪圖用
  # 為了區分建議交易點性質,採用了不同的取值
  _setBarChartTrade: ->
    switch
      when markPut and @bar.chart_root_markUncertain then switch
        when @buoySwim?.preferBuying
          @bar.chartTrade = -0.6
        when @buoySwim?.preferSelling
          @bar.chartTrade = 0.6
      else switch
        when @buoySwim?.preferBuying
          @bar.chartTrade = -1.2
        when @buoySwim?.preferSelling
          @bar.chartTrade = 1.2



  # 繪圖用
  _setBarChartTrendAs:(suggest)->
    # 兩種畫法,第一種跟行情形態似乎更和諧,主要體現盈虛變化,謙受益滿招損,故滿則溢
    obj = if true
      longOpen: 0.7
      shortOpen: -0.7
      longKeep: 0.1
      shortKeep: -0.1
      longClose: 1
      shortClose: -1
      zeroKeep: 0
    else
      longOpen: 1
      shortOpen: -1
      longKeep: 0.1
      shortKeep: -0.1
      longClose: 0.7
      shortClose: -0.7
      zeroKeep: 0

    @bar.chartTrend = obj[suggest]
      
    _assert(@bar.chartTrend?,'error no chart trend mark')









  _debugSuggest:(suggest)->
    unless suggest? and @signalSwim?
      return
      
    assertion = (/short/i.test(suggest) and @signalSwim.isDownward()) or (/long/i.test(suggest) and @signalSwim.isUpward())

    if assertion
      return

    _assert.log(assertion, """wrong signal #{suggest} found at: _setChartSignalValue
        @signalSwim: #{@signalSwim.constructor.name}
        @bar: #{@bar.lday()},
        @lastBar: #{@lastBar?.lday()},
      """
    )
  



  # return 新確認或原已確認今仍延續 signal swim
  # 結果可為 null
  _decideSignalSwim:->

    sswim = if @signalFishName? then @[@signalFishName].swim else null
    #_assert.log({info:'_decideSignalSwim', @signalFishName, sswim}) unless sswim?
    return sswim  # 可為 null





  _decideSignalSwim0:->
    
    switch  # 為了避免多重繼承,故不分立 class 而以此分解
      # 無須繁雜,一以貫之
      when (not optBuoySelectSignal) and forbidInsteadOfConvert then @_rootSecSignalFishName()
      
      # 備考
      when @contract.isRootSec() then @_rootSecSignalFishName() 
      when @contract.isOPTIOPT() then @_derivativesSignalFishName()
      else @_commonSignalFishName()

    sswim = if @signalFishName? then @[@signalFishName].swim else null
    #_assert.log({info:'_decideSignalSwim', @signalFishName, sswim}) unless sswim?
    return sswim  # 可為 null




  # 對於 rootSec 這就是 optSwim, 分別適宜 long call / long put 
  _setSignalSwim:(obj)->
    # 僅更新之後方須重設,延續者則不必重設故  
    if obj is @signalSwim
      return

    if obj? 
      @signalSwim = obj 
      @signalSwim._resetRsi()
      if @contract.isRootSec()
        # 對於 rootSec 這就是 optSwim, 分別適宜 long call / long put 
        @optSwim = @signalSwim

        if optSetAllOperators
          @callSwim().setOptOperator(@optOperators)
          @putSwim().setOptOperator(@optOperators)
        else 
          @optSwim.setOptOperator(@optOperators)
    
    else
      # 對於 rootSec 這就是 optSwim, 分別適宜 long call / long put 
      @optSwim = @signalSwim = null
    






  # 按照設計 buoySwim 可以 null, 此時 signal 為 keep
  _decideBuoyFishName: (aName) ->
    if aName?
      @_setBuoyFishNameTo(aName)
    else
      @_rootSecBuoyFishName()



  # 行情已令 buoy 買賣切換,即新的買賣點出現,但須過濾以往為完成的交易點,故稱為 try  
  # 魚同則不生新
  _setBuoySwim:()->
    switch
      when @buoyFishName?
        @buoySwim = @[@buoyFishName].swim      
      else
        @buoySwim = null  # 接下來, singal 會據此設置為 keep





  ###
    設置雙重 buoy 可以避免 buoy 中斷,新系統兩個 buoy 同時跟蹤價格, 故製作臨時的切換信號系統,以便適應buoy之需要
    
    經測試觀察發現, 除非強行平倉情形,其餘情況不需要切換.
    且,即便強行平倉情形,在 forbidInsteadOfConvert 為 true 時,亦不將 short 類信號轉換成 long 類信號.而是等待行情自然轉換.

    只要 buoySwim 設計思路是對的. 即劃分出可以(而非必須)買或賣的行情段.具體買賣點則由 buoy 自定.
    今後若改進 buoySwim 系統, 應保持目前設計原則,至少應該不影響正確的交易


  ###
  signalEntryBuoy: (buoy, buoyMessage) ->
    # 在本分支,基礎證券自己無買賣,指示衍生品買賣
    if @contract.isRootSec()
      return @_rootSecEntryBuoy(buoy, buoyMessage)
    
    else if @contract.isOPTIOPT() then switch
      # 在本分支,期權等衍生品由基礎證券指引操作,故原始的 signalFish / buoyFish 皆無意義  
      when @contractHelper.hasShortPosition() and /buy/i.test(buoy.actionType)
        # 將信號設置為short
        @_renewSignalSwim(@shortSignalFishName)
      else
        # 將信號設置為 long
        @_renewSignalSwim(@longSignalFishName)
        
    switch
      # 其他品種則按需生成 signal, 自動適應 buy / sell, 但 short / long 不能更改
      when @signalFishName?
        aFishName = if buoy.isBuyBuoy() then @buyBuoyFishName else @sellBuoyFishName
        _assert(aFishName is buoy.fishName, 'a fish name is not buoy fish name')

        @_renewBuoySwim(buoy.fishName)

        signal = @liveSignal(buoy)
        
        unless signal?
          {buoyName,actionType,costOfPosToCloseByMe,fishName} = buoy
          _assert.log({
            bug:'[ BUG!!! ] no signal', @secCode,@timescale,actionType,costOfPosToCloseByMe
            shortPosition: @contractHelper.hasShortPosition()
          })
          return

        {signalTag} = signal
        _assert.log({debug:'signalEntryBuoy >> liveSignal', signalTag})

        @signalSwim.entryBuoy(this, signal, buoy, buoyMessage, =>
          buoy.suggestionPassed() # buoy.instructed = false
          _assert.log({info: '@signalSwim.entryBuoy', afterSent: signal.signalTag})
        )
      
      else
        _assert.log({info:'signalEntryBuoy >> buoy entry ignored', @signalFishName})


  




  # 根據 signalFishName + buoyFishName 生成新的 signal
  liveSignal: (buoy) ->
    @signalSwim.newSignal(buoy)





  # rootSec 專用; contract.isRootSec()
  _rootSecEntryBuoy: (buoy, buoyMessage) ->
    #_assert.log({dev:'_rootSecEntryBuoy', buoyName:buoy.buoyName, buoyMessage, @signalFishName, rootSymbol:@contract.symbol})
    unless buoy? then return

    switch @signalFishName
      when @callFishName then switch buoy.actionType
        when 'buy' #then 'suggest open call position'
          @rootSuggestOpenCallPosition(buoy)
        when 'sell' #then 'suggest close call position'
          @rootSuggestCloseCallPosition(buoy)
      when @putFishName then switch buoy.actionType
        when 'buy' #then 'suggest close put position'
          @rootSuggestClosePutPosition(buoy)
        when 'sell' #then 'suggest open put position'
          @rootSuggestOpenPutPosition(buoy)
      else
        _assert.log({info:'_rootSecEntryBuoy >> no signalFishName'})


  
  
  
  # rootSec 專用; contract.isRootSec()
  rootSuggestOpenCallPosition: (buoy)->
    {stillReflective, stage, nowSuggestedPositionChange, suggestionType, suggestedTradePrice, root_sec_stageSetter, fake} = buoy
  
    if @lastSuggestOpenCallPrice isnt suggestedTradePrice

      # 開 call 先平 put
      if stillReflective and (@lastSuggestOpenPutPrice or (@putSwim().openedOpts().length > 0))
        # 注意,此處的參數,用以避免死循環      
        fakeBuoy = {stillReflective:false, stage, nowSuggestedPositionChange, suggestionType:'reflected', suggestedTradePrice, root_sec_stageSetter, fake:true}
        @rootSuggestClosePutPosition(fakeBuoy)

      obj = {
        msg: 'OpenCallPosition'
        right: 'C'
        action: 'buy'
        stage
        type: suggestionType
        rsPositionChange: nowSuggestedPositionChange
        rootSymbol: @contract.symbol
        strongRoot: @straightCall()
        root_sec_stageSetter
        by: if fake then 'rootSuggest REFLECTED' else 'rootSuggest'
      }

      @emit('rootSuggest', obj)      
      _assert.log(obj)      
      @lastSuggestClosePutPrice = suggestedTradePrice
  
  
  
  
  
  # rootSec 專用; contract.isRootSec()
  rootSuggestOpenPutPosition: (buoy)->
    {stillReflective, stage, nowSuggestedPositionChange, suggestionType, suggestedTradePrice, root_sec_stageSetter, fake} = buoy
  
    if @lastSuggestOpenPutPrice isnt suggestedTradePrice

      # 開 put 先平 call
      if stillReflective and (@lastSuggestOpenCallPrice or (@callSwim().openedOpts().length > 0))
        # 注意,此處的參數,用以避免死循環      
        fakeBuoy = {stillReflective:false, stage, nowSuggestedPositionChange, suggestionType:'reflected', suggestedTradePrice, root_sec_stageSetter, fake:true}
        @rootSuggestCloseCallPosition(fakeBuoy)

      obj = {
        msg: 'OpenPutPosition'
        right: 'P'
        action: 'buy'
        stage
        type: suggestionType
        rsPositionChange: nowSuggestedPositionChange
        rootSymbol: @contract.symbol
        strongRoot: @straightPut()
        root_sec_stageSetter
        by: if fake then 'rootSuggest REFLECTED' else 'rootSuggest'
      }
      @emit('rootSuggest', obj)      
      _assert.log(obj)      
      @lastSuggestClosePutPrice = suggestedTradePrice
  




  # rootSec 專用; contract.isRootSec()
  rootSuggestCloseCallPosition: (buoy)->
    {stillReflective, stage, nowSuggestedPositionChange, suggestionType, suggestedTradePrice, root_sec_stageSetter, fake} = buoy

    if @lastSuggestCloseCallPrice isnt suggestedTradePrice

      if stillReflective and buoyStrategyDone
        # 注意,此處的參數,用以避免死循環
        fakeBuoy = {stillReflective:false, stage, nowSuggestedPositionChange, suggestionType:'reflected', suggestedTradePrice, root_sec_stageSetter, fake:true}
        @rootSuggestOpenPutPosition(fakeBuoy)

      obj = {
        msg: 'CloseCallPosition'
        right: 'C'
        action: 'sell'
        stage
        type: suggestionType
        rsPositionChange: nowSuggestedPositionChange
        rootSymbol: @contract.symbol
        strongRoot: @straightCall()
        root_sec_stageSetter
        by: if fake then 'rootSuggest REFLECTED' else 'rootSuggest'
      }
      @emit('rootSuggest', obj)      
      _assert.log(obj)      
      @lastSuggestClosePutPrice = suggestedTradePrice

    # 以上還不夠,若由於 openPut 而引發,則須進一步發出強制關閉窗口指令,防止其他條件不滿足令平倉建議得不到實施
    unless stillReflective
      if optCloseOpposites
        #要用到 closeDerivatives
        swim = @callSwim()
        swim.closeDerivatives(this)



  # rootSec 專用; contract.isRootSec()
  rootSuggestClosePutPosition: (buoy)->
    {stillReflective, stage, nowSuggestedPositionChange, suggestionType, suggestedTradePrice, root_sec_stageSetter, fake} = buoy

    if @lastSuggestClosePutPrice isnt suggestedTradePrice

      if stillReflective and buoyStrategyDone
        # 注意,此處的參數,可以避免死循環
        fakeBuoy = {stillReflective:false, stage, nowSuggestedPositionChange, suggestionType:'reflected', suggestedTradePrice, root_sec_stageSetter, fake:true}
        @rootSuggestOpenCallPosition(fakeBuoy)

      obj = {
        msg: 'ClosePutPosition'
        right: 'P'
        action: 'sell'
        stage
        type: suggestionType 
        rsPositionChange: nowSuggestedPositionChange
        rootSymbol: @contract.symbol
        strongRoot: @straightPut()
        root_sec_stageSetter
        by: if fake then 'rootSuggest REFLECTED' else 'rootSuggest'
      }
      @emit('rootSuggest', obj)      
      _assert.log(obj)      
      @lastSuggestClosePutPrice = suggestedTradePrice
      
    # 以上還不夠,若由於 openCall 而引發,則須進一步發出強制關閉窗口指令,防止其他條件不滿足令平倉建議得不到實施
    unless stillReflective
      if optCloseOpposites
        #要用到 closeDerivatives
        swim = @putSwim()
        swim.closeDerivatives(this)






  initStatistics: ->
    ###
    # 可以針對一組指標進行峰谷頻率統計,但加上對應的filter,可能令代碼過於複雜,故複雜統計還是通過
    # 數次循環來逐一計算比較簡單,也不會很慢

    # 以下代碼限制為一次僅作一種統計,且僅統計一個指標;並且僅統計@序列()這部分數據

    # 不要試圖擴展到指標組,會增加複雜程度
    ###
    if statsTag? and (statsTag is 'bor峰值統計')
      #統計參數 = @poolOptions.統計參數 ? {}  # 為便於下面的設置故, 若null則設為{}
      # 達到比較可能回調的bor值或lory幅度,峰值後往往有衝刺,否則可取 30
      #@警戒百分位 = 統計參數.警戒百分位 ? 85
      {
        @警戒百分位 = 85
        @計峰篩選 = (bar)-> bar.入選計峰 = (bar.low > bar.bay) and (bar.high > bar.ma_price10)
        @計谷篩選 = null # 未完成,也未用到
        @入選計峰 = (bar)-> (bar.low > bar.bay) and (bar.high > bar.ma_price10)
        @入選計谷 = -> true #未用
        基數 = 0
        levels = null  # TopBotProbabs 有默認值
        sampleDataName = 'bor' # 動低幅
        僅限最近 = null #160
      } = 統計參數 ? {}

      if statsTag is 'bor峰值統計'
        @borProbabs = new TopBotProbabs(@contractHelper, @secCode, @timescale, statsTag, sampleDataName)
        @borProbabs.擬統計峰值頻率({計峰基數:基數, 計峰目標:levels, 入選計峰:@入選計峰})
      else if statsTag is '谷值統計'
        #需要時,參照bor峰值統計,大同小異
        return



    
  initResearchMode: ->  
    if research
      @uplasting = new UpLasting(@contractHelper, @secCode, @timescale)
      @learn = new LearnFlow(@contractHelper, @secCode, @timescale)



  initComplexMode: ->
    if not simple
      @sma05 = new MaFlow(@contractHelper, @secCode, @timescale,'ma_price05','close',5)
      @sma10 = new MaFlow(@contractHelper, @secCode, @timescale,'ma_price10','close',10)
      @sma20 = new MaFlow(@contractHelper, @secCode, @timescale,'ma_price20','close',20)
      @sma150 = new MaFlow(@contractHelper, @secCode, @timescale,'ma_price150','close',150)

      homeName1 = 'yinfishx'
      @yangfishy = new YangFishY({swimOnFishNames, @contractHelper,tbaName:'bay',rawDataName:'low',cornerName:'high',homeName:homeName1}) #,ratioName:'lory'
      homeName2 = 'yangfishx'
      @yinfishy = new YinFishY({swimOnFishNames, @contractHelper,tbaName:'tay',rawDataName:'high',cornerName:'low',homeName:homeName2}) #,ratioName:'hiry'
      @yinfishyArray = []
      @yangfishyArray = []
      
      @botRatios = new TopBotProbabs(@contractHelper, @secCode, @timescale, '求谷比low','low')
      @botRatios.ratioName = 'bor' # 早期中文名 見底 指標
      @topRatios = new TopBotProbabs(@contractHelper, @secCode, @timescale, '求峰比high','high')
      @topRatios.ratioName = 'tor' # 早期中文名 見頂 指標
      @ratio = new RatioFlow(@contractHelper, @secCode, @timescale, @underlyingIndicator)
      @ratioMa = new MaFlow(@contractHelper, @secCode, @timescale,'rma','ratio',rmaArg)




  # ---------------------- constructor end ----------------------

  nowOnDuty: (aBoolean, strongRoot) ->
    @onDutyWithHistData = aBoolean

    # 僅當此為 OPT/IOPT
    if strongRoot?
      @contractHelper.optStrongRoot(strongRoot)



  ### beforePushPreviousBar 須謹慎使用,因會造成時空狀況複雜難懂易錯.
  # 此法會在 nextBar 之前執行, 執行後, 所在的 comingBar() 會令 @bar = bar, 然後執行 nextBar
  # 大部分情況或可避免使用,而改在 nextBar 中引用 previousBar 的狀態
  # 此處實質代碼已經過審閱,未發現問題. 
  # 檢查日期:(後續檢查應同樣記錄日期)
  #   [20171107] 未發現問題.
  ###
  beforePushPreviousBar: (aPool)->
    # 在此設置,意味著僅採用已經確認的趨勢
    @_setSpecialBars(aPool)




  ### 
    此處代碼可作為示範,演示如何在 DataFlow 的後續 flow 中, 為前期 flow 補充記錄已經完畢的狀態
    由於代碼中不引用前期 flow 的狀態,而僅利用 bar 數據判斷分析設置,故避開任何時空錯亂問題. 
    此時的 @bar 是前期 flow 目前的 @previousBar 由於存在時差,故錯後一位,好像美國今天是日本昨天
    所以 beforePushPreviousBar 盡量不用,若用須如此仔細善巧才行.
    此外,此處未直接使用 'closeHighBand' 等等名稱,而是用 @bband.highBandCName 也是最好的方式.
    這樣如果 'closeHighBand' 等改名,就不需要到處找引用到他的代碼,系統其它地方由於趕工可能忽略這一點,見到則改正
  ###
  _setSpecialBars:(aPool)->
    if @bar.lowBelowLine(@bband.highBandCName)
      @yinfish.downXHighBandBar ?= @bar
    if @bar.lowBelowLine(@bband.highBandBName)
      @yinfish.downXHighBandBBar ?= @bar
    if @bar.lowBelowLine(@bband.maName)
      @yinfish.downXBbandMaBar ?= @bar
    if @bar.lowBelowLine(@bband.lowBandBName)
      @yinfish.downXLowBandBBar ?= @bar
    if @bar.closeUpCross(@bband.maName, @previousBar)
      @yinfish.latestUpXBbandMaBar = @bar
    if @bar.close > 0.5 * (@bar.ta + @bar.bay)
      if (not @yinfish.upXMidyBar?) or (@yinfish.upXMidyBar.momentBefore(@yinfish.cornerBar, @timescale)) 
        @yinfish.upXMidyBar = @bar
    else
      @yinfish.upXMidyBar = null




  #nextBar:(pool=this)->
  #  super(pool)
  



  # 此法將是唯一入口
  comingBar:(aBar,aPool=this)->
    unless aBar?
      #_assert.log('debug a bar:',aBar)
      return this
    if (/^minute$/i.test(@timescale))
      if (aBar.date < @poolOptions.skipToDate) 
        #_assert.log('debug bar.date < @poolOptions.skipToDate', @poolOptions.skipToDate)
        return this

    unless @lastBar? 
      @emit('hasData',this) 

    if @lastBar? and aBar.date < @lastBar.date
      return this

    #_assert.log('debug: aBar:',aBar.day,aBar.date)
    #_assert.log('[debug comingBar] aBar.day | @bar.day:', aBar?.day, @bar?.day)    
    super(aBar,aPool)#(aBar,this) # this is not used  
  
    # 用於尚未開市時,分析歷史數據;開市後,若非當值則停止

    # 無先後依賴的計算可以map,否則用 for.
    # 更緊密的組合計算已經嘗試過了,不能再精簡了.就這樣不用再合併了.
    [@rsi, @sma05, @sma10, @sma20, @ema20, @sma150, @bband].map((each,idx)-> each?.comingBar(aBar,aPool)) # 補缺計算普通均線
    # 此法僅依賴 bband 標準差等數據, 不依賴其他行情結構分析結果
    @contractHelper.withBar(aBar)

    [@mayangfishx,@mayinfish,@mayinfishx,@mayinfishb,@mayangfishb].map((each, idx)-> each?.comingBar(aBar, aPool))
    
    # 位置似乎不對,但不知是否以下代碼需要此法先完成
    #@semiCycleNames?.map((each,idx)-> aPool[each].comingBar(aBar,aPool))
    
    [@topRatios, @botRatios].map((each,idx)-> each?.comingBar(aBar,aPool)) # 計算頂底指標,其計算方法獨立於陰陽魚系統.

    for each in [@ratio, @ratioMa]  # 計算均線變化率,以及衍生指標,先後有依賴
      each?.comingBar(aBar,aPool) # 不可用 map
    
    [@yinfish, @yangfish].map((each,idx)->each?.comingBar(aBar,aPool))
    aBar.mda = fix(0.5*(aBar.ta + aBar.ba))

    [@yangfishf,@yangfisht,@yinfishf,@yinfishx, @yangfishx].map((each,idx)->each?.comingBar(aBar,aPool))
    aBar.mdx = fix(0.5*(aBar.tax + aBar.bax))

    # @yinfish, @yangfishy, @yinfishy 次第有意義,不可顛倒
    for fish in [@yangfishy, @yinfishy] # 計算陰陽魚中先後依賴部分,順序不可顛倒,其中陰魚中有陰中之陽魚,其中有陽中之陰魚
      fish?.comingBar(aBar, aPool) # 順序不可顛倒故不可 map!
    
    @yangxt = @yangfisht # @yangfishx
    
    # 在fish運算之後才能算概率 #@borProbabs.comingBar(aBar,aPool)
    # 計算漲幅分佈概率,依賴陰陽魚. 並計算長均峰谷帶魚
    @borProbabs?.comingBar(aBar,aPool)
    
    if @isTodayBar(aBar)
      @secPosition.獲悉最近價(aBar.close)    


    # 注意: 以此條件,非期權非基礎證券,非a股等其他證券,圖形會不顯示信號線,這是正常的
    if @availableForTrading

      # (從上方移此)
      @semiCycleNames?.map((each,idx)-> aPool[each].comingBar(aBar,aPool))
      @cceNames?.map((each,idx)-> aPool[each].comingBar(aBar,aPool))

      # 現不依賴 buoy 故置於其前
      # 若將來新增內容依賴 buoy 則須置於其後,並置於 @checkPurity() 之前
      @relativeBars()

      for fishName, buoy of @_buoys
        buoy.comingBar(aBar, aPool)
      
      # 要用 gradeBuy 等 buoy 生成的變量,故置於其後  
      @checkPurity()

      @_renewSignalSwim()
      for fishName, buoy of @_buoys
        buoy.trace(aPool)
      @_renewBuoySwim()


    @uplasting?.comingBar(aBar,aPool)
    @learn?.comingBar(aBar,aPool)







  # 對於符合當前 swim 方向的歷史數據,記錄偽操作信號:
  currentSwimRecordHistChartSig:(histBuoy)->
    if @signalSwim?.hasKeepSignal()
      return
    # !! 此處必須用當前的 signalSwim,非常恰當,勿改 !! 
    @signalSwim?.recordHistChartSig(this,histBuoy)





  #--------------------------------------------------

  求末:(n)->
    @barArray?[-n..]




  # 類別: 'yinfishArray'等等
  求前魚:(類別)->
    @formerObject(類別)
    #@[類別][-2..-2][0]




  __fishSizes:(fishName,host)->
    if host?
      filter = (each) -> each.startBar.day > host.startBar.day
    else
      filter = -> true 
    (each.size for each in @fishArray(fishName) when filter(each)).sort((a,b)-> b-a)
  



  __showPriceGrades:->
    @contractHelper.helpShowPriceGrades(@bar.close)
    











###

  (20180607)
  關鍵指標 4x / 2x2t

  經過仔細研究對照,確定涵蓋主要交易點和交易區間的指標為
    bbbbat(x) bbbyangfisht
    bbbtax    bbbyinfishx
    bat(x)    yangfisht(x)
    tax       yinfishx

###
class CyclePool extends Pool


  root_buyBuoyStage: (stageLabel, functionName) ->
    @buyBuoy.root_sec_stageSetTo(stageLabel, functionName, @root_sec_putCycle())



  root_sellBuoyStage: (stageLabel, functionName) ->
    @sellBuoy.root_sec_stageSetTo(stageLabel, functionName, @root_sec_putCycle())





  # -------------------------------- 買買條件組 -------------------------------
  ###
    Nexus:
    • the central and most important point or place: the nexus of all this activity was the disco.
    沒有找到更合適的詞.先以此來定義.

    思路:
      所有交易點都需要的過濾條件,集中寫以免重複定義,繁瑣引用
      主要是布林線和天地線


      # (20180524 15:52 新思路) 
      # 參閱 srefine.md.coffee class Nexus 說明
      
      盤局出入策略
      
        在前期 Nexus 方法定義之後,發現頂底買賣非常好定義,再經過分析,可通過粗細不同的行情系統,用盤局出入策略完成成功的交易.
        例如,在 hour 跨度上,屬於純陽末期的賣出點,放在 minute 行情中,就變成了高位盤局交易點,即從長驅直入的上落,轉換成階梯上落
        據此,則僅需定義好階梯箱體內上下出入即可,最多補充突破時的同向追倉點(以防之前已經在舊的頂底平倉)
      
      據此盤局出入策略思路,以前較難定義和過濾的交易點,變得容易

  ###



  # (20180603 17:06)
  sellNexusSimpleStop: ->
    #@sellNexusSimpleStop20180608()
    @sellNexusSimpleStop20180609()




  # (20180609 10:27)
  # 空中加油
  # 要領: 1. 上昇過程 2. 低位補倉
  sellNexusSimpleStop20180609: ->
    {bbbyinfish, bbbyinfishx, bbayinfishx} = @bband
    n = 2

    switch
      # 首先確認上昇過程
      when not (@yinfishx.size in [1..3]) then false  # not 後面必須加括號
      when bbbyinfishx.size > n or bbayinfishx.size > n then false      
      when not @startUponFormer(@yinfishx,'yinfishxArray', 'tax') then false
      # 不用此法: #when @bband.startBelowFormer(bbbyinfishx, 'bbbyinfishxArray', 'bbbtax') then false
      when @mainfishYin() then false
      when not (@bbbyangxCycleX() or @yangxCycleX()) then false

      # 創歷史新高過程中小憩
      when not @bar.lowBelowLine('bbbtax') then false
      when not (@closeLowMid() or @closeLowDrop()) then false

      # 避免頭部補倉,買到高位
      # 用 grade 避免高位盤整時天價補倉. 無須增加 and @yinfish.size > x, 結果無差異
      when @bar.close > @buyBuoy.grade[6] then false
      # 僅限補倉一次,避免越補越高
      when @yangfisht.sellStopBar? then false
      when bbbyinfishx.sellStopBar? then false      
      # 若無以上過濾條件,則會買到高位
      when @bar.closeBelowLine('bbatax') then false  
      # 會買到轉點附近,故不可用此法: #when not @bar.closeBelowLine('bbatax') then false  
      
      # 陽魚之頭
      else
        @root_buyBuoyStage 'continue','sellNexusSimpleStop20180609'
        @yangfisht.buyNexusBar = @bar
        @yangfisht.sellStopBar = @bar
        bbbyinfishx.sellStopBar = @bar
        true





  # (20180608 23:45)
  sellNexusSimpleStop20180608: ->
    newHighOnly = false
    fish = if newHighOnly then @yinfish else @yinfishx

    switch
      # 首先確認上昇過程
      when not (@bbbyangxCycleX() or @yangxCycleX()) then false
      when @mainfishYin() then false

      # 避免跌前補倉
      # 方法待定,思路為取陰魚記憶為上,限定陰魚尺寸.先看圖找規律
      when @yangfisht.sellStopBar? then false

      # 創歷史新高過程中小憩
      # 方法待定. 思路是去陽魚之頭
      when fish.size in [0..3] and @bar.indicatorDrop('close',@previousBar)
        @root_buyBuoyStage 'continue','sellNexusSimpleStop20180608'
        @yangfisht.buyNexusBar = @bar
        @yangfisht.sellStopBar = @bar
        true
      else false





  mainfishYin: ->
    @yangfish.mainfish?.isYinfish() or @yinfish.mainfish?.isYinfish()




  # (20180603 17:06)
  sellNexusSimpleStop20180603: ->
    testIt = false
    switch
      # (20180607 21:34) 嘗試思路; 待完善
      when @barIsCurrent(@yangxt.revertBar) and testIt
        @root_buyBuoyStage 'continue','sellNexusSimpleStop20180603'
        @yangfisht.buyNexusBar = @bar 
        true

      # 陽長階段之補充買入
      # (20180606 17:08)
      when @root_sec_callCycle() and @mayinfishx.size is 0 then switch
        # 趨勢確認
        when @bar.indicatorRise('close', @previousBar) then false
        when @bband.bbbyangfish.startAfter(@bband.bbbyinfish) then false
        when @bband.bbbyangfisht.size < barsLeadFishShift then false
        
        # 尚未觸及均線,強勢回調補倉
        when not (@yangfishx.maBrokenBar? or @yinfishx.maBrokenBar?) and @bar.indicatorDrop('close', @previousBar)
          @root_buyBuoyStage 'continue'
          @yangfisht.buyNexusBar = @bar  # 以便與止盈止損對應 
          true
        
        # 首次觸及均線當日補倉,其後忽略
        when @yangfishx.maSellStopBar? or @yinfishx.maSellStopBar? then false
        when (@barIsCurrent @yangfishx.maBrokenBar) or (@barIsCurrent @yinfishx.maBrokenBar)
          @root_buyBuoyStage 'continue'
          @yangfisht.buyNexusBar = @bar  # 以便與止盈止損對應
          @yangfishx.maSellStopBar = @bar
          @yinfishx.maSellStopBar = @bar
          true
          

      # (20180606 20:44) 以上條件邏輯清晰,按照測試時數據,選點較好; 而以下條件有待提煉過濾掉不恰當的買入點
      # 為研究上述條件,暫時屏蔽以下條件
      #when true then false 

      # (20180605 20:04)
      # @bband.bbbyangish 居 @bband.yinfish 前, 上漲後橫盤,出現補倉點
      when @bband.bbbyangfisht.size > barsLeadFishShift*10 and @bband.bbbyangfish.startBefore(@bband.yinfish) and @bband.bbbyangfisht.startBefore(@mayinfish) then switch
        when not @yangfishx.size in [1..5] then false
        # 嚴格限制價格起點在 bbbbat 之下; 若不欲如此嚴格,則注釋下行:
        when @yangfishx.startBar.higher('bax','bbbbat') then false
        
        when @bar.higher('high','bbta') then false
        # (20180606) 是必須漲還是寫漏了 not?
        when @bar.indicatorDrop('close', @previousBar) then false
        when @yangfisht.buyNexusBar? then false
        else
          @root_buyBuoyStage 'continue'
          @yangfisht.buyNexusBar = @bar  # 以便與止盈止損對應 
          true
        
      # @yangfishx 居前
      # 以此為主.定義補倉,避免踏空
      when @yangfishx.startBefore(@bband.yinfish) then switch
        # 在未出現多頭止盈觸發條件之前皆可落均線即補倉
        when @bband.bbbyangfish.bbbyangfishtBrokenBar? then false
        when @mayinCycleB() then false
        when @bband.bbayinfishx.size > barsLeadFishShift then false
        when @bband.yinfish.size > barsLeadFishShift then false
        #when @bar.indicatorDrop('bbandma', @earlierBar) then false
        when @bar.closeBelowLine('bbandma')
          @root_buyBuoyStage 'continue'
          @yangfisht.buyNexusBar = @bar  # 以便與止盈止損對應 
          #@bband.bbbyangfishx.buyNexusBar = @bar
          true

        else false

      # @yangfishx 居後(盤局)
      # 暫忽略
      when @yangfishx.startAfter(@bband.yinfish) then false #  switch

      else false






  # (20180521 17:30)
  # (20180521 20:17 改)
  # 賣出點組合過濾條件
  sellNexus: ->
    conceptTest = false
    switch
      when conceptTest then switch
        # 以下應融入 sellInGgCycle 分支體系,先臨時測試
        #@cceBxbtFf.sellPoint(2,'向下報價')
        #@cceBxbtXt.alongPresellCross(2)
        
        #when @cceAxatXt.alongPresellCross(2)
        #  @root_sellBuoyStage('definite')
        
        when @cceGgXt.alongPresellCross(2)
          @root_sellBuoyStage('definite')
        
        else false
      else
        @sellInGgCycle()

        #@sellNexusSimple() #or @buyNexusSimpleStop()
        #@buyNexusSimpleStop()






  ###
    避免出現歧義 put 平倉點, 可採用以下條件過濾:

    # 旨在不生成歧義 put 信號,一旦 @root_sec_putCycle 定義改變, 隱藏的信號又會自動展示,不用改寫定義
    when @root_sec_putCycle() then false
  ###
  # (20180521 17:30)
  # 買入點組合過濾條件
  buyNexus: ->
    conceptTest = false
    
    switch
      when conceptTest then switch
        # 以下應融入 buyInGgCycle 分支體系,先臨時測試
        when @cceGgXt.buyPoint(2,'向上報價')
          @root_buyBuoyStage('definit') 
        when @cceBxbtFf.buyPoint(2,'向上報價') 
          @root_buyBuoyStage('definit') 
        when @cceAxatFf.buyPoint(2,'向上報價')
          @root_buyBuoyStage('definit') 
        
        #when @cceFfXt.buyPoint(2,'向上報價')
        #  @root_buyBuoyStage('definit') 

        #when @cceBxbtXt.buyPoint(2,'向上報價')
        #  @root_buyBuoyStage('definit') 


        #when @cceBxbtXt.alongBuyLineCross(2)
        #  @root_buyBuoyStage('definit') 

        #when @cceAxatXt.alongBuyLineCross(2)
        #  @root_buyBuoyStage('definit') 
        
        #when @cceFfXt.alongBuyLineCross(2)
        #  @root_buyBuoyStage('definit') 
        
        else false
        
      else
        # 不再需要以下各法時, 亦可獨立使用
        @buyInGgCycle()

        #@buyNexusSimple() or @sellNexusSimpleStop()
        
        # 臨時測試研究
        #@buyNexusSimple()
        #@sellNexusSimpleStop()





  cce_sellCommon: ->
    switch
      # 外切僅限使用最外層,以免太早交易
      when @cceBgbgXt.presellPoint(2) then true  
      when @cceGgXt.presellPoint(2) then true
      #when @cceBxbtXt.presellPoint(2) then true
      
      when @cceBgbgXt.sellPoint(2,'向下報價') then true
      when @cceGgXt.sellPoint(2,'向下報價') then true
      when @cceBxbtXt.sellPoint(2,'向下報價') then true
      when @cceAxatXt.sellPoint(2,'向下報價') then true
      
      else false





  cce_buyCommon: ->
    switch
      when @cceGgXt.buyPoint(2,'向上報價') then true
      when @cceBxbtFf.buyPoint(2,'向上報價') then true
      when @cceAxatFf.buyPoint(2,'向上報價') then true
      else false






  ###
    賣出點捷徑:(20180525 21:05)
      bbta,bbbta,bbatax,ta 四條線足矣.實則,bbta為主,輔以bbbta已經足夠,線上者賣出可也
      極度簡化!
      故,後期可再提煉現有策略
      由於出入不大,暫時不作整理,待其他部分完成能用的代碼之後,再完善之
    
    圖示: 20180525 20:30 ~ 21:00之截圖,附帶文字說明
  ###
  # (20180525 23:09) 賣出捷徑
  # (20180526 16:21) 改為獨立 function
  sellNexusSimple: ->
    #@sellNexusSimple20180526()
    @sellNexusSimple20180608()







  # 2x2t or 4x 新體系
  # (20180608 22:00) 建立 
  # 第一賣出點 sell1: 創歷史新高以至之後數日內, call 之最佳止盈點, 而不作為 put 之開倉點. 
  #   1a 兩陰魚都成型,各自天線可以藉以賣出
  #   1b 少數變異情形,即 bbbyinfishx 之 size 始終未來得及超過1, 即已下穿,故須及時捕捉,提前止盈
  # 第二賣出點, 高位橫盤觸頂
  # 第三賣出點, 定義追加賣出(以便put操作),即 
  #   3a 破位後, 以及 
  #   3b 盤局中的賣出點
  # 第四賣出點 sell4: 主體下穿 bbbba, put 開倉

  # TODO: 化整為零,各自做成自洽 function 以便選用, 並行, 且易於維護. 編程時,思維勿受硬件制約.
  sellNexusSimple20180608: ->
    switch
      when @sellInGgCycle() then true

      when @sellOnCycleRightSide() then true
      when @sellOnTaxDXBbbTax() then true
      when @sellAfterBatSeparate() then true
            
      # 備考
      #when @sellNexusSimple4() then true  # 有獨特賣出點,待延續 sellAfterBatSeparate 思路改進
      
      #when @_sellNexusSimple3_() then true # 目前行情極少, 以後再測
      #when @_sellNexusSimple1_() then true  # 賣出點較少, @sellOnTaxDXBbbTax 基本包涵此法賣出點
      #when @_sellNexusSimple2_() then true  # 類似, 但次於 sellOnTaxDXBbbTax

      # 以下是使用單元最小化編程方式寫的; 其他部分待逐步改寫
      #when @sellOnTaxDXBbbTax_simplest_demo() then true
      
      else false






  ###

    buyBottomInGgYinFfYang: sellTopInGgYangFfYin
    buyContinueInGgYinFfYang: sellContinueInGgYangFfYin
    buyContinueInGgYangFfYang: sellContinueInGgYinFfYin
    buyInGgYangFfYin: sellInGgYinFfYang
    buyInGgYinFfYin: sellInGgYangFfYang

  ###
  sellInGgCycle: ->
    switch
      when @sellInGgYangCycle() then true
      #when @sellInGgYinCycle() then true
      
      else false






  sellInGgYangCycle: ->
    switch
    
      # 先確定大環境
      when @ggCycle.isYin then false
      
      # call: top 新高隨後平倉點
      #when @sellInGgYangFfYang() then true

      # put: top; call: stopWin
      when @sellTopInGgYangFfYin() then true
      
      # call: stopWin, put: continue
      when @sellContinueInGgYangFfYin() then true
      
      else false






  sellInGgYinCycle: ->
    switch
      # 先確定大環境
      when @ggCycle.isYang then false

      # put: continue
      when @sellContinueInGgYinFfYin() then true

      # call: top / stopWin
      when @sellInGgYinFfYang() then true

      else false






  # call: top
  # 此時不做 put
  # 期權的早期止盈
  # (期權需要早出晚歸,即越早賣出價格越高,因有虛增價格且不斷萎縮)
  # 用 buyContinueInGgYangFfYang 追進補倉,輔助本法
  # (20180713 17:00) 改定
  sellInGgYangFfYang: ->
    # 此時不做 put
    stageLabel = if @root_sec_putCycle then 'mirror' else 'top'

    switch
      when not @ffCycle.isYang then false

      when @cce_sellInGgYangFfYang()
        @root_sellBuoyStage(stageLabel, 'cce_sellInGgYangFfYang')

      # 屏蔽以下舊模式
      when true then false

      when @ffCycle.cycleYinfish.gapSoldBar? then false
      when not @closeHighRise() then false
      when not @sellTopInGgYang() then false
      
      else
        @ffCycle.cycleYinfish.gapSoldBar = @bar
        @root_sellBuoyStage(stageLabel, 'sellInGgYangFfYang')




  # 此時不必賣出
  # 羅列全部然後去掉陽陽止盈場景下不需要的而已
  # 其餘場景倣此
  cce_sellInGgYangFfYang: ->
    @cce_sellInFfYang()

    #@cce_sellCommon()





  # (20180718 17:37) 效果尚可
  cce_sellInFfYang: ->
    switch
      when @cceBgbgXt.sellPoint(2,'向下報價') then true
      #when @cceGgXt.sellPointFfYang(1,'向下容忍價') then true
      #when @bar.higher('bbatax','ta') and @cceAxatXt.sellPointFfYang(1,'向下容忍價') then true
      else false








  # 由於涉及不止一個 cycle 故須在此設計
  sellTopInGgYang: ->
    # [5, barsLeadFishShift], 濾除短暫盤整,以及 fishf 上跳之後的陰魚部分(由專門的後續賣出 function 解決)
    ff_range = [5, barsLeadFishShift]
    # 必須覆蓋 @ffCycle.yinHead() 之 range 範圍 ff_range
    xt_range = [1, ff_range[1]]

    switch
      when not @ffCycle.yinHead(ff_range) then false
      when not @xtCycle.sellAtTop('向下極限價', xt_range, 'taf') then false
      else true





  # call: top
  # 不做 put
  # put: 由於 ggCycle.isYang, 故不做
  # 根據 YinFishF 定義, 在 ggCycle.isYang 情形下, ffCycle.cycleYinfish 與 @yinfish 重合, 故直接用 ta 不必用 taf 
  sellTopInGgYangFfYin: ->
    # 不做 put
    stageLabel = switch
      # 實則此時,按照目前設計,多處於 root_sec_putCycle
      when @root_sec_putCycle() then 'mirror'
      when @ffCycleYangfishGapped() then 'top'
      else 'stopWin'

    switch
      when not @ffCycle.isYin then false
      
      when @cce_sellTopInGgYangFfYin()
        @root_sellBuoyStage(stageLabel, 'cce_sellTopInGgYangFfYin')

      when true then false

      when not @closeHighRise() then false

      when not @xtCycle.sellFromTop() then false
      
      #when @closeLowBelow('baf') then false 
      #when @bar.higher('baf', 'bat') then false

      else
        @root_sellBuoyStage(stageLabel, 'sellTopInGgYangFfYin')
        true





  cce_sellTopInGgYangFfYin: ->
    @cce_sellCommon()






  # call: top
  # [put: 易錯,乾脆不做]
  # 不開 put 後患永絕,亦免繁雜, 設為 mirror
  # (20180712 13:48) 改寫為僅記錄第一次破位
  sellContinueInGgYangFfYin: ->
    stageLabel = switch 
      # mirror 就是單純用來反射給對應期權,而本身不操作的信號
      when @root_sec_putCycle() then 'mirror'
      when @ffCycleYangfishGapped() then 'top'
      else 'stopWin'

    switch
      when not @ffCycle.isYin then false

      when @cce_sellContinueInGgYangFfYin()
        @root_sellBuoyStage(stageLabel, 'cce_sellContinueInGgYangFfYin')
      
      when true then false
      
      when not @ffCycle.bottomBrokenBar? then false

      when not @closeHighRise() then false

      
      # 意在過濾掉短暫的中繼盤整階段,用時長來抉擇需要因 timescale 而異,不夠靈活,待發現更好的方案
      when not (@ggCycle.longPausedYangCycle() or @ffCycleYangfishGapped()) then false
      
      when not @xtCycle.sellFromTop('向下極限價') then false

      # 陽中之陰情形之下,低於 baf, 甚至 bat 低於 baf 皆近谷底故不賣
      when @closeLowBelow('baf') or @bar.higher('baf', 'bat') then false

      else
        @root_sellBuoyStage(stageLabel, 'sellContinueInGgYangFfYinBreakDown')







  # 交易點較原有方法少,但細看原有方法之檢測結果,多出來的那些點有些不合理
  cce_sellContinueInGgYangFfYin: ->
    @cce_sellCommon() 







  # call: top; put: stopWin/continue(慎之又慎)
  # (20180709 15:52 可用,待完善)
  # (20180711 17:20 草草複查一遍,當前行情段內交易點不多,以後再查)
  sellContinueInGgYangFfYin_Backup: ->
    switch
      when not @ffCycle.isYin then false
      when not @ffCycle.nearBottomBrokenBar(0.5) then false
      when not @ffCycle.underBottomBrokenBar() then false
      
      # 未下台階不續開
      when @ffCycle.yangfishStartedHigher(this,2) then false

      # 增加 baf 短促停工隨後即新生情形的賣出點; 太困一直打瞌睡沒法思考. 
      # (20180711 17:16 複查) spy 行情暫不合適

      # 以下為設計初期混亂代碼,有空再考究決定無用則刪除
      #when not @xtCycle.yinYin() then false
      #when not @xtCycle.cycleYinfish.size > 5 then false
      # 防止在 baf 之上形成回昇時,誤以為是 put 開倉點
      #when @ffCycle.cycleYangfish.size > barsLeadFishShift and not @bar.higher('baf','bat') then false
      #when @ffCycle.cycleYangfish.size > 0.3*barsLeadFishShift and @closeHighUpon('ba') then false

      # 以下與 buyBottomInGgYinFfYang 大同
      else
        stageLabel = switch 
          when @root_sec_callCycle() then 'top'
          when not @xtCycle.rootingHighUpon('ta') then 'stopWin'
          else 'stopWin'
        @root_sellBuoyStage(stageLabel, 'sellContinueInGgYangFfYinBreakDown')
        true






  # (20180715 18:38) 因本法較為寫法特別,未用通法 sellFromTop 改寫, hour 下看,還是需要改寫.現在環境不佳,噪音大,稍後再解決
  # (20180709 16:38 初成)

  # put: continue, call: top
  # 根據諸魚定義,此時,實際 @yinfish, @yangfish 與 fishf 重疊, 故 ba / ta 短暫等價於 baf / taf
  sellContinueInGgYinFfYin: ->
    stageLabel = if @root_sec_callCycle() then 'top' else 'continue'

    switch
      when not @ffCycle.isYin then false

      when @cce_sellContinueInGgYinFfYin()
        @root_sellBuoyStage(stageLabel, 'cce_sellContinueInGgYinFfYin')

      when true then false  

      # 防止築底時開倉 put, 注意用 @ggCycle
      when not @ggCycle.yangHead([1, barsLeadFishShift]) then false

      when not @closeHighRise() then false
      
      # 若從天而降則須頂天賣出
      when @xtCycle.rootingHighUponOrEqual('ta') and not @closeHighUpon('ta') then false
      # 否則亦須略作限價,須不低於 baf 向上若干. 限度太高會漏失開 put 賣出點,為免繁瑣,且不更細分,籠統設限.若發現風險,再作研究
      when not (@xtCycle.rootingHighUponOrEqual('ta') or @closeHighAbovePrice(@contractHelper.略向上報價(@bar.baf))) then false

      # 不足以取代上兩行,待行情合適時再改進.目前上昇過程中,看不到相關行情
      #when not (@xtCycle.sellFromTop('向下極限價',[1,5]) or @ffCycle.sellAtTop('向下極限價',[1,5])) then false

      else
        @root_sellBuoyStage(stageLabel, 'sellContinueInGgYinFfYin')
  




  # 在此場景下出現的點都不對,需要再研究,也許不需要這個場景
  cce_sellContinueInGgYinFfYin: ->
    # 先回復 否, 待研究透徹
    return false

    return @cce_sellCommon()
    





  # call: top / stopWin
  # 有時看似可做空開 put,但邏輯複雜化,風險亦放大,故不可開 put
  # (20180715 用基礎 function sellFromTop 改寫)
  # (20180711 16:54 複查,清潔) 以上闕如部分,應該還沒有做,但當前行情不方便觀察.
  # (20180709 17:06 初建) 僅定義了最重要的部分,
  #   TODO: 尚缺 1. 中段觸及 taf 賣出 2. 體內初期屯卦反復期止盈

  sellInGgYinFfYang: ->
    methodxt = '略向下報價' #if @isMinute then '略向下報價' else '向下報價'
    methodff = if @isMinute then '略向下報價' else '向下報價'

    stageLabel = switch
      when @root_sec_putCycle() then 'continue'
      when @ffCycle.rootingHighUponOrEqual('ta') then 'stopWin' 
      else 'top'

    switch
      when not @ffCycle.isYang then false

      when @cce_sellInGgYinFfYang()
        @root_sellBuoyStage(stageLabel, 'cce_sellInGgYinFfYang')

      when true then false

      when not @closeHighRise() then false

      when not @ffCycle.sellFromTop(methodff, [1,null]) then false
      when @xtCycle.priceDropTooMuchFromTba(methodxt) then false


      # 以下舊代碼經過對比,可濾過一些賣出點,但有無尚待進一步觀察.已知會漏掉一些有用的賣出點.
      #when not (@ffCycle.yinHead([1,barsLeadFishShift]) or @yinfishxTopInGgYinFfYang()) then false
      # 排除已經突破ta,連續上昇未曾休息段
      #when @ffCycle.rootingHighUpon('ta') and @yinfishx.size is @yinfishf.size then false
      # 尚未突破ta,體內調節部分 stopWin
      #when not (@ffCycle.rootingHighUponOrEqual('ta') or @stopWinInGgYinFfYang()) then false
      
      else
        @root_sellBuoyStage(stageLabel, 'sellInGgYinFfYang')





  # 先嘗試簡單策略: 不賣出
  # 比之通法,變動較大
  cce_sellInGgYinFfYang: ->
    @cce_sellInFfYang()
    
    ###
    switch
      #when @cceGgXt.sellPoint(2,'向下報價') then true
      #when @cceAxatXt.sellPoint(2,'向下報價') then true

      #when @cceBxbtFf.sellPoint(2,'向下報價') then true
      #when @cceAxatFf.sellPoint(2,'向下報價') then true

      #@cce_sellCommon
      # 外切僅限使用最外層,以免太早交易  
      #when @cceGgXt.presellPoint(2) then true
      #when @cceBxbtXt.presellPoint(2) then true
      
      #when @cceGgXt.sellPoint(2,'向下報價') then true
      #when @cceBxbtXt.sellPoint(2,'向下報價') then true
      #when @cceAxatXt.sellPoint(2,'向下報價') then true
    ###  







  # taf 橫走,中段反彈至此再回頭之 top call 平倉點補充條件
  yinfishxTopInGgYinFfYang: ->
    switch
      when not @xtCycle.rootingHighUpon('taf') then false
      when not @xtCycle.yinHead() then false
      # 排除低位(或更高位?)
      when not @bar.lowBelowLine('taf') then false
      # 可能另須價格過濾等條件,是需要再增補
      else true





  # 體內築底萌動期的止盈
  # 記錄同質bar,以此為基準, and yangHead 
  stopWinInGgYinFfYang: ->
    # 兩線交疊,可能為止盈點
    if @bar.tax is @bar.taf
      @ffCycle.stopWinBarInGgYinFfYang = @bar
    
    {stopWinBarInGgYinFfYang} = @ffCycle
    
    switch
      # 以此過濾無須止盈的上昇過程
      when not @xtCycle.rootingLowBelow('baf') then false
      # 以此無法過濾勿再嘗試: #when @startUponFormer(@yinfishx,'yinfishxArray','tax') then false
      
      when not @ffCycle.yinHead([2,5]) then false
      when not stopWinBarInGgYinFfYang? then false
      when @barsAfter(stopWinBarInGgYinFfYang) > barsLeadFishShift then false
      else true







  # 右側賣出點
  # 確定性的 definite
  # (20180705 14:22 set up)
  sellOnCycleRightSide: ->
    switch
      when not @closeHighRise() then false

      when @sellOnGgCycleYangYangRightSide() then true
      when @sellOnBxbtCycleYangYangRightSide() then true

      # 尚未完成: when @sellOnGgCycleYangYinRightSide() then true
      
      when @sellOnBxbtCycleYangYinRightSide() then true
      when @sellOnBxbtCycleYinYinRightSide() then true

      else false





  # 真正創新高天線之後出現確定的 call 平倉賣出點,不含 put 開倉
  # (20180705 17:44)
  sellOnGgCycleYangYangRightSide: ->
    batSeparateBarExists = @recordBatSeparateBar()?
    switch
      # 不得 put 開倉,陽中之陽,非即將暴跌故
      # 旨在不生成歧義 put 信號,一旦 @root_sec_putCycle 定義改變, 隱藏的信號又會自動展示,不用改寫定義
      when @root_sec_putCycle() then false
      when not @ggCycle.yangYang(2) then false
      # 過濾掉低位
      when not batSeparateBarExists then false
      # 過濾掉短暫盤整的中繼行情
      when not (@closeHighUpon('bbbtax') or @closeHighUpon(@higherLineName)) then false
      else
        @root_sellBuoyStage('definite', 'sellOnGgCycleYangYangRightSide')
        true





  # 反彈未創新高之 call 平倉賣出點,不含 put 開倉
  # (20180705 17:44)
  sellOnBxbtCycleYangYangRightSide: ->
    {bxbtCycle} = @bband
    switch
      # 不得 put 開倉,陽中之陽,非即將暴跌故
      # 旨在不生成歧義 put 信號,一旦 @root_sec_putCycle 定義改變, 隱藏的信號又會自動展示,不用改寫定義
      when @root_sec_putCycle() then false
      # 不得僭越純陽之地
      when @yinfish.size < 11*barsLeadFishShift then false
      #when @ggCycle.yangYang(2) then false

      when not bxbtCycle.yangYang(2) then false
      # 過濾掉短暫盤整的中繼行情
      when not (@closeHighUpon('bbbtax') or @closeHighUpon(@higherLineName)) then false
      #when not @closeHighUpon('bbbtax') then false
      when bxbtCycle.cycleYinfish.size < 0.5*barsLeadFishShift then false
      else
        @root_sellBuoyStage('definite', 'sellOnBxbtCycleYangYangRightSide')
        true







  # 不易定義,暫且擱置.
  # 真正創新高天線之後出現確定的 call 平倉賣出點,含 put 短線開倉
  # (20180705 17:44)
  sellOnGgCycleYangYinRightSide: ->
    switch
      when @root_sec_callCycle() then false
      when not @ggCycle.yangYin(2) then false
      
      when @xtCycle.yangYang(2) then false
      when not (@closeHighUpon('bbbtax') or (@closeHighUpon(@higherLineName) and @closeHighUpon('ta'))) then false
      
      else
        @root_sellBuoyStage('definite', 'sellOnGgCycleYangYinRightSide')
        true





  # 反彈未創新高之 call 平倉賣出點,含 put 開倉
  # (20180705 17:44)
  sellOnBxbtCycleYangYinRightSide: ->
    {bxbtCycle} = @bband
    switch
      # 不得 put 開倉,陽中之陽,非即將暴跌故
      when @root_sec_callCycle() then false
      # 不得僭越純陽之地
      #when @yinfish.size < 11*barsLeadFishShift then false
      when @ggCycle.yangYang(2) then false
      #when @xtCycle.yangYang(2) and @yangfisht.size < barsLeadFishShift then false

      when not bxbtCycle.yangYin(2) then false
      # 過濾掉短暫盤整的中繼行情
      when not (@closeHighUpon('bbbtax') or @closeHighUpon(@higherLineName)) then false
      when bxbtCycle.cycleYinfish.size < barsLeadFishShift then false

      # 濾除長熊陰魚內反彈中繼      
      when bxbtCycle.cycleYinfish.startBar.higher('ta','bbbtax')

      else
        @root_sellBuoyStage('definite', 'sellOnBxbtCycleYangYinRightSide')
        true





  # 反彈未創新高之 call 平倉賣出點,含 put 開倉
  # (20180705 17:44)
  sellOnBxbtCycleYinYinRightSide: ->
    {bxbtCycle} = @bband
    switch
      # 不得 put 開倉,陽中之陽,非即將暴跌故
      when @root_sec_callCycle() then false
      # 不得僭越純陽之地
      when @yinfish.size < 11*barsLeadFishShift then false

      when bxbtCycle.cycleYangfish.size > 0.5*barsLeadFishShift then false

      when not @xtCycle.yinYin(2) then false
      when not bxbtCycle.yinYin(2) then false

      # 過濾掉谷底的偽賣出點
      when @yinfishx.startBar.higher('ta','tax') then false

      when not (@closeHighUpon('bbbtax') or @closeHighUpon(@midLineName)) then false
      else
        @root_sellBuoyStage('definite', 'sellOnBxbtCycleYinYinRightSide')
        true










  # 初步測試,思路對的,仍需花時間仔細斟酌,去掉低位賣出點,以及其他噪音
  # (20180624 建立)
  # (20180625 14:31 注:)
  # 下跌中繼賣出點.
  # 分歧之後的峰值賣出點以及下坡上的凸起但越走越低的賣出點,一旦不走低就停止賣出
  # 其中分歧之後的峰值首次賣出點,即切入賣出點上行部分(含創新高和反彈)再過濾後的結果; 
  # 凸起是後續中繼賣出點(通過對比tax前後高度來過濾)
  sellAfterBatSeparate: ->
    {bbbyinfishx} = @bband
    # 檢測有無此 bar
    batSeparateBarExists = @recordBatSeparateBar()?
    {yinxHeadBar} = @yinfish
    # 兩者差別 yinfish.size < n 可以淘汰熊市所有反彈高點, 而 yinfishx.size < n 則用於限制在小陰魚頭幾天
    yinsize = if @coverBearAndBull then @yinfishx.size else @yinfish.size
    
    switch
      when not batSeparateBarExists then false
      
      when not yinxHeadBar? then false
      when @yinfishx.startBar.indicatorRise('high', yinxHeadBar) then false
      when yinsize is 0 then false


      # 以下排除條件仿照 sellOnTaxDXBbbTax 並作了剪裁
      # yinsize > 1 令 yinfish/yinfishx startBar 可成為賣出點,亦令陰魚第二第三條 bar 不必收高,合乎其他要求即可高位平倉
      when (yinsize > 1) and not @closeHighRise() then false
      when yinsize > 0.5*barsLeadFishShift then false
      # 接近 tax 才可以賣出. 
      when @highFarBelowLine('tax') then false
      
      # 熊市
      # 牛市不必用此法
      when @yinfish.size < barsLeadFishShift*5 then false

      # (20180630 21:06)
      # 過濾掉反彈中途賣出點
      when bbbyinfishx.size < 0.5*barsLeadFishShift then false

      # (20180629 21:32) 引用自舊法
      # 在近在咫尺的情況下,須等待上 ta 再賣出;但注意,需要將符合條件的高處天線的賣出點都列舉出來
      #when @bbbyangxCycleX() and 
      when @nearAndEasyUpReachLine('ta') then false
      # 純模仿,未經深思,等待上 bbbtax 才賣出
      #when @bbbyangxCycleX() and 
      when @nearAndEasyUpReachLine('bbbtax') then false
      
      else
        type = if @timescale is 'minute' and batSeparateBarExists and @yinfish.size < barsLeadFishShift 
          'top' 
        else 
          'stopWin'
        if @rightStageToSell(type)
          @root_sellBuoyStage(type, 'sellAfterBatSeparate')
          @yinfish.batSeparateSoldBar = @bar
          @yinfishx.batSeparateSoldBar = @bar
          true
        else
          false



  # (20180630 17:20) 獨立成 function
  # 某線,例如 ta / bbbtax 在布林線上軌以內,算易於觸及,可再增加趨勢限定,以過濾較低賣出點
  # 舊注釋:在近在咫尺的情況下,須等待上某線 再賣出;但注意,需要將符合條件的高出天線的賣出點都列舉出來
  nearAndEasyUpReachLine: (aLineName) ->
    switch
      when @yinfishx.startBar.higher('high',aLineName) then false
      when @bar.higher(@highestLineName,aLineName) or @bar.higher('bbta',aLineName) then true
      else false






  # return the bar(may be null)
  # (20180622 建立)
  # (20180625 17:40) 改正
  # 本法可一次性完成,故不必放置於 relativeBars 集中計算
  recordBatSeparateBar: (all=false) ->
    # 無論以下哪種情形以及 all 取值如何,下行均成立:
    if @yinfish.batSeparateBar?
      return @yinfish.batSeparateBar
    
    # 所記錄的是在陰魚下出現的第一條或其後的 yangfisht 下行新生的 bar
    if @bar.higher('bat','bax') and @yangfisht.size is 0 and @yangfishx.size > 0
      @yangfish.batSeparateBar = @bar
      @yinfish.batSeparateBar ?= @bar
      #_assert.log({debug:'recordBatSeparateBar', bat:@bar.bat, bax:@bar.bax})

    # (20180625 17:40)
    if all
      @yangfish.batSeparateBar ? @yinfish.batSeparateBar
    else
      @yinfish.batSeparateBar
  
  

  
  
  # return the bar(may be null)
  # (20180625 16:53)
  # 本法非一次性完成,故須放置 relativeBars 集中計算
  recordYinxHeadBar: ->
    #if @yinfish.size > 5*barsLeadFishShift
    if @bband.bbbyinfishx.size > barsLeadFishShift
      @recordYinxHeadBarRelative()
    else 
      @recordYinxHeadBarAbsolute()





  # 記錄相對於相鄰的前一陰魚低的小陰魚,但可能實際是逐步走高的
  recordYinxHeadBarRelative: ->
    if (@yinfishx.size is 2) and (@yinfishx.size isnt @yinfish.size)
      @yinfish.yinxHeadBar = @yinfishx.startBar
      
    return @yinfish.yinxHeadBar





  # 記錄較之前記錄更低的小陰魚,其他的忽略
  recordYinxHeadBarAbsolute: ->
    # 小陰魚尺寸不足時,直接回復之前記錄,可能是 null
    unless @yinfishx.size is 2 and (@yinfishx.size isnt @yinfish.size)
      # 可能是 null
      return @yinfish.yinxHeadBar

    # 小陰魚尺寸足夠時,若無記錄,或小陰魚頭較記錄更低,則更新記錄
    if (not @yinfish.yinxHeadBar?) or @yinfishx.startBar.indicatorDrop('high', @yinfish.yinxHeadBar)  
      @yinfish.yinxHeadBar = @yinfishx.startBar
      
    return @yinfish.yinxHeadBar


  



  # tax Down Cross 向下穿過(DX) bbbtax 之後出現賣出點
  # 為了便於多線程並行,可使用 callback,此為示範,暫時未用
  # (20180622 建立)
  # (20180625 14:08) 定稿 tested on SPY
  # 此法理路清晰又簡單,無論代碼多長,關鍵點就是切入之後逢高賣出,牛熊普被
  sellOnTaxDXBbbTax_simplest_demo: (callback) ->
    @recordTaxDXBbbTaxBar()
    return @bar.taxDXBbbTax
    




  sellOnTaxDXBbbTax: (callback) ->
    {bbbyinfishx} = @bband
    taxDXBbbTaxBar = @recordTaxDXBbbTaxBar()
    batSeparateBarExists = @recordBatSeparateBar()?
    
    # 兩者差別 yinfish.size < n 可以淘汰熊市所有反彈高點, 而 yinfishx.size < n 則用於限制在小陰魚頭幾天
    yinsize = if @coverBearAndBull then @yinfishx.size else @yinfish.size
    
    switch
      when not taxDXBbbTaxBar? then false
      
      # (20180630 21:15)
      # 僅當創新高並終結之後,陰魚內才允許以本法定位賣出點(有待大量驗證,若不妥可注釋)
      # 思路可取,條件待優化,太困明天繼續(末位的 > 可能是反的)
      when @isMinute and @batSeparateBarNotExistsOrEscaped() then false

      # yinsize > 1 令 yinfish/yinfishx startBar 可成為賣出點,亦令陰魚第二第三條 bar 不必收高,合乎其他要求即可高位平倉
      when (yinsize > @barsAfter(taxDXBbbTaxBar) > 2) and not @closeHighRise() then false
      # 接近 tax 才可以賣出. 例外是,熊市中,允許內切之後第一個 bar,high 達不到 tax 附近,也賣出,避免大跌受損
      when @highFarBelowLine('tax') and ((@yinfish.size < barsLeadFishShift) or (@barsAfter(taxDXBbbTaxBar) > 1)) then false
            
      # 逢高賣出,但要方式錯失賣出時機
      # 大陰魚內,可多次逢高賣出,適用於波動範圍大頻率高的衍生品
      # 含義是 yinfishx 在下穿後賣出,且 high 更低,就不再提供賣出點.
      #when @coverBearAndBull and @yinfishx.taxDXBbbTaxSoldBar?.momentAfter(taxDXBbbTaxBar, @timescale) then false
      when @coverBearAndBull and @bar.indicatorDrop('high', @yinfishx.taxDXBbbTaxSoldBar) then false
      # 大陰魚實際僅賣一次,適用於巴菲特式長期股票持倉策略 
      #when (not @coverBearAndBull) and @yinfish.taxDXBbbTaxSoldBar?.momentAfter(taxDXBbbTaxBar, @timescale) then false
      when (not @coverBearAndBull) and @bar.indicatorDrop('high', @yinfish.taxDXBbbTaxSoldBar) then false
      
      # 用於精準定位,排除後續低位賣出噪音
      when yinsize > 1.5*barsLeadFishShift then false
      when @barsAfter(taxDXBbbTaxBar) > 0.5*barsLeadFishShift then false

      # (20180622 21:28) 下行非策略,僅為測試用來分別標記是否可行.
      #when @timescale is 'minute' and not batSeparateBarExists then false # for test only
      else
        stageLabel = if @timescale is 'minute' and batSeparateBarExists and @yinfish.size < barsLeadFishShift
          'top' 
        else 
          'stopWin'
        
        if @rightStageToSell(stageLabel)          
          @root_sellBuoyStage(stageLabel, 'sellOnTaxDXBbbTax')
          @yinfish.taxDXBbbTaxSoldBar = @bar
          @yinfishx.taxDXBbbTaxSoldBar = @bar
          true
        else
          false




  # 此為補救措施,最好在生成信號時,增強過濾條件
  rightStageToSell: (stageLabel) ->
    # 已測試,無bug. 先屏蔽, 若欲使用,則去掉 if 前的 #
    return true #if stageLabel isnt 'stopWin'

    minutes = 10
    n = 8

    switch
      when @contractHelper.closingIn(minutes) then true
      when @bar.close > @buyBuoy.grade[n] then true
      else false





  # (20180701 16:36) 獨立設置
  # 上漲未出現分歧,或出現分歧破位下跌已久,而行情變異,行走於 ta 之上, 此時仿照未出現分歧處理
  # (20180630 21:15) 初建. 舊注:
  # 僅當創新高並終結之後,陰魚內才允許以本法定位賣出點(有待大量驗證,若不妥可注釋)
  # 思路可取,條件待優化,太困明天繼續(末位的 > 可能是反的)
  batSeparateBarNotExistsOrEscaped: ->
    batSeparateBarExists = @recordBatSeparateBar()?
    {bbbyinfishx} = @bband

    switch
      when batSeparateBarExists then false 
      # 以下條件須分解分析設計(昨天想到的,不完整,當時睏了睡了)
      when (@yinfish.size < barsLeadFishShift) or (bbbyinfishx.size > 0.5*barsLeadFishShift) then false
      else false #(true?)

    #not (batSeparateBarExists and (@yinfish.size < barsLeadFishShift or bbbyinfishx.size > 0.5*barsLeadFishShift))






  # return the bar(may be null)
  # (20180622 17:34)
  # (20180628 10:25) 以下定義反復測試看不出錯誤,但始終無法呈現所有的切入點,原因不明
  recordTaxDXBbbTaxBar: ->
    {bbbyinfishx} = @bband
    {startBar} = @yinfishx

    switch
      # 避免重複和後移
      when @yinfishx.taxDXBbbTaxBar? then null
      when startBar.higher('bbbtax', 'tax') then null
      when not @bar.indicatorDrop('tax', startBar) then null
      when @bar.higher('bbbtax','tax')
        bbbyinfishx.taxDXBbbTaxBar = @bar
        @yinfishx.taxDXBbbTaxBar = @bar
        @yangfisht.taxDXBbbTaxBar = @bar
        #@yangfishx.taxDXBbbTaxBar = @bar
        @bar.taxDXBbbTax = true
    
    return @yangfisht.taxDXBbbTaxBar ? bbbyinfishx.taxDXBbbTaxBar ? @yinfishx.taxDXBbbTaxBar #? @yangfishx.taxDXBbbTaxBar

  # 注: 以前用 relativeBars() 所做的記錄,可仿照上述 function 改寫,單元最小化,一物一用





  # 原始寫法
  recordTaxDXBbbTaxBar_origin: ->
    {bbbyinfishx} = @bband
    {startBar} = @yinfishx
    # 如此寫法,可支持某日交叉,正好相等的情形
    if @bar.indicatorDrop('tax', @previousBar) and @bar.higher('bbbtax','tax') and not @previousBar.higher('bbbtax', 'tax')
      bbbyinfishx.taxDXBbbTaxBar = @bar
      @yinfishx.taxDXBbbTaxBar = @bar
      @yangfisht.taxDXBbbTaxBar = @bar
      #@yangfishx.taxDXBbbTaxBar = @bar
      @bar.taxDXBbbTax = true
    
    return @yangfisht.taxDXBbbTaxBar ? bbbyinfishx.taxDXBbbTaxBar ? @yinfishx.taxDXBbbTaxBar #? @yangfishx.taxDXBbbTaxBar







  # (20180626 17:24) 從原來的大 sellNexusSimple function 內取出獨立, 一物一用
  # 臨時命名,稍後根據屬性重新命名
  # 原第四賣出點
  # (20180619 9:27) 原定義
  # sell4: 主體下穿, put 開倉
  # 思路: 跌穿 bbbba, 低於 bbbbat, @yangfisht.size < 3, bbayinfishx.startBefore bbbyangfisht, 破位不過若干 bar
  sellNexusSimple4: ->
    {bbayinfishx, bbbyangfisht} = @bband
    
    switch
      when not @closeHighRise() then false
      when not bbayinfishx.startBefore(bbbyangfisht) then false
      when not @bar.highBelowLine('bbbba') then false
      
      when @barsAfter(@yinfish.brokenBar) < 5 then switch
        # 'hour' 行情下不夠嚴密,易出現盤局底部賣出,且未發現過濾之法
        when @timescale isnt 'minute' then false
        when (bbbyangfisht.size > 0) and (@yangfisht.size > 0) then false
        else
          if @rightStageToSell('top')
            @root_sellBuoyStage('top')
            true
          else
            false
      else false





  # (20180626) 獨立,一物一用
  # 賣出點較少, @sellOnTaxDXBbbTax 基本包涵此法賣出點, 備考
  # 原 第一賣出點
  # 創歷史新高以至之後數日內, call 之最佳止盈點, 而不作為 put 之開倉點. 
  # 第一賣出點 sell1: 創歷史新高以至之後數日內, call 之最佳止盈點, 而不作為 put 之開倉點. 
  #   1a 兩陰魚都成型,各自天線可以藉以賣出
  #   1b 極少數變異情形,即 bbbyinfishx 之 size 始終未來得及超過1, 即已下穿,故須及時捕捉,提前止盈
  # 後續無論盤升或回跌,都游刃有餘,可以補倉 call, 亦可以開 put
  # 注意, bbatax 有時倒掛,高於 bbbtax, 但創新高時,一定不會倒掛
  # (20180610 21:40) 代碼可初步固定
  _sellNexusSimple1_: ->
    {bbayinfishx, bbbyinfishx, bbbyangfisht} = @bband

    switch
      when not @closeHighRise() then false

      # 第四賣出點
      when bbayinfishx.startBefore(bbbyangfisht) and @bar.highBelowLine('bbbba') and @barsAfter(@yinfish.brokenBar) < 5 then false
      
      # 下行會導致爬升過程中賣出太早,故不妥
      #when bbbyinfishx.size in [0..8] then switch
      # 要求創歷史新高,故用 @yinfish 而非 @yinfishx 等
      when @yinfish.size in [2..barsLeadFishShift] then switch
        when not @closeHighUpon('bbatax') then false
        #when not @closeHighUpon('bbbtax') then false
        #when (bbbyinfishx.size in [2..barsLeadFishShift*0.5]) then switch
      
        # 1a 兩陰魚都成型,各自天線可以藉以賣出
        when (bbbyinfishx.size in [1..barsLeadFishShift])
          @root_sellBuoyStage 'stopWin'
          true
          # 不可如此: #@yangfisht.sellStopBar = null

        # 1b 極少數變異情形,即 bbbyinfishx 之 size 始終未來得及超過1, 即已下穿,故須及時捕捉,提前止盈
        when @bar.higher('tax', 'bbatax') and @yinfishx.size > 3         
          @root_sellBuoyStage('stopWin')
          true

        # (20180611 6:46)
        # 1c
        # 若上述條件第一賣出點仍有脫漏,可記錄 bbatax 跌穿之 bar bbataxBrokenBar 
        # 並據此以及 @yinfish.size 等設計後續賣出操作
        
        else false
      else false







  # (20180626 18:09) 獨立,一物一用
  # 類似, 但次於 sellOnTaxDXBbbTax, 備考
  # 第二賣出點, 高位橫盤觸頂
  # 高位橫盤觸頂, 可作為 call 止盈平倉點, 若存在 bbbyangfishtBrokenBar 則可作為 put 開倉點, 
  # 似乎不妨多多益善, 然而最後一筆若在突破上昇前平倉,會導致 call 太早賣出,嚴重影響收益
  # 與第一賣出點頗為相似,但細節有差異,應分別定義,不必強行求同; 而最大區別是排除創新高情形:
  _sellNexusSimple2_: ->
    {bbayinfishx, bbbyinfishx, bbbyangfish, bbbyangfisht} = @bband
    {bbbyangfishtBrokenBar} = @yinfish
    switch
      when not @closeHighRise() then false

      # 第四賣出點
      when bbayinfishx.startBefore(bbbyangfisht) and @bar.highBelowLine('bbbba') and @barsAfter(@yinfish.brokenBar) < 5 then false
      
      # 下行會導致爬升過程中賣出太早,故不妥
      #when bbbyinfishx.size in [0..8] then switch
      # 要求創歷史新高,故用 @yinfish 而非 @yinfishx 等
      # 第一賣出點
      when @yinfish.size in [2..barsLeadFishShift] then false

      # 第二賣出點, 高位橫盤觸頂
      # 高位橫盤觸頂, 可作為 call 止盈平倉點, 若存在 bbbyangfishtBrokenBar 則可作為 put 開倉點, 
      # 似乎不妨多多益善, 然而最後一筆若在突破上昇前平倉,會導致 call 太早賣出,嚴重影響收益

      # 與第一賣出點頗為相似,但細節有差異,應分別定義,不必強行求同; 而最大區別是排除創新高情形:
      when @yinfish.size < barsLeadFishShift then false

      # 注意, bbatax 有時倒掛,高於 bbbtax, 但使用 bbbtax 更為保險
      # 不要此項: #when bbbyinfishx.size > barsLeadFishShift and bbayinfishx.size > barsLeadFishShift then switch
      when (@yinfishx.startBar.highUponLine('bbbtax') or @yinfishx.startBar.highUponLine('bbatax')) then switch
        # 不符合此條件的,可在止損function內定義
        
        # 在近在咫尺的情況下,須等待上 ta 再賣出;但注意,需要將符合條件的高處天線的賣出點都列舉出來
        when @nearAndEasyUpReachLine('ta') then false

        when @yinfish.size < barsLeadFishShift*3 and @bar.higher('tax','bbbtax') and @yangfisht.startBefore(@yinfishx) then false
        when @yinfish.size < barsLeadFishShift*2 and not @closeHighUpon('bbbtax') then false
        # 降低要求,利於逃命
        when @yinfish.size > barsLeadFishShift*2 and not @closeHighUpon('bbatax') then false

        # (20180618 9:49) 添加後半截之後, 解決了脫漏賣出點bug
        #when bbayinfishx.size < 2 then false
        # 這是為了照顧不久盤直接跌情形
        when bbayinfishx.size < 2 and @yinfishx.size < 3 then false
        # 高出 bbta 很多, 此時要求 bbayinfishx.size < 2
        when bbayinfishx.size < 2 and @bar.higher('bbatax', 'bbta') and @bar.higher('ta','bbta') then false
        # 此時更強一些,故將條件再收緊一些
        when bbayinfishx.size < 3 and @bar.higher('bbbat', 'bbta') then false

        when @yinfishx.size in [0..barsLeadFishShift] 
          @root_sellBuoyStage(if bbbyangfishtBrokenBar then 'top' else 'stopWin')
          true
          #不可如此: #@yangfisht.sellStopBar = null

        # 上述條件第二賣出點仍有脫漏,可記錄 bbatax 跌穿之 bar bbataxBrokenBar         
        # 並據此以及 @yinfishx.size 等設計後續賣出操作
        
        else false
      else false





  # (20180626 18:26) 獨立,一物一用
  # 經測,當前行情極少出現,故合併a/b,備考  
  # 原第三賣出點, 定義追加賣出(以便put操作),即 
  #   3a 破位後, 以及 
  #   3b 盤局中的賣出點
  _sellNexusSimple3_: ->
    {bbayinfishx, bbbyinfishx, bbbyangfish, bbbyangfisht} = @bband
    {bbbyangfishtBrokenBar} = @yinfish
    switch
      when not @closeHighRise() then false

      # 第四賣出點
      when bbayinfishx.startBefore(bbbyangfisht) and @bar.highBelowLine('bbbba') and @barsAfter(@yinfish.brokenBar) < 5 then false
      
      # 下行會導致爬升過程中賣出太早,故不妥
      #when bbbyinfishx.size in [0..8] then switch
      # 要求創歷史新高,故用 @yinfish 而非 @yinfishx 等
      # 第一賣出點
      when @yinfish.size in [2..barsLeadFishShift] then false

      # 第二賣出點, 高位橫盤觸頂
      # 高位橫盤觸頂, 可作為 call 止盈平倉點, 若存在 bbbyangfishtBrokenBar 則可作為 put 開倉點, 
      # 似乎不妨多多益善, 然而最後一筆若在突破上昇前平倉,會導致 call 太早賣出,嚴重影響收益

      # 與第一賣出點頗為相似,但細節有差異,應分別定義,不必強行求同; 而最大區別是排除創新高情形:
      when @yinfish.size < barsLeadFishShift then false

      # 注意, bbatax 有時倒掛,高於 bbbtax, 但使用 bbbtax 更為保險
      # 不要此項: #when bbbyinfishx.size > barsLeadFishShift and bbayinfishx.size > barsLeadFishShift then false
      when (@yinfishx.startBar.highUponLine('bbbtax') or @yinfishx.startBar.highUponLine('bbatax')) then false
      
      # 第三賣出點 將作為 put 開倉或補倉點
      # 定義追加賣出(以便put操作),即 
      # 3a 破位後, 以及 
      # 3b 盤局中的賣出點

      # 共性
      when @yinfish.size < barsLeadFishShift then false
      when @yangfishx.size > barsLeadFishShift*2 then false
      when bbbyangfisht.size > barsLeadFishShift*2 then false 

      # 3a
      # 思路: 久盤之後跌穿 mata, bbbbat 破位下行
      # (20180612 15:47)      
      when (@yinfish.size > barsLeadFishShift*4) and @yinfishx.startBar.highUponLine('mata') then switch
        # 不符合此條件的,可在止損function內定義

        # 在近在咫尺的情況下,須等待上 ta 再賣出;但注意,需要將符合條件的高處天線的賣出點都列舉出來
        when @nearAndEasyUpReachLine('ta') then false

        # (20180618 4:29) add line, 限定 ta 對於現價已呈"遙不可及"之相:
        when @bar.higher(@highestLineName,'ta') or @bar.higher('bbta','ta') then false

        when bbbyangfisht.size > 1 then false
        when not @closeLowBelow('bbbbat') then false
        when not @bar.closeBelowLine('mata') then false
        when @yinfishx.size in [1..4]
          @root_sellBuoyStage 'top'
          true
        else false

      # 3b
      # 思路: @yinfishx.startBar 低於前,賣出, stage 為 top 即 put 可翻作開倉
      # (20180610 20:23)
      # (20180611 11:21) 定義成功
      # (20180623 15:26) 增加限制條件
      #when @yinfish.startBefore(@yangfishx) and @yinfishx.startBar.high < bbayinfishx.yinfishxHead?.low then switch
      when @yinfish.startBefore(@yangfishx) and @yinfishx.startBar.high < @yinfish.yinxHeadBar?.low then switch  
        when @yangfishx.startBar isnt @yinfish.cornerBar and @yangfishx.cornerBar.highUponLine('bbbba') then false
        when @yangfishx.size > barsLeadFishShift then false
        #when @yangfisht.size > barsLeadFishShift then false
        when @yinfishx.startBar.highUponLine('bbatax') then false
        when @yinfishx.startBar.highUponLine('bbbtax') then false
        when @yinfishx.size in [1..5]
          @root_sellBuoyStage 'top'
          true
        else false
      else false





  # ------------- 其他舊思路 暫時保留備考 -------------
  sellNexusSimple_old: ->
    {bbayinfishx, bbbyinfishx, bbbyangfish, bbbyangfisht} = @bband
    {bbbyangfishtBrokenBar} = @yinfish
    switch
      when not @closeHighRise() then false

      # 舊思路,邏輯不嚴密,暫時備考
      # (20180610 4:08)
      # 可繼續研究,但暫時太多信號      
      when not (bbbyinfishx.size in [8..barsLeadFishShift]) then switch
      #when bbbyinfishx.size in [2..8] then switch 
        when @yinfishx.size in [3..4] and @closeHighUpon('bbatax')
          @root_sellBuoyStage 'top'
          true
          # 不可如此: #@yangfisht.sellStopBar = null
        else false

      # 定義域.此項定義邏輯等同止盈,僅時間範圍不一樣,有無道理,待觀測.可能是想象出來的.
      # 為測試其他選項暫時屏蔽
      when barsLeadFishShift > bbbyinfishx.size > 3 then switch
        # 可以過濾掉此線在上昇部分
        #when bbayinfishx.size < 4 then false
        when @yinfishx.size in [1..5] and @closeHighUpon('bbatax')
          @root_sellBuoyStage 'stopWin'
          true
          # 不可如此: #@yangfisht.sellStopBar = null
        else false

      else false









  # 最高價顯著低於某線
  # (20180622 17:34)
  highFarBelowLine: (aLineName) ->
    #adjustedHigh = if /minute/i.test(@timescale) then @contractHelper.略向上報價(@bar.high) else @contractHelper.向上報價(@bar.high)
    adjustedHigh =  @contractHelper.向上容忍價(@bar.high)
    @bar.highBelowLine(aLineName) and (adjustedHigh < @bar[aLineName])





  sellNexusSimple20180526: ->
    lbta = @smallOne('bbta','bbbta')

    switch
      # 冒尖賣出
      # (20180606 17:00)
      when barsLeadFishShift*2 > @bband.bbbyinfish.size > 5 and @earlierBar.higher('bbbta','tax') and @bar.higher('bbbta', 'bbta') and @bar.closeUponLine('bbbta')
        @root_sellBuoyStage 'top'
        true

      # 已觸及均線是根本前提,
      # 主要用 @mayinfishx 記錄, 特例當 @yangfishx 起於 @bband.bbbyinfish 之前,以 @yangfishx 記錄
      # 排除不出現上述記錄情形
      # (20180606)
      when not (@yinfishx.maBrokenBar? or (@yangfishx.maBrokenBar? and @yangfishx.startBar.lowBelowLine('bbbba'))) then false
      
      # 陰線創新高,賣出
      # (20180606)
      #when @bar.tax > @bar.bbbta > @bar.bbta and @yinfishx.size is 0 and @bar.yin() and @bar.low < @previousBar.close
      when (not @pureYang()) and @bar.tax > @bar.bbbta and @yinfishx.size is 0 and @bar.yin() and @bar.low < @previousBar.close
        @root_sellBuoyStage 'top'
        true

      # 除了陰線創新高之外,新高不賣出
      when @yinfishx.size is 0 then false
      # 除了上述條件,收低不賣出
      # (20180606)
      when @bar.indicatorDrop('close', @previousBar) then false

      when 1 < @yinfish.size < barsLeadFishShift and @yinfish.startBar.higher('bbbta','high') and @yinfish.startBar.higher('high','bbatax') and @bar.highUponLine('bbatax') and @bar.highUponLine('ta')
        @root_sellBuoyStage 'top'
        true

      # 濾除純陽主升段之賣出
      when @mayinfish.size < barsLeadFishShift then false

      # 濾除下跌 bar 追跌賣出(價位會受損失且可能不成交故)
      #when @isCurrentData() and @bar.indicatorDrop('close', @previousBar) then false
      when @isCurrentData() and @bar.closeBelowLine(lbta) then false

      # 捷徑賣出點
      when @bar.highUponLine(lbta) then switch

        # (20180602 20:04) 新增排除條件
        # [bug?] 思路正確,但所出結果並不完全合理,懷疑代碼中有筆誤或其他bug 待查
        when @yangfishx.startBefore(@bband.yinfish) then @fatingYang()
        
        # 承接上述條件,起於 @bband.yinfish 之後, @bband.bbbyinfish 之前
        when @yangfishx.startBefore(@bband.bbbyinfish) then switch
          # 排除 bbbta 低於 bbta
          when @bar.higher('bbta','bbbta') then false
          # 排除起點處 bbbta 高於前方 @bband.yinfish 起點處的 bbta
          when @bband.bbbyinfish.startBar.bbbta >= @bband.yinfish.startBar.bbta then false
          else @fatingYang()

        when @yinfishx.size in [1..4] and @bar.highUponLine(lbta)  #('bbbta')
          @root_sellBuoyStage 'top'
          true

        else false

      else false



  
  # 取得其值小的線之線名
  smallOne: (lineA, lineB, bar=@bar) ->
    if bar[lineA] > bar[lineB] then lineB else lineA

  bigOne: (lineA, lineB, bar=@bar) ->
    if bar[lineA] < bar[lineB] then lineB else lineA

  

  # 陽消(恐陰將長)
  fatingYang: ->
    switch
      # 排除正在上昇
      when @yinfishx.size is 0 then false
      # 排除尚無破位標誌 bbbyangfishtBrokenBar
      when not @bband.bbbyangfish.bbbyangfishtBrokenBar? then false
      # 排除低於破位點
      when @bar.indicatorDrop('close', @bband.bbbyangfish.bbbyangfishtBrokenBar) then false
      # 排除收低於前 bar
      when @bar.indicatorDrop('close', @previousBar) then false
      
      # 排除已經賣出,且再次出現信號時,低於 bbta
      #when @yangfishx.brokenSoldBar? and not @bar.closeUponLine('bbta') then false
      # 排除任何收低於 bbta
      when not @bar.closeUponLine('bbta') then false
      
      # 排除已經賣出,且再次出現信號時, 低於 bbbta
      when @yangfishx.brokenSoldBar? and not @bar.closeUponLine('bbbta') then false
      # 排除任何收低於 bbbta
      #when not @bar.closeUponLine('bbbta') then false
      
      else
        @yangfishx.brokenSoldBar ?= @bar
        @root_sellBuoyStage 'top'
        true




  # (20180526) 改為獨立 function
  sellNexus20180521: ->
    switch
      # 以上軌以及 bbta 為關鍵,進行過濾.從上軌外側切入內側,綜合股價之陰魚,最好在上昇過程中止盈賣出
      when @fishYang() then @fishYangSellNexus()

      # 以中軌為關鍵,高於中軌時,可以空頭賣出
      # (20180524 15:49) 在新的盤局策略下,僅取趨勢確定型的補倉點
      when @fishNotYang() then @fishNotYangSellNexus()

      else false




  # (20180521 17:30)
  # (20180522 20:08 單列)
  # (20180524 16:18 改寫)
  fishYangSellNexus: ->
    #@fishYangSellNexusOrigin()
    @fishYangSellNexusBox()




  # (20180524 16:19) 改寫自 fishYangSellNexusOrigin
  fishYangSellNexusBox: ->
    switch
      # (20180524 16:59)
      # 過濾純陽區域的假賣出點,但不淨
      #when @bband.yinfish.size < barsLeadFishShift or @mayinfish.size < barsLeadFishShift then false
      # (20180524 20:10)
      # 過濾純陽區域的假賣出點,就目前行情看可行      
      when @bband.yinfish.size < barsLeadFishShift*2 then false #and @mayinfish.size < 2 then false
      # 濾除較低的賣出點
      # 濾除低於 bbta 且低於 mata 者
      #when @bar.closeBelowLine('bbta') and @bar.closeBelowLine('mata') then false
      # 濾除同時低於 bbta bbbta 者
      when @bar.closeBelowLine('bbta') and @bar.closeBelowLine('bbbta') then false
      # 以上據盤局出入法新增過濾條件

      # 以下原有代碼
      when @bar.indicatorDrop('close', @previousBar) then false
      # spy 實例看似乎無須將上述條件分拆為以下對於非純陽段更為寬鬆的條件
      #when @pureYang() and @bar.indicatorDrop('close', @previousBar) then false
      #when @bar.indicatorDrop('high', @previousBar) then false
      
      # (20180523)
      when @yinfishx.size < 3 and @yinfish.size < barsLeadFishShift*2 then false
      # (20180524 10:32)
      when @yinfishx.size < 2 and @yinfish.size >= barsLeadFishShift*2 then false
      
      # 以下使用 @yinfishx, @bband.yinfish, @bband.bbbyinfishx 及其均線 tax, bbta, bbbtax
      #when @yinfishx.size > 0 and @contractHelper.向上報價(@bar.high) < @bar.tax then false
      # bbta 久盤之後出現,此時頂天賣出,所謂頂天,亦即 tax 高於 bbta 小於 bbbtax
      when @bar.bbbtax > @bar.tax > @bar.bbbta then true
      # 以此保留剛創新高之後可能出現的止盈點,過濾掉 bbta 形成很久之後欲上行突破時出現的 tax 小於橫行下壓 bbta 情形
      #when @bband.yinfish.size is 0 then @bar.tax < @bar.bbta 
      when @bband.bbbyinfishx.size is 0 then @bar.tax < @bar.bbbtax 

      else false





  # (20180522) 原始版未完成定義
  # (20180524 15:49) 在新的盤局策略下,僅取趨勢確定型的同向追賣補倉點
  # 故以下定義為破位同向補倉賣出點  
  fishNotYangSellNexus: ->      
    switch
      # 暫時沿用 (20180523) 
      when @timescale is 'hour' and @tempSellStrategyFromBuoy() then true # 其中部分可改寫作為此處主體,分別為陰魚起點,中繼下跌,見以下注釋
      
      # 取法於 tempSellStrategyFromBuoy
      #when @yangfishx.cornerBar.highBelowLine('bbba') then switch
      #  when pool.mayinCycleB() and @bar.highUponLine(@midLineName) \ # (20180523) 在 pool 中增加以下過濾條件
      #  #and @mayangfishb.size is 0 \
      #  and @bar.closeDownCross(@midLineName, @previousBar) \
      #  and @bar.indicatorDrop('close', @previousBar) # new add (20180523)
      #    @sellBuoy.stage = 'continue'
      #    true
      #  else false


      when @bband.yinfish.size < barsLeadFishShift then false
      when @mayinfishx.size < barsLeadFishShift then false
      else false






  # 暫時沿用 (20180523)   
  # 此法在舊法中,純陽期末賣出功能較好,另有不太純淨的中繼賣出功能,在目前環境惡劣情形下,暫時先用,移至pool,命名為 tempSellStrategyFromBuoy
  tempSellStrategyFromBuoy: ->
  # 節選自 HoloSellBuoyFitMarket,代碼盡量不改動
  # (20180506 19:40建立)
  # (20180509 上午更新)
  #fitMarket20180506: (pool) ->
    {yinfish,yinfishx,mayangfishb,mayinfishb,mayinfishx,bband,bband:{bbbyinfishx}} = this #pool
    switch
      when @bar.indicatorDrop('close', @previousBar) and @bar.indicatorDrop('high', @previousBar) then false

      # (20180511 20:43)
      when (mayinfishx.coveredBars?.length > 1) and (0 < yinfish.size < barsLeadFishShift*2) #and \
      #@bar.highUponLine(@midLineName)  # 另價格上昇,前已述及
        @sellBuoy.stage = 'begin'
        true 
      
      # (20180510) 
      # 目的: 過濾掉盤局末期,剛剛起漲的錯誤賣出點.
      # 狀態不佳.可能雜.
      when @bar.closeUponLine('bbta') and @bar.closeUponLine(@higherLineName) and (@bar[@higherLineName] > @bar.bbta) and (mayangfishb.size > 0)
        false

      # (20180511)
      # 篩除過早賣出,但不確定是否全局適用,先嘗試一下看有無問題.(經測試,增加了 bband.yinfish.size 限制,以令作用於盤局)
      when bband.yinfish.size > barsLeadFishShift*2 and @bar.closeUponLine(@higherLineName) then false

      # 賣出策略兩種: 1. 純陰 2. 非純陰

      # 1. 純陰賣出
      
      # 1.a 陰魚起始
      # (20180511 20:43)
      # 此法似普適,非僅最高點起始之純陰第一段,待下一版本分支作為主導賣出點,再提煉
      when (mayinfishx.coveredBars?.length > 1) and (0 < yinfish.size < barsLeadFishShift*2) #and @bar.highUponLine(@lowLineName)  # 另價格上昇,前已述及
        @sellBuoy.stage = 'begin'
        true 

      # 謹慎.此條件理路無誤,各品種若直接使用亦無誤.
      # 但在主證券指示期權進出情境,因期權隨時間而削價,須考慮萬一形成延後,以及延後的影響.
      # sell,put翻譯為開倉則好,call翻譯為平倉,會否價格吃虧. 
      # 影響應該不大,且減少進出費用以及反復進出出現差錯帶來的損失之後,或可彌補延後所致的損失.
      # 故重點是繼續使用此條件,必要時,期權選擇稍微遠些的,避免逼近行權而 time value 急劇消失的情形即可
      # 但作為範例,在設計策略時,須時時留意期權的時效問題.
      # 僅適用於小時及分鐘
      when /minute|hour/i.test(@timescale) and bband.yinfish.size < barsLeadFishShift then false
      when /minute/i.test(@timescale) and mayinfishx.size < barsLeadFishShift then false

      when yinfish.size in [1..4] then switch
        when @bar.closeBelowLine(@highLineName) then false
        when yinfish.startBar.closeVari < mayangfishb.maxVari
          @sellBuoy.stage = 'begin'
          true        
        else false

      # 1.b 純陰中繼
      when pool.pureYin() then switch
        
        # (20180523) 分析此法可作為普通的陰循環放到此處程序體,用於陰循環中繼下跌條件,注意此處是收盤跌,且跌破均線,與通常寫法不同

        # (20180511)
        when pool.mayinCycleB() and @bar.highUponLine(@midLineName) \ # (20180523) 在 pool 中增加以下過濾條件
        and @mayangfishb.size is 0 and @bar.closeBelowLine(@midLineName) and @bar.indicatorDrop('close', @previousBar) # new add (20180523)
          @sellBuoy.stage = 'continue'
          true

        else false

      else false





  # (20180526) 與 buyNexusSimple 合用
  ###
    思路: 
      須通過變量標記買入點,然後對有買入點的 bbbyangfishx 作止損監測
      有兩種情形,看能否簡化. 1. 此線尚在,將要破位,尚未破位,先行止盈 2. 此線已經過去,現在是新魚第一 bar,必須清倉(比例 100%)
      僅處理第二種情形
      (20180529 補記)
      一度誤認為與 @yangfishx 不同,僅有一種情形, bar 跌穿 bbbbax 之後才會發生下滑,故更為簡單
      實則存在跳空下跌情形,故沿用原處理方法
  ###
  buyNexusSimpleStop: ->
    #@buyNexusSimpleStop20180526()
    @buyNexusSimpleStop20180602()





  # bax 止損止盈外加 bbbbat 止盈 
  buyNexusSimpleStop20180602: ->
    # 由於標記不同,止盈止損分別定義
    switch
      when @buyNexusStopWin()
        # 標記為 stopWin / stopLoss. stopWin 則 stillReflective 操作為補倉操作,可有可無.
        @root_sellBuoyStage 'stopWin'
        true

      when @buyNexusStopLoss()
        # 標記為 stopWin / stopLoss. stopWin 則 stillReflective 操作為補倉操作,可有可無.
        @root_sellBuoyStage 'stopLoss'
        true
      
      else false




  buyNexusStopWin: ->
    @buyNexusStopWin20180602()
    #@buyNexusStopWin20180619()



  buyNexusStopLoss: ->
    return false
    
    @buyNexusStopLoss20180602()




  # 由 buyNexusStopWin20180602 改陽魚種類, @yangfisht 取代 @yangfishx 尚未改完,發現可能無必要,先測試舊法
  buyNexusStopWin20180619: ->
    running = @isCurrentData()
    testIt = false
    switch
      # (20180607 21:49) 嘗試思路 待完善
      when @barIsCurrent(@yinfishx.revertBar) then switch
        when not testIt then false
        else
          @root_sellBuoyStage 'continue'
          true

      # 跟盤局止盈止損不同,前提是 @yangfisht 先起    
      when @yangfisht.startAfter(@bband.yinfish) then false

      # 收低不賣
      when @bar.indicatorDrop('close', @previousBar) then false

      # 若無此限制這部分應是正常的賣出限制條件,而非特殊止盈條件 :)
      when @mayinfish.size >= barsLeadFishShift then false
      
      #when @bar.highUponLine('bbbta') and (0 < @bband.bbbyinfish.size < barsLeadFishShift) then true

      # 跌破 bax 之前先跌破 bbbbat 而止盈的情形
      when @bband.bbbyangfish.bbbyangfishtBrokenBar? then switch
        when @yinfishx.size is 0 then false 
        when @bar.indicatorDrop('close', @bband.bbbyangfish.bbbyangfishtBrokenBar) then false
        when @bar.indicatorDrop('close', @previousBar) then false
        # 首次止盈無須高於 bbta, 之後則需要
        when @yangfisht.brokenSoldBar? and not @bar.closeUponLine('bbta') then false
        else
          @yangfisht.brokenSoldBar ?= @bar
          true
      
      # 跌破 bax 而止盈的情形; 方法相同,前提不同
      when @yangfishtStop()
        # 標記為 stopWin 此時 stillReflective 操作為補倉操作,可有可無.
        @root_sellBuoyStage 'stopWin'
        true
      
      else false



  # (20180619) 經測試,在今天行情中,僅有第一個條件有信號
  buyNexusStopWin20180602: ->
    running = @isCurrentData()
    testIt = false
    switch
      # (20180607 21:49) 嘗試思路 待完善
      when @barIsCurrent(@yinfishx.revertBar) then switch
        when not testIt then false
        else
          @root_sellBuoyStage 'continue'
          true

      # 跟盤局止盈止損不同,前提是 @yangfishx 先起    
      when @yangfishx.startAfter(@bband.yinfish) then false

      # 收低不賣
      when @bar.indicatorDrop('close', @previousBar) then false

      # 若無此限制這部分應是正常的賣出限制條件,而非特殊止盈條件 :)
      when @mayinfish.size >= barsLeadFishShift then false
      
      #when @bar.highUponLine('bbbta') and (0 < @bband.bbbyinfish.size < barsLeadFishShift) then true

      # 跌破 bax 之前先跌破 bbbbat 而止盈的情形
      when @bband.bbbyangfish.bbbyangfishtBrokenBar? then switch
        when @yinfishx.size is 0 then false 
        when @bar.indicatorDrop('close', @bband.bbbyangfish.bbbyangfishtBrokenBar) then false
        when @bar.indicatorDrop('close', @previousBar) then false
        # 首次止盈無須高於 bbta, 之後則需要
        when @yangfishx.brokenSoldBar? and not @bar.closeUponLine('bbta') then false
        else
          @yangfishx.brokenSoldBar ?= @bar
          true
      
      # 跌破 bax 而止盈的情形; 方法相同,前提不同
      when @yangfishxStop()
        # 標記為 stopWin 此時 stillReflective 操作為補倉操作,可有可無.
        @root_sellBuoyStage 'stopWin'
        true
      
      else false


  
  # 未必盡是止損,也可能是止盈.但是處於盤局嘗試買入之後,故很可能止損或僅有微利.
  buyNexusStopLoss20180602: ->
    switch
      # 跟上漲止盈不同,前提是 @yangfishx 後起
      when @yangfishx.startBefore(@bband.yinfish) then false

      # 收低不賣
      when @bar.indicatorDrop('close', @previousBar) then false

      # 跌破 bax 而止盈但也可能止損的情形;方法相同,前提不同.
      when @yangfishxStop()
        # 標記為 stopWin 此時 stillReflective 操作為補倉操作,可有可無.
        @root_sellBuoyStage 'stopLoss'
        true
      else false





  # (20180602)
  ### 
  注意:
     由於要求先有買入信號,後有止盈止損,故圖形看未必在出現止盈止損結構時隨即顯現.
     若之前無策略買入點,則不顯現策略止盈點.
  ###
  yangfishxStop: ->
    formerx = @formerObject('yangfishxArray')
    running = @isCurrentData()
    {yinfish:{yangfishxBrokenBar}} = @bband

    switch
      when not (formerx?.buyNexusBar? or @yangfisht.buyNexusBar?) then false
      when @bar.indicatorDrop('high', @previousBar) then false
      when yangfishxBrokenBar? then switch
        when @barsBetween(yangfishxBrokenBar, @bar) < barsLeadFishShift then true
        else false

      else false





  # 以下代碼是尚未整理出以上思路之前的,待稍事休息後立即改寫 (20180526 17:10)
  buyNexusSimpleStop20180526: ->
    fishx = @bband.bbbyangfishx
    formerx = @bband.formerObject('bbbyangfishxArray')
    running = @isCurrentData()

    switch
      # 情形一
      when fishx?.buyNexusBar? then switch
        # 既然已經找到 former yangfishx, 則開倉與止盈止損共用條件已不需要重複
        # 止盈止損條件
        when @previousBar.closeBelowLine('bbbbax')  #lowBelowLine('bbbbax')
          # 標記為 stopWin / stopLoss. stopWin 則 stillReflective 操作為補倉操作,可有可無.
          @root_sellBuoyStage 'stopWin' # 'stopLoss'
          true
        else false

      # 情形二 (尚未完善,會導致太早平倉)
      #when formerx?.buyNexusBar? and formerx.endBar is fishx.formerEndBar then switch
      # 保險起見,不管之前有無 buyNexusBar 在跳空破位情形之下,一律給予止損機會
      when formerx? and (formerx.endBar is fishx.formerEndBar or fishx.startBar.indicatorDrop('bbbbax', formerx.endBar)) then switch
        when true then false # 此行可臨時屏蔽此邏輯分支,以待開發完善
        when @bar.indicatorDrop('close', @previousBar) then false

        when running and fishx.size < barsLeadFishShift and not formerx.stopped?
          # 標記為 stopWin / stopLoss. stopWin 則 stillReflective 操作為補倉操作,可有可無.
          @root_sellBuoyStage 'stopWin' # 'stopLoss'
          # 及時停止信號,以免頻繁發出反射信號,導致相反產品錯誤開倉
          formerx.stopped = true
          true

        when not running and fishx.size < barsLeadFishShift and not formerx.stopShown?
          # 標記為 stopWin / stopLoss. stopWin 則 stillReflective 操作為補倉操作,可有可無.
          @root_sellBuoyStage 'stopWin'
          # 及時停止信號,以免頻繁發出反射信號,導致相反產品錯誤開倉
          formerx.stopShown = true
          true

        else false
        
      # 除了上述兩種情形皆無須止損
      else false










  ###
    買入點捷徑: (20180526 16:24)
      昨晚發現賣出點捷徑,並定義成功,今天上午思考買入點有無類似捷徑.之前已知主要買入點可藉助 bbba / bband.bbyangfish 定義
      因週末 IB 無法連接,故採用 HSI 行情,初步確定,雖然沒有賣出點那麼簡潔,但亦可通過配合 yangfishx 簡單定義.
      組合條件要點為:
        1. bband.bbyangfish 已經成型 (.size > barsLeadFishShift)
        2. 有 yangfishx 起於其下,且價格已經反彈至其上,亦非前段 yangfishx 剛剛反彈失敗跌破導致
        3. 上述 yangfishx 起點之初若干 bars 內為買入點,必須附帶止盈止損賣出點,即 yangfishx 終點(亦即跌破點)
    圖示為 20180526 at 10:51:44 右側 console 有文字說明

    測試研究
      以上策略做出來後,不完美.有可能改用 @bband.bbbyangfishx 替換 yangfishx 會減少噪音點
      但由於此方案雖不完美但可用,故擬先保存下來,另開分支 sqplus 研究替換方案的可能性, 若可行再並入新分支 sp
   ###
  # (20180526 16:23) 買入點捷徑
  # 初步定義,尚不純淨
  buyNexusSimple: ->
    # 亦可在此法內使用:
    #@buyNexusSimple20180611()

    # 以下備考:
    #@buyNexusSimple_sp()
    #@buyNexusSimple_sq()
    #@buyNexusSimple_so()
    #@buyNexusSimple20180608()
  




  # 2x2t or 4x 新體系
  # (20180611) 買入點思路: 
  # 第一買入點和第二買入點: 皆根據 bbbbat; 視乎需要,可以分開或合併寫.
  # 其中在標記點之上的, 為第一買入點, stage 為 bottom, 開 call 平 put
  # 否則為第二買入點, 又分為兩種情形, 1. stage 為 stopWin, 僅限 put 平倉; 2. stage bottom for open call long position 
  # 第三買入點, 第一買入點之後, 即 stage 標記為 bottom 的點同期或之後的 yangfishx 起點, stage 為 bottom, 開 call 平 put
  # 第四買入點, 創新高過程中略有回調即買入, stage: continue
  # (20180627 17:50) 拆分成功
  buyNexusSimple20180611: ->        
    switch
      # 不再需要以下各法時, 亦可獨立使用
      when @buyInGgCycle() then true

      when @buyOnCycleRightSide() then true

      # 此法為新法
      when @buyOnBaxUXBbbBat() then true
      
      # 以下各項為舊法
      # 純陽
      #when @buyNexusSimple4a() then true      
      # 4b 非純陽之陽魚大箱體
      #when @buyNexusSimple4b() then true

      # 檢測確定有用, minute 行情屏蔽 2c 似乎更精純
      #when @buyNexusSimple2() then true

      # 備考
      # 以下兩則在 hour 週期條件下有些作用, minute 行情下機會不多,噪音跟信號都有,主要是觸線的低位可以找出來
      #when @_buyNexusSimple1_() then true
      # 依賴第一買入點作標記
      #when @_buyNexusSimple1_() or @_buyNexusSimple3_() then true  
      
      else false
   





  ###

    buyBottomInGgYinFfYang: sellTopInGgYangFfYin
    buyContinueInGgYinFfYang: sellContinueInGgYangFfYin
    buyContinueInGgYangFfYang: sellContinueInGgYinFfYin
    buyInGgYangFfYin: sellInGgYinFfYang
    buyInGgYinFfYin: sellInGgYangFfYang

  ###
  buyInGgCycle: ->
    switch
      #when @buyInGgYinCycle() then true
      when @buyInGgYangCycle() then true
      
      else false






  # (20180707 18:11) finished set up. 
  buyInGgYinCycle: ->
    switch
      # 先確定大環境
      when @ggCycle.isYang then false

      # put: stopWin
      # 暫時沿用原法
      when @buyInGgYinFfYin() then true

      #when @cce_buyBottomInGgYinFfYang() then true

      # call: bottom, put: stopWin
      when @buyBottomInGgYinFfYang() then true

      # put: stopWin, call: continue
      #when @buyContinueInGgYinFfYang() then true

      else false








  buyInGgYangCycle: ->
    switch
      # 先確定大環境
      when @ggCycle.isYin then false

      # put: stopWin
      when @cce_buyInGgYangFfYin() then true

      # put: stopWin
      #when @buyInGgYangFfYin() then true
      
      # call: continue
      #when @buyContinueInGgYangFfYang() then true

      else false










  # 注意: 在特定的標的,例如 SPY / QQQ 實質上整體行情的大環境是陽.只是截取的片段 ggCycle 呈現陰而已.需要牢記. 
  # 盤局,底部, 將轉換為put 止盈平倉, call 開倉
  # (20180706 21:51 初建)
  # (20180710 15:43 複查並清潔)
  buyBottomInGgYinFfYang: ->
    stageLabel = if @root_sec_callCycle() then 'bottom' else 'definite'

    switch
      when not @ffCycle.isYang then false

      # 先用原法
      #when @cce_buyBottomInGgYinFfYang()
      #  @root_buyBuoyStage(stageLabel,'cce_buyBottomInGgYinFfYang')
    
      #when true then false

      when not @xtCycle.rootingLowBelow('baf') then false
      when not @xtCycle.buyFromBottom('向上容忍價', [1, 0.5*barsLeadFishShift], 'baf') then false

      when not (@closeLowMid() or @closeLowDrop()) then false
      else 
        #@yangfisht.buyNexusBar = @bar
        @root_buyBuoyStage(stageLabel,'buyBottomInGgYinFfYang')
      



  # 簡單套用則不如原法,需要訂製
  cce_buyBottomInGgYinFfYang: ->
    @cce_buyCommon()





  buyBottomInGgYinFfYang_Origin: ->
    switch
      when not @ffCycle.isYang then false
      when not @xtCycle.rootingLowBelow('baf') then false
      
      # 濾除太高
      when @xtCycle.priceRoseTooMuchFromStart() then false
      # @ffCycle, 有其道理. ggCycle.isYin 則 ffCycle 若為陽,唯有 @yangfishf 與 @yangfish 陽魚重合階段階段才有可能
      when @ffCycle.priceRoseTooMuchFromTba() then false

      when not (@closeLowMid() or @closeLowDrop()) then false
      

      # 起於 baf 之下
      when not @xtCycle.rootingLowBelow('baf') then false
      when not @xtCycle.yangHead() then false
      else 
        stageLabel = if @root_sec_callCycle() then 'bottom' else 'definite'
        @root_buyBuoyStage(stageLabel,'buyBottomInGgYinFfYang')
        #@yangfisht.buyNexusBar = @bar
        true


  
  


  # 空中加油買入點,突破 @bar.taf 仍在 @yinfish 魚內未創新魚那段
  # 採用向上突破前 @yinfishf 之首為過濾條件
  # 需要防止演變為追高買入
  # (20180707 18:11) finished set up.
  # (20180710 16:21) 複查,代碼有些複雜,有些行似乎沒有發揮作用,並且漏掉盤升過程買入點,有空再仔細查. 
  buyContinueInGgYinFfYang: ->
    method = if @isMinute then '向上報價' else '向上極限價'
    stageLabel = switch
      when @root_sec_putCycle() then 'stopWin'
      when @bar.lowUponLine('ta') then 'continue'
      else 'definite'

    switch
      when not @ffCycle.isYang then false

      #when @cce_buyContinueInGgYinFfYang()
      #  @root_buyBuoyStage(stageLabel,'cce_buyContinueInGgYinFfYang')
      #when true then false

      # 除外適用 buyBottomInGgYinFfYang 者
      when @xtCycle.rootingLowBelow('baf') then false

      when not (@closeLowMid() or @closeLowDrop()) then false
      
      when not @buyFfYang(method,[1,null]) then false
      
      else 
        @root_buyBuoyStage(stageLabel,'buyContinueInGgYinFfYang')
        #@yangfisht.buyNexusBar = @bar
        true





  # 不適合用 cce 方式,因其未曾交叉故,但可應用 cce 過濾其中下跌過程噪音買入點
  cce_buyContinueInGgYinFfYang: ->
    @cce_buyCommon()






  # 與 buyFfYin 大同小異,系由彼法改寫而來
  buyFfYang: (method='向上容忍價',range=[1, null],aLineName) ->
    methodxt = if @isMinute is 'hour' then null else '略向上報價'

    switch
      when @ffCycle.buyFromBottom(method, range, aLineName) then true
      # 此處參數有變動,注意 range
      when @xtCycle.buyFromBottom(methodxt, [1, 0.5*barsLeadFishShift]) then true
      else false








  # (20180714 16:48) 先不分 cp 嘗試一下
  # [原始設計: 此類僅限於 close put,不可做多; 亦不必分解為底部及空中]
  # 很多交易點無必要出現,整體有待改進
  # 程序主體與 buyBottomInGgYinFfYang 一樣, 但是 stageLabel 不同
  # (20180707 18:11) finished set up. 
  # (20180711 15:26) clean
  buyInGgYinFfYin: ->
    stageLabel = 'definite'

    switch
      # 此類僅限於 close put,不可做多; 亦不必分解為底部及空中
      when @root_sec_callCycle() then false

      when not @ffCycle.isYin then false
      when @ffCycleYangfishGapped() then false

      # 此法暫時回答 false, 沿用原有方法(效果不佳時再改)
      when @cce_buyInGgYinFfYin()
        @root_buyBuoyStage(stageLabel,'buyInGgYinFfYin')

      when not (@closeLowMid() or @closeLowDrop()) then false
      

      when not @buyFfYin('向上報價') then false

      else 
        @root_buyBuoyStage(stageLabel,'buyInGgYinFfYin')





  ffCycleYangfishGapped: ->
    @ffCycle.cycleYangfish.gapped




  # 簡單沿用舊法
  # 有空才轉換成新法,即便不止盈也無大礙
  cce_buyInGgYinFfYin: ->
    false



  

  # (20180713 17:11 task: 補齊相對於新高隨即平倉的及時追進補倉能力,不用擔心買錯,後續有很多機會平倉)
  # (20180707 20:40 初建) 睏,過濾不很精,仍需再測試改進
  # 最初模仿 buyContinueInGgYinFfYang

  # 空中加油買入點,突破 @bar.ta 並創新高,而 yangfishf 未上跳那段, 場景與 sellInGgYangFfYang 一致,並為彼補倉
  # 採用向上突破前 @yinfishf 之首為過濾條件
  buyContinueInGgYangFfYang: ->
    stageLabel = if @root_sec_putCycle() then 'mirror' else 'continue'

    switch
      # 旨在不生成歧義 put 信號,一旦 @root_sec_putCycle 定義改變, 隱藏的信號又會自動展示,不用改寫定義
      #when @root_sec_putCycle() then false

      when not @ffCycle.isYang then false

      #when @cce_buyContinueInGgYangFfYang()
      #  @root_buyBuoyStage(stageLabel,'cce_buyContinueInGgYangFfYang')
      #when true then false

      # 未上台階不續開 (但須限定一定長度)
      when @xtCycle.yinfishStartedLower(this, barsLeadFishShift) then false

      when not (@closeLowMid() or @closeLowDrop()) then false      
    
      # 需要分成兩類情形過濾: 1. tax / bax 接近,採用通常方法 2. tax / bax 遠離, 採用追進方法
      when not (@normalBuyInGgYangFfYang() or @onFlyBuyInGgYangFfYang()) then false
      
      when @closeHighRise() then false
      
      else 
        @root_buyBuoyStage(stageLabel,'buyContinueInGgYangFfYang')
        @ffCycle.cycleYinfish.gapSoldBar = null
        #@yangfisht.buyNexusBar = @bar
        true





  cce_buyContinueInGgYangFfYang:->
    @cce_buyCommon()




  
  normalBuyInGgYangFfYang: ->
    @xtCycle.buyFromBottom('向上極限價',[1,5],null)

  
  
  
  
  onFlyBuyInGgYangFfYang: ->
    switch
      when @ffCycle.cycleYinfish.size is 0 then false

      # 任意符合其一則可以通過, 兼具離開地線太遠,及天地間距太大,則濾除
      when @xtCycle.priceRoseTooMuchFromTba('向上極限價') and (@bar.taf < @contractHelper.向上容忍價(@bar.baf)) then false

      # 濾除太早, @xtCycle 天地間距大時,由於下不著地,乾脆待反彈之後再買[除非今後找到更好的濾除條件]
      # 思路: 選最低點很難,買不到最低會被止損,影響後續操作,故乾脆等待回昇之後再買
      when @bar.higher('taf','tax') and (@bar.taf < @contractHelper.向上容忍價(@bar.baf)) then false
      
      else true






  # (20180711 21:27) 為補救個別買入點而設置,不如放棄
  buyLocatedContinueInGgYangFfYang: ->
    switch
      when @xtCycle.yangHead([1, barsLeadFishShift]) then true
      when @ggCycle.yinHead([1,3]) then switch
        when not @ffCycle.priceRoseTooMuchFromTba() then true
        # 非常複雜勉強且造成很多噪音,不如放棄此處的單個買入點,直至找到合適的方法
        #when @closeLowUnderPrice(@contractHelper.向上極限價(@bar.baf)) and @closeLowUnderPrice(@contractHelper.向上極限價(@ffCycle.startBar.baf)) then true
        else false
      else false







  # (20180714 16:36) 改進 @ffCycle.buyFromBottom 參數
  # 當前設計: 由於陽中之陰情形下不做 put 故亦無須平倉,但是由於美股多頭特性,可以做 call; 故用 mirror 反射(20180712 20:01)
  # [備考: 原始設計: 此類僅限於 put stopWin,不做 call 開倉; 亦不必分解為底部及空中]
  # (為簡化代碼不做,若據實則有部分可做,須設置過濾條件,天線不長為重點)
  # 程序主體與 buyBottomInGgYinFfYang 一樣, 但是 stageLabel 不同
  # 以下仿 buyInGgYinFfYin 
  # (20180707 21:09 初建) 睏,未細看,待審校
  # (20180712 21:04) 簡單編輯,待細看審校
  buyInGgYangFfYin: ->
    stageLabel = if @root_sec_callCycle() then 'definite' else 'mirror' #'stopWin'

    switch
      when not @ffCycle.isYin then false


      when not @buyFfYin() then false

      when not (@closeLowMid() or @closeLowDrop()) then false
      
      # 以下舊代碼,暫時先全部注釋看效果,再逐個檢驗.
      # 濾除太高
      #when not (@xtCycle.yangHead([4, 0.5*barsLeadFishShift]) or @ffCycle.yangHead([2,5])) then false
      
      else 
        @root_buyBuoyStage(stageLabel,'buyInGgYangFfYin')
        #@yangfisht.buyNexusBar = @bar
        true





  buyFfYin: (method='向上報價',range=[1, null],aLineName) ->
    methodxt = if @timescale is 'hour' then '向上容忍價' else null

    switch
      when @ffCycle.buyFromBottom(method, range, aLineName) then true
      # 先使用默認參數試試看
      when @xtCycle.buyFromBottom(methodxt) then true
      else false






  # 不可以用 Xt, 因無法區分跌落圈外的非所轄範圍(餘處凡使用 Xt 者均需小心)

  # put: stopWin; 
  # call: [ VERY DANGEROUS !!! ] 謹防突然暴跌
  # (20180719 18:26 頗為完善)
  cce_buyInGgYangFfYin: ->
    stageLabel = if @root_sec_putCycle() then 'stopWin' else 'uncertain'

    switch
      when not @ffCycle.isYin then false

      # 1. call / put 兩類,但 call 將標記為 uncertain or mirror
      when @cceBgbgFf.buyPoint(3,'略向上報價')
        @root_buyBuoyStage(stageLabel, 'cceBgbgFf.buyPoint')

      # 初反彈許可從地線而起,不及 bgbgCycle. 長盤之後, buyBarCross 地線就不可取了, 用更外層的 cceBgbgFf 來決定
      when @ffCycle.cycleYangfish.size < 2*barsLeadFishShift and @cceGgFf.buyPoint(13,'向上容忍價')
        @root_buyBuoyStage(stageLabel, 'cceGgFf.buyPoint')

      # 不可以用 Xt, 因無法區分跌落圈外的非所轄範圍(餘處凡使用 Xt 者均需小心)
      #when @cceGgXt.buyPoint() #when @cceBgbgXt.buyPoint()

      # 2. 以下專門針對 put 平倉 stopWin
      when not @root_sec_putCycle() then false 
      # 過濾非甩出地線情形,使用默認參數,向上容忍價; 若設置太大,則需要甩開很遠,會丟失未甩遠的機會
      when not @cceBgbgFf.innerYangDropOut('向上容忍價') then false
      
      # 甩出圈外的情形
      when @cceFfXt.buyPoint(3,'向上極限價')
        @root_buyBuoyStage(stageLabel, 'cceGgFf.buyPoint')

      else false





  ###
  # 這段似僅一現於後起陰魚之前段, @yangfishf 尚未躍上的時段;
  # 若盤整長度未達標即再度上行,則仍屬於中繼形態,buyContinueInGgYangFfYang
  # 若達標則演化為陽中之陰 ggYangFfYin, 有 buyInGgYangFfYin
  # 故此法是介於以上兩法之間,可能是多餘的,僅需定義好 buyContinueInGgYangFfYang 所適用的 @yinfish.size 令其等同 @yangfishf 尚未躍上時限即可
  # 盤局,底部,  call 開倉,將轉換為put 止盈平倉
  # 仿 buyBottomInGgYinFfYang
  # (20180707 21:13 初建)
  _buyBottomInGgYangFfYang_: ->
    switch
      when not @ffCycle.isYang then false
      when not @xtCycle.rootingLowBelow('baf') then false
      
      # 濾除太高
      when @xtCycle.priceRoseTooMuchFromStart() then false
      # @ffCycle
      when @ffCycle.priceRoseTooMuchFromTba() then false

      # @yangfisht 在大陽循環內跟 @yangfishx 不一直一樣, 且有部分不重疊
      when @yangfisht.startBar.higher('bat','baf') then false
      when @yangfisht.size < 1 then false
      when @yangfisht.size > 0.5*barsLeadFishShift then false
      else 
        stageLabel = if @root_sec_callCycle() then 'bottom' else 'stopWin'
        @root_buyBuoyStage(stageLabel,'_buyBottomInGgYangFfYang_')
        #@yangfisht.buyNexusBar = @bar
        true

  ###
  





  
  
  buyOnCycleRightSide: ->
    {bxbtCycle} = @bband

    switch
      when not (@closeLowMid() or @closeLowDrop()) then false
      # 避免出現實為 put 平倉信號的指示,防止早買
      when not @root_sec_callCycle() then false
      # 此處不用 yangYang(2), 天線長不買故
      when not @xtCycle.yangYang() then false
      
      # 從天而降不買
      when @xtCycle.isYang and @xtCycle.cycleYinfish.startBar.highUponLine('bbbtax') then false
      when @xtCycle.cycleYinfish.startBar.highUponLine('bbbtax') then false
      #when @xtCycle.isYang and @xtCycle.cycleYinfish.startBar.highUponLine('bbbtax') then false
      
      # 要麼天線無長度持續創新高,要麼在天線下方持續反彈,過天線則不買
      when @bar.higher('tax','ta') and (@closeHighRise() or bxbtCycle.cycleYinfish.size > 0) then false
      when bxbtCycle.cycleYinfish.size > 0 and not (@xtCycle.cycleYinfish.size < 5 and @yangfishx.size < 2*barsLeadFishShift) then false
      #when not (@xtCycle.cycleYinfish.size is 0 or bxbtCycle.cycleYinfish.size is 0) then false
      else
        @root_buyBuoyStage('definite','buyOnCycleRightSide')
        #@yangfisht.buyNexusBar = @bar
        true






  # bax 上穿 bbbbat 構成後續的買入點
  # (20180622 建立)
  # (20180622 22:41) 定義測試成功
  # (20180625 20:57) 推敲; 尚有瑕疵,初步可用
  buyOnBaxUXBbbBat: (callback) ->
    @recordBaxUXBbbBatBar()
    {bbbyangfisht, bbbyinfishx} = @bband
    {baxCrossBbbBatBar, baxDXBbbBatBar, baxUXBbbBatBar} = @yinfish
    batSeparateBarExists = @recordBatSeparateBar()?

    k = if /minute/i.test(@timescale) then 0.5 else 2
    switch
      when not (@closeLowMid() or @closeLowDrop()) then false
      
      # 適用於嚴格篩選 call 買入點, 不含 put 止盈平倉點
      when @slipAfterBatSeparateBar() then false

      # 指定陽魚內,逢低買入,不追高.
      # 此陽魚目前指定 @yangfisht; 未必至善,可觀察改進.
      when @yangfisht.buyNexusBar? and @bar.indicatorRise('high', @yangfisht.buyNexusBar) then false
      
      # 未切割不買,切割點為下切更不買
      when not baxCrossBbbBatBar? then false
      when baxCrossBbbBatBar is baxDXBbbBatBar then false

      # @yinfishx.size is 0 創新高,此時亦不可
      when @yinfishx.size is 0 then false
      # 正在創新低,亦不可
      when @yangfishx.size is 0 then false
      when @yangfisht.size is 0 then false
      
      # 穿越已久; 不必限制. 若限制則無追加買入點; 可在分類中顯現
      #when @barsAfter(baxUXBbbBatBar) > barsLeadFishShift*k then false
      
      # 雖然向上穿越,但是待穿越時, @yangfishx.size 已經太大, 
      #when @yangfishx.size > barsLeadFishShift*k then false
    
      # 若非切入段,且起點更低,則不可
      when (not @yangfisht.startBar.higher('bbbbat','bat')) and \
      @startBelowFormer(@yangfisht, 'yangfishtArray', 'bat') and \
      (not @bar.indicatorRise('high', @formerObject('yangfishtArray')?.cornerBar)) then false

      # 熊市,須反彈上行過程中才可以 call 開倉,否則為 put 平倉
      when @yinfish.size > 5*barsLeadFishShift and bbbyangfisht.size < barsLeadFishShift then false 
      #  @root_buyBuoyStage 'stopWin'
      #  @yangfisht.buyNexusBar = @bar
      #  true

      else 
        #stageLabel = if @barsAfter(baxUXBbbBatBar) > barsLeadFishShift*k then 'continue' else 'bottom'
        stageLabel = if @slipAfterBatSeparateBar() then 'stopWin' else 'bottom'
        if @rightStageToBuy(stageLabel)
          @root_buyBuoyStage(stageLabel, 'buyOnBaxUXBbbBat')
          @yangfisht.buyNexusBar = @bar
          true
        else
          false




  # 此為補救措施,最好在生成信號時,增強過濾條件
  rightStageToBuy: (stageLabel)->
    # 已測試,無bug. 先屏蔽, 若欲使用,則去掉 if 前的 #
    return true #if stageLabel isnt 'stopWin'
    
    minutes = 10
    n = 4

    switch
      when @contractHelper.closingIn(minutes) then true
      when @bar.close < @sellBuoy.grade[n] then true
      else false





  # 分歧破位後下滑過程
  # (20180701 16:20) 初建 
  slipAfterBatSeparateBar: ->
    batSeparateBarExists = @recordBatSeparateBar()?
    # 此法在下跌過程中,與 bbbyangfishx 等同 
    {bbbyangfisht} = @bband

    switch
      when not batSeparateBarExists then false

      # 此法在下跌過程中,與 bbbyangfishx 等同. 長度短則為小漣漪(?) 且起頭低於前身, 則判斷多為下滑
      when bbbyangfisht.size < barsLeadFishShift and not @bbbyangfishtUponFormerHead() then true
      
      # 限制其長度原因是取其持續向上突破
      when @yinfishx.size < barsLeadFishShift and @yinfishxUponFormerHead() then false

      else true






  # record down and up crossing of bbbbat by bax
  # 向上穿越實為向內切入, bax 不一定高於前 bar. 向下穿越則名副其實.
  # (20180622 22:00 建立)
  recordBaxUXBbbBatBar: ->
    switch 
      # 注意使用 bax 而不是 bat; 在下跌行情中, bax bat 是重合的.
      when @bar.higher('bax', 'bbbbat') and not @previousBar?.higher('bax', 'bbbbat') 
        @yinfish.baxUXBbbBatBar = @bar
        @yinfish.baxCrossBbbBatBar = @bar
      when @bar.higher('bbbbat', 'bax') and not @previousBar?.higher('bbbbat', 'bax')
        @yinfish.baxDXBbbBatBar = @bar
        @yinfish.baxCrossBbbBatBar = @bar






  # 現價以及魚頭皆高於之前的頭
  bbbyangfishtUponFormerHead: ->
    {bbbyangfisht} = @bband
    headValue = bbbyangfisht.startBar.bbbbat
    formerValue = switch
      when @yangfish.bbbyangfishtHead? and @yinfish.bbbyangfishtHead?
        Math.max(@yangfish.bbbyangfishtHead.bbbbat, @yinfish.bbbyangfishtHead.bbbbat)
      when @yangfish.bbbyangfishtHead?
        @yangfish.bbbyangfishtHead.bbbbat
      when @yinfish.bbbyangfishtHead?
        @yinfish.bbbyangfishtHead.bbbbat

    (@bar.bbbbat > headValue) and (headValue > formerValue) and @yangfishx.startBar.bbbbat > formerValue






  yinfishxUponFormerHead: ->
    # 暫時使用已有設置
    {yinxHeadBar} = @yinfish
    {startBar} = @yinfishx
    
    switch
      when not yinxHeadBar? then false
      when startBar is yinxHeadBar then false
      else startBar.indicatorRise('high', yinxHeadBar)





  # 用於屏蔽掉陰魚內開盤跳空向上貼近天線 tax
  # (20180613 20:11) 從 buyNexusSimple20180611 獨立成function
  jumpTop: ->
    @bar.higher('mata', 'tax') and @bar.higher('bbatax', 'tax') and \
    @contractHelper.略向上報價(@bar.high) > @bar.tax and \
    # 下行嘗試過不可以
    #@yinfishx.startBar.open > @contractHelper.向上容忍價(@yinfishx.formerEndBar?.high) and \
    @yinfishx.size < barsLeadFishShift and @mayinfish.size > barsLeadFishShift




  # (20180626 23:06) 獨立,一物一用
  # buy 4a 純陽 
  buyNexusSimple4a: ->
    {bbayinfishx, bbbyangfish, bbbyangfisht, bbbyangfishx, bbbyinfish, bbbyinfishx} = @bband
    @yangfisht.flyTimes ?= 0
    
    # 中繼補倉限制回調天數
    nyf = 5
    n = 2
    
    switch
      when not (@closeLowMid() or @closeLowDrop()) then false

      # 試圖屏蔽掉陰魚內開盤跳空向上貼近天線 tax
      #when @jumpTop() or @yangfishx.bearJumpBar? then false
      # 太過,可能導致無法及時平倉止盈
      #when @jumpTop() or @yangfishx.bearJumpBar? or bbbyangfishx.bearJumpBar? then false

      # (20180612 20:59 建立)
      # 第四買入點, 創新高過程中略有回調即買入, stage: continue
      # bbbyinfish.size bbayinfishx.size, mayinfish.size ~~皆為0~~(實際情形複雜,其一為0即可 20180615 16:21補記)
      # 此即 sellNexusSimpleStop20180609 所欲解決的問題,可惜我忘記了,如此則將兩處代碼融合唯一,置於此處

      # (20180613 16:47), 分為兩類,4a. 純陽 4b. 盤局大箱體
      
      # 4a 純陽 
      # 沒有寫 bbayinfish.size is 0 是因為沒有做該魚(暫時用不著),若將來有該魚,即應改用
      # (最新改動: 20180615 16:23)
      when @yinfish.size in [1..nyf] and (@mayinfish.size is 0 or bbayinfishx.size is 0 or bbbyinfish.size is 0) then switch
        when @yangfisht.flyTimes > 3 then false  # > 5
        when @yangfishx.bbayinfishxBrokenBar? then false
        when bbbyangfisht.bbayinfishxBrokenBar? then false
        
        # 不可以,部分需要陽線收高也在盤中低點買入(20180615 16:25)
        #when @bar.indicatorRise('close', @previousBar) then false
        
        # 以下取自 sellNexusSimpleStop20180609
        # 避免頭部補倉,買到高位
        # 用 grade 避免高位盤整時天價補倉. 無須增加 and @yinfish.size > x, 結果無差異
        #when @bar.close > @buyBuoy.grade[6] then false
        #when not @startUponFormer(@yinfishx,'yinfishxArray', 'tax') then false

        when @yinfish.size in [0..3]  #[0..1]
          if @rightStageToBuy('continue')
            @root_buyBuoyStage('continue','buyNexusSimple4a')
            @yangfisht.flyTimes++
            true
          else
            false

        else false







  # (20180626 23:13) 獨立.
  buyNexusSimple4b: ->
    {bbayinfishx, bbbyangfish, bbbyangfisht, bbbyangfishx, bbbyinfish, bbbyinfishx} = @bband
    @yangfisht.flyTimes ?= 0
    
    # 中繼補倉限制回調天數
    nyf = 5
    n = 2
    
    switch
      when not (@closeLowMid() or @closeLowDrop()) then false

      # 試圖屏蔽掉陰魚內開盤跳空向上貼近天線 tax
      #when @jumpTop() or @yangfishx.bearJumpBar? then false
      # 太過,可能導致無法及時平倉止盈
      #when @jumpTop() or @yangfishx.bearJumpBar? or bbbyangfishx.bearJumpBar? then false

      # (20180612 20:59 建立)
      # 第四買入點, 創新高過程中略有回調即買入, stage: continue
      # bbbyinfish.size bbayinfishx.size, mayinfish.size ~~皆為0~~(實際情形複雜,其一為0即可 20180615 16:21補記)
      # 此即 sellNexusSimpleStop20180609 所欲解決的問題,可惜我忘記了,如此則將兩處代碼融合唯一,置於此處

      # (20180613 16:47), 分為兩類,4a. 純陽 4b. 盤局大箱體
      
      # 4a 純陽 
      # 沒有寫 bbayinfish.size is 0 是因為沒有做該魚(暫時用不著),若將來有該魚,即應改用
      # (最新改動: 20180615 16:23)
      when @yinfish.size in [1..nyf] and (@mayinfish.size is 0 or bbayinfishx.size is 0 or bbbyinfish.size is 0) then false
   
      when @bar.closeUponLine(@bigOne('bbbtax', 'bbatax')) then false

      # 4b 非純陽之陽魚大箱體
      when @closeLowDrop() and @yinfish.size > nyf and @yinfishx.size in [0..nyf] and @bar.higher('bat','mata') and bbbyinfishx.size is 0 and bbayinfishx.size is 0 then switch
        when @yangfisht.flyTimes > 3 then false
        when @bar.indicatorRise('close', @previousBar) then false

        # 試圖排除陰魚 top 買入
        # (20180613 16:32)
        when @yinfish.size > barsLeadFishShift and @bar.highUponLine('bbatax') and not @bar.higher('bat','ta') then false
        when @closeHighUpon('mata') and not @bar.higher('bat','mata') then false
        
        # 以下取自 sellNexusSimpleStop20180609
        # 首先確認上昇過程
        #when not (@yinfishx.size in [1..3]) then false  # not 後面必須加括號
        when not @startUponFormer(@yinfishx,'yinfishxArray', 'tax') then false
        when @bband.startBelowFormer(bbbyinfishx, 'bbbyinfishxArray', 'bbbtax') then false
        when @mainfishYin() then false
        when not (@bbbyangxCycleX() or @yangxCycleX()) then false

        # 創歷史新高過程中小憩
        when not @bar.lowBelowLine('bbbtax') then false
        when @bar.closeBelowLine('bbatax') then false  
        # 會買到轉點附近,故不可用此法: #when not @bar.closeBelowLine('bbatax') then false  

        # 避免頭部補倉,買到高位
        # 用 grade 避免高位盤整時天價補倉. 無須增加 and @yinfish.size > x, 結果無差異
        when @bar.close > @buyBuoy.grade[6] then false
        # 僅限補倉一次,避免越補越高
        #when @yangfisht.sellStopBar? then false
        #when bbbyinfishx.sellStopBar? then false      
        # 若無以上過濾條件,則會買到高位

        when @yinfishx.size in [0..3] #[0..1]
          if @rightStageToBuy('continue')
            @root_buyBuoyStage('continue','buyNexusSimple4b')
            @yangfisht.flyTimes++
            true
          else 
            false
        else false
      else false





  _buyNexusSimple1_: ->
    {bbayinfishx, bbbyangfish, bbbyangfisht, bbbyangfishx, bbbyinfish, bbbyinfishx} = @bband
    
    # 中繼補倉限制回調天數
    nyf = 5
    n = 2
    
    switch
      when not (@closeLowMid() or @closeLowDrop()) then false

      # 試圖屏蔽掉陰魚內開盤跳空向上貼近天線 tax
      #when @jumpTop() or @yangfishx.bearJumpBar? then false
      # 太過,可能導致無法及時平倉止盈
      #when @jumpTop() or @yangfishx.bearJumpBar? or bbbyangfishx.bearJumpBar? then false

      # (20180612 20:59 建立)
      # 第四買入點, 創新高過程中略有回調即買入, stage: continue
      # bbbyinfish.size bbayinfishx.size, mayinfish.size ~~皆為0~~(實際情形複雜,其一為0即可 20180615 16:21補記)
      # 此即 sellNexusSimpleStop20180609 所欲解決的問題,可惜我忘記了,如此則將兩處代碼融合唯一,置於此處

      # (20180613 16:47), 分為兩類,4a. 純陽 4b. 盤局大箱體
      
      # 4a 純陽 
      # 沒有寫 bbayinfish.size is 0 是因為沒有做該魚(暫時用不著),若將來有該魚,即應改用
      # (最新改動: 20180615 16:23)
      when @yinfish.size in [1..nyf] and (@mayinfish.size is 0 or bbayinfishx.size is 0 or bbbyinfish.size is 0) then false
   
      when @bar.closeUponLine(@bigOne('bbbtax', 'bbatax')) then false

      # 4b 非純陽之陽魚大箱體
      when @closeLowDrop() and @yinfish.size > nyf and @yinfishx.size in [0..nyf] and @bar.higher('bat','mata') and bbbyinfishx.size is 0 and bbayinfishx.size is 0 then false

      #由於中繼買入點已經定義,故以下無須顧忌,可直接排除各類攀高買入
      when @yangfisht.buyNexusBar? then false
      # (20180613 16:32) 
      when @yinfish.size > nyf and @bar.highUponLine('bbatax') then false

      # 第一買入點, 第二買入點
      # 第一買入點和第二買入點: 皆根據 bbbbat; 視乎需要,可以分開或合併寫.
      # 其中在標記點之上的, 為第一買入點, stage 為 stopWin, 平 put, 否則為第二買入點.
      when bbbyangfisht.size in [1..barsLeadFishShift*2] then switch
        when @bar.highUponLine('bbatax') then false
        # (20180613 21:37) 試圖排除高位盤局時的假買入點
        when @yinfish.size < barsLeadFishShift*3 and @yangfishx.bbayinfishxBrokenBar? then false
        #when @yangfishx.bbayinfishxBrokenBar? then false

        # 第一買入點
        # 在標記點之上, 
        #   平 put (沒問題) 
        #   開 call (最初設計意圖,但有難度)
        # (20180614 18:06) 改
        #when bbbyangfisht.size in [1..5] and @bbbyangfishtUponFormerHead() then switch
        # (20180616 18:56)
        when bbbyangfisht.size in [1..5] and @bbbyangfishtUponFormerHead() and not bbbyangfisht.typeOneBuy? then switch
          # 邏輯不對,本來就是在下跌過程中買 put 而對 put 作止盈交易,怎麼可以限制為多頭市場
          # (原注) 增加此項過濾純陰,防止連續下跌時連續出現買入點,或有更好方法可以解決
          #when @bbbyinxCycleX() or @yinxCycleX() then false

          # (20180615 23:16) 
          when (@bar.high >= @bar.tax) and not @bbbyinxCycleX() then false

          else 
            # 根據定義的 bbbyangfisht.size in [1..5] stage 不確定是 bottom
            @root_buyBuoyStage(if @bbbyinxCycleX() or @yinxCycleX() then 'stopWin' else 'bottom')
            @yangfisht.buyNexusBar = @bar
            bbbyangfisht.typeOneBuy = @bar
            true

        else false





  # (20180627 11:37) 獨立
  # 原第二買入點
  # 2a 不僅用於 put 平倉止盈, 更可用於 call 開倉
  # 2b 僅用於 put 平倉止盈
  # 2c. 第二買入點 補充情形 新低, put 止盈平倉
  buyNexusSimple2: ->
    {bbayinfishx, bbbyangfish, bbbyangfisht, bbbyangfishx, bbbyinfish, bbbyinfishx} = @bband
    
    # 中繼補倉限制回調天數
    nyf = 5
    n = 2
    block2a = false
    block2b = false
    block2c = true # minute 行情,似乎無此更精純

    switch
      when not (@closeLowMid() or @closeLowDrop()) then false

      # 試圖屏蔽掉陰魚內開盤跳空向上貼近天線 tax
      #when @jumpTop() or @yangfishx.bearJumpBar? then false
      # 太過,可能導致無法及時平倉止盈
      #when @jumpTop() or @yangfishx.bearJumpBar? or bbbyangfishx.bearJumpBar? then false

      # 第四買入點, 創新高過程中略有回調即買入, stage: continue
      when @yinfish.size in [1..nyf] and (@mayinfish.size is 0 or bbayinfishx.size is 0 or bbbyinfish.size is 0) then false   
      when @bar.closeUponLine(@bigOne('bbbtax', 'bbatax')) then false
      when @closeLowDrop() and @yinfish.size > nyf and @yinfishx.size in [0..nyf] and @bar.higher('bat','mata') and bbbyinfishx.size is 0 and bbayinfishx.size is 0 then false

      #由於中繼買入點已經定義,故以下無須顧忌,可直接排除各類攀高買入
      when @yangfisht.buyNexusBar? then false
      when @yinfish.size > nyf and @bar.highUponLine('bbatax') then false

      # 第一買入點, 第二買入點
      when bbbyangfisht.size in [1..barsLeadFishShift*2] then switch
        when @bar.highUponLine('bbatax') then false
        # (20180613 21:37) 試圖排除高位盤局時的假買入點
        when @yinfish.size < barsLeadFishShift*3 and @yangfishx.bbayinfishxBrokenBar? then false
        #when @yangfishx.bbayinfishxBrokenBar? then false

        # 第一買入點
        when bbbyangfisht.size in [1..5] and @bbbyangfishtUponFormerHead() and not bbbyangfisht.typeOneBuy? then false
          
        # 第二買入點 反彈確認
        # 第二買入點, 又分為兩種情形: 
        #   1. stage 為 stopWin, 僅限 put 平倉; 2. stage bottom for open call long position 
        # 不在標記點之上.分為兩類. 代碼順序與實際順序(先後順序)相反.
        # 按先後順序,首先出現止盈點(2.2),即漲過之前的 startBar 之後更出現(2.1) @yinfishx 新高
        # 2a 不僅用於 put 平倉止盈, 更可用於 call 開倉

        # 原始設計
        #when @bar.close > @bband.formerObject('bbbyangfishtArray',barsLeadFishShift)?.startBar.close then switch
        # 曾經嘗試並被否定:
        # (20180616 17:35) 嘗試縮短要求的長度, 經測試,會增加噪音
        # (20180616 17:35) 嘗試更換為 @yangfisht, 不合適
        # (20180616 17:35) 嘗試更換為 @yangfishx, 長度限制減半,略多出幾點,但似不如原始設計精煉
        
        # (20180618 17:32) 思路正確
        when @bar.close > @formerObject('yangfishtArray', 0.5*barsLeadFishShift)?.startBar.close and \
        not bbbyangfish.bbbyangfishtBrokenBar? then switch  
        
          #when @yangfisht.startBefore(@yinfishx) and @yinfishx.size < 6 then switch
          # (20180616 17:49) 不過濾反而將錯就錯有一些低位買點出現,故不用
          #when @yangfisht.startBefore(@yinfishx) and @startUponFormer(@yinfishx, 'yinfishxArray', 'tax') then switch
          when @yangfisht.startBefore(@yinfishx) then switch
          
            # 測試開關
            when block2a then false
          
            else 
              @root_buyBuoyStage('bottom','buyNexusSimple2a')
              @yangfisht.buyNexusBar = @bar
              true
          
          # 2b 僅用於 put 平倉止盈
          #when @bbbyinxCycleX() then false
          # (舊注釋) 用 else 以便包含尚無 @bbbyangfishtHead 之首度回調情形 
          
          # 測試開關
          when block2b then false

          # (20180618 17:53) 
          when @yangfisht.size > 5 then false
          else
            @root_buyBuoyStage('stopWin','buyNexusSimple2b')
            # 此處不可標記,否則 2.1 無法產生
            #@yangfisht.buyNexusBar = @bar
            true
        else false

      # 2c. 第二買入點 補充情形 新低, put 止盈平倉
      # 僅用於 put 止盈平倉,故可行

      #when bbbyangfisht.size in [0..1] then switch
      # (20180614 17:55) 改為排除純陰情形,以免持續下跌時買入; 
      # 然而邏輯不通,因本欲 put 止盈,應以陰魚為體故,
      # 有空時嘗試改用 rsi/closeVari 過濾
      
      # (20180618 15:30)
      when bbbyangfish.size is 0 then switch

        # 測試開關
        when block2c then false

        when @bar.highUponLine('bbatax') then false
        when bbbyangfisht.startBar.bbbbat > @yinfish.bbbyangfishtHead?.bbbbat then false
        when bbbyangfisht.startBar.bbbbat > @yangfish.bbbyangfishtHead?.bbbbat then false
        when not @yangfisht.startBar.lowBelowLine('bbbbat') then false
        when @yangfish.size in [1..barsLeadFishShift]
          if @rightStageToBuy('stopWin')
            @root_buyBuoyStage('stopWin','buyNexusSimple2c')
            @yangfisht.buyNexusBar = @bar
            true
          else 
            false
        else false
      else false





  # (20180627 11:37) 獨立
  _buyNexusSimple3_: ->
    {bbayinfishx, bbbyangfish, bbbyangfisht, bbbyangfishx, bbbyinfish, bbbyinfishx} = @bband
    
    # 中繼補倉限制回調天數
    nyf = 5
    n = 2
  
    switch
      when not (@closeLowMid() or @closeLowDrop()) then false

      # 試圖屏蔽掉陰魚內開盤跳空向上貼近天線 tax
      #when @jumpTop() or @yangfishx.bearJumpBar? then false
      # 太過,可能導致無法及時平倉止盈
      #when @jumpTop() or @yangfishx.bearJumpBar? or bbbyangfishx.bearJumpBar? then false

      # (20180612 20:59 建立)
      # 第四買入點, 創新高過程中略有回調即買入, stage: continue
      # bbbyinfish.size bbayinfishx.size, mayinfish.size ~~皆為0~~(實際情形複雜,其一為0即可 20180615 16:21補記)
      # 此即 sellNexusSimpleStop20180609 所欲解決的問題,可惜我忘記了,如此則將兩處代碼融合唯一,置於此處

      # (20180613 16:47), 分為兩類,4a. 純陽 4b. 盤局大箱體
      
      # 4a 純陽 
      # 沒有寫 bbayinfish.size is 0 是因為沒有做該魚(暫時用不著),若將來有該魚,即應改用
      # (最新改動: 20180615 16:23)
      when @yinfish.size in [1..nyf] and (@mayinfish.size is 0 or bbayinfishx.size is 0 or bbbyinfish.size is 0) then false
   
      when @bar.closeUponLine(@bigOne('bbbtax', 'bbatax')) then false

      # 4b 非純陽之陽魚大箱體
      when @closeLowDrop() and @yinfish.size > nyf and @yinfishx.size in [0..nyf] and @bar.higher('bat','mata') and bbbyinfishx.size is 0 and bbayinfishx.size is 0 then false

      #由於中繼買入點已經定義,故以下無須顧忌,可直接排除各類攀高買入
      when @yangfisht.buyNexusBar? then false
      # (20180613 16:32) 
      when @yinfish.size > nyf and @bar.highUponLine('bbatax') then false

      # 第一買入點, 第二買入點
      when bbbyangfisht.size in [1..barsLeadFishShift*2] then false
      # 2c. 第二買入點 補充情形 新低, put 止盈平倉
      when bbbyangfish.size is 0 then false

      # 第三買入點
      # 第三買入點, 第一買入點之後, 即 stage 標記為 bottom 的點同期或之後的 yangfishx 起點, stage 為 bottom, 開 call 平 put
      # 注意此處 size 和第一買入點須互補? 目前不完全互補,故有一些買入點會漏掉
      when bbbyangfisht.typeOneBuy? and bbbyangfisht.size > barsLeadFishShift then switch        
        when @bar.highUponLine('bbatax') and not @yangfisht.startBar.highUponLine('bbatax') then false
        when @yangfisht.startBefore(bbbyangfisht) then false
        
        # (20180612 17:30) 意圖過濾非順勢買入點
        when @mayinfish.size > barsLeadFishShift and @yangfisht.startBar.lowBelowLine('mata') and bbbyinfishx.size < barsLeadFishShift then false
        when @mayinfish.size > barsLeadFishShift and @yangfisht.startBar.lowBelowLine('mata') and bbayinfishx.size < barsLeadFishShift then false
        
        # (20180616 21:47) 有效. 買點少
        when @root_sec_putCycle() and @yangfisht.startBar.lowUponLine('bbbbat') then false
        # 以下兩種過濾方法,皆有一點效果.但也都不圓滿,待以後完善
        #when @formerObject('yangfishtArray',2).size < 5 then false
        #when @yangfisht.startBar.bat < @formerObject('yangfishtArray',3).startBar.bat then false
        # 用否定式,不用肯定式,以便包含首次先前無記錄情形
        when @yangfisht.startBar.bat < bbbyangfisht.yangfishtHead?.bat then false
        when @yangfisht.size in [1..5]
          @root_buyBuoyStage 'bottom'
          @yangfisht.buyNexusBar = @bar
          true
        else false
      else false






  # 2x2t or 4x 新體系
  buyNexusSimple20180608: ->
    {bbbyangfisht} = @bband
    switch
      when @bar.highUponLine('bbatax') then false

      # 低位較穩買入
      when bbbyangfisht.size > barsLeadFishShift then switch
        # 低位較穩買入
        when @yangfisht.size in [1..2] and @yangfisht.startBar.lowBelowLine('bbbbat')
          @root_buyBuoyStage 'bottom'        
          @yangfisht.buyNexusBar = @bar 
          true
        
        # 上漲追加買入
        # (20180610 23:10) 須解決買入點高,貼在天線類上面的情況
        when not (@bbbyangxCycleX() or @yangxCycleX()) then false
        when @mainfishYang() and @yangfisht.size > 0 and @barIsCurrent(@yangxt.revertBar)
          @root_buyBuoyStage 'continue'        
          @yangfisht.buyNexusBar = @bar 
          true

        when off and @bbbyangxCycleX() and @yangfisht.size in [1..2]
          @root_buyBuoyStage 'continue'        
          @yangfisht.buyNexusBar = @bar 
          true
        
        else false

      # 低位買入變種
      # 若需要新低不久即買入,可在以下條件基礎上再過濾
      when off and barsLeadFishShift > bbbyangfisht.size > 3 and @yangfisht.size in [2..5] and @yangfisht.startBar.lowBelowLine('bbbbat')
        @root_buyBuoyStage 'bottom'        
        @yangfisht.buyNexusBar = @bar 
        true

      else false






  mainfishYang: ->
    @yangfish.mainfish?.isYangfish() or @yinfish.mainfish?.isYangfish()






  buyNexusSimple_so: ->
    n = 3
    switch
      # 開倉與止盈止損共用條件
      when @bband.bbbyangfisht.size < barsLeadFishShift then false
      when @yinfishx.size is 0 then false
      when @yangfish.size is 0 then false
      when @yangfishx.size is 0 then false

      # 比較 bbba, bbbba, 取其高者, 必須起於其下,且居於其下,方可
      when @bar.higher('bbbba','bbba') and (@yangfishx.startBar.lowUponLine('bbbba') or @bar.lowUponLine('bbbba')) then false
      when @bar.higher('bbba','bbbba') and (@yangfishx.startBar.lowUponLine('bbba') or @bar.lowUponLine('bbba')) then false

      # 限制 @yangfishx 尺寸以及買入點出現位置

      # 此項 @yangfishx 尺寸不限制則出現假買點,若簡單限制則部分買點不出現
      # [臨時,待完善] 然而以人工設定的長度作為限制,不理想.待尋找更好辦法.
      when @bband.bbyangfish.size > barsLeadFishShift*10 and not (barsLeadFishShift*2 > @yangfishx.size > n) then false
      # 欲替代上行過濾條件,但實際不能,加上亦無妨
      when @bband.bbbyangfish.size is 0 then false 

      when @timescale is 'hour' and @bar.closeUponLine('bbba') and @bar.closeUponLine('bbbba') then false

      # 買入點共用濾除條件
      when @bar.low > @previousBar.close then false
      when @isCurrentData() and @bar.indicatorRise('close', @previousBar) then false
      
      # 全部忽略 bbbbat 跌落 bbba 以下的常規買入點,若空頭欲止盈,在止盈 function 中定義
      when @bar.higher('bbba','bbbbat') then false

      else 
        switch
          when @bar.higher('bbba','bbbbat')
            @root_buyBuoyStage 'stopWin'
          
          else
            @root_buyBuoyStage 'bottom'
        
        @yangfisht.buyNexusBar = @bar 
        #@bband.bbbyangfishx.buyNexusBar = @bar
        true




  buyNexusSimple_sq: ->
    n = 3
    switch
      # 開倉與止盈止損共用條件
      when @bband.bbyangfish.size < barsLeadFishShift then false
      when @yangfishx.startBar.lowUponLine('bbba') then false
      #when @bband.bbbyangfishx.startBar.higher('bbbbax','bbba') then false

      # 限制 @yangfishx 尺寸以及買入點出現位置
      when not (barsLeadFishShift*2 > @yangfishx.size > n) then false
      when @timescale is 'hour' and @bar.higher('ba', 'bbba') and @bar.closeUponLine('ba') then false
      #when @bar.closeBelowLine('bbba') then false
      when @bar.highBelowLine('bbba') then false

      # 買入點共用濾除條件
      when @bar.low > @previousBar.close then false
      when @isCurrentData() and @bar.indicatorRise('close', @previousBar) then false
      
      else
        @root_buyBuoyStage 'bottom'
        @yangfisht.buyNexusBar = @bar
        #@bband.bbbyangfishx.buyNexusBar = @bar
        true




  buyNexusSimple_sp: ->
    n = 1
    fishx = @bband.bbbyangfishx
    keyBaName = if @contract.isCASH() and @timescale in ['minute','hour'] then 'ba' else 'bbba'

    switch
      # 開倉與止盈共用條件
      when @bband.bbyangfish.size < barsLeadFishShift then false
      #when fishx.startBar.lowUponLine(keyBaName) then false
      when fishx.startBar.higher('bbbbax', keyBaName) then false

      # 限制 fishx 尺寸以及買入點出現位置
      when not (barsLeadFishShift*3 > fishx.size > n) then false
      when @timescale is 'hour' and @bar.higher('ba', keyBaName) and @bar.closeUponLine('ba') then false
      #when @bar.closeBelowLine(keyBaName) then false
      when @bar.highBelowLine(keyBaName) then false

      # 買入點共用濾除條件
      when @bar.low > @previousBar.close then false
      when @isCurrentData() and @bar.indicatorRise('close', @previousBar) then false
      
      else
        @root_buyBuoyStage 'bottom'
        fishx.buyNexusBar = @bar
        @yangfisht.buyNexusBar = @bar  # (20180603) 臨時增加,以便與止盈止損對應 
        true





  # (20180526) 改為獨立 function
  buyNexus20180521: ->
    switch
      # (20180524 16:06) 在新的盤局策略下,僅取趨勢確定型的追買補倉點    
      when @fishYang() then @fishYangBuyNexus()

      # 陰生段空頭平倉止盈買入點. 定義非常成功
      when @fishNotYang() then @fishNotYangBuyNexus()

      else false




  # (20180522) 原始定義未完成
  # (20180524 16:06) 在新的盤局策略下,僅取趨勢確定型的追買補倉點
  # 以下僅定義盤局出入策略所需之部分追買補倉點  
  fishYangBuyNexus: ->
    switch
      # 會出現反彈頂端出現買點的錯誤情形, spy hour  
      #when @yangEmerging() then true      
      when @bar.low >= @previousBar.close then false
      # 交易過程中,現價高於前收時不行
      #when @isCurrentData() and @bar.indicatorRise('close', @previousBar) then false
      else false




  # (20180521 17:30) 建立
  # (20180524 16:17) 改寫
  fishNotYangBuyNexus: ->
    #@fishNotYangBuyNexusOrigin()
    @fishNotYangBuyNexusBox()





  # (20180524 16:11) 改寫自 origin 版本,僅存盤局出入法所需買點
  fishNotYangBuyNexusBox: ->
    switch
      when @yangEmerging() then true      
      # yangfishx 以及 mayangfishx size 達標,bar 橫跨 bbba
      # (20180524 17:06) 
      # 根據盤局出入法新增過濾條件如下
      when (not @pureYin()) and @bband.bbyangfish.size < barsLeadFishShift then false
      # 濾除未觸底
      when (not @pureYin()) and @bar.lowUponLine('bbba') and @previousBar.lowUponLine('bbba') then false      
      # 濾除均線與價格皆下行的下跌中繼假買入點(spy 分鐘圖為基準,仍未過濾乾淨,可能因為方法太粗,未暇深入研究以下的取點代碼邏輯故)
      when (not @pureYin()) and @bar.bbandma < @bar.bbba and @mayangfishx.size < 2 and @yangfishx.size < 4 then false      
      # (20180524 19:41)
      when @timescale is 'minute' and @yangfishx.startBar is @yinfishx.cornerBar and @bar.bbandma < @bar.bbba then false
      when @timescale is 'minute' and @yangfishx.startBar is @yinfishx.cornerBar and @bar.close < @bar.bbba then false
      # 以上為根據盤局出入法新增的過濾條件

      # 以下為原有代碼
      # 已經下跌一段時間,屬於 mayinCycleB 無疑
      when @mayinfish.size < barsLeadFishShift then false
      # 但剛剛創階段低點不久
      when @yangfishx.size > barsLeadFishShift then false
      # 由下軌構成的地線已經形成,或雖未形成,但股價陽魚x之起點起步於下軌之外
      #when (@bband.bbyangfish.size < 1) and not (@yangfishx.startBar.lowBelowLine(@lowestLineName)) then false
      when (@bband.bbyangfish.size < 1) and not (@yangfishx.startBar.lowBelowLine(@lowerLineName)) then false
      # 大拐角買點
      when @yinCornerBox() then true 
      else false




  # (20180525 14:59)
  # 已確認之盤局底部,可以用鏡像方法,call/put 互換操作
  # 測試結果: 顯示的買入點比應該的少,未明 bug 所在
  yangEmerging: ->
    switch 
      when @bar.low >= @previousBar.close then false
      # mabax 在 bbba 之上不行
      when @bar.mabax > @bar.bbba then false
      when @bband.bbyangfish.size < barsLeadFishShift then false
      when @mayangfishx.size < 5 then false
      when @yangfishx.size < barsLeadFishShift then false
      when @bar.lowBelowLine('bbba') and @bar.highUponLine('bbba')
        @root_buyBuoyStage 'bottom'
        true
      else false



  # (20180524 16:15) 來自 yinCornerOrigin
  # (20180524 19:49) 未改寫. 待大體完成,有空時仔細研究,推敲
  yinCornerBox: ->
    switch
      # 非此段下跌低點起始,且非起於 bbba 之下,則濾除
      when @yangfishx.startBar isnt @yinfish.cornerBar and not (@yangfishx.startBar.lowBelowLine('bbba')) then false
      # 剛開始
      when @bband.bbyangfish.size > 3 and not (@yangfishx.startBar.lowBelowLine('bbba')) then false
      when @yangfishx.size > 7 then false
      when @bar.low >= @previousBar.close then false
      # 交易過程中,現價高於前收時不行
      when @isCurrentData() and @bar.indicatorRise('close', @previousBar) then false
      when @bar[@lowLineName] > @bar.low > @bar[@lowerLineName]
        @root_buyBuoyStage 'continue'
        # 並非起點,或底點,未確認故
        #@root_buyBuoyStage 'bottom'  #'begin'
        true
      else false





  # ----------------------------- original functions -------------------------------


  # (20180521 17:30)
  # (20180522 20:08 單列)
  # (20180524 15:44 更名)
  # 此原始版本的特點是全面,幾乎盡攝所有的陽魚賣出點
  # 由於新思路採用盤局頂底策略,故此保存此法,另開新法,從此法中提取所需部分,忽略其他賣出點,並用作後續開發
  fishYangSellNexusOrigin: ->
    switch
      # 存在問題: 在此純陽段,尚需過濾早期的賣出點(查下以前是怎麼做到的)
      when @pureYangFilterOut() then false 
      when @bar.indicatorDrop('close', @previousBar) then false
      # spy 實例看似乎無須將上述條件分拆為以下對於非純陽段更為寬鬆的條件
      #when @pureYang() and @bar.indicatorDrop('close', @previousBar) then false
      #when @bar.indicatorDrop('high', @previousBar) then false
      
      # (20180523)
      when @yinfishx.size < 3 and @yinfish.size < barsLeadFishShift*2 then false
      # (20180524 10:32)
      when @yinfishx.size < 2 and @yinfish.size >= barsLeadFishShift*2 then false
      
      # 以下使用 @yinfishx, @bband.yinfish, @bband.bbbyinfishx 及其均線 tax, bbta, bbbtax
      #when @yinfishx.size > 0 and @contractHelper.向上報價(@bar.high) < @bar.tax then false
      # bbta 久盤之後出現,此時頂天賣出,所謂頂天,亦即 tax 高於 bbta 小於 bbbtax
      when @bar.bbbtax > @bar.tax > @bar.bbbta then true
      # 以此保留剛創新高之後可能出現的止盈點,過濾掉 bbta 形成很久之後欲上行突破時出現的 tax 小於橫行下壓 bbta 情形
      when @bband.yinfish.size is 0 then @bar.tax < @bar.bbta 
      when @bband.bbbyinfishx.size is 0 then @bar.tax < @bar.bbbtax 

      else false





  # (20180523) 先過濾掉連續上漲過程
  pureYangFilterOut: ->
    false






  # (20180524 16:12) 更名保留原本
  # 陰生段空頭平倉止盈買入點
  # 定義非常成功
  fishNotYangBuyNexusOrigin: ->
    switch
      # 已經下跌一段時間,屬於 mayinCycleB 無疑
      when @mayinfish.size < barsLeadFishShift then false
      # 但剛剛創階段低點不久
      when @yangfishx.size > barsLeadFishShift then false
      # 由下軌構成的地線已經形成,或雖未形成,但股價陽魚x之起點起步於下軌之外
      #when (@bband.bbyangfish.size < 1) and not (@yangfishx.startBar.lowBelowLine(@lowestLineName)) then false
      when (@bband.bbyangfish.size < 1) and not (@yangfishx.startBar.lowBelowLine(@lowerLineName)) then false
      # 大拐角買點
      when @yinCornerOrigin()
        @root_buyBuoyStage 'bottom'  #'begin'
        true 
      else false

  
  
  
  
  # (20180524 16:13) 更名保留原本
  # 定義非常成功
  yinCornerOrigin: ->
    switch
      when @yangfishx.startBar isnt @yinfish.cornerBar and not (@yangfishx.startBar.lowBelowLine('bbba')) then false
      when @bband.bbyangfish.size > 3 and not (@yangfishx.startBar.lowBelowLine('bbba')) then false
      when @yangfishx.size > 7 then false
      when @bar.low >= @previousBar.close then false
      # 交易過程中,現價高於前收時不行
      when @isCurrentData() and @bar.indicatorRise('close', @previousBar) then false
      when @bar[@lowLineName] > @bar.low > @bar[@lowerLineName] then true
      else false





  # ------------------------------ 以上 買買條件組 -----------------------------

  # (20180518) move here from HoloBuyBuoyFitMarket
  # 陰陽錯雜的時期,即盤局,此法理路不妥.
  # 盤局頂天賣出,貼地買入才是對的. 買點不在 yang_cycle 中
  puzzledYangCycle: () ->
    switch
      when not @mayangxCycleX() then false
      else @commonYangCycle()






  # (20180518) move here from HoloBuyBuoyFitMarket
  # (20180515)
  # 定義別法 純陽 cycle 全程之買入點
  # 可在通法上增加條件
  # 本法現存問題
  #   1. 參見 commonYangCycle,
  #   2. 另一個問題就是在短期切片中,在分鐘線上,剛創新高即回落,因此純陽的那部分實則是一次循環的高位
  pureYangCycle: (n=3) ->
    switch
      when not @pureYang() then false

      #設法過濾末段假買點(週線似乎有效)
      when @timescale is 'minute' and @mayangfishb.size < @mayangfishx.size then false # 純陽專用
      # spy hour 尚有漏網,未找到方法前,須通過上漲輪次記錄,暴力阻止
      when @timescale in ['minute', 'hour'] and @mayangfishb.yStarts?.length > n then false # 專用於純陽段
      
      else @commonYangCycle()





  # (20180518) move here from HoloBuyBuoyFitMarket
  # (20180517 11:06)
  # 定義總法 commonYangCycle 買入規則.
  # (20180520 21:49)  
  # 本法思路清晰,容易理解.
  # 現存問題: 過濾掉末期即將破位時的假買點,有待研究(或許其他地方代碼中已經有現成的思路但想不起來了)
  commonYangCycle: ->
    k = 1.06
    switch
      when not @mayangxCycleB() then false
      when @pureYin() then false      
      when @bar.lowBelowLine(@lowLineName) then false # 此法若要用的話,應該用記錄,出現以後都不買,非僅當下不買
      
      # (20180520 21:49)
      # 下行思路正確,但魚不合適,因mayangfishb 其 rawData 為 ma 故不能對應; 採用 yangfishx 測試效果亦不理想,還需要研究
      # 此處須限制 mayangfishb 範圍內 cornerBar 對應的 closeVari 低於 maxVari
      #when @yangfishx.cornerBar.closeVari*k < @yangfishx.maxVari then false
      #when @mayangfishb.cornerBar.closeVari*k < @mayangfishb.maxVari then false
    
      when @bar.closeBelowLine(@highLineName) then true
      else false






  # (20180518) move here from HoloSellBuoyFitMarket
  # (20180515 22:19 建)
  # (20180517 11:33 改)
  # 定義別法.純陰全程之賣出點
  # 觸發賣出次數限 2次
  pureYinCycle: (n=2) ->
    switch
      when not @pureYin() then false
      else @commonYinCycle(n)





  # (20180518) move here from HoloSellBuoyFitMarket
  # (20180517 11:10)
  # 定義總法.
  # 觸發賣出次數限 1次
  commonYinCycle: (n=1) ->
    switch
      when not @mayinxCycleB() then false
      when @mayinfishb.upxBars > n then false
      when @bar.closeUponLine(@midLineName) then true
      else false








  ### 
  (20180508) 
  純陰純陽
    如前定義

  陽長陰長
    不如命名為 yangCycleABC, yinCycleABC 
    亦可以天地線協同均線定義,同向為純,例如地線類與均線同漲為純;
    何時終結,如何判斷?
      或可均線與 index - x bar 比較,以過濾短期反復,但亦延遲判斷;期權後後勝於前前,故判斷遲緩無礙
      relativeBars


  這項技術很有價值,但今天很睏,無法系統思考和完善.
  存此雛形,留待今後改進並應用.
  參閱 su.md.coffee
  ###




  # (20180702 04:51)
  relativeCycles: ->



  # (20180702 04:51)
  relativeFishes: ->





  # (20180517 16:18 遷移) 從 buoyflow_base 遷移至此
  # 可視需要記錄本法(魚)所宿其他法起始 bar 等等有用的 bar,以便快速描述相互關係
  # 很少輸情況下可用以簡化代碼.但亦可不用本 function 搜集而直接通過 pool 引用
  relativeBars: ->
    # 非一次性記錄,並且需要多次使用的,需要集中在使用之前計算好,故須匯集在此處
    @recordYinxHeadBar()

    {bbayinfishx, bbbyangfish, bbbyangfisht, bbbyangfishx, bbbyinfish} = @bband
    # 現不依賴 buoy 故在使用時,置於其 .comingBar() 之前
    # 若將來新增內容依賴 buoy 則須置於其後,並置於 @checkPurity() 之前
    # (20180619 9:40)
    if @bar.closeDownCross('bbbba', @previousBar)
      bbbyangfish.brokenBar = @bar
      @yinfish.brokenBar = @bar

    # (20180614 21:42) 陰魚(熊市)跳空高開避免高位買入故記錄在 @yangfishx, 此處不買,待 @yangfishx 更新時,也就跌了,無記錄
    if @bbbyinxCycleX() and @jumpTop()
      # 仍會漏掉一些,例如起跳後, 此 bbbyangfishx 才出生, 或 yangfishx 即 yangfisht, 皆短促
      bbbyangfishx.bearJumpBar = @bar 
      @yangfishx.bearJumpBar = @bar

    # (20180613 22:47) bbmaBrokenBar 用於輔助設計上昇中繼追買點,過濾盤局形成後的假買點
    # 跟之前 maBrokenBar 相似但有不同,故先分開寫,將來經分析比較,可以此取代
    if @yinfish.size < 5 and @bar.lowBelowLine('matax')
      @yangfishx.bbmaBrokenBar = @bar
    else if @yinfish.size > barsLeadFishShift*3
      @yangfishx.bbmaBrokenBar = null

    # (20180613 18:27) bbayinfishxBrokenBar 用於輔助設計上昇中繼追買點,過濾盤局形成後的假買點
    if (@yinfish.size in [1..5]) and @bar.lowBelowLine('bbatax')
      @yangfishx.bbayinfishxBrokenBar = @bar
      bbbyangfisht.bbayinfishxBrokenBar = @bar
    else if @yinfish.size > barsLeadFishShift*3
      @yangfishx.bbayinfishxBrokenBar = null
      bbbyangfisht.bbayinfishxBrokenBar = null

    # (20180611 16:44) bbbyangfisht.yangfishtHead
    # 用於輔助定義第三買入點
    # 此魚 size 達標則記錄其起始 bar, 後續買入點須高於此bar. ~~[錯]記錄首次,後續不作更新~~
    if @yangfisht.size > 0 #and not bbbyangfisht.yangfishtHead?
      bbbyangfisht.yangfishtHead = @yangfisht.startBar

    # (20180611 15:58) @bbbyangfishtHead
    # 用以輔助測定買入點
    # 此魚 size > 預定值, 則記錄其 startBar. 後續之魚,與前比較,據 bbbbat 高低不同,而分判買入點類型
    # 用 yangfish / yinfish 記錄試
    if bbbyangfisht.size > barsLeadFishShift
      if @yangfish.bbbyangfishtHead isnt bbbyangfisht.startBar
        @yangfish.bbbyangfishtHeadBefore = @yangfish.bbbyangfishtHead
        @yangfish.bbbyangfishtHead = bbbyangfisht.startBar
      if @yinfish.bbbyangfishtHead isnt bbbyangfisht.startBar
        @yinfish.bbbyangfishtHeadBefore = @yinfish.bbbyangfishtHead
        @yinfish.bbbyangfishtHead = bbbyangfisht.startBar


    # (20180611 10:55) @yinfishxHead
    # 用來輔助設定第三賣出點
    # 記錄盤局內,小反彈之高點,以便在下次反彈見頂時判斷是否適合開倉 put
    if @yinfish.size > barsLeadFishShift and @yinfishx.size > barsLeadFishShift and @yinfishx.startBar.highBelowLine('bbbtax')
      if @yinfishx.startBar isnt @bband.bbayinfishx.yinfishxHead
        @bband.bbayinfishx.yinfishxHead = @yinfishx.startBar

    # (20180607 19:57) 變節點 revertBar
    # 注意使用時用 @bar.day 來比較,不可直接比較 @bar, 因在變動故
    if @yangxt.size is 0
      if not @yinfishx.revertBar?
        @yinfishx.revertBar = @bar
        @yangfish.mainfish = @yinfish.mainfish = @yinfishx
      else
        @yinfishx.revertBar = @bar

    if @yinfishx.size is 0
      if not @yangxt.revertBar?
        @yangxt.revertBar = @bar
        @yangfish.mainfish = @yinfish.mainfish = @yangxt
      else if @barIsCurrent(@yangxt.revertBar)
        @yangxt.revertBar = @bar


    # (20180510 21:00)
    # 記錄 mayangfish x 中的 b 小段    
    if @mayangfishb.size is barsLeadFishShift*2
      @mayangfishx.bStarts ?= []
      unless @mayangfishb.startBar in @mayangfishx.bStarts[-1..]
        @mayangfishx.bStarts.push(@mayangfishb.startBar)
      
    # (20180511 17:11)
    # 記錄 @yinfish 中的 @mayinfishx 小段
    # 注意,兩種起點不同,先須設限:
    if @mayinfishx.startAfter(@yinfish) and @mayinfishx.size is barsLeadFishShift
      @yinfish.myinxStarts ?= []
      unless @mayinfishx.startBar in @yinfish.myinxStarts[-1..]
        @yinfish.myinxStarts.push(@mayinfishx.startBar)

    # (20180511 20:32建立)
    # (20180512 17:41改正)
    # 檢測純陽結束,陰生.
    # 所覆 bars >= 2 則賣出 
    if 0 < @mayinfishx.size < barsLeadFishShift # 還可以再限制為純陽而非盤局,方法很多,例如 0 < @yinfish.size < barsLeadFishShift
      @mayinfishx.coveredBars ?= []
      {coveredBars} = @mayinfishx
      # 使用 @previousBar 原因是 @bar 尚未定型,故多有不便. 餘處應倣此
      if @previousBar.highBelowLine('matax')
        unless @previousBar in coveredBars
          coveredBars.push(@previousBar)


    # (20180516 23:24)
    # 記錄 mayangfish b 中的 @bband @yinfish 小段    
    # 用於純陽上昇過程,排除後期的高風險買入點
    if @bband.yinfish.size is 5 #barsLeadFishShift
      @mayangfishb.yStarts ?= []
      unless @bband.yinfish.startBar in @mayangfishb.yStarts[-1..]
        @mayangfishb.yStarts.push(@bband.yinfish.startBar)
  
    # (20180517 11:24)
    # @mayinfishb 跌落過程中之,價格上穿 bbma 次數
    if @mayinxCycleB() and @previousBar.closeUpCross(@midLineName,@earlierBar)
      @mayinfishb.upxBars ?= 0
      @mayinfishb.upxBars++

    # (20180602 18:26)
    # stopWin
    if @yangfishx.size > 5 and @yangfishx.startBefore(@bband.yinfish) and @yangfishx.startBefore(@bband.bbbyangfisht)
      if @bband.bbayinfishx.size is 0 and @bband.yinfish.size < 3
      #if @bband.bbbyinfish.size is 0 and @bband.yinfish.size is 0
        #_assert.log({debug: 'stopWin', bar:@bband.bbbyangfish.bbbyangfishtBrokenBar?, size:@bband.bbayinfishx.size})
        @yinfish.bbbyangfishtBrokenBar = null 
        @bband.bbbyangfish.bbbyangfishtBrokenBar = null
      else if @bar.lowBelowLine('bbbbat') #or (@bband.bbbyangfisht.size is 0 and @bband.bbbyangfisht.forwarding)
        @yinfish.bbbyangfishtBrokenBar ?= @bar
        @bband.bbbyangfish.bbbyangfishtBrokenBar ?= @bar

    # (20180606 11:07)
    # 記錄均線破位
    if @bar.closeDownCross('bbandma',@previousBar)
      @yangfishx.maBrokenBar = @bar
      @yinfishx.maBrokenBar = @bar


    # (20180603 09:56) 不太對,太困
    if @previousBar? 
      if (@bband.yinfish.yangfishxBrokenBar isnt @previousBar) and (@previousBar.low is @previousBar.bax)
        @bband.yinfish.yangfishxBrokenBar = @previousBar
        #_assert.log({debug:'yangfishxBrokenBar', day:@previousBar.lday(), yinfish:@bband.yinfish.startBar.lday()})




  # 直接以根本陰魚為主體,陽魚似乎任選無異
  mayinCycleB: (n=5) ->
    @mayinfish.size > 0 and @mayangfishb.size <= n

  
  


  # 採用定義不同,長短有異的魚類作為檢測標誌.即: 主長,客短,以利連續
  # 此處: 陽主陰客
  mayangxCycleB: (n=5) ->
    n = 5
    @mayangfishx.size > 0 and @mayinfishb.size <= n #(@mayinfishb.size in [0..n])

    # 另一種表述
    #@mayangfishx.size > n and (@mayinfishb.startBefore(@mayangfishx) or @mayinfishb.size in [0..n])




  # 採用定義不同,長短有異的魚類作為檢測標誌.即: 主長,客短,以利連續
  # 此處: 陰主陽客
  mayinxCycleB: (n=5) ->
    @mayinfishx.size > 0 and @mayangfishb.size <= n #(@mayangfishb.size in [0..n])





  # 以下採用同類
  mayangxCycleX: (n=5) ->
    @mayangfishx.size > 0 and (@mayinfishx.size <= n)




  mayinxCycleX: (n=5) ->
    @mayinfishx.size > 0 and (@mayangfishx.size <= n)





  # 陽生
  yangxCycleX: (n) ->
    switch
      when n then switch
        # 陽前陰後, 陰魚不太長
        when @yangxt.startBefore(@yinfishx) then @yinfishx.size <= n

        # 非陽前陰後, 陽魚足夠長
        when @yangxt.size > n then true

        else false

      # 無參數 n 情形
      # 陽前陰後
      when @yangxt.startBefore(@yinfishx) then true
      else false




  # 陰生
  yinxCycleX: (n) ->
    #@yinfishx.size > 0 and (@yangxt.size <= n)
    switch
      # 有參數 n 情形
      when n then switch
        # 陰前陽後, 陽魚不太長
        when @yinfishx.startBefore(@yangxt) then @yangxt.size <= n
        
        # 非陰前陽後,陰魚足夠長
        when @yinfishx.size > n then true
        
        else false

      # n 為 null 情形
      # 陰前陽後
      when @yinfishx.startBefore(@yangxt) then true
      else false





  # bband B level
  # 定義: bbbyangfishx 早於 bbbyinfishx, 排除其中後起的 bbbyangfisht 段
  bbbyangxCycleX: ->
    {bbbyangfishx, bbbyangfisht, bbbyinfishx} = @bband
    switch
      when bbbyangfishx.startBefore(bbbyinfishx) then switch
        # t is subclass of x
        when bbbyangfisht.startAfter(bbbyinfishx) then false
        else true
      else false





  # bband B level
  bbbyinxCycleX: ->
    {bbbyinfishx, bbbyangfisht} = @bband
    switch
      when bbbyinfishx.startBefore(bbbyangfisht) then true
      else false






  # (20180517 16:18 遷移) 從 buoyflow_base 遷移至此
  # 純陰純陽檢測
  checkPurity: ->
    {bbbyinfishx,bbyangfish} = @bband
    # 檢測純陽是否依舊的標誌,即是否已經下穿;創新高之後清零從新檢測
    if @bar.closeDownCross('gradeSell', @previousBar)
      @yangfish.dxGSBar = @bar
      @yangfish.bought = false
    
    if @bar.closeDownCross(@midLineName, @previousBar)
      @yangfish.dxMABar = @bar
      # 盤局陰中之陽最近一段上漲是否均線破位,宜採用yangfishx
      @yangfishx.dxMABar = @bar
      # bbyangfish 更適合記錄純陽最近一段上漲是否均線破位
      bbyangfish.dxMABar = @bar

    if @bar.closeDownCross('mdx', @previousBar) and @bar.mdx > @bar.bbta
      @yangfishx.dxMDBar ?= @bar
      @yangfishx.bought = false

    # 新高清零
    if @yinfish.size is 0
      @yangfish.dxGSBar = null
      @yangfish.dxMABar = null
      @yangfishx.dxMABar = null
      bbyangfish.dxMABar = null
      @yangfish.dxMDBar = null
   
    # 新高清零    
    if bbbyinfishx.size is 0
      @yangfishx.dxMABar = null    

    # 檢測純陰
    if @bar.closeUpCross('gradeBuy', @previousBar)
      @yinfish.uxGBBar = @bar
      @yinfish.sold = false

    # 新低清零  
    if @yangfish.size is 0
      @yinfish.uxGBBar = null 

    # 尚不周全,待讀圖完善
    if @bar.closeUpCross('mdx', @previousBar)
      @yinfishx.uxMDBar = @bar
      @yinfishx.sold = false

    # 新低清零 (20180512 11:49 補闕)
    # bbyangfish 可否?
    #if bbyangfish.size is 0
    # @yinfishx.uxMDBar = null











### 
  舊注釋,備考
  包含提取 contractDetails 的方法. 故可用於索取期權資料.
  期權工作步驟: 1. 索取期權資料,抽取一組期權代碼 2. 用這些代碼申請歷史行情 3. 篩選期權品種 4. 指定 callCode/putCode 
  5. @bar[@callCode]可提取期權價 6. 期權價視作技術指標 7. 在證券買賣點基礎上,通過背離確認期權買賣點 8. 設法發出交易指令
###  

class IBPoolBase extends CyclePool

  @pick:(poolOptions)->
    {secCode,timescale} = poolOptions
    theClass = switch timescale
      when 'minute' then MinuteIBPool
      when 'MINUTE' then RecentMinuteIBPool
      when 'hour' then HourIBPool
      when 'day' then DayIBPool
      when 'DAY' then RecentDayIBPool
      when 'week' then WeekIBPool
      when 'month'
        if secCode in ioptRoots
          HKIOPTRootSecMonthIBPool
        else
          MonthIBPool
    return new theClass(poolOptions)



    
  #IBPoolBase
  histIBDataBar: (aBar)->
    @comingBar(aBar)




  emitCancelRequest: (cancelIds) ->
    if @onDutyWithHistData and cancelIds.length > 0
      messageSymbol = 'cancelIds'
      @emit(messageSymbol, cancelIds)
      _assert.log({
        info: 'emitCancelRequest'
        messageSymbol
        cancelIds
      })






  # messageSymbol: '穿行信號'
  emitOrderSignal: (messageSymbol, {signal, order}) ->
    if @onDutyWithHistData
      miniCopy = signal.emitObj()
      @emit(messageSymbol, {signal: miniCopy, order})

      {buoy,isCloseSignal,isOpenSignal,checker,maker} = signal
      {action, price, vol} = order
      _assert.log({
        info: 'emitOrderSignal'
        action
        isCloseSignal
        isOpenSignal
        checker
        maker
        fullStake: @contractHelper.fullStake()
        stakeRemain: @contractHelper.stakeRemain() 
        price
        plannedPosition: buoy.nowSuggestedPositionChange
        rootSuggestPositionChange: buoy.gotSuggestBar?.rootSuggestPositionChange
        vol
      })






  emitRequestIfReayToClose: ->
    if doCloseWindow and @contract.isOPTIOPT() and @contractHelper.readyToClose()  
      @emit('pool:closeOPTWindow')
      @contractHelper.selfCloseRequestSent()










class IBPoolForOPTsBase extends IBPoolBase

  
  
  ###
  記錄強制多頭平倉狀態, 並且將趨勢設為 bearish, 以便接受多頭倉位平倉信號
  注意不要跟 call/put 混淆.無論是 call 還是 put, 
     若為多頭倉位,此時漲勢到頭,走勢都設置為 bearish 或者 bear, 多頭倉位都予以平倉.
     若為空頭倉位,則反之可知
  ###
  forceStopSecProcess: (callbackOrderFilled) ->
    _assert.log('接到基礎證券信號,即將強行平倉此期權品種多頭倉位,然後關閉期權線程')
    # 將 forceLong/shortClose = true 狀態記錄在 contractHelper 以便查詢,並且將成交回報 callback 記錄在 secPosition 以便發回反饋 
    @contractHelper.forceStopSecProcess(callbackOrderFilled)



  cleanRootSecAfterOPTClose: (secCode)->
    _assert.log({debug:'cleanRootSecAfterOPTClose', secCode})

    # 以下代碼使用 secCode 中的P/C標記,故QQdata提供的牛熊證數據,其代碼沒法判斷
    unless IBCode.isOPT(secCode)
      _assert.log({debug:'cleanRootSecAfterOPTClose >> not opt:', secCode})
      return null 
        
    operator = if IBCode.isCallOPT(secCode)
      _assert.log({debug:'cleanRootSecAfterOPTClose >> is call', secCode})
      @optOperators.caller
    else
      _assert.log({debug:'cleanRootSecAfterOPTClose >> is put', secCode})    
      @optOperators.putter

    operator.cleanAfterStopProcess(secCode)









class IBPoolForOPTs extends IBPoolForOPTsBase


  # ---------------------------------------- buoy fish name ------------------------------------------

  ###
    用途: 
      用於確定是否要打開或關閉期權線程
    
    思路:
      由於期權行情不如基礎證券那樣連續和完整,故使用基礎證券輔助判斷期權之開關.
      避免在行情成住壞滅的後期開啟交易進程.

    存疑:
      兼在此處或僅在 signalFish 決定是否關閉期權交易進程.
  ###
  _rootSecBuoyFishName: ->
    @_rootSecBuoyFishName20180429()




  ### 
    此法亦展示 buoy 操作軌跡的一種方法.
  ###

  # 可以為 null,無須補充首日默認值
  _rootSecBuoyFishName20180429: ->
    switch
      when @sellBuoy.nowBuoyFitsSignal then @_setBuoyFishNameTo(@sellBuoyFishName)
      when @buyBuoy.nowBuoyFitsSignal then @_setBuoyFishNameTo(@buyBuoyFishName)
      else @_setBuoyFishNameTo(null)





  _setBuoyFishNameTo: (aName) ->
    if @buoyFishName isnt aName
      @_buoyFishNameChanged(aName)  # 可先作相應處理,例如發佈當前期權平倉並停止買入訊息
      @buoyFishName = aName





  # 可先作相應處理,例如發佈當前期權平倉並停止買入訊息
  _buoyFishNameChanged: (aName) ->
    # if @contract.isRootSec() then ...





  # for test only
  # 20180412
  _buyBuoyFishFitsPut02: (rsi) ->  
    rsi ?= 30
    @bar.closeBelowLine(@lowerLineName) and (@bar.rsi < rsi) 




  # 不得不清倉時才清倉
  # 亦可與其他條件並用
  _sellBuoyFishFitsCall20180427: (rsi) ->
    #破位之後點即賣出
    (barsLeadFishShift > @mayinfishb.size > 0) and @bar.indicatorRise('close', @previousBar)



  _sellBuoyFishFitsCall02:(rsi) ->
    # 設置很高沒用的,背離時,反而會高位錯過賣出機會; 
    # 具體數值無意義,須統計階段高點低點之分佈,而以背離為契機.RSI 絕對數無大用
    # 由於此處僅為開啟期權設置條件故無須精確.操作自有期權 buoy 更好算法
    rsi ?= 60 
    @bar.closeUponLine(@highLineName) and (@bar.rsi > rsi)


  # ---------------------------------------- signal fish name ------------------------------------------



  # 力求簡化,嚴格. put / call 皆可賺錢,不偏不倚即可,不必遷就 call
  # gradeSell / gradeBuy 的設置比較主觀,所以盡量不用
  _rootSecSignalFishName:->
    @_rootSecSignalFishName20180418()


  # (20180418)
  _rootSecSignalFishName20180418: ->
    putFish = @[@putFishName]
    callFish = @[@callFishName]
    noSignalFishName = not @signalFishName?
    noneOrCall = noSignalFishName or (@signalFishName is @callFishName)
    noneOrPut = noSignalFishName or (@signalFishName is @putFishName)
    switch
      # putFish: yinfish~, shortSignalFish~
      when @root_sec_putCycle()
        @_setPutFishAsSignalFishName()

      # callFish: yangfish~, longSignalFish~
      when @root_sec_callCycle()
        @_setCallFishAsSignalFishName()

      else
        @signalFishName = null
    



  # (20180416)
  _rootSecSignalFishName07: ->
    putFish = @[@putFishName]
    callFish = @[@callFishName]
    noSignalFishName = not @signalFishName?
    noneOrCall = noSignalFishName or (@signalFishName is @callFishName)
    noneOrPut = noSignalFishName or (@signalFishName is @putFishName)
    switch
      # putFish: yinfish~, shortSignalFish~
      when noneOrCall and (@mayinfishb.size > 0) and (@bar.matab > @bar.gradeBuy) and @bar.lowBelowLine('gradeBuy')
        @_setPutFishAsSignalFishName()
      when noneOrCall and @bar.closeBelowLine('gradeSell') and @bar.closeBelowLine('gradeBuy')
        @_setPutFishAsSignalFishName()
        
      # callFish: yangfish~, longSignalFish~
      when noneOrPut and @bar.closeUponLine('gradeSell') and @mayinfishb.size is 0
        @_setCallFishAsSignalFishName()      
      when noneOrPut and @bar.closeUponLine('gradeSell') and @bar.matab < @bar.gradeBuy
        @_setCallFishAsSignalFishName()
    
      when (@bar.gradeBuy <  @bar.close < @bar.gradeSell) # 適合 short Call/Put, 但本系統禁止 short 故設置為 null
        @signalFishName = null        




  # [20180411]
  _rootSecSignalFishName06: ->
    putFish = @[@putFishName]
    callFish = @[@callFishName]
    noSignalFishName = not @signalFishName?
    noneOrCall = noSignalFishName or (@signalFishName is @callFishName)
    noneOrPut = noSignalFishName or (@signalFishName is @putFishName)
    switch
      # putFish: yinfish~, shortSignalFish~
      when noneOrCall and @bar.closeBelowLine('gradeBuy') and @bar.lowBelowLine('gradeSell')
        @_setPutFishAsSignalFishName()

      # (20180412)
      # issue: 此條件不完善,會造成上躥下跳,尚未想出補救方法
      #when noneOrCall and (@mayangfishb.size < 1) and @bar.highBelowLine('gradeBuy') and (@bar.gradeBuy >  @bar.close > @bar.gradeSell)
      #  @_setPutFishAsSignalFishName()

      # callFish: yangfish~, longSignalFish~
      # 在 gradeSell 之上, 且不在 gradeBuy 之下
      when noneOrPut and @bar.closeUponLine('gradeSell') and @bar.highUponLine('gradeBuy')
        @_setCallFishAsSignalFishName()
    
      when (@bar.gradeBuy <  @bar.close < @bar.gradeSell) # 適合 short Call/Put, 但本系統禁止 short 故設置為 null
        @signalFishName = null        




  # [20180325]
  _rootSecSignalFishName05: ->
    putFish = @[@putFishName]
    callFish = @[@callFishName]
    noSignalFishName = not @signalFishName?
    noneOrCall = noSignalFishName or (@signalFishName is @callFishName)
    noneOrPut = noSignalFishName or (@signalFishName is @putFishName)
    switch
      # putFish: yinfish~, shortSignalFish~
      when noneOrCall and @root_sec_putCycle()
        @_setPutFishAsSignalFishName()

      # callFish: yangfish~, longSignalFish~
      when noneOrPut and @root_sec_callCycle()
        @_setCallFishAsSignalFishName()
    
      when noSignalFishName and (@barIsCurrent @startBar)
        @_setCallFishAsSignalFishName()
        


  # 思路是取陽中之陽,陰中之陰
  # 但結果與預想的不一致,需要更多觀察,以便找出合理的定義方式
  # 暫時沿用過往定義
  fishYang: ->
    if tighter
      #@_fishYang01()
      #@xtCycle.realYang()
      @xtCycle.isYang

    else # 粗分牛段
      @root_sec_callCycle()


      #@_fishYang20180430()
      #@_fishYang20180504()
      #@_fishYang20180509()

      #@fishYang20180607()
      
      







  fishYang20180607: ->
    if true
      @yangxCycleX()  #(barsLeadFishShift)
    else
      # 僅僅臨時看下指標效果,不是策略
      @bbbyangxCycleX()






  fishNotYang:->
    if tighter
      #@_fishNotYang01()
      #@xtCycle.realYin()
      @xtCycle.isYin

    else # 粗分熊段
      @root_sec_putCycle()

      #@_fishNotYang20180430()
      #@_fishNotYang20180504()
      
      #~~@_fishNotYang20180516()~~ 不用此法
      #@_fishNotYang20180509()
      
      #@_fishNotYang20180607()






  # 新代碼盡量直接使用此法
  root_sec_callCycle: ->
    @bband.bxbtCycle.realYang(2)
    #or (@bband.bxbtCycle.isYin and not @bband.bxbtCycle.realYin())

    ###@xbtCycle.realYang()
    #@bband.bxbtCycle.isYang
    #@ggCycle.isYang
    #@ggCycle.realYang()
    # 不合適
    #if @isMinute then @ffCycle.realYang() else @bband.bxbtCycle.realYang(2) 
    ###




  # 新代碼盡量直接使用此法
  root_sec_putCycle: ->
    @bband.bxbtCycle.realYin(2)
    #or (@bband.bxbtCycle.isYang and not @bband.bxbtCycle.realYang())

    ###@xbtCycle.realYin()
    #@bband.bxbtCycle.isYin
    #@ggCycle.isYin
    #@ggCycle.realYin()
    # 不合適
    #if @isMinute then @ffCycle.realYin() else @bband.bxbtCycle.realYin(2) 
    ###  






  _fishNotYang20180607: ->
    if true
      @yinxCycleX()  #(barsLeadFishShift)
    else
      # 僅僅臨時看下指標效果,不是策略
      @bbbyinxCycleX()






  # 理論上合理,適用於一些長期下跌走成大圓形底的品種,
  # 但不普遍適用,尤其不合用於 SPY,無深跌故
  # 若要用,需要增補例外條件,即深跌用此法,淺調用前法
  _fishNotYang20180516: ->
    @mayinCycleB(barsLeadFishShift*3)


  _fishYang20180509: ->
    @mayangxCycleB()


  _fishNotYang20180509: ->
    @mayinxCycleB()  #(barsLeadFishShift)



  _fishYang20180504: ->
    @mayangfishb.startBefore(@mayinfishx)



  _fishNotYang20180504: ->
    @mayinfishxEarly()


  
  _fishYang20180430: ->
    @bbyangfishEarly()



  _fishNotYang20180430: ->
    @bbandYinfishEarly()



  _fishYang01: ->
    @mayangfishbEarly()




  _fishNotYang01: ->
    @mayinfishbEarly()




  _derivativesSignalFishName: ->
    @_commonSignalFishName()



  _commonSignalFishName:->
    switch
      when @contractHelper.isBiwayOrJustHasShortPosition() then @_rootSecSignalFishName()
      when @contract.isOPTIOPT() then @_setLongFishAsSignalFishName()
      else @_rootSecSignalFishName()





  _setCallFishAsSignalFishName: ->
    if @contract.isRootSec()
      @signalFishName = @callFishName
    else
      @_setLongFishAsSignalFishName() # 名異實同,方便定製




  _setPutFishAsSignalFishName: ->
    if @contract.isRootSec()
      @signalFishName = @putFishName
    else
      @_setShortFishAsSignalFishName() # 名異實同,方便定製
    



  _setLongFishAsSignalFishName: ->
    @signalFishName = @longSignalFishName



  _setShortFishAsSignalFishName: ->
    @signalFishName = @shortSignalFishName



  
  
  # 強勢區域  
  # 反向運行時間限制需要窄一些
  
  # (20180511 22:57) 建立
  # (20180512 21:57) 改正
  # 無論如何定義,其關鍵為:
  #   1. 創新高過程中 
  #   2. 尚未見轉勢跡象
  pureYang: ->
    ###
    定義要點:
      1. 陽魚之內
      2. 或為陽魚之角,或 mayinfishx.size < 限定
      3. 陽魚內需對 mayangfishx 之起始點數,需要限制嗎?
    ###
    (@mayinfish.size < 5) and @mayangxCycleX()





  # (20180511)
  ###
    (20180512 22:24)補註
    定義比 pureYang 複雜,原因是,SPY 其實只有陽中之陰,因此要兼顧兩種情況:
      1. 真正的陰中之陰, 適用於 SQQQ 等
      2. 陽中之陰第一段, 適用於 SPY 等
    後者,亦即奠定盤局深度的那一段,之後進入收斂形態後的上落,均非純陰.
    後者是本系統主要標的.
  ###
  pureYin: ->
    ### 
    定義要點:
     1. 陰魚之內
     2. 其中僅有一個 mayinfishx 起始點(可行嗎?)
     3. 此時為陰魚之角或此時 @mayangfishx.size < 限定
    ###
    #@pureYin20180511()
    @pureYin20180516()


  # 實驗性質,待觀察效果異同
  # 環境惡劣,勿輕易使用.
  # 用前須再仔細分析完善
  pureYin20180516: ->
    switch
      # should be?
      when not @mayinxCycleX() then false
      when @barIsCurrent @yinfish.cornerBar then true
      when @mayinfish.size < 5 then false
      when @mayangfishb.size > 5 then false
      when @mayinfishx.startBar isnt @mayinfish.startBar then false
      when @mayangfishb.startBar isnt @mayangfishx.startBar then false
      else true



  pureYin20180511: ->
    switch
      when not @mayinxCycleX() then false
      when @mayinfish.size < barsLeadFishShift then false
      when @barIsCurrent @yinfish.cornerBar then true

      when @yinfish.myinxStarts?.length isnt 1 then false
      when @mayangfishx.size < barsLeadFishShift then true

      else false




  straightCall: ->
    #@straightCall_grade()
    @straightCall20180607()


  
  straightCall20180607: ->
    {bbbyangfishx, bbbyinfish} = @bband
    bbbyangfishx.startBefore(bbbyinfish)



  straightCall_grade: ->
    {cornerBar} = @yinfish
    cornerBar.lowUponLine('gradeSell') and cornerBar.lowUponLine(@lowerLineName) and @bar.highUponLine('gradeBuy') and @mayinfish.size is 0





  straightPut: ->
    #@straightPut_grade()
    @straightPut20180607()



  straightPut20180607: ->
    {bbbyangfisht,bbbyinfish} = @bband
    bbbyinfish.startBefore(bbbyangfisht) and bbbyangfisht.size < barsLeadFishShift



  straightPut_grade: ->  
    @bar.highBelowLine('gradeBuy') and @bar.closeBelowLine('bbandma') and @mayangfishb.size is 0 and \
    @bar.close < @previousBar?.close




  _notNewYang: ->
    not @_newYang()



  _newYang: ->
    {highBandBName,lowBandBName,maName} = @bband
    switch
      when @yangfishEarly() then false
      when @_lowBandBBottom() then true
      else @yinfish.cornerBar is @yangfish.startBar and @bar.higher(lowBandBName,@bband.yinfish.tbaName)




  _notYangOrNewYang:->
    not @_yangOrNewYang()








  _yangOrNewYang:->
    @_newYang() or @yangfishEarly()




  _notYang:->
    not @yangfishEarly()




  yangfishEarly:->
    @yangfish.startBefore(@yinfish)



  # 系補救措施,所欲解決的問題,本可通過行情再剪裁解決.故無須花費太多精力.
  # 尚不完善  
  _lowBandBBottom: ->
    cornerBar = @yinfish.cornerBar
    @bar.indicatorRise(@bband.maName, cornerBar) and \
    (@yangfishx.startBar is @yinfish.cornerBar or @yinfishx.cornerBar.onMid('low', @yinfish, @yangfish)) and \
    @bar.indicatorRise(@bband.lowBandBName, cornerBar) and \
    @bar.indicatorRise(@bband.highBandBName, @previousBar)

  
  
  _currentEarningLong:->
    r = 1.1
    (not @isCurrentData()) or @contractHelper.hasEarningLongPosition(r)



  _currentStakeStillAmple: ->
    (not @isCurrentData()) or @contractHelper.stakeStillAmple()





  _currentEarningShort: ->
    r = 1.1
    (not @isCurrentData()) or @contractHelper.hasEarningShortPosition(r)




  _closeInsideHighBandB:->
    {highBandBName} = @bband
    @bar.closeBelowLine(highBandBName)
  


  _riseInsideHighBandB:->
    {highBandBName} = @bband
    @bar.lowBelowLine(highBandBName) and @_barRose()

  
  
  _barRose: ->
    switch
      #when @bar.indicatorRise('high', @previousBar) then true
      #when @bar.indicatorRise('close', @previousBar) then true
      when @bar.indicatorRise('high', @earlierBar) and @previousBar.indicatorRise('high', @earlierBar) then true
      when @bar.indicatorRise('close', @earlierBar) and @previousBar.indicatorRise('close', @earlierBar) then true
      else false



  _dropInsideLowBandB:->
    {lowBandBName} = @bband
    @bar.highUponLine(lowBandBName) and @_barDropped()



  _barDropped:->  
    #(@bar.indicatorDrop('low', @previousBar) or @bar.indicatorDrop('close', @previousBar))
    switch
      when @bar.indicatorDrop('low', @earlierBar) and @previousBar.indicatorDrop('low', @earlierBar) then true
      when @bar.indicatorDrop('close', @earlierBar) and @previousBar.indicatorDrop('close', @earlierBar) then true
      else false











class ResearchPool extends IBPoolForOPTs








# 此研究工具臨時存在. 待動態圖解決之後,即遷移至 IBPoolForOPTs 除非另有獨特新功能需要另設,就無須此法了
class ComparePool extends ResearchPool

  toCompare:->
    (@secCode in optRoots) and @poolOptions.comparing #and @contractHelper.isUsStock 



  derivativeIBDataBarEnd: (secCode)->  
    _assert.log('derivative IB data Bar End: ',secCode)



  # 收到衍生品行情時,有兩種情形:
  # 1. 自身行情已經接收完畢, histIBDataEnd, 直接填寫數據即可
  # 2. 自身行情尚未接收完,此時就有些數據沒法填寫,須先緩存,然後集中錄入
  derivativeIBDataBar: (secCode,aBar)->
    unless @toCompare()
      return
      
    {rightLimit} = @contractHelper
    if rightLimit? and rightLimit isnt secCode[-9..][0]
      return
    if aBar?.date?
      #_assert.log("devrivate data bar:",secCode, aBar.day)
      theBar = @barAtDate(aBar.date)
      theBar?[secCode] = aBar.close
    else
      @quoteCache ?= {}
      @quoteCache[secCode] ?= []
      @quoteCache[secCode].push(aBar)
      _assert.log("[debug derivative IB data Bar] just cache a bar of ", secCode)
  



  fillDerivativeData:->
    unless @quoteCache?
      return
    for secCode, barArray of @quoteCache
      for aBar in barArray
        @barAtDate(aBar.date)?[secCode] = aBar.close
  




  # 此法依賴ib 接口,若接口變化,可能永遠沒有結束信號出現,此時需要在繪圖時,預先做一次 fill data
  histIBDataBarEnd:(callback)->
    @fillDerivativeData()





  # 此法生效時表明我為衍生品,默認為SPY期權.
  suggestionByRoot: (action, strongRoot, stage, rsPositionChange, type)->
    @contractHelper.optStrongRoot(strongRoot)
    
    # 可能其他地方需要此變量以便通過篩選過濾,委託發出後,須還原此變量
    @contractHelper.suggestOfRoot = action
    
    switch action
      when 'buy'
        @buyBuoy.suggestedByRoot(this, strongRoot, stage, rsPositionChange, type)
      when 'sell'
        @sellBuoy.suggestedByRoot(this, strongRoot, stage, rsPositionChange, type)      







    
class IBPool extends ComparePool

  #IBPool
  histIBDataBarEnd: (sendXtraInfo)->
    super(null)
    @extraInfo()
    sendXtraInfo(@quoteInfo) # 仍需此回執,以便主程序做其他事情,如關閉過時證券窗口



  #IBPool
  realtimeBar: (tick,callback)->
    unless tick?
      return

    if @bar?
      @emitRequestIfReayToClose()

      newBar = @bar.joinNewTick(@secCode,tick, @timescale)
      #_assert.log('debug realtime:', tick.time, newBar.date)
      @comingBar(newBar,this)

      # 用於繪圖.此時所有層次計算均已完成,故若生成 bar 中製圖變量的邏輯順序不錯,則皆可正確繪圖.
      # 當前 bar 製圖變量生成比較分散和混亂, 有空須加以整理並集中於此處
      callback?(this)

    else
      newBar = null
    # debug 美股數據
    #if IBCode.isABC(@secCode) then _assert.log("[debug] received tick from ib, joined as new bar: ", tick, newBar)



  
  
  newOrderStatus: (order) ->
    @contractHelper.newOrderStatus(this, order)




  #IBPool
  __depthRatioRecords:(fishName,x=0) ->
    stat = (fish)->
      day: fish.startBar.day
      size: fish.size
      ratio: fish.cornerDepthRatio
    (stat(fish) for fish in @fishArray(fishName) when fish.cornerDepthRatio >= x).concat([stat(@[fishName])])



  __tableDepthRatioRecords:(fishName,x=0)->
    console.table(@__depthRatioRecords(fishName,x))
  


  #IBPool
  __findUndefinedDepthRatio:(fishName)->
    (fish for fish in @fishArray(fishName) when not fish.cornerDepthRatio?)
  

  

  #IBPool
  # 注意: 
  #   行情片段的截取,目前僅完成了外部數據部分,將來如果採用IB數據,須仿照外部數據的處理方法,
  #   利用 poolOptions.skipToDate 和 poolOptions.cutLen 其中之一,即可輕鬆完成
  externalData: (callback)->
    if @poolOptions.ibData
      callback(null,null,this)
      return 
        
    @lastFakeBar = null

    secCode = @secCode
    timescale = @timescale
    forex = @forex # = 'wallstreetcn' # 方便從用戶界面靈活設置
    revert = true
    weekend = null 
    fakeIdx = null
    cleanArray = null
    cleanLen = null
    isABCash = IBCode.isABCash(@secCode)
    #_assert.log('isABCash?', @secCode, isABCash)
    if isABCash
      weekend = (moment().utc().day() in [0,6]) 
    else 
      weekend = (moment().day() in [0,6]) # 怪異js 時間!!!

    update = (periodName=@timescale) => #不要帶參數
      first = not @bar?
      fakeQuote = dev and weekend and (not first) # 是否製作用於開發的假數據
      # _assert.log('first:',first)
      len = null
      {cutLen} = @poolOptions
      
      #_assert.log('debug cutLen @ timescale:',cutLen,periodName) # 以此發現了 fday 問題.已經解決.備用.
      
      len = switch 
        when cutLen? and (cutLen > 3) and not /minute/i.test(periodName) then cutLen
        when @contract.isIOPT() and periodName is 'fdays' then 300
        else
          if first then 350000 else 305


      # qqdata 特殊:
      # 港股用 一分鐘行情 轉換成其他小時 分鐘行情, 因 qqdata 尚無這些數據
      if periodName[..5] in ['hour','minute','MINUTE','second'] and @contract.exchange is 'SEHK'
        periodName = 'minute'
  
      hists {symbol:secCode, type:periodName,units:len,forex:forex}, (err,arr) =>
        # if @timescale is 'day' then _assert.log 'debug', arr[-1..][0].close
        if err? or ((not arr? or arr.length < 1))
          callback(first,null,this) # 仍需此回執,以便主程序做其他事情,如關閉過時證券窗口
          _assert.log('err or not arr? or arr.length < 1: ',err?.code, arr?.length)
          return null

        if arr?
          if not fakeQuote
            for bar,idx in arr when bar?
              # close window when forced to
              @emitRequestIfReayToClose()

              if bar.constructor.name isnt 'FakeMinuteBar'
                @comingBar(bar)
              else 
                #fakeBar(bar)
                @_fakeBar(bar, fakeQuote, callback)
          else
            cleanArray ?= (bar for bar in arr when bar?)
            cleanLen ?= cleanArray.length
            fakeIdx ?= cleanLen - 2
            for bar,idx in cleanArray
              if (bar.constructor.name is 'FakeMinuteBar') and idx is fakeIdx
                #fakeBar(bar, true)
                @_fakeBar(bar, fakeQuote, callback)
                if revert
                  fakeIdx-- 
                  revert = fakeIdx > 1  # 轉向之前保持true,到0轉向,變為false
                else 
                  fakeIdx++
                  revert = fakeIdx > cleanLen - 2  # 轉向之前保持false,到最大序號轉向,變為true
 
          @extraInfo()
          # @quoteInfo 僅騰訊數據源有,且隨時更新,故切不可用於記憶需要記憶的屬性
          # 若其他數據源此處則可callback @bar 以呈報行情
          qto = arr[-1..][0].qqdata?.qto # 注意此中有即時行情,故一律更新,並呈送證券窗口備用.
          if qto
            _.assign(@contractHelper.quoteInfo, qto)
          #callback(first, @quoteInfo,this) # 仍需此回執,以便主程序做其他事情,如關閉過時證券窗口
        callback(first, @quoteInfo,this) # 仍需此回執,以便主程序做其他事情,如關閉過時證券窗口
        return

    # 先下載初始數據,不待延時

    if @contract.exchange is 'SEHK' and @timescale in ['MINUTE','minute','hour','minute60']
      p = 'fdays'
    else 
      p = null
    

    # 本來不用參數,單純為了 minute 下載更新之前,先下載 5日minute 數據而設. 更新時則不用參數
    update(p) #似乎未運行?

    # 然後,再定時更新
    秒 = 1000 #分鐘 = 60*秒#小時 = 60*分鐘
    # fx168, wallstreetcn 行情數據,分鐘線不是即時更新的;
    period = switch  #  凡 switch 其中 when 之順序皆不可輕易更改
      when @selecting
        # 此時不存在循環,僅用一次; 因集中下載行情,需要防止網站控制訪問,故採用30 秒
        30 * 秒
      when @contractHelper.momentTrading()
        if timescale in ['MINUTE','minute','minute05','minute15','minute30','minute60','hour']
          5 * 秒
        else
          5 * 秒  # 更新日週月線
      else switch
        when @contract.secType is 'IOPT' and @timescale in ['minute', 'MINUTE', 'hour'] and dev and @poolOptions.paperTrading
          5 * 秒
        when dev
          60 * 秒
        else
          30 * 60 * 秒
  
    itv = setInterval(update, period)
    @intervals ?= []
    @intervals.push(itv)



  _fakeBar:(fMinuteBar,fakeQuote,callback)-> # fbar 可以是即時tick 或假 一分鐘行情(如騰訊港股美股一分鐘行情)
    fbar = fMinuteBar
    if fbar?
      # 特殊處理
      if fakeQuote # 用於開發的假數據
        fbar = fbar.fakeQuote()
      # 正式開始
      if @bar?
        # 經檢測  qqdata 之 fakeMinute 並非於此節選,保留此功能備用
        #_assert.log("debug _fakeBar day and date:",fbar.date < @bar.date, fbar.momentBefore(@bar, @timescale))
        if (fbar.date < @poolOptions.skipToDate) or fbar.momentBefore(@bar, @timescale)
          #_assert.log('debug @bar skip:',fbar.date)
          callback(null,null,this)          
          return
        newBar = @bar.joinNew(fbar, @timescale)?.asExternal(@timescale)
      else
        _assert(fbar.date, 'no date')
        # 經測試 qqdata 之 fakeMinute 節選發生於此
        if fbar.date < @poolOptions.skipToDate
          #_assert.log('debug fbar skip:',fbar.date)
          callback(null,null,this)
          return
        if not @lastFakeBar?
          newBar = fbar.asExternal(@timescale)
          @lastFakeBar = newBar
        else
          newBar = @lastFakeBar.joinNew(fbar, @timescale)?.asExternal(@timescale)

      # 測試時記得設置 dataflow_base comingBar testForExternalData 為 true
      # [有待觀察] 嘗試以後,似乎如此繪圖完整,機理暫時沒空深究
      if true      
        @comingBar(newBar)
      else 
        # [續上注] 以下代碼會出現 hour 歷史燭線不全只有一個價位,備考
        if @isTodayBar(newBar)
          @comingBar(newBar)
        else if newBar.momentAfter(@lastFakeBar, @timescale) # 若非當天,等待下一個時刻的假分鐘bar 出現才處理之前一個bar
          @comingBar(@lastFakeBar)
      @lastFakeBar = newBar
    


  clearIntervals:->
    for interval in (@intervals ? [])
      clearInterval(interval)
    @intervals = null



  #IBPool
  extraInfo:->
    # 是否為其他數據源人為補齊此法
    @quoteInfo ?= @contractHelper.quoteInfo
    @quoteInfo.timescale = @timescale
    @quoteInfo.cutOptions = @buildCutOptions()
  


  #IBPool
  buildCutOptions:-> 
    #_assert.log('[debug] now build cut options')




  getFocusFish: (barName='downXHighBandBBar') ->
    if (@yinfish? and @yinfish.startBar.momentBefore(@yangfish.startBar, @timescale)) or @yinfish?[barName]?
      return @yinfish
    # reverse() 會改變所在的array! 很容易出錯
    copy = (aFish for aFish in @yinfishArray).reverse()
    for aFish in copy when aFish[barName]?
      _assert.log('debug: corner day', aFish.cornerBar.day)
      return aFish



  #IBPool
  # 截取近期行情的目的是展開折疊在回跌箱體中的混沌行情,故截取時不能改變趨勢標誌.
  # 因此,當反彈未觸及ta至bay 1/2 時,採用陰魚整段,否則採取拐點略微提前n天
  barSkipTo:(fish,n)->
    bar = null
    if fish.upXMidyBar?
      bar = fish.cornerBar
    else
      bar = fish.startBar
    @barBefore(bar, n) ? @startBar



  barDateSkipTo:(fish,n) ->
    @barSkipTo(fish,n).date



  lengthSince:(fish,npre=null)->
    1 + @barArray.length - @barArray.indexOf(@barSkipTo(fish, npre)) 
  


  _lengthSinceCornerOf:(fish)->
    1 + @barArray.length - @barArray.indexOf(fish.cornerBar)




class InDayIBPool extends IBPool
  
  lengthSince:(fish,npre=5)->
    super(fish,npre)




class HourIBPoolBase extends InDayIBPool
 






class HourIBPool extends HourIBPoolBase

  # put: stopWin; 
  # call: [ VERY DANGEROUS !!! ] 謹防突然暴跌
  # (20180719 18:26 頗為完善)
  cce_buyInGgYangFfYin: ->
    stageLabel = if @root_sec_putCycle() then 'stopWin' else 'uncertain'

    switch
      when not @ffCycle.isYin then false

      # 1. call / put 兩類,但 call 將標記為 uncertain or mirror
      when @cceBgbgFf.buyPoint(3,'略向上報價')
        @root_buyBuoyStage(stageLabel, 'cceBgbgFf.buyPoint')

      # 初反彈許可從地線而起,不及 bgbgCycle. 長盤之後, buyBarCross 地線就不可取了, 用更外層的 cceBgbgFf 來決定
      when @ffCycle.cycleYangfish.size < 2*barsLeadFishShift and @cceGgFf.buyPoint(13,'向上容忍價')
        @root_buyBuoyStage(stageLabel, 'cceGgFf.buyPoint')

      # 不可以用 Xt, 因無法區分跌落圈外的非所轄範圍(餘處凡使用 Xt 者均需小心)
      #when @cceGgXt.buyPoint() #when @cceBgbgXt.buyPoint()

      # 2. 以下專門針對 put 平倉 stopWin
      when not @root_sec_putCycle() then false 
      # 過濾非甩出地線情形,使用默認參數,向上容忍價; 若設置太大,則需要甩開很遠,會丟失未甩遠的機會
      when not @cceBgbgFf.innerYangDropOut('向上容忍價') then false
      
      # 甩出圈外的情形
      when @cceFfXt.buyPoint(3,'向上極限價')
        @root_buyBuoyStage(stageLabel, 'cceGgFf.buyPoint')

      else false











class MinuteIBPoolBase extends InDayIBPool
  refineSettings:->
    super()  
    @underlyingIndicator = 'bbandma' # 各週期可定制





    

class MinuteIBPool extends MinuteIBPoolBase

  # MinuteIBPool
  buildCutOptions:->
    return
    # 有了 fishx 分鐘線看來不需要截取
    super()
    if @cutOptions?
      #_assert.log('@cutOptions already exists')  
      return @cutOptions

    fish = @getFocusFish('downXLowBandBBar') #('downXBbandMaBar')
    _assert.log("debug: get focus fish start day: ",fish?.startBar.day, @bar.day)

    if fish?
      n = 20
      obj =
        master: @constructor.name
        viewId: 'MINUTE'
        skipToDate: @barDateSkipTo(fish,n)   # 計算結果可能在首日之前而為null 故以首日彌補
        quotePieceLen: @lengthSince(fish, n)
    else
      _assert.log('no fish available?')
      obj =
        master: @constructor.name
        viewId: 'MINUTE'
        skipToDate: @startBar.date
        quotePieceLen: @size + 1
    @cutOptions = obj







  # ----------------------------   strategy  -------------------------------

  # put: stopWin; 
  # call: [ VERY DANGEROUS !!! ] 謹防突然暴跌
  # (20180719 18:26 頗為完善)
  cce_buyInGgYangFfYin: ->
    stageLabel = if @root_sec_putCycle() then 'stopWin' else 'uncertain'

    switch
      when not @ffCycle.isYin then false

      # 1. call / put 兩類,但 call 將標記為 uncertain or mirror
      when @cceBgbgFf.buyPoint(3,'略向上報價')
        @root_buyBuoyStage(stageLabel, 'cceBgbgFf.buyPoint')

      # 初反彈許可從地線而起,不及 bgbgCycle. 長盤之後, buyBarCross 地線就不可取了, 用更外層的 cceBgbgFf 來決定
      when @ffCycle.cycleYangfish.size < 2*barsLeadFishShift and @cceGgFf.buyPoint(13,'向上容忍價')
        @root_buyBuoyStage(stageLabel, 'cceGgFf.buyPoint')

      # 不可以用 Xt, 因無法區分跌落圈外的非所轄範圍(餘處凡使用 Xt 者均需小心)
      #when @cceGgXt.buyPoint() #when @cceBgbgXt.buyPoint()

      # 2. 以下專門針對 put 平倉 stopWin
      when not @root_sec_putCycle() then false 
      # 過濾非甩出地線情形,使用默認參數,向上容忍價; 若設置太大,則需要甩開很遠,會丟失未甩遠的機會
      when not @cceBgbgFf.innerYangDropOut('向上容忍價') then false
      
      # 甩出圈外的情形
      when @cceFfXt.buyPoint(3,'向上極限價')
        @root_buyBuoyStage(stageLabel, 'cceGgFf.buyPoint')

      else false










class RecentMinuteIBPool extends MinuteIBPoolBase







class DayWeekMonthIBPoolBase extends IBPool

  barDateSkipTo:(fish)->
    @barBefore(fish.cornerBar).date









class DayIBPoolBase extends DayWeekMonthIBPoolBase
  refineSettings:->
    super()
    @underlyingIndicator = 'bbandma' # 各週期可定制
    # 注釋下行則仍用 20  
    # @bbandArg = 400



# 最近yangfishy對應行情段
class RecentDayIBPool extends DayIBPoolBase



class DayIBPool extends DayIBPoolBase

  refineSettings:->
    super()  
    # 注釋下行則仍用 20  
    @bbandArg = 400
    @underlyingIndicator = 'bbandma' # 各週期可定制



  #DayIBPool
  buildCutOptions:->
    if @cutOptions?
      return @cutOptions

    {yinfishArray} = @bband
    fish = null
    if yinfishArray.length > 0
      fish = (@bband.yinfishArray[-1..][0])
    else
      fish = @yinfish
    obj =
      master: @constructor.name
      viewId: 'DAY'
      skipToDate: @barDateSkipTo(fish)
      quotePieceLen: @lengthSince(fish)
    @cutOptions = obj




class WeekIBPool extends DayWeekMonthIBPoolBase




class MonthIBPoolBase extends DayWeekMonthIBPoolBase

  # MonthIBPoolBase
  buildCutOptions:->
    if @cutOptions?
      return @cutOptions

    #查找之前跌破bbandma的陰魚,求其cornerBar以後行情長度
    fish = @getFocusFish('downXHighBandBBar')

    # return:
    if fish?
      obj = 
        master: @constructor.name    
        viewId: 'DAY'
        skipToDate: @barDateSkipTo(fish)   # 月線可能以月末日期為日期
        quotePieceLen: @lengthSince(fish) * 20
    else
      obj =
        master: @constructor.name    
        viewId: 'DAY'
        skipToDate: @startBar.date
        quotePieceLen: 0 # 以0作為長度參數,外部數據部件將下載完整行情
    @cutOptions = obj
    



class MonthIBPool extends MonthIBPoolBase




class HKIOPTRootSecMonthIBPool extends MonthIBPoolBase

  # HKIOPTRootSecMonthIBPool
  refineSettings:->
    super()  
    @underlyingIndicator = 'bbandma' # 各週期可定制



  # HKIOPTRootSecMonthIBPool
  comingBar:(aBar,aPool=this)->
    super(aBar,aPool)
    # 目前使用騰訊數據,其實無須此法,直接通過 extraInfo 傳遞. 
    # 備用機制.
    if @isCurrentData()
      @emit('antiVanishPrice', @antiVanishPrice())



  # HKIOPTRootSecMonthIBPool
  extraInfo:->
    super()
    @quoteInfo.antiVanishPrice = @antiVanishPrice()



  # HKIOPTRootSecMonthIBPool
  antiVanishPrice:->
    {closeHighBandB,bbandma} = @yinfish.startBar
    if @yinfish.cornerBar.low > closeHighBandB
      closeHighBandB
    else
      bbandma






module.exports = {Pool,IBPoolBase}
