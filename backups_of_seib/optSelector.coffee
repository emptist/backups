###

  [todo]


  目前,此法藏在 contractHelper 中了. 
  有空時, 將其顯露於本法.以期一物一用
  此法與 contractHelper 關係為此法內含 contractHelper
  此法放置於 pool 內,獨立完成期權選擇
  其中,申請 contractDetails 的功能, 似乎是應該放置母體, 但因期權信息之申請模式不同,且後續ib版本已經分離為獨立接口,故應
  分離於此






# vscode bug: mv a file will not rm the original  
###



EventEmitter = require 'events'
moment = require 'moment-timezone'

assert = require './assert'
BaseFactors = require './basefactors'
ContractDetailsBase = require './contractDetails'
{IBCode} = require './secode'
Position = require './asecurityPosition'
{期權配資上限,usingQQData,startBar99} = require './config'



# 選擇call/put
# 期權策略思路:
#  1. 只做美股之 SPY, 不做任何其他品種;但是系統功能不作限制,以便未來經過論證十分需要時,可以隨意選品種
#  2. 只做 long 不做 short 尤其是 bare short, 為杜絕無限風險,任何 short 都不做 
#  3. 進出點: SPY 低標準差時,上穿天線買入 call ; 標準差高位回落,天線僵持賣出 call. 
# SPY 的 put 只有大熊市確立才買,另行研究策略
class OPTSelectorBase #extends EventEmitter
  @pick:(contractHelper)->
    new OPTSelector(contractHelper)

  constructor:(@contractHelper)->

  ###
    有空時,整體從 contractHelper 中搬遷過來,以便一物一用
  ###
  # 善遠離 out of the money
  # 善遠離 out of the money
  _targetOPTDefinitions: (pool)->
    # 先擴展yinfishx
    @_addExtensionToYangFishX(pool)
    pool.yangfishx.fakeBarLevels()
    expiry = @_getMonthString(@_recommendedOPTMonth())
    expiryNext = @_getMonthString(@_recommendedOPTMonth(1))
    array = [
      # 實價, 現在有利價
      #{right:'C', strikeLevel:'level0', expiry}
      #{right:'P', strikeLevel:'level10', expiry}
      # 虛價, 預期可達價
      #{right:'C', strikeLevel:'level10', expiry:expiry}
      #{right:'P', strikeLevel:'level0', expiry:expiry}
      # 虛假, 假造的level
      {right:'C', strikeLevel:'level99', expiry:expiryNext}
      {right:'P', strikeLevel:'level00', expiry:expiryNext} 
      # 仍存在bug, 以下兩項如果放在上面,則遠月就不出現,未知bug在何處
      {right:'C', strikeLevel:'level99', expiry:expiry}
      {right:'P', strikeLevel:'level00', expiry:expiry}
    ]
    # assert.log("definition: ", array)
    return array


class OPTSelector extends OPTSelectorBase


module.exports = OPTSelectorBase