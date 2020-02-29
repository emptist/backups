moment = require 'moment-timezone'
IBSignal = require './cordonsignal'
assert = require './assert'
EventEmitter = require 'events'
{dev,speakout,bestLevel} = require './config'


# 特定趨勢對應特定方向的signal,故做一個聚合法
# 注意:
#   signal 不是在任何趨勢下都一定有的,如果是不能做空的品種,在熊以及熊末兩種相位是沒有操作的,故沒有signal
#   這不是bug,只需檢查當時趨勢是什麼即可
class PairTrendSignalBase extends EventEmitter
  constructor:({@trend,@signal})->
    {@contractHelper} = @trend
    {@isUsStock} = @contractHelper

    @messageSymbol = '穿行信號'
    @tempSameDaySignals = {} # for research only

    # 將原有設計中存入其他變量的一些記錄放置於此
    @sentBuoyEntries = {} # 濃縮拷貝
    
  ###
  # 尚未肯定最終是單一signal還是一組(其中一對異類同向,一開一合)合理,故先保留兩個變量
  # @signal 
  #   1. 不做空品種,有些趨勢下沒有signal
  #   2. signal不固定,隨著趨勢變化,不可以存歷史記錄
  #   3. 所以歷史記錄需要放在本法,本法是持續的
  ###

  ### 
  在 contractHelper.forceLongClose 情形下: 
    pool 已經預先強行設置好 @trend 為 bearish
    此處進一步設置 signal 為 forced,
    OPTLongClose signal 則可自由選擇,可以僅在 forced 時才確認 sell buoy 為 justified, 亦可忽略之,一律放行
  ###
  resetSignal:(pool)->
    @signal = IBSignal.pickFor(@trend)
    if @contractHelper.forceLongClose
      @signal.setAsForced()


  comingBar:(aBar,aPool)->
    @trend.comingBar(aBar,aPool)
    @signal?.comingBar(aBar,aPool)
  

  ### 
  這是住在pool.crosses 中的 cordonBuoys 中的某個buoy通過 pool.trendflowSignal 轉發至此的消息
  
  轉一圈發過來的原因:
    1. buoy和signal非一一對應關係,buoy有可能在signal中,
    2. buoy再記憶此signal,會造成circular關係,js處理不好;
    3. 又,buoy可能先後出現在不同的signal中,故buoy不方便記憶所在的signal
    4. 但是為何 signal 要記憶buoys? 有必要嗎? 可以從pool.crosses.cordonBuoys中查找,但不方便,故記憶當時的buoys備查

  要點:
    1. 此時已知此 bar 已經觸發進出操作入口 (已經在 buoyflow 中 _recordHistChartEntry 存入 bar 用於後續繪圖研究)
    2. 此趨勢此時未必有 signal
    3. 此 signal 方向與 buoy 方向未必一致,唯有一致才通過
  ###
  entryBuoy:(pool,buoy,msg)->
    @signal?.readyToEmit(buoy,msg,(signal,order)=>
      if signal?
        @emit(@messageSymbol,{signal,order})
        @_postEmitSignal(pool,buoy,{signal,order})
      else
        assert.log("[debug]entryBuoy >> #{@signal?.constructor.name} rejected a buoy", buoy.buoyName)
    )

    
  recordHistChartSig: (pool,buoy)->
    {cordon:{latestCrossBar},actionType} = buoy
    # 限制只記錄一次
    if @signal?.justified(buoy) and (actionType isnt @_recordedActionType)
      @_recordedActionType = actionType
      @_recordChartSig(pool,buoy,true)

  # 此法必須用兩次, 其中一次是歷史行情之偽信號, 用於繪圖研究
  _recordChartSig: (pool,buoy,fake)->
    x= if fake then pool.bar.day else @signal.emitTime # or emitTimestamp? 為可讀日期
    title = if /bull/i.test(@trend.trendSymbol) then '多' else '空'
    text = "#{if fake then buoy.buoyName else @signal.orderPrice}@#{@signal.signalTag}"
    buoy.helpRecordChartSig({x,title,text})

  _postEmitSignal:(pool,buoy,{signal,order}) ->
    {buoyName,signalTag,buoyStamp} = signal
    @_recordChartSig(pool,buoy)

    # 用 buoy.sentBuoyEntry(), 其中 sentObj 製作一個copy, 見 todo.md
    @sentBuoyEntries[buoyStamp] = buoy.sentBuoyEntry()

    msg = "[_postEmitSignal]#{@trend.contractHelper.secCode}: #{@constructor.name} #{buoyStamp} #{@messageSymbol}"
    assert.log(msg)
    
    # 歷史信號目前僅作研究開發之用,不影響交易.發行版可注釋此行
    @_addHistory()
    @optsLookout(pool)
  
  # 選擇call/put
  # 期權策略思路:
  #  1. 只做美股之 SPY, 不做任何其他品種;但是系統功能不作限制,以便未來經過論證十分需要時,可以隨意選品種
  #  2. 只做 long 不做 short 尤其是 bare short, 為杜絕無限風險,任何 short 都不做 
  #  3. 進出點: SPY 低標準差時,上穿天線買入 call ; 標準差高位回落,天線僵持賣出 call. 
  # SPY 的 put 只有大熊市確立才買,另行研究策略
  optsLookout: (pool, sig=@signal)->
    unless @isUsStock
      return 

    # 已經建立另外的突破追蹤機制,以下機制可能無用,留以備考. 
    if sig.isLongOpenSignal
      @contractHelper.callOperator.lookout(pool,sig)
    else if sig.isLongCloseSignal
      @contractHelper.putOperator.lookout(pool,sig)



  #有必要嗎?
  _addHistory:->
    unless dev
      return

    {orderClassName,buoyName} = @signal
    {timescale} = @trend
    similar = @tempSameDaySignals[orderClassName]
    if similar? and moment(similar.buoys[similar.buoyName].day).isSame(@signal.buoys[buoyName].day,timescale)
      similar.privateCombine(@signal)
    else if @signal.isValidHistoricTime()
      @tempSameDaySignals[orderClassName] = @signal
    
    if @trend.isCurrentBar()
      @emit('liveSignalEmerged',@signal.historyRec())
    return


  whyNoSignal:->
    aBug = @signal?
    if @trend.isBearPhase() or @trend.isBearishPhase()
      unless @contractHelper.isShortable()
        aBug = false
    assert.log('sometimes there should not be a signal, and is this one a bug? ', aBug)


  # 記錄 orderId, 用於後續更新成交狀況對號入座
  # [bug] 此法 追蹤結果,前面的一些function參數對不上
  sentSignal:(signal, orderId)->
    {signalTag,orderClassName,buoyStamp} = signal
    @sentBuoyEntries[buoyStamp]?.orderId = orderId
  
  # 對於回補,撤單等重要
  sentOrderStatus:(order)->
    {order:{action,lmtPrice},orderStatus,orderStatus:{orderId,status,filled,avgFillPrice,lastFillPrice,remain}} = order
    assert.log @constructor.name," [ DEBUG ] 收到 orderStatus, action and status信息:", order.orderStatus, action, status

    for key, buoy of @sentBuoyEntries when buoy.orderId is orderId
      buoy.orderStatus = orderStatus
    

    # 測試結果是可以的,由於直接使用了 buoy 所有buoy引用版當然都一樣.


class PairTrendSignal extends PairTrendSignalBase




module.exports = PairTrendSignal

###
# 理論上一種趨勢不應有兩種操作方向
# 但經常趨勢定義不準,從而可能萬不得已,需要有兩個操作方向. 這時可以用以下Object,放置於 @signal 位置,並對其他功能做相應調整
class PairTrendSignalTwins extends PairTrendSignalBase
  constructor:(@trend, @signalTwins)->

class SignalTwins
  constructor:(@openSignal,@closeSignal)->
###