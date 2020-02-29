util = require 'util'
path = require 'path'
say = require 'say'
moment = require 'moment'
{hists} = require path.join __dirname,'..','..','sedata'
{Position} = require path.join __dirname,'..','..','asecurityPosition'
{IBCode} = require path.join __dirname,'..','..','secode'
{nowTrading} = require path.join __dirname,'..','..','secode'
{MaFlow,EMaFlow,BBandFlow} = require path.join __dirname,'..','..','maflow'
DataFlow = require path.join __dirname,'..','..','dataflow'
RatioFlow = require path.join __dirname,'..','..','ratioflow'
{YScoreFlow,ScoreFlow,LayerFlow,LevelFlow} = require path.join __dirname,'..','..','layerscore'
{Explorer} = require path.join __dirname,'..','..','tracer'

{IBDataBar, IBRealtimeBar} = require path.join __dirname,'..','..','databar'
{Flow:{zeroLevel,rmaArg,pureYinYang,calcScore,calcLayer,calcLevel,scoreIntoBar,layerIntoBar,levelIntoBar}} = require path.join __dirname,'..','..','config'
{YinFish,YangFish,YinFishX,YinFishZ,YangFishX,YinFishY,YangFishY,YangFishZ} = require path.join __dirname,'..','..','fishflow'
{TopBot,TopBotWithFishes} = require './topbotflow'

### 池 以游魚
定義:
  就是讀取時序ObsoleteBArray數列(最為關鍵的是高低兩邊數據)求頂底指標(tor線/低)以及陰yangfish(天yangfishArray)
套疊:
  可以隨機取樣,算法不變.任何一組ObsoleteBArray數據都可以求池/魚.
  這將極度簡化天地頂底的套疊計算.
輸入:
  注意讀入的是ObsoleteBArray,而非ticks中的一筆成交.
  ticks乃至各級ObsoleteBArray(積聚),另外做接口接進來.
###

### 區間 有起止,其中起點預知,止住點未知
  若有sampleDataName,則高低皆取此單值計算陰yangfish等指標
  例如 ma_price10
###

# ObsoleteBArray:[{高:2,低:1},......]
# 起止無用,因僅僅需要對endIndex求內池


