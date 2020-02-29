# 將分散處理的與證券類型掛鉤的功能集中於此
{fix} = require './fix'
_assert = require './devAssert'
{baseFactors} = require './config'
{IBCode} = require './secode'
ldb = require('lowdb')

#storage = require('lowdb/lib/file-async')
#lsdb = ldb "db/dbLiveSignals.json", storage
#lsdb.defaults({liveSignals:[]}).value() unless lsdb.has('liveSignals').value()

class BaseFactors
  @pick:({secCode,timescale,contract:{secType,right}})->
    #{secType,right} = contract
    switch secType
      when 'OPT'
        switch right
          when 'C'
            return new CallOptionBaseFactors({secCode, timescale})
          when 'P'
            return new PutOptionBaseFactors({secCode, timescale})
          else
            return new OptionBaseFactors({secCode, timescale})
      when 'CASH'
        return new CashBaseFactors({secCode, timescale})
      when 'IOPT'
        switch right 
          when 'C'
            return new HKIOPTBaseFactors({secCode, timescale})
          when 'P'
            return new HKIOPTBaseFactors({secCode, timescale})
          else
            return new HKIOPTBaseFactors({secCode, timescale})
      when 'STK'
        switch  #  凡 switch 其中 when 之順序皆不可輕易更改
          when IBCode.isHuShen(secCode)
            return new AStockBaseFactors({secCode, timescale})
          when /HSI/i.test(secCode) or IBCode.isHK(secCode)
            return new HKStockBaseFactors({secCode, timescale})
          when IBCode.isABC(secCode)
            return new USStockBaseFactors({secCode, timescale})
          else
            return new CommonBaseFactors({secCode, timescale})

  # @timescale 目前沒用;
  # 但wbv_pool.coffee 設置poolOptions的代碼,似乎可以合併至此,故先保留.不合併也無妨礙,故此事優先度拍在最後
  constructor:({@secCode,@timescale})->
    @facts = new IBCode(@secCode).parameters(baseFactors)
    
  # 更新@bar備計算用
  withBar: (@bar)->
    return

  manualBuyAutoPrice: (name)->
    if /set$/i.test(name)
      @bar.close 
    else
      @向上報價()

  manualSellAutoPrice: (name)->
    if /set$/i.test(name)
      @bar.close 
    else 
      @向下報價()





class CommonBaseFactors extends BaseFactors


  向上報價: (p=@bar.close)->
    fix(p * (1+@facts.報價因子)) 
  向下報價: (p=@bar.close)->
    fix(p / (1+@facts.報價因子))

  向上容忍價: (p=@bar.close)->
    fix(p * (1+@facts.容忍因子)) 
  向下容忍價: (p=@bar.close)->
    fix(p / (1+@facts.容忍因子))

  向上極限價: (p=@bar.close)->
    fix(p * (1+@facts.極限因子)) 
  向下極限價: (p=@bar.close)->
    fix(p / (1+@facts.極限因子))



class CashBaseFactors extends CommonBaseFactors

    
class USStockBaseFactors extends CommonBaseFactors


class OptionBaseFactors extends CommonBaseFactors


class CallOptionBaseFactors extends OptionBaseFactors

class PutOptionBaseFactors extends OptionBaseFactors


# 例如香港股市品種
class PriceGradeBaseFactors extends BaseFactors  
  withBar: (@bar)->
    @calculateDeltas(@bar)

  calculateDeltas: (@bar) ->
    @facts.priceGrade = @bar.hkPriceGrade()
    @facts.容忍差價 = @facts.容忍格數 * @facts.priceGrade
    @facts.極限差價 = @facts.極限格數 * @facts.priceGrade
    @facts.報價差價 = @facts.priceGrade
  


  向上報價: (p=@bar.close)->
    fix(p + @facts.priceGrade)

  向下報價: (p=@bar.close)->
    fix(p - @facts.priceGrade)

  向上容忍價: (p=@bar.close)->
    fix(p + @facts.容忍差價)

  向下容忍價: (p=@bar.close)->
    fix(p - @facts.容忍差價)

  向上極限價: (p=@bar.close)->
    fix(p + @facts.極限差價)

  向下極限價: (p=@bar.close)->
    fix(p - @facts.極限差價)


class HKStockBaseFactors extends PriceGradeBaseFactors

class HKIOPTBaseFactors extends HKStockBaseFactors

class HKCallIOPTBaseFactors extends HKIOPTBaseFactors

class HKSellIOPTBaseFactors extends HKIOPTBaseFactors


class AStockBaseFactors extends CommonBaseFactors





module.exports = BaseFactors


