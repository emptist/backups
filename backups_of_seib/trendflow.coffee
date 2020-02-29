assert = require './assert'
BaseDataFlow = require './dataflow_base'
PairTrendSingal = require './pair_trendsignal'
{fix} = require './fix'

###
# 牛,似牛(熊中見牛),熊,似熊(牛中見熊), 暗合陰陽太極之意
# 作用: 根據其他Flow提供的分析結果,判斷4種趨勢,Bull,Bear,BullTail,BearTail,分別對應於相應的signal
# [追記: 經研究,發現了 breakthrough 和 swim 兩類法的存在, 並發現以之為趨勢判斷甚好] 
# [追記: 經嘗試,發現 trendflow 應該記錄所依據的 trendCheckers 隨之設定 trendsymbol, 否則需要設置n套方法,對應不同的依據]
參考 swimflow.coffee:
  相應英文名: start(Bar) --- pause(Bar) --- restart(Bar) --- end(Bar)
  配以方向之上落 up/down 形成趨勢: 
  ---> bull(up start) --- bullish(up pause) --- bull(up restart) --- bearish(up end) ---> 牛熊兩種可能
  ---> bear(down start) --- bearish(down pause) --- bear(down restart) --- bullish(down end) ---> 牛熊兩種可能
  其中對應 最佳開倉點 --- 止盈平倉點 --- 重返開倉點 --- 止盈平倉點 --- .... --- 最佳清倉點

###



class TrendFlowBase extends BaseDataFlow
  # trendCheckers 如 目前設計為 breakthrough
  # 均線在系統中的作用也就是判斷一下牛熊而已,故可從pool中遷移至此法內計算,而不必計算太多的均線
  @pick: (contractHelper)->
    {contract:{secType}} = contractHelper
    assert(secType, 'wrong, no sec type')
    switch secType
      when 'IOPT'
        trend = new IOPTTrendFlow(contractHelper)
      else
        trend = new TrendFlow(contractHelper)    
    return new PairTrendSingal({trend})



  constructor: (@contractHelper)->
    super(@contractHelper)
    @trendSymbol = null
  

  firstBar:(pool)->
    super(pool)

  # 此時實則未知趨勢如何,bar 未完成故, 暫且沿用前一 bar 趨勢為趨勢
  nextBar:(pool)->
    @bar.chartTrend ?= @_chartTrend[@trendSymbol]

  isBullPhase:->
    @trendSymbol is 'bull'
  isBullishPhase:->
    @trendSymbol is 'bullish'
  isBearPhase:->
    @trendSymbol is 'bear'
  isBearishPhase:->
    @trendSymbol is 'bearish'




  _chartTrend:
    bull: 1
    bear: -1
    bullish: 0.3
    bearish: -0.3


    
  # 若存在bar,則定義有缺漏
  _debugTrends:->
    (bar for bar in @barArray when not bar.chartTrend?)




class TrendFlow extends TrendFlowBase


class IOPTTrendFlow extends TrendFlow


              

class TrendFlowBackup extends TrendFlowBase
  # 勿刪除, 以防 breakthrough 或需要融入以下思路 
  ###舊注
  # @bar.chartTrend 純用作繪圖,其他地方切勿引用
  # 注意: 
  # 為何不可以將isBull等定義寫入pool,而在此引用?
  # 因為pool所有功能已經完成,不應該再隨便添加只為此法私用的function,造成系統永無一個部件已經完成,並且今後如果不再使用本法,要去系統各處刪除廢棄的function
  # 總之,一法一用.不改舊法.自力更生,互補影響.此為大量浪費時間之後才獲得的教訓.
  # 原則是,不要污染系統,不要改別人的東西.
  # 有兩種寫法,其中用prototype的仍然會污染系統,雖然不污染文件,但污染運行時的內存,可能與其他模塊命名衝突,見README.md
  # ------------------------------------------------------------------------------------------------------
  #
  # 以下思路正確,待逐步完善形成定稿
  # 牛,似牛(熊中見牛),熊,似熊(牛中見熊)
  ###
  __detectTrend_old_verion__:(pool)->
    {yinfishx,yangfishx,yinfishy,yangfishy} = pool
    #@_detectTrend_v01(pool)
    # 先粗後細,先定大體牛熊,再找出似牛似熊,其餘即純牛熊
    # 根據 fishx 陰陽魚先後定牛熊大體
    aSymbol = switch
      when yinfishx.startBar.isBefore(yangfishx.startBar)
        #大體為熊
        switch
          when yangfishx.size > 2 
            if yinfishy.size < 2 then 'bullish'
            else
              'bearish' #bear ?
          else 
            'bear'
      else
        #大體為牛
        switch
          when yinfishx.size > 2
            if (yangfishy.size > 2) and (Math.min(yinfishy.size, yinfishx.size) < 3) then 'bullish'
            else
              'bearish'
          else
            'bull'
  ###  
          #when Math.max(yinfishx.size, yinfishy.size) > 4 then 'bearish'
          #when yinfishy.startBar.isBefore(yangfishy.startBar) then 'bearish'
  ###




module.exports = TrendFlowBase