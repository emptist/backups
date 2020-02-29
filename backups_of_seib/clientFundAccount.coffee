###

  南無本師釋迦牟尼佛
  南無阿彌陀佛
  南無文殊師利菩薩
  南無普賢菩薩
  南無觀世音菩薩
  南無大勢至菩薩
  南無地藏王菩薩摩訶薩

  由見說何法 智說成無上 勝者見緣起 垂教我敬禮

  諸佛正法賢聖僧 直至菩提永皈依 我以所修諸善根 為利眾生願成佛

###

### 
本文件最初設計為從屬於 clientAccount
[20171225新思路] 
  在 contractHelper 內克隆一份本法,即可將指令生成全部任務移動到證券線程內部,
  由於僅投資於一兩個指數品種,故此方案合理
###

assert = require '../assert'
{IBCode} = require '../secode'
util = require('util')
_ = require('lodash')

OrderManager = require '../plot'
{IBCapital} = require './clientFundAccountCapital'
{分倉資金量,percentLimitOPT,percentLimitIOPT,safetyLevel,useFundAccountTrader} = require '../config'


###
  單幣種fundAccount
  承擔賬戶水平的風險控制,策略體系中的保本策略,在此定義.
  1. 單品種虧損達到設定程度則予以止損
  2. 單品倉位比重控制,風險品種限倉比例隨著bor值而變動,呈現反比例關係

  原則:
    保本策略取象秋冬,肅殺收藏,務求滴水不漏,保住本金.因此除了在確保最後防線的前提下,盡可能賺回
    手續費以外,不求盈利擴張.保證在買入正確,有所盈利的情況下,不會轉勝為敗,任意反復,均全身而退.

  注意:
    為力求簡潔,fundAccount將完全不理會投資組合,而只見個別品種.針對賬戶主人定義的品種風險程度,和他
    對風險管理的配置要求,給不同的單個品種制定限額,並確定持股分散度的上下限.下限是指如果僅持有一
    個品種,最多能允許多高比重.上限是指,最多可以同時持有多少不同的品種.
    因此,賬戶分散投資設定,可能修改證券自身產生的權重.實際權重是兩股力量的合力形成的.

    # 在此處根據風險偏好,設定倉位控制參數,實現槓桿管理的機制
    # 槓桿管理在其他注釋中沒有提到,請注意.

###


###
  容易混淆的objects:
    通過fundAccount查詢到的aSecurityPosition,也可以稱為證券品種,跟 security 證券系統中的證券,是兩碼事.通過
    查賬,得不到那個完整的證券object,因此需要命名為aSecurityPosition,以便與證券相互區別.兩者所知是不同的.
    aSecurityPosition所知,附錄於後.
    系統存在這個gap.兩個東西不一樣,不要弄混淆了.
    這也是合理的,因為fundAccount完全不需要知道證券系統中證券所知道的那些知識,就可以自我管理,實時止
    盈止損保本操作了.
    因此不必去整合.
###
class FundAccount
  constructor:(@賬號)->
    @fundPortfolio = {}
    @資產 = new IBCapital(@賬號)  # 此處似應保留,因早前嘗試過單列賬戶窗口,而彼設計用到此法,勿破壞此機制

  reviewPosition: (aPosition)->
    {secCode, position, 證券市值} = aPosition
    # 此時可能還沒有生成 positionData
    if position? and (Number(position) isnt 0 or 證券市值 isnt 0)
      @fundPortfolio[secCode] = aPosition
    else if @fundPortfolio[secCode]?
      #@fundPortfolio[secCode] = aPosition
      delete(@fundPortfolio[secCode])
    # 將用於主副線程間傳遞,因分散出去的賬戶無由得知總體信息故
    return @fundPortfolio

  # 更新記錄, 糾正外匯信息: 成本價,positionData
  記錄資產:(value)->
    @newCapitalValue = value
    @資產.renew(value)
    #util.log "[debug]IBCapital >> renew", @資產




class IBFundAccount extends FundAccount