# 例如: new Pool({統計參數:{僅限最近:20}})
class Pool extends DataFlow
  # 以 object 作為參數,寫法有些不同,注意需要另行設置默認值:
  constructor:(@參數={},@customs=null)->
    # 高效的寫法是 {@某某=默認,@某甲,@某乙} = @參數
    {
      @contract
      @startIndex=0
      @fleaMax=5
      @forex='wallstreetcn'
      @sampleDataName=null
      @週期名=null 
      @secCode=null
      # 計算協均所需變量,協均即 harmonic mean, 俗譯為 調和均數
      # 協價名即'high','low','open','close',等等,
      # 協權是求加權協均的變動指數權數,為x時,資金比重為價格倒數1/p的x次方冪,為0時,為1,即等額
      @協權=0
      # null則不算協均
      @yangfish協價名=null
      @yinfish協價名=null
      @轉勢臨界幅度=10
      statsTag='峰值統計'  # 因操作需要,必須做峰值統計
      統計參數={}
    } = @參數
    
    super(@secCode,@週期名)
    @onDuty = false
    
    @回幅 = @參數.回幅[@週期名] ? {陰:0.0618, 陽:0.0618} # 0.05 better?

    # 採用補充計算方法,如果源數據已有均值則不會重複計算
    @sma05 = new MaFlow(@secCode,@週期名,'ma_price05','close',5)
    @sma10 = new MaFlow(@secCode,@週期名,'ma_price10','close',10)
    #@sma20 = new MaFlow(@secCode,@週期名,'ma_price20','close',20)
    @ema20 = new EMaFlow(@secCode,@週期名,'ema_price20','close',20) 
    @bband20 = new BBandFlow(@secCode,@週期名,'ema_price20','close',20) # 亦可使用 ma_price20
    @sma150 = new MaFlow(@secCode,@週期名,'ma_price150','close',150)
    @botRatios = new TopBot(@secCode, @週期名, '求谷比low','low')
    @botRatios.ratioName = 'bor' # 早期中文名 見底 指標
    @topRatios = new TopBot(@secCode, @週期名, '求峰比high','high')
    @topRatios.ratioName = 'tor' # 早期中文名 見頂 指標


    # 以下均線魚,用不著計算天地均,故參數中可去掉 tbaName.
    mx回幅 = @回幅.陰 / 8
    fl = new YinFishX(rawName: 'ma_price150',fishName: 'yinfishLongMa',回幅:mx回幅) #,tbaName: 'taLongMa')
    fs = new YinFishX(rawName: 'ma_price10',fishName: 'yinfishShortMa',回幅:mx回幅) #,tbaName: 'taxsma')
    #@secCode,@週期名,@statsTag,
    @longMaTBF = new TopBotWithFishes(@secCode,@週期名,'longMaTBF','ma_price150',@startIndex,[fl])
    @shortMaTBF = new TopBotWithFishes(@secCode,@週期名,'shortMaTBF','ma_price150',@startIndex,[fs])
    @ratio = new RatioFlow(@secCode,@週期名)
    
    if calcScore then @scores = new ScoreFlow(@secCode,@週期名) # YScoreFlow(@secCode,@週期名) # 
    if calcLayer then @layers = new LayerFlow(@secCode,@週期名)
    if calcLevel or true # 一定需要的 
      # 特殊處理的買賣策略,放在特別的LevelFlow 中定義
      @levels = LevelFlow.pick(@secCode, @週期名, @contract)
      @explorer = Explorer.pick(@secCode, @週期名, @contract)
  
    @ratioMa = new MaFlow(@secCode,@週期名,'rma','ratio',rmaArg)
    @ratioTBF = new TopBotWithFishes(@secCode,@週期名,'ratioTBF','ratio',@startIndex) # tbIndicator would be 'rma' or 'ratio'
    yinf = new YinFishZ(rawName:'rma',fishName:'yinfishzm',tbaName:'tazm') # 嘗試用 fishx 出錯, # 回幅:回幅
    yangf = new YangFishZ(rawName:'rma',fishName:'yangfishzm', tbaName:'bazm')
    @ratioMaTBF = new TopBotWithFishes(@secCode,@週期名,'ratioMaTBF','rma',@startIndex,[yinf,yangf]) # tbIndicator would be 'rma' or 'ratio'

    ###
      以下所有@變量均可再設置,故不需要進入@證券,無須修改代碼,需要時直接重設即可
    ###
    @bor值上限 = 7 # 今低較前低已上漲幅度,須研究bortor條件,設定不可跌到@bor值下限的數值
    @bor值下限 = 0.003

    ### 此@ObsoleteBArray僅供測試時用
      嵌套時,頭尾序號都是絕對序號,故存ObsoleteBArray組會複雜.
      若不需要,代碼無須改動,只需注釋掉
    ###
    @ObsoleteBArray = []
    @liveBar = null #僅部分情況下才有此法

    # 每讀一數則加一,故未讀入數據時,先倒算一位
    @endIndex = @startIndex - 1
    
    # 中文名 僅為 兼容舊命名體系
    @yinfish = new YinFish({@secCode,@週期名,tbaName:'ta',rawName:'high',cornerName:'low'})
    @yangfishy = new YangFishY({@secCode,@週期名,tbaName:'bay',rawName:'low',cornerName:'high',homeName:'yinfish'})
    @yinfishy = new YinFishY({@secCode,@週期名,tbaName:'tay',rawName:'high',cornerName:'low',homeName:'yangfishy'})
    # 默認的 fishName 是 constructor.name.toLowerCase,故此處須指定魚的名字,以求魚中之魚,仍可反復折疊
    @yangfishy2 = new YangFishY({@secCode,@週期名,tbaName:'bay2',rawName:'low',cornerName:'high',homeName:'yinfishy',fishName:'yangfishy2'})
    @yinfishy2 = new YinFishY({@secCode,@週期名,tbaName:'tay2',rawName:'high',cornerName:'low',homeName:'yangfishy2',fishName:'yinfishy2'})
    @yangfish = new YangFish({@secCode,@週期名,tbaName:'ba',rawName:'low',cornerName:'high'})
    @yinfishx = new YinFishX({@secCode,@週期名,tbaName:'tax',rawName:'high',cornerName:'low',回幅:@回幅.陰})
    @yangfishx = new YangFishX({@secCode,@週期名,tbaName:'bax',rawName:'low',cornerName:'high',回幅:@回幅.陽})

    
    ### yinfishArray存yinfish,yangfishArray存yangfish,並非必須.
      若需要則去掉注釋,代碼無須改變.
      初始即放置,因yinfishyangfish設計,不會冗餘第一魚故

      魚Array中保存下來的魚,除了尚未完形的,都是長度大於1的
      找到最近長度大於某數值的魚,比較其尾.序與末魚之頭.序,可知單邊行情走了多久
    ###
    @yinfishArray = []
    @yangfishArray = []
    @yinfishxArray = []
    @yangfishxArray = []
    @yinfishyArray = []
    @yangfishyArray = []
    @yinfishy2Array = []
    @yangfishy2Array = []
    
    # 動魚溢出次數,用於自動調整 回幅 參數
    @xyiFlea = 0
    @xyaFlea = 0

    # --------- 以下為策略部分 ---------

    @勢或偏多 = null
    @勢或偏空 = null


    ###
    # 由於lorx,hirx之計算獨立於 fish,僅計算一次,故無需考慮嵌套折疊時,新建內池初始設置
    # 可以針對一組指標進行峰谷頻率統計,但加上對應的filter,可能令代碼過於複雜,故複雜統計還是通過
    # 數次循環來逐一計算比較簡單,也不會很慢

    # 以下代碼限制為一次僅作一種統計,且僅統計一個指標;並且僅統計@序列()這部分數據

    # 不要試圖擴展到指標組,會增加複雜程度
    ###
    #{statsTag='峰值統計',統計參數={}} = @參數
    if statsTag?
      #統計參數 = @參數.統計參數 ? {}  # 為便於下面的設置故, 若null則設為{}
      # 達到比較可能回調的bor值或lorx幅度,峰值後往往有衝刺,否則可取 30
      #@警戒百分位 = 統計參數.警戒百分位 ? 85
      {
        @警戒百分位 = 85
        @計峰篩選 = (bar)-> bar.入選計峰 = (bar.low > bar.bax) and (bar.high > bar.ma_price10)
        @計谷篩選 = null # 未完成,也未用到
        @入選計峰 = (bar)-> (bar.low > bar.bax) and (bar.high > bar.ma_price10)
        @入選計谷 = -> true # 未完成,也未用到
        基數 = 0
        levels = null  # TopBot 有默認值
        # 動低幅 lorx 更為實用但不默認,bor指標不依賴參數故
        # 看圖時看lorx,若要在策略買賣時使用,則需特別注意參數設置
        sampleDataName = 'lorx' # 動低幅
        僅限最近 = null #160
      } = 統計參數

      if statsTag is '峰值統計'
        @probabs = new TopBot(@secCode, @週期名, statsTag,sampleDataName)
        @probabs.擬統計峰值頻率({計峰基數:基數, 計峰目標:levels, 入選計峰:@入選計峰})
      else if statsTag is '谷值統計'
        #需要時,參照峰值統計,大同小異
        return

    # 本用於清空intervals,但並非必須,若用多線程,本線程關閉則intervals自然就清空了
    @intervals = []


  # ---------------------- constructor end ----------------------

  nowOnDuty: (aBoolean) ->
    @onDuty = aBoolean
    @explorer?.nowOnDuty(aBoolean)
    
  # 此法將是唯一入口[尚未完成]
  comingBar:(aBar,aPool=this,callback)->
    unless aBar?
      return this
    if @lastBar? and aBar.date < @lastBar.date
      return this
    super(aBar,aPool)#(aBar,this) # this is not used  

    @adjustXParams()
    # 無先後依賴的計算可以map,否則用 for.
    # 更緊密的組合計算已經嘗試過了,不能再精簡了.就這樣不用再合併了.
    [@sma05,@sma10,@sma20, @ema20, @sma150, @bband20].map((each)-> each?.comingBar(aBar)) # 補缺計算普通均線
    
    [@topRatios,@botRatios].map((each)-> each?.comingBar(aBar,aPool)) # 計算頂底指標,其計算方法獨立於陰陽魚系統.

    [@yangfish,@yinfishx,@yangfishx].map((each)->each?.comingBar(aBar,aPool)) #計算陰陽魚中無依賴部分
    
    # @yinfish,@yangfishy,@yinfishy 次第有意義,不可顛倒
    for fish in [@yinfish,@yangfishy,@yinfishy] # 計算陰陽魚中先後依賴部分,順序不可顛倒,其中陰魚中有陰中之陽魚,其中有陽中之陰魚
      fish.comingBar(aBar, aPool) # 順序不可顛倒故不可 map!
    for fish in [@yangfishy2,@yinfishy2]
      fish.comingBar(aBar, aPool)
    # 在fish運算之後才能算概率 #@probabs.comingBar(aBar,aPool)
    [@probabs, @longMaTBF, @shortMaTBF].map((each)->each.comingBar(aBar,aPool))  # 計算漲幅分佈概率,依賴陰陽魚. 並計算長均峰谷帶魚
    @scores?.comingBar(aBar,aPool)
    @layers?.comingBar(aBar,aPool)
    @levels?.comingBar(aBar,aPool)
    
    for each in [@ratio,@ratioMa,@ratioTBF,@ratioMaTBF]  # 計算均線變化率,以及衍生指標,先後有依賴
      each.comingBar(aBar,aPool) # 不可用 map

    @currentBar = @isCurrentBar()
    if @currentBar
      @secPosition.獲悉最近價(aBar.close)    
      # 待各種fish 算好後才好計劃倉位
      @計劃倉位()

    # 或是或不是當天都可以:  (從 tracer 轉移至此)
    @mayCloseShort = (not @currentBar) or (@secPosition.isShortPosition() and @secPosition.成本價?)
    @mayCloseLong = (not @currentBar) or (@secPosition.isLongPosition() and @secPosition.成本價?)



    @explorer?.comingBar(aBar, aPool) # 進入 explorer

    if callback? then callback(aBar)
    if @size is 1 
      @emit('hasData',this) 
    return this



  # return this
  序列:(aBarArray,所求魚)->
    for bar in aBarArray
      @comingBar(bar, this)
    return this


  
  adjustXParams: ->
    xya = @yangfishx
    xyi = @yinfishx
    unless (xya? and xyi?)
      return
      
    #last = @ObsoleteBArray[xya.尾.序] # @endIndex 不行! 直接指向最後一天了,切切注意此設計缺陷!
    last = xya.bar
    return null unless last?
    {high,low,close,open,tax,bax} = last
    if ((Math.max(open,close) - tax) > (tax - bax) > 0)
      @xyiFlea++
      if @xyiFlea > @fleaMax
        @xyiFlea = 0
        xyi.回幅 *=0.809
        @customs.get("poolOptions.回幅.#{@週期名}")
          #.find("回幅.#{@週期名}")
          .merge({陰:xyi.回幅})
          .value()
    if ((bax - Math.min(open,close)) > (tax - bax) > 0)
      @xyaFlea++
      if @xyaFlea > @fleaMax
        @xyaFlea = 0
        xya.回幅 *=0.809
        @customs.get("poolOptions.回幅.#{@週期名}") #.find("回幅.#{@週期名}")
          .merge({陽:xya.回幅})
          .value()

  
  fishSizes:(fishName,host)->
    if host?
      filter = (each) -> each.startBar.day > host.startBar.day
    else
      filter = -> true 
    (each.size for each in @["#{fishName}Array"] when filter(each)).sort((a,b)-> b-a)

  barAt:(idx)->
    if idx >= 0
      @barArray[idx]
    else
      @barArray[idx..][0]

  #-------------------------------------------

  
  # 本法亦應移至 bar 但先須將協價計算改寫完畢
  計劃倉位:()->
    kellyPosition = @bar.kellyPosition()
    if @yinfish協價名?
      自身權衡係數 = @bar["ta#{@yinfish協價名}倒價"] / 3 #假定3為最大
      plannedPosition = kellyPosition * 自身權衡係數
    else
      plannedPosition = kellyPosition
    @bar.plannedPosition = plannedPosition
    return plannedPosition
    
    # TODO: 思路不錯,計算不妥. 宜改為現價位與魚頭的比值作為基本的參照點
    # 定投一般是反做了,應該用bax或地均的協均,而非從yinfish頭開始定投.
    # 須在應用Pool時已經打開協均計算開關,否則為 null

    # 注意:
    #   計劃倉位 若超過1,意味著槓桿,若限制其過1,則不適用槓桿
    #   此控制權限,應放在賬戶買賣評估中

    # ================== 以上計算計劃倉位 =======================






  #--------------------------------------------------


  求末:(n)->
    @barArray?[-n..]
  求末燭: ->
    @bar
  求前魚:(類別)->
    @[類別][-2..-2][0]


  ### 折疊和嵌套:)
   不依賴池中存ObsoleteBArray,所以不用
   可先把ObsoleteBArray截取好再傳給本法,本法僅去頭不切尾
  ###

  求池:(某魚,某ObsoleteBArray)->
    ObsoleteBArray = 某ObsoleteBArray ? @ObsoleteBArray
    某魚.池 = new @constructor(@參數)
    某魚.池.startIndex = 某魚.頭.序
    某魚.池.序列(ObsoleteBArray?[-某魚.size..])

  求魚池:(本魚, 所求魚)->
    今池 = @[本魚].池 = new @constructor(@參數)
    今池.startIndex = @[本魚].頭.序
    ### 僅適用於末位 魚
      若想用於任意魚,須修改 序列,以便接受第三個參數{起,止},並據此截取行情
    ###
    今池.序列(@ObsoleteBArray[-@[本魚].size..], 所求魚)
    ### 如果不想複製,可複用該 本魚,並且改Array
    今池[本魚] = @[本魚]
    今池[本魚+'Array']= [@[本魚]]
    ###
    ### 如果想複製,可用以下代碼,無須改Array
    # 如果需要 jsonify 則需要使用:
    ###
    今池[本魚].頭 = @[本魚].頭
    今池[本魚].尾 = @[本魚].尾
    return 今池

  yinfish求池: ->
    @求魚池('yinfish', 'yangfish')

  yangfish求池: ->
    @求魚池('yangfish', 'yinfish')

  # 匯集主要的objects
  objectCollection:->
    return {@sma05,@sma10,@sma150,@sma20,@taxsma,@ema20,@bband20,@yinfish,@yinfishy,@yinfishy2,@yangfish,@yangfishy,@yangfishy2,@scores,@levels,@layers}


