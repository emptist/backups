# https://github.com/hakanensari/fixer-io

request = require 'requestretry'
myRetryStrategy = require './myretry'


### param:
symbol: usdjpy 之類
interval: 沒用
validRanges:
 [ '1d',
   '5d',
   '1mo',
   '3mo',
   '6mo',
   '1y',
   '2y',
   '5y',
   '10y',
   'ytd',
   'max' ]

   這個api會自動跳轉數據間隔,所以下載到的數據不確定是小時/日/週/月數據
###
n = 3
history = (param, callback)->
  if param.symbol.length < 5
    return callback '代碼不對',null

  # 這是在 requestretry之外的
  徹底重連重下 = (err)->
    if n > 0
      n--
      console.error "#{param.symbol} jsonsina.coffee >> history 將重試: ", err
      history(param, callback)
    else
      callback "#{param.symbol} jsonsina >> history 已多次重試: #{err}",null

  # encodeURI see yqldata.coffee
  url = "https://finance-yql.media.yahoo.com/v7/finance/chart/#{param.symbol.toUpperCase()}=X?range=#{param.range}&interval={param.interval}&indicators=quote&includeTimestamps=true&includePrePost=true&events=div%7Csplit%7Cearn&corsDomain=finance.yahoo.com"


  options =
    url: url
    json: true
    timeout: 9000
    maxAttempts: 9  #// (default) try 9 times
    retryDelay: 1000  #// (default) wait for 5s before trying again
    retryStrategy: myRetryStrategy

  request options, (error, res, json)->


    if error?
      return 徹底重連重下(error)
    else
      if json.error?
        return 徹底重連重下(error)

      if res?.attempts > 1
        console.log(param.symbol,'數據請求次數: ', res.attempts)

      obj = {}
      for each in json.chart.result
        for k, v of each
          obj[k] = v
      obj.timestamp = ((1000 * each) for each in obj.timestamp)
      for each in obj.indicators.quote
        obj[k] = v for k, v  of each
      delete obj.indicators

      callback null, obj

convertyahoo = (yo)->
  keys = [
    'timestamp'
    'open'
    'high'
    'low'
    'close'
    'volume'
    ]
  arr = []
  l = yo.timestamp.length
  while l > 0
    obj = {}
    for key in keys
      obj[key] = yo[key].shift()
    arr.push obj
    l--

  return arr

module.exports =
  yahooforex: history
  convertyahoo: convertyahoo

#在下行前面加或去一個#就可以測試,測試完記得加回去
###
history {symbol:'JPYUSD',range:'max'},(err, obj)->
  console.log err,  convertyahoo obj
###
