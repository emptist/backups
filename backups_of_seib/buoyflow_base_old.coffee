# 注釋詳見文末

moment = require 'moment-timezone'
BaseDataFlow = require './dataflow_base'
{IBCode} = require './secode'
{useOverlock} = require './config'
{fix} = require './fix'
assert = require './assert'


# 浮標
class BuoyFlowBase extends BaseDataFlow
  constructor:({@cordon,@tillMinute=0})->
    {
      @contractHelper,contractHelper:{@secCode,@facts,@timescale,@contract},
      buoyNamePrefix,cordonIndex,basePrice,overlockPrice,edgePrice
    } = @cordon
    
    super(@contractHelper)
    
    # 注意bestPrice和worstPrice是固定的, 在穿刺形成時即固定下來
    @bestPrice = basePrice
    @worstPrice = if useOverlock then overlockPrice else edgePrice

    @buoyName = "#{buoyNamePrefix}@#{cordonIndex}"
    @addTime = new Date().getTime()
    @buoyMessage = "#{@buoyName}: entry point emitted"

  # 此時沒有 @previousBar
  firstBar:(pool)->
    super(pool)
    @trace(pool)


  # 此時必有 @previousBar
  nextBar:(pool)->
    super(pool)
    @trace(pool) 
 
  # 策略追蹤
  trace:(pool)->
    if @_strategyFilter(pool)
      @_recordHistChartInfo(pool)
      # 注意: 如果限制 onDuty 則只有一個週期的行情會實時監控,故宜提供設置選項(config)
      if pool.onDuty and @_detectEntryPoint(pool)
        pool.signalSwim?.entryBuoy(pool,this,@buoyMessage)
        

  _recordHistChartInfo:(pool)->
    # 對於歷史數據,此處即可直接記錄其bar:
    @_recordHistChartEntry()
    # 對於符合當前 swim 方向的歷史數據,記錄偽操作信號:
    pool.currentSwimRecordHistChartSig(this)
  
  ###
    不同的策略在開發過程中,可使用 extends 方式各自新建class文件,以免混亂
    具體方法參考 buoyflow_old.coffee (對舊系統的微調銜接)
    亦可一個文件單獨寫一個這一個function,不同策略不同文件
    
    此法捕捉有策略價值的穿刺點.可將各種策略揀擇置於此法
  ###
  _strategyFilter:(pool)->
    @_cordonFitLimitation() and @cordon.arround(@bar)

  # 因應買賣方向選擇部分的cordon作為操作依據;理論上似乎可行,實際效果不佳,故備考
  _cordonFitLimitation:->
    return true

  # 此法選擇操作時機
  _detectEntryPoint:(pool)->
    assert.subJob()
    return false
  
  
  # 記錄潛在交易入口, 作為研究參考,若已經在 buoy 追蹤過程中賦值者,則不改動
  _recordHistChartEntry: ->
    # 即時行情不用此法記錄,有另外的判別記錄程序
    {latestCrossBar} = @cordon
    switch
      when @xUpLatest()
        latestCrossBar.chartBuyEntry ?= @buoyName
      when @xDownLatest()
        latestCrossBar.chartSellEntry ?= @buoyName
      else
        throw 'Error: no latest cross and this should not occur'


  
  helpRecordChartSig:(obj) ->
    return

  # 注意與 swim 方向相反相成
  xUpLatest:->
    # switch @cordonIndex
    @cordon.xUpLatest?()
  # 注意與 swim 方向相反相成
  xDownLatest:->
    @cordon.xDownLatest?()



module.exports = BuoyFlowBase







###
[原則]

  復利原則.
  寧可不賺,不可虧本
  在盈利前提下趨向高頻交易


[條件設定小結]
(20170723插補,20170805修訂):

經過一段時間的研究開發測試,總結出一些規律.記錄如下:

1.  買賣均由穿越特殊價格線觸發,在穿越bar完成後決定買賣方向,穿越後波動中捕捉更好價格,在同向運動瞬間實施開倉或止損止盈操作;
    [注釋: 例如1分鐘線,前一分鐘穿越,決定方向;排除變動中的未定情形.注意選擇所依據的行情尺寸]
2.  上述特殊價格線最好是水平線或小幅度上昇下降的準水平線,
3.  判斷上穿下穿盡量使用 > 和 <,謹慎使用 >=, <=. 因等於(=)隱含兩種可能,方向模糊易致混淆; 
    但在方向未變前提下,判斷是否觸發交易則須測試研究. >=, <= 可能適用於止盈操作,因止盈的意思是到價即交易,不管上到還是落到止盈價.
    附之前相關注釋:
      奇妙 hackSellActionPrice
      > 或  < 用於止損, 而相同的價格, >= 或 <=  即可止盈,無須另外設置

4.  buoy浮標系統設置限制價位, [worstPrice, bestPrice] 構成價格區間, bestPrice 為前bar成功穿越臨界線 的價格:
    bestPrice 在買入浮標中,指判趨勢向上的臨界線,低於此線向上趨勢不成立,雖低價卻無由買入,浮標失效刪除;賣出浮標反之.
    worstPrice 在買入浮標中,指能夠接受的最高限價;在賣出浮標中,指能接受的最低限價. 可通過 f(bestPrice, 極限差價) 設定.