class IBPool extends Pool
  constructor:(@參數={},@customs=null)->
    super(@參數,@customs)
    @secPosition = Position.pick(@secCode,@contract)
    @isBull = false
    @isBear = false
    

    
  adjust:(number)->
    number  
  realtimeBar: (tick,callback)->
    if tick?
      rb = new IBRealtimeBar(tick)
      if @bar?
        newbar = @bar.joinNew(rb, @週期名)
      else
        newbar = null
      #console.log rb,newbar,@bar
      @comingBar(newbar,this,callback)
  histBar: (aBar)->
    if aBar?
      newbar = new IBDataBar(aBar)
      @comingBar(newbar) 
  
  externalData: (callback)->
    callback false
  
  bullish:->
    bull = (@commonBullish() or @specialBullish()) and not @specialBearish() and @lineUp('ema_price20')
    @bar.isBull =  if bull then 0.5 else 0
    bull    
  commonBullish:->
    @yangfish.size > @yinfish.size
  specialBullish:->
    {close, high, ta, tay, tay2} = @bar    
    {startBar} = @yinfishy
    onTay = close > tay or close > tay2
    onTa = startBar.tay > startBar.ta
    onTa or onTay or @yinfishy.forward
  specialBearish:->
    {close,low,ba,bay,bay2} = @bar
    yay = @yangfishy 
    yay.forward # or (close < bay)
  
  backUpBearishFilter: ->
    {rma,taz} = @bar
    (rma < @previousBar?.rma) or (taz > zeroLevel and @ratioMaTBF.yinfishzm.size > 2 and @ratioMaTBF.yinfishzm.startBar.date < @ratioMaTBF.yangfishzm.startBar.date) # 非常有效的主段過濾器


  bearish:->
    #@yinfish.size > @yangfish.size
    not @bullish()

  # 強多頭市場,為求簡單,則僅用於日線週線月線,若欲在分時行情上使用,須確保數據完整,否則需要進行下一層次的嵌套,令系統變得複雜
  strongBull:->
    @bullish() and @yangfishy.startedUpon('ba')
  # 強空頭市場,同上注釋
  strongBear:->
    @bearish() and @yinfishy.startedBelow('ta')
  extremeBull:->
    @bullish() and @yangfishy.startedUpon('score5')
  # 強空頭市場,同上注釋
  extremeBear:->
    @bearish() and @yinfishy.startedBelow('score5')

  #這裡可以處理多空切換相關事宜
  changedIsBull:(aBoolean)->
    if /^hour|^minu|^secon/i.test(@週期名)
      #util.log 'got changedIsBull message now isBull: ', (if @bar? then  @bar.day else 'no bar yet,'), aBoolean
      'do something'
    else
      @emit('changedIsBull', aBoolean)
    @setBear(not aBoolean)

  setBull: (aBoolean)->
    if @isBull isnt aBoolean
      @changedIsBull(aBoolean)
      @isBull = aBoolean
    return @isBull
  
  setBear: (aBoolean)->
    if @isBear isnt aBoolean
      # 這裡可以處理多空轉換相關事宜
      @isBear = aBoolean
    return @isBear 

  # 以下兩個,為舊思路,暫時保留備考
  buyFilter:->
    {close,open,low,high,bay,bay2} = @bar
    head = 4 > @yangfishy.size > 0 or (bay > bay2 and 4 > @yangfishy2.size > 0)
    x =   ((high > @bay >= low) or (high > @bay2 >= low)) and close >= open
    return head or x
  sellFilter:->
    {close,open,low,high,tay,tay2} = @bar
    head = 4 > @yinfishy.size > 0 or (tay2 > tay and 4 > @yinfishy2.size > 0)
    x =  ((high >= tay >= low) or (high >= tay2 >= low)) # and close <= open
    return head or x
  

  # 有用思路,備考勿刪!!!
  # 根據30分鐘 小時 或日線 天地線加上輔助線確定買賣點  
  有用備考_longFilteredEntry: ->
    {ba,bay,bay2,level5} = @bar
    #y2 or y
    # ba 適用於較少的分時行情數據,若為完整數據則注釋掉 <= ba
    ready = bay2 <= bay <= ba or ba < bay2 <= bay <= level5
    if ready
      for f in [@yinfishy, @yinfishy2] # @yinfish, 會出現空頭市場下跌途中大量假的買點
        if f.有用備考_longFilteredEntry(this)
          return true
    else if bay2 <= level5 and @yinfishy2.buyCross() #or @levels.buyCrossAny(this) # buyCrossAny 臨時放在這裡測試未仔細思考
      return true
    return false
  
  #sellEntry: -> @levels.sellCrossAny(this)