class FundAccountTrader extends FundAccount
  constructor:(@賬號)->
    super(@賬號)
    
    # 分類資產比重之和若大於1則表示允許槓桿
    # 而證券品種是否允許槓桿,則由策略(在證券中?)限定(妥當否?)
    #@單品倉位上限 = 32 / 100 #單個aSecurityPosition上限
    # 最多可占多少實際資產比重,注意如果超過1,則表示帶有槓桿!
    @總倉位上限 = 95 / 100   
    # 此數字無用,因只需控制港幣數額即可
    @percentLimitIOPT = percentLimitIOPT
    @percentLimitOPT = percentLimitOPT
    @低風險總比例上限 = 95 / 100
    assert(@總倉位上限 * @低風險總比例上限 * percentLimitIOPT * percentLimitOPT < 1, '倉位比重控制參數出錯')
    @不得融資 = true # 我們不融資
    @orderManager = new OrderManager()

  # 通過此法將本地 fundPortfolio 中的 secPosition 與 contractHelper 中的同化為一
  resetPortfolioFor:(portfolio,secPosition)->
    if portfolio?
      @fundPortfolio = {}
      for code, jsonPosition of portfolio when jsonPosition.position isnt 0
        @fundPortfolio[code] = jsonPosition
    unless secPosition?
      return
    {secCode} = secPosition
    # 有可能本證券並無持倉
    @reviewPosition(secPosition)


  最小分倉資金量: ->
    a = 分倉資金量[@資產.幣名]
    if not a?
      throw "未知貨幣#{@資產.幣名}"
    else
      return a






  _numberOfSecsInclude:(secCode=null) ->
    # 由於 portfolio 內可能包含一個 cash position, 故需要檢測是否有此項目,以便調整 len
    len = _.keys(@fundPortfolio).length
    switch
      when not secCode? then len
      when @fundPortfolio[secCode]? then len
      else len + 1

  # 處理來自系統的策略信號(不含賬戶層次的保 本 信 號)
  # 要點: 計算出倉位變動比率,再決定加倉或減倉
  securitySysSignal:(secSignal, callback)->
    unless secSignal?
      return
    secSignal.checker = "#{@constructor.name} securitySysSignal"

    {checker,secCode,buoyStamp} = secSignal
    assert.log("[debug]securitySysSignal >> secSignal.checker:", checker, secCode, buoyStamp)
    # 處理非外匯品種新開倉
    # 若系外匯開倉則已在 clientAccount 中處理, 不會來到此地
    unless secSignal.isOpenSignal  # 非真正新開倉
      msg = "Rejected: the signal is not open signal"
      callback(null, msg)
      return 
    if (@品種數量上限() >= @_numberOfSecsInclude(secCode))
      @openPosition(secSignal, callback)
    else
      msg = "Rejected: existing securities reach max number limit" # 持倉品種數量超出限量
      callback(null,msg)

  openPosition:(secSignal,callback)->
    {buoyStamp,contractHelper,contract,orderPrice,plannedPositionChange,secCode} = secSignal
    #{isShortable, contract,quoteInfo:{每手},secPosition:{positionData}} = contractHelper
    secSignal.checker = "#{@constructor.name} openPosition"
    assert.log("[debug]openPosition >> secSignal.checker:",secSignal.checker,secCode,buoyStamp)

    if plannedPositionChange > 1 and @不得融資
      plannedPositionChange = 1
    
    if plannedPositionChange <= 1 #or not @不得融資

      # $>>> contractHelper fundAvailabe    
      # 分戶倉位須增減比例和委託金額理論上只需計算一次,但實際操作,會有零頭,價格變動,應該每次重算
      equally = true
      amntAvailabe = @freeStake(contract,equally)
      unless amntAvailabe?
        return callback(null,'Rejected: stake left undefined')
      money = Number(@資產.可用餘額)
      if money <= 0
        return callback(null,"Rejected since no money left: #{money}")
      fundAvailabe = Math.min(plannedPositionChange * amntAvailabe, money)
      if fundAvailabe <= 0
        return callback(null,"Rejected since max fund is #{money}")
      multi = if contract.secType is 'OPT' then Number(contract.multiplier) else 1
      volChange = fundAvailabe / (multi * orderPrice)
      # $>>> end

      if volChange <= 0
        util.log("[debug] here is a problem, volChange < 0: ",volChange,secCode)
        debugger
        return callback(null,"Rejected: volChange is 0")
      
      指令 = @orderManager.orderRefer(secSignal)
      指令.vol ?= ~~volChange # 分批股數
      return callback(指令)

  __testAll:(contract,equally=true)->
    freeStake: @freeStake(contract,equally)
    fullStake: @fullStake(contract,equally)
    求市值: @求市值(contract.secCode)
    可用餘額: @資產.可用餘額
    maxAmountNow: @maxAmountNow(contract,equally)
    求資產總額: @求資產總額()
    barrier: safetyLevel[contract.currency]
    money: @求資產總額() - safetyLevel[contract.currency]
    求同級總倉上限: @求同級總倉上限(contract)
    求額度上限: @求額度上限(contract,equally)
    總淨值: @資產.總淨值
    求極限比重: @求極限比重(contract)
    為高風險: @為高風險(contract)
    應分倉: @應分倉()
    最小分倉資金量: @最小分倉資金量()
    品種數量上限: @品種數量上限()
    均攤分母: if @為高風險(contract) then @_numberOfHighRisksInclude(contract.secCode) else @_numberOfLowRisksInclude(contract.secCode)


  # 該單品配資餘額
  freeStake:(contract,equally=true)->
    assert(contract, 'no contract')
    # 資金管理應可分配的餘額,但可能因為行情變化,或其他品種佔用而不足此數
    remainingStake = @fullStake(contract,equally) - @求市值(contract.secCode)
    Math.min(remainingStake, @資產.可用餘額)
  求市值:(secCode)->
    @fundPortfolio[secCode]?.證券市值 ? 0 #HoldingValue

  # 該單品配資上限
  fullStake:(contract, equally=true)->
    assert(contract, 'no contract')  
    money = @求資產總額()
    if contract.secType in ['OPT','IOPT']
      barrier = safetyLevel[contract.currency]
      assert(barrier, 'no safety level defined')
      money = money - barrier
    #return money * @求同級總倉上限(contract) * @求額度上限(contract, equally)
    @whatisthis = money * @求同級總倉上限(contract)
    return money * @求額度上限(contract, equally)

  求資產總額: ->
    @資產.總淨值

  求同級總倉上限:(contract)->
    {secType} = contract
    switch secType
      when 'OPT' then @總倉位上限 * @percentLimitOPT
      when 'IOPT' then @總倉位上限 * @percentLimitIOPT
      else
        @總倉位上限 * @低風險總比例上限

  求額度上限:(contract,equally=true)->
    if equally then @求均攤比重(contract) else @求極限比重(contract)


  求極限比重:(contract)->
    if @為高風險(contract) and @應分倉()
      50 / 100
    else
      100 / 100

  為高風險:(contract)->
    contract.secType in ['OPT','IOPT']

  應分倉: ->
    @求資產總額() > @最小分倉資金量()

  求均攤比重:(contract)->
    {secCode} = contract
    counts = if @為高風險(contract) then @_numberOfHighRisksInclude(secCode) else @_numberOfLowRisksInclude(secCode)
    1 / counts 

  _numberOfHighRisksInclude:(secCode) ->
    # 由於 portfolio 內可能包含一個 cash position, 故需要檢測是否有此項目,以便調整 len
    codes = (code for code, jsonPosition of @fundPortfolio when @為高風險(jsonPosition.contract))
    len = codes.length
    if secCode in codes
      len 
    else 
      len + 1
  
  _numberOfLowRisksInclude:(secCode) ->
    # 由於 portfolio 內可能包含一個 cash position, 故需要檢測是否有此項目,以便調整 len
    codes = (code for code, jsonPosition of @fundPortfolio when not @為高風險(jsonPosition.contract))
    len = codes.length
    if secCode in codes
      len 
    else 
      len + 1


  # 每個資金單位最少1萬,但是可以人工設置|@我品種數量上限|這個變量
  品種數量上限: ->
    @我品種數量上限 ?= Math.max(2,(@求資產總額() / @最小分倉資金量()))