5.  設置容忍差價 ignorableDelta 以過濾小幅度非轉折性行情"擾動",避免頻繁無利操作(指本系統尚無獲利保障的情形. 高頻交易本身不是問題).
6.  在容忍差價範圍內,通過價格階梯,來截斷容忍區間,觸線即交易;這些截斷限價階梯可以是重要的水平或準水平指標線,亦可為成本線,之前反向操作價等等
7.  目前已經設計好的水平或準水平指標線有:陰陽魚系統中的天地中線系列,小陰魚之level線(適合多頭操作模式,即系統主要模式).
    (小陰魚之level線適用於多頭為主的操作系統.適宜空頭操作模式的小陽魚level線設計遇到一些難題未解決,故暫缺)
8.  價格隨著水平線下行是絕對賣出條件,水平線保持水平或上昇是買入前提條件,即,水平線下跌時,若價格不向上突破之前水平,則不可買入[bar 內反轉怎麼辦? 細切行情尺寸即可,例如分鐘線] 
    [可加入的其他穿越性指標線有布林線上下中及衍生層次線,可惜不是水平線,故變動不居,不好前後比較]
9.  報價(差價),極限(差價),容忍(差價) 參考英文: asking~, utmost~, ignored/ignorable~
10. 容忍差價範圍的意義:
      止損模式下,是超過容忍區間的波動才進入監控;
      止盈模式下,則是達到容忍範圍即可以獲利了結.
    被重要價格階梯線截斷時則即刻操作,對兩種模式意義相同.故此重要價格階梯可稱為 expectedPrice(s[],一組)
11. 現有代碼仍偏重止損,應偏重止盈,才能實現高頻交易.可能需要設計出止盈機制


[止盈與止損]

首先,本系統僅選擇強趨勢的美股三大指數ETF類品種,以及短線類牛熊證品種(將來或可擴展至美股三大指數之期貨),為主要投資標的.

在此前提下:
  1.  美股三大指數ETF品種設計前提是,可假設其必定獲利,問題只是如何獲利(時間成本多大).故重點是止盈機制設計.
      美股三大指數ETF品種從根本上說是無須止損的,因其必然創新高(在未來百年內),止損僅為避免增加時間成本.故止損的出現次數
      應該很少,且僅在必須快要觸及成本的情況下,必須止損.因此,止損線不應隨意提高.很可能,根據行情結構製作的平倉系統已經預
      先賣出了. 因此,對於美股指數ETF類投資標的,止盈止損的用途主要是針對大趨勢中小波動的多次獲利,要求在盈利狀態下操作,
      回補時要求價格至少不高於止盈賣出價;若無此高頻勝算,則不交易為最佳交易操作.
      美股指數較大的止盈操作機會,出現在日線行情之天線形成若干天之後,同時此時是緩慢上昇或橫向運行於布林線上軌與中上軌之間,
      此處的布林線參數採用長線參數,即月線20m均線為中軌,日線則推算為400日均線為中軌.突然大幅回調均出現在此類情形之下.
      [以下進一步梳理美股指數思路和參數]
  2.  短線衍生產品,當止損時,已經有較大損失,故不堪反復止損,因此重點同樣是止盈機制設計.
      或者說不符合盈利預期的價格波動一律需要及時止損.已經虧損的真實止損是止盈的特例.
      因此,高風險高收益衍生品,如牛熊證,設計要點是盈利預期價格@時間,即對比 @previousBar.nextBarExpectedPrice 不及則
      止盈.
      此外,亦曾發現與牛熊證1分鐘線與美股指數月線水平的相似性,即出現天線之後若干分鐘,且價格在布林線上軌和中上軌之間運行趨緩,
      此時多轉而下跌.
      [以下進一步梳理牛熊證等衍生品思路和參數]


[以前注釋]
教訓: 
    這部分策略的開發,經歷了多次的反復,始終在一個矛盾中循環,
      思路一: 盡量減少不必要止損,做大段行情;
      思路二: 寧可不賺,不可虧本.
    因此,在嚴和寬之間反復搖擺.
終極原則: 復利原則.
  高頻交易為正道,低頻交易為錯誤.
  即使策略仍存在漏洞,做不到及時準確回補,也必須做到另外一半,就是及時準確止盈止損.其後只需加強回補功能即可.
基本要求:
  1. 盈利不能變成虧損,今天資產不能低於昨天收盤
  2. 換成技術語言就是,只要出現過 worstPrice 以上的價位,就不可以錯過, 應發出 signal,否則為跟價失敗.
  3. 虧損不能無節制擴大,只要低於砍倉線,無論跌了多少都必須先立即砍倉,哪怕砍倉點是歷史最低點也是正確的止損操作.
  4. 高頻交易,在確保盈利的前提下,頻率越高越好.永遠消除試圖減少操作次數的心理.

BuoyFlow 浮標,標記動態價格區間
  由於這是object,所以可以靈活設計變量以輔助策略實施.
  可在每次查證信號是否滿足發佈條件時,記錄有意義的價格.結合指令激發價隨觸發時價格變動,確定bor回昇或衝高回落時才買賣.
  這一塊可以深入研究.甚至形成價格階梯,涵蓋所有可能的變動.

設計思路:
一個證券可以有多種浮標,各自可設置先決條件,例如bor指標初次回昇,以及委託(上或下)限價,例如昨收盤,或等待符合條件時,用當時價位
浮標條件滿足時,隨時滿足隨時加入信號之浮標組,新來barArray經過信號發放給各浮標,浮標自動變動其三價: 委託(上或下)限價,理想價,行動價;
信號再搜索符合預定條件並且達到行動價的第一個浮標,發出信號.
信號發出後,即記錄剛才信號,並不再接受同向信號,同時產生反向的回補信號,如此循環.
其中有所變動的只是原先設計中的價格追蹤部分,新設計交給浮標來完成;以及將多個信號壓縮為一個,其中帶有浮標組.其他部分不變.

###