# externalData pool, old name: SecPool
class EDPool extends IBPool
  # 代碼,池名,週期名,長
  externalData: (callback)->
    secCode = @secCode
    週期名 = @週期名
    forex = @forex # = 'wallstreetcn' # 方便從用戶界面靈活設置
    lastFakeBar = null
    fakeBar = (fbar)=> # fbar 可以是即時tick 或假 一分鐘行情(如騰訊港股美股一分鐘行情)
      if fbar?
        if @bar?
          newbar = @bar.joinNew(fbar, @週期名).asExternal(@週期名)
        else
          unless lastFakeBar?
            newbar = fbar.asExternal(@週期名)
            lastFakeBar = newbar
          else
            newbar = lastFakeBar.joinNew(fbar,@週期名).asExternal(@週期名)
        
        if @isTodayBar(newbar)
          @comingBar(newbar)
        else if newbar.day > lastFakeBar.day
          @comingBar(lastFakeBar)
        lastFakeBar = newbar

    update = (periodName=@週期名) => #不要帶參數
      first = @bar is null #@endIndex <= 0
      len = if first then 0 else 305
      
      # 港股用 一分鐘行情 轉換成其他小時 分鐘行情
      if periodName[..5] in ['hour','minute','second'] and @contract.exchange is 'SEHK'
        periodName = 'minute'
  
      hists {symbol:secCode, type:periodName,units:len,forex:forex}, (err,arr) =>
        if err? or ((not arr? or arr.length < 1))
          callback(first,null) # 仍需此回執,以便主程序做其他事情,如關閉過時證券窗口
          return null

        if arr?
          for bar in arr when bar?
            if bar.constructor.name is 'FakeMinuteBar'
              fakeBar(bar)
            else
              @comingBar(bar)
 
          # @quoteInfo 僅騰訊數據源有,且隨時更新,故切不可用於記憶需要記憶的屬性
          # 若其他數據源此處則可callback @bar 以呈報行情
          @quoteInfo = arr[-1..][0].qqdata?.qto # 注意此中有即時行情,故一律更新,並呈送證券窗口備用.
 
        callback(first, @quoteInfo) # 仍需此回執,以便主程序做其他事情,如關閉過時證券窗口
        return

    # 先下載初始數據,不待延時

    if @contract.exchange is 'SEHK' and @週期名 in ['minute','hour']
      p = 'fdays'
    else 
      p = null
    
    update(p) # 本來不用參數,單純為了 minute 下載更新之前,先下載 5日minute 數據而設. 更新時則不用參數

    # 然後,再定時更新
    秒 = 1000 #分鐘 = 60*秒#小時 = 60*分鐘
    # fx168, wallstreetcn 行情數據,分鐘線不是即時更新的;
    unless nowTrading(secCode)
      period = 30 * 60 * 秒
    else if 週期名 in ['minute','minute05','minute15','minute30','minute60','hour']
      period = 5 * 秒
    else
      period = 5 * 秒  # 更新日週月線
    @intervals.push(setInterval(update, period))




module.exports = {Pool,IBPool,EDPool}