# 新系統:
# 思路是拆分 fundAccount 功能為兩大類
#   1. 基本信息更新維護,放置於main process, 向各證券窗口推送信息
#   2. 交易計算功能,放置於contractHelper.secPosition,直接在證券窗口完成最終下單指令,不再需要在main process完成
class IBFundAccountTrader extends FundAccountTrader
  # $<<< IBAccount, 第二參數改成 secPosition
  # 無論之前,只要是開倉信號,就給開標準倉; 除非已同向持,且數量超過標準
  forexOpenSignal: (secSignal, secPosition, callback)->
    {isLongSignal, isCloseSignal, secCode} = secSignal
    {isLongPosition} = secPosition
    # 唯一例外: 原有同向倉位,且量 >= 標準倉位
    加倉 = isLongPosition? and isLongSignal
    unless 加倉 and @資產.餘額過標()
      openForexPosition = (secSignal,callback)->
        order = @orderManager.orderRefer(secSignal)
        vol = if isCloseSignal
            Math.abs(secPosition.positionData)
          else
            volBaseInUSD

        order.vol = Math.max(volBaseInUSD, (order.vol ? vol))
       
        callback(order) if order.vol >= volBaseInUSD

      secSignal.checker = "#{@constructor.name} forexOpenSignal"
      openForexPosition(secSignal,callback)

  





module.exports = {IBFundAccount,IBFundAccountTrader}
