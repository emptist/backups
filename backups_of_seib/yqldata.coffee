# https://developer.yahoo.com/yql/guide/yql-code-examples.html#yql_javascript
# {fetchUrl, fetchStream,CookieJar} = require 'fetch'

{fetchUrl} = require 'fetch'
moment = require 'moment'

# todo: 使用雅虎給的授權,可以多查一些數據
clientId = "dj0yJmk9SUMwMVRMVVVKWWdMJmQ9WVdrOVVqaFNUMjQzTTJNbWNHbzlNQS0tJnM9Y29uc3VtZXJzZWNyZXQmeD02YQ--"
clientSec = "0f5e889c5de80669e9f35faae90aea2d777e33fe"

options =
  method: 'GET'

h = "https://query.yahooapis.com/v1/public/yql?"
f = "&format=json&diagnostics=true&env=store://datatables.org/alltableswithkeys"


# 似乎只能取500個交易日,超過需要分解
historicaldata = (param, callback)->
  {symbol, units} = param
  us = symbol.toUpperCase()
  # 經研究,雅虎不太支持usdjpy這樣的查詢,而是用jpy=x這樣的奇怪方式
  # 注意雙引號中的單引號是必須的
  if /^USD[A-Z]{2}/i.test us
    s = "'#{us[3..]}=X'" # 注意雙引號中的單引號是必須的
  else
    s = "'#{us}'" # 注意雙引號中的單引號是必須的


  n = Math.min(500, (units ? 500))
  if n is 0 then n = 500

  # 注意雙引號中的單引號是必須的
  end = "'#{moment().format('YYYY-MM-DD')}'" # 注意雙引號中的單引號是必須的
  start = "'#{moment().subtract(n, 'days').format('YYYY-MM-DD')}'" # 注意雙引號中的單引號是必須的

  # 在長長長長長長的代碼中,可以用反斜杠臨時換行,方便閱讀,
  # 而coffee將會當成無換行的連著的長長長長長的同一行文字,
  # 但是如果反斜杠後面緊跟其他字符,有可能是轉義字符,即保留特殊字符原意,不加以轉換的意思
  # 所以.....以下幾行coffee看成是一行
  q = "q=select * from yahoo.finance.historicaldata \
  where symbol=#{s} and startDate=#{start} and endDate=#{end} \
  | sort(field='Date', descending='false')"

  #s = ' | sort(field="Date", descending="false")'

  url = encodeURI("#{h}#{q}#{f}")

  fetchUrl url, options, (err,meta, body) ->
    if err
      console.error "yqldata >> ", err
      callback err, meta, null
    else
      try
        er = null

        calc = (each)->
          o = {}
          for k, v of each when not /Symbol/i.test k
            o[k.toLowerCase()] = if /Date/i.test k then v else Number(v)
          o.day = new Date o.date

          
          return o

        arr = JSON.parse(body).query.results.quote.map((p)-> calc(p))

      catch error
        er = "yqldata >> calc #{each.Symbol}: #{error}"

      callback er, arr, meta





tickdata = (string,callback)->
  # 去空格,加引號
  symbols = "(\"#{string.replace(/\s/g,'').replace(/\,/g,'\", \"')}\")"

  q = "q=select * from yahoo.finance.quote where symbol in #{symbols}"

  url = encodeURI("#{h}#{q}#{f}")

  fetchUrl url, options, (err,meta, body) ->
    if err
      console.error "yqldata >> #{symbol}:", err
      callback err, null, meta
    else
      callback null, JSON.parse(body).query.results, meta





module.exports =
  histy: historicaldata
  ticky: tickdata

###
historicaldata {symbol:'ibm', units: 30}, (err, arr, meta)->
  console.log err, arr#, meta
###
###
tickdata 'IBM,AAPL', (err, data)->console.log err, data
###
