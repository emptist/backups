###
 Copyright(c) 2016- Jigme Ko <jigme1968@gmail.com>
 MIT Licensed
###
# 擬改用
# http://tradingview.fx168.com/TradingInterface/history/?symbol=JPY&resolution=1d&from=1375759065&to=1470367065
# http://tradingview.fx168.com/TradingInterface/history/?symbol=GBP&resolution=1d&from=1375759065&to=1470367065
# http://tradingview.fx168.com/TradingInterface/history/?symbol=GBP&resolution=5&from=1468708500&to=1470370685
# http://tradingview.fx168.com/TradingInterface/history/?symbol=GBP&resolution=W&from=1375762909&to=1470370909
# http://tradingview.fx168.com/TradingInterface/history/?symbol=GBP&resolution=M&from=1375763051&to=1470371051
# http://tradingview.fx168.com/TradingInterface/history/?symbol=GBP&resolution=240&from=1449637200&to=1470371116 # 4h
# http://tradingview.fx168.com/TradingInterface/history/?symbol=GBP&resolution=90&from=1462593600&to=1470371174 # 90min
# 或 華爾街新聞(與上類似)
# http://apimarkets.wallstreetcn.com/v1/tradingView/history?symbol=USDJPY&resolution=1&from=1470268800&to=1470391219
# http://apimarkets.wallstreetcn.com/v1/tradingView/history?symbol=USDJPY&resolution=5
# http://apimarkets.wallstreetcn.com/v1/tradingView/history?symbol=USDJPY&resolution=15
# http://apimarkets.wallstreetcn.com/v1/tradingView/history?symbol=USDJPY&resolution=30
# http://apimarkets.wallstreetcn.com/v1/tradingView/history?symbol=USDJPY&resolution=1h
# http://apimarkets.wallstreetcn.com/v1/tradingView/history?symbol=USDJPY&resolution=2h
# http://apimarkets.wallstreetcn.com/v1/tradingView/history?symbol=USDJPY&resolution=4h
#

# http://hq.sinajs.cn/rn=1457510432632list=fx_seurjpy,fx_sgbpjpy,fx_seurgbp,fx_seurchf,fx_shkdusd,fx_seuraud,fx_seurcad,fx_sgbpaud,fx_sgbpcad,fx_schfjpy,fx_sgbpchf,fx_scadjpy,fx_saudjpy,fx_seurnzd,fx_sgbpnzd
# http://hq.sinajs.cn/?_=0.04818517481908202&list=fx_susdcnh
# 改寫為外匯行情
{restring,recode} = require '../../secode'
request = require 'request'
iconv = require 'iconv-lite'
hqstr2obj = require './sinaticks2obj'


hqstr2objfx = (symbol,tickstr,obj)->
  c = recode(symbol, 0) #symbol[4..] # usdcnh
  #tickstr = eval("hq_str_#{symbol}")
  tick = "#{c},#{tickstr}".split(',')
  # 共有34項,最後一項不知何用
  obj[symbol] =
    symbol:tick[0]
    現: Number(tick[2])
    未知3: Number(tick[3])
    前: Number(tick[4])
    波幅: Number(tick[5])
    開: Number(tick[6])
    高: Number(tick[7]) # 賣入報價
    低: Number(tick[8]) # 賣出要價
    現: Number(tick[9])
    名稱: tick[10]
    漲幅: Number(tick[11])
    漲跌: Number(tick[12])
    振幅: Number(tick[13])
    近高: Number(tick[15])
    近低: Number(tick[16])
  obj[symbol].day = obj[symbol].時間 = new Date "#{tick[18]} #{tick[1]}"
  obj[symbol].備註 = tick[17]
  obj[symbol].報價 = tick[14]
  return obj

forex = (string, callback)->

  # reformat the codes in string argument
  codes = (recode(each,'sina') for each in string.split(',')).join(',')
  #codes = ("fx_s#{each}" for each in string.split(',')).join(',')
  obj = {}
  options =
    url:"http://hq.sinajs.cn/list=#{codes}"
    json: false
    encoding:null

  request options, (err, res, data)->
    return callback err if err
    unless err?
      text=iconv.decode(data, 'GBK')

      # TODO: 替換掉 eval
      eval(text)
      for symbol in codes.split(',')
        tickstr = eval("hq_str_#{symbol}")
        hqstr2obj(symbol,tickstr,obj)

      callback err, obj

module.exports = forex

###test
forex 'fx_susdcny,usdcnh',(e, data)->
  console.log data
###
