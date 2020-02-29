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

###

assert = require './assert'
BaseDataFlow = require './dataflow_base'
CordonFlowBase = require './cordonflow'
{levelNames,bbandNames,fishMaNames,recordCordonHistory} = require './config'


class XFlowBase extends BaseDataFlow
  # select specific xflow class
  # level0-level10 最容易操作,故暫時僅採用此levels
  # cordonType: levels, bband, fish
  @pick: (contractHelper) ->
    new XLevelsFlow(contractHelper)

  constructor:(@contractHelper)->
    super(@contractHelper)
    @initCordonBuoys()

  # each sub-object can have its own method
  initCordonBuoys:->
    @cordonBuoys = CordonFlowBase.pickAllLevel(@contractHelper)

  comingBar:(bar,pool)->
    super(bar,pool)
    for key, cordonBuoy of @cordonBuoys
      cordonBuoy.comingBar(@bar,pool)
  


  # 開發工具
  __activeCordons: ->
    obj = {}
    for key, cordonBuoy of @cordonBuoys when cordonBuoy.cordon.arround(@bar)
      obj[key] = cordonBuoy
    return obj
  


class XLevelsFlow extends XFlowBase






module.exports = XFlowBase

