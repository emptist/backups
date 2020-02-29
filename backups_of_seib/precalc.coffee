  # 這種寫法完全錯誤,Smalltalk oop 才方便理解和維護
  # 先分牛熊,後定進出;牛熊宜寬,進出須嚴
  #   陰短陽長,名之為牛
  #   越於常軌,而有進出
  preCalc: (pool)->
    # score 過濾時,須注意區分陽線陰線,以及頂部底部
    {bor,ta,deltar,open,high,low,close,bax,tax,taz,hirx,lorx,ratio,rma,openscore,closescore,highscore,lowscore,ma_price10,ma_price150} = @bar
    {@ratioMaTBF,@longMaTBF,@shortMaTBF,ratioTBF:{yangfishz,yinfishz},yinfish,yinfishx,yinfishy,yangfish,yangfishx,yangfishy,secPosition} = pool
    {yinfishzm,yangfishzm} = @ratioMaTBF
    {yinfishLongMa} = @longMaTBF
    {yinfishShortMa} = @shortMaTBF

    secPosition?.facts = @facts

    pre = @previousBar
    ear = @earlierBar
    yinfishsize = yinfish.size()
    yinfishxsize = yinfishx.size()
    yinfishcorner = (yinfish.cornerDistance()> 30) and (yinfish.cornerBar.lowscore < 2) 
    yangfishxfilter = (yangfishx.size() > 1) and yangfishx.startBar.highscore < 5
    scoreBottom = yinfishcorner and yangfishxfilter # 用了1個小時時間,才找出來這些邏輯關係

    if false  # 貌似簡單,實在複雜,不要弄了,以後讓機器學習
      scoreBull = scoreBottom or (lowscore is 9)

    # 邏輯有誤,參考下面 longMaUnderLowScore
    longMaOnHighScore = ma_price150 > @score8
    longMaOnHighScoreFilter = (yinfishy.startBar.ma_price150 <= yinfishy.startBar.score8)
    shortMaOnHighScore = ma_price10 > @score9
    shortMaOnHighScoreFilter = (yinfishy.startBar.ma_price10 <= yinfishy.startBar.score9)
    maOnHighScore = (longMaOnHighScore and longMaOnHighScoreFilter) or (shortMaOnHighScore and shortMaOnHighScoreFilter)
    

    # 牛熊分段要寬,以便進出操作區段完整, 在此基礎上再提煉精華    
    yinfishBull = yinfish.isBull(3)
    yinfishxBull = yinfishx.isBull(3)
    fishBull = yinfishBull or (tax > ta and yinfishxBull)
    #longMaUp = @longMaTBF.botDistance() >= longMaUpConfirmDays
    #shortMaUp = @shortMaTBF.botDistance() >= shortMaUpConfirmDays
    ratioMaUp = @ratioMaTBF.botDistance() >= shortMaUpConfirmDays #rma > prev.rma and ratio >= rma
    
    yinfishShortMaBull = yinfishShortMa.isBull(maTolerableDays) and tax > ta   # 直線上漲,無須賣出段
    yinfishLongMaBull = yinfishLongMa.isBull(maTolerableDays) # 長均須除險
    
    # 因為要補齊陰極養生的初升段,並且未找到直截了當的規則,故代碼變得複雜(且仍混雜不合格的小反彈行情),若放棄這部分,則以下多行代碼都不需要
    yinfishzBull = yinfishz.isBull(5) or yinfishzm.isBull(maTolerableDays)
    yinfishzRewarmBase = (not yangfishz.retrograde) and (yangfishz.size() > rewarmConfirmDays)
    yinfishzRewarmPart1 = yinfishzRewarmBase and (yinfishz.size() > yangfishz.size() > rewarmConfirmDays)# and (rma < 0)
    yinfishzRewarmPart2 = yinfishzRewarmBase and (yinfishShortMaBull or yinfishzBull)
    # 尚需排除一路下跌,並將持續情形
    yinfishzRewarm =  (not yinfishLongMaBull) and (yinfishzRewarmPart1 or yinfishzRewarmPart2) and (not longMaUnderLowScore)
    longMaUnderLowScore = (yangfishy.maDown('ma_price150') and (yangfishy.startBar.ma_price150 < yangfishy.startBar.score2))
    #shortMaUnderLowScore = (ma_price10 < yangfishy.startBar.ma_price10 < yangfishy.startBar.score2)
    #maUnderLowScore = longMaUnderLowScore or shortMaUnderLowScore

    #isBull = (yinfishBull or yinfishxBull or yinfishzBull or yinfishMaBullOrRewarm or yinfishShortMaBull)
    isBull = (yinfishLongMaBull or yinfishShortMaBull or yinfishzRewarm or longMaOnHighScore) and ((not longMaUnderLowScore) or yinfishsize < 2) 
    
    mostStrict = true
    if mostStrict # 臨時加強設置
      isBull = ma_price10 > ear.ma_price10 and high > ma_price10 and isBull
    
    # 如需通過日線以上行情確定多空,則去掉下2行注釋
    #minsec = /^minu|^secon/i.test(@週期名)
    #if minsec then isBull = pool.isBull
    
    setBear = (aBoolean)=>
      if @isBear isnt aBoolean
        # 這裡可以做一些事情.然後:
        @isBear = aBoolean
      return @isBear 

    setBull = (aBoolean)=>
      # 如需通過日線以上行情確定多空,則去掉下行注釋
      #unless minsec then pool.setBull(aBoolean) # 暫時無暇整體移至 pool,先湊合一下

      if @isBull isnt aBoolean
        # 這裡可以做一些事情,然後:
        @isBull = aBoolean
        setBear(not aBoolean)
      return @isBull
    

    @guardian?.isBull = setBull(isBull)
    @guardian?.isBear = setBear(not @isBull)
    

    predlt = pre.deltar
    #@prmaUp = (ma_price10 > ear.ma_price10) or (rma > ear.rma)
    uponMa = close > ma_price10 > low*0.994 or close > ma_price150 > low*0.994
    @notNewLow = ((yangfishy.size() > 1) and (yangfishz.size() > 1)) or (close > open) or uponMa #low isnt bax
    dropEnd = @notNewLow or ratioMaUp or (deltar > 0)
    @longPointBor雙底 = (0 > bor) and (pre.bor > bor > ear.bor) and dropEnd
   
    @borTurnUp = @bor值初回昇(pool)
    dltRise = pool.ratio.deltarBottomUp
    buyEntry = dltRise or @borTurnUp
    basicLong = buyEntry and @notNewLow

    lowscoreDrop = lowscore < pre.lowscore or pre.lowscore < ear.lowscore # 越級或降級都可以
    highscoreDrop = highscore < pre.highscore or pre.highscore < ear.highscore
    scoreDrop = lowscoreDrop or highscoreDrop    
    # 還可以限制到 陽魚頭或低於地均的bar
    selectedLong = basicLong and (scoreDrop or lowscore < 2)# and ((lowscore < 10) or yinfishxsize is 1)  # 僅剩部分 newlow 需要去掉,需要對 @notNewLow 加以限制
    @mayOpenLong = selectedLong  and pool.yangfishy.amountOfClosedBars < 5
   
    strictbuyEntry = dltRise and @borTurnUp
    strictBasicLong = strictbuyEntry and @notNewLow
    strictSelectedLong = strictBasicLong and (scoreDrop or lowscore < 2)
    #@mayOpenLong = strictSelectedLong  #selectedLong #basicLong#

    #else if @isBear
    
    @mayCloseLong = not @todayBar or (secPosition? and secPosition.bigLongPosition() and secPosition.成本價?)
    @guardian?.mayCloseLong = @mayCloseLong
    # 非常有效的主段過濾器
    mainFilter = rma <= pre.rma or (taz > zeroLevel and yinfishz.size()>3 and yinfishz.startBar.date > yangfishz.startBar.date) # 非常有效的主段過濾器
    ratioOnRma = ratio >= rma

    lowOnMa10 = low > ma_price10
    highOnMa10 = high > ma_price10 
    highOnRiskLine = (highscore > 9) or (lowscore > 9)# and (close > @score9)
    hirxDrop = (ear.hirx > 0 or pre.hirx > 0) and (pre.hirx > hirx * (1 + 1 / 100))
    lorxDrop = (ear.lorx > 0 or pre.lorx > 0) and (pre.lorx > lorx * (1 + 1 / 100))
    yinfishxHead = (4 > yinfishxsize > 1 or (yinfishxsize is 1 and open > close and highscore > 9)) and not yinfishx.retrograde
    longRiskPiece = yinfishxHead #or shortMaOnHighScore # 後者無大用
    dltDrop = (ear.deltar > 0 or predlt >= 0) and (predlt > deltar * (1 + 1 / 100))
    baseCloseLong = longRiskPiece and (dltDrop or (highscore > 9 and (hirxDrop or lorxDrop))) and (lowscore < 8 or highOnRiskLine) and highOnMa10# false #testonly
    @shouldCloseLong = @mayCloseLong and baseCloseLong #and maOnHighScore# and mainFilter and ratioOnRma

    #filter = close < duePrice and bor > 0
    @mayOpenShort = @shouldCloseLong  and pool.sellFilter() #or (high >= tax)

    @mayCloseShort = not @todayBar or (secPosition? and secPosition.bigShortPosition() and secPosition.成本價?)
    @guardian?.mayCloseShort = @mayCloseShort
    dltRise = deltar > pre.deltar and 0 > pre.deltar
    filter = (ratio >= rma or (ma_price150 > pre.ma_price150 and (0.05 > ratio > 0 or low < ma_price150)))
    
    @shouldCloseShort = @mayCloseShort and @notNewLow and dltRise and pool.buyFilter()
    @lorxTurnDown = lorxDrop and (ear.lorx < pre.lorx) # and (pre.lorx >= @lorx臨界線)
   