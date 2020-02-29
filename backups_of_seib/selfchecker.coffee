# [20180110] 
# 系統自我檢測法類
_ = require 'lodash'
_assert = require './devAssert'
{dev} = require './config'

class SelfCheckerBase
  @pick:(contractHelper,target)->
    switch target
      when 'Buoy' then new BuoyChecker()
      when 'Signal' then new SignalChecker()
      when 'Order' then new OrderChecker()
      else new SelfChecker()

  changed:(object)->
    _.assign(this, object)
    @_check()
    return this
  
  _check:->

class SelfChecker extends SelfCheckerBase


### [20180110]
  以下兩法,擬置於 contractHelper 法內, 方便直接報送 data
  對於不方便內涵 contractHelper 者,例如 fundTrader 則可採用 callback 或 eventemit 方式來上報到 contractHelper 中的 checker
###
class BuoyChecker extends SelfChecker

class SignalChecker extends SelfChecker
  _check:->
  
class OrderChecker extends SelfChecker

module.exports = SelfCheckerBase