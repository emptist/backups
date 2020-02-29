request = require 'requestretry'
iconv = require 'iconv-lite'
myRetryStrategy = require './myretry'

{fetchUrl} = require 'fetch'


###
http://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php
完整: /Market_Center.getHQNodeData?
簡單: /Market_Center.getHQNodeDataSimple?

/Market_Center.getHQNodeData?page=1&num=40&sort=amount&asc=0&node=hs_a&symbol=&_s_r_a=sort
/Market_Center.getFundNetCount?page=1&num=5&sort=date&asc=0&node=open_fund
/Market_Center.getHQNodeDataSimple?page=1&num=40&sort=amount&asc=0&node=lof_hq_fund&_s_r_a=sort
新浪行情數據的主要用語:
http://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/Market_Center.getHQNodes

###

qsort = (param, callback)->

  host = "http://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php"
  c = param.category ? 'sh_b'
  s = param.sort ? 'amount'
  n = param.topn ? '40'

  #針對 etf_hq_fund 的特殊處理,濾除貨幣基金:
  if c is 'etf_hq_fund'
    n += 10
    isetf = true

  options =
    url: "#{host}/Market_Center.getHQNodeDataSimple?page=1&num=#{n}&sort=#{s}&asc=0&node=#{c}&symbol=&_s_r_a=sort"
    json: false
    encoding: null
    timeout: 7000
    maxAttempts: 5  #// (default) try 5 times
    retryDelay: 1000  #// (default) wait for 5s before trying again
    retryStrategy: myRetryStrategy


  request options, (err, res, data)->
    if err?
      callback err, null

    else

      arr = null
      try
        arr = eval iconv.decode(data, 'GBK')
      catch error
        callback error, arr
        console.error 'sortsina.coffee >> qsort', error
        return

      if isetf #去掉貨幣基金,缺行情數據故
        resp = (each for each in arr when (not /^(1590|511)/.test each.code))
      else
        resp = arr

      callback err, resp

fsort = (param, callback)->

  host = "http://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php"
  c = param.category ? 'sh_b'
  s = param.sort ? 'amount'
  n = param.topn ? '40'

  #針對 etf_hq_fund 的特殊處理,濾除貨幣基金:
  if c is 'etf_hq_fund'
    n += 10
    isetf = true

  options =
    url: "#{host}/Market_Center.getHQNodeDataSimple?page=1&num=#{n}&sort=#{s}&asc=0&node=#{c}&symbol=&_s_r_a=sort"
    json: false
    encoding: null
    timeout: 7000
    maxAttempts: 5  #// (default) try 5 times
    retryDelay: 1000  #// (default) wait for 5s before trying again
    retryStrategy: myRetryStrategy


  fetchUrl options.url, {method:'GET'}, (err, meta, body)->
    if err?
      console.error("[error]sortsina >> fetchUrl:",err)
      callback err, null
    else
      arr = null
      try
        arr = data = eval(body.toString())
      catch error
        callback error, arr
        console.error 'sortsina.coffee >> qsort', error
        return

      if isetf #去掉貨幣基金,缺行情數據故
        resp = (each for each in arr when (not /^(1590|511)/.test each.code))
      else
        resp = arr

      callback err, resp



module.exports = fsort

### 在這行前面加或去一個#就可以測試,測試完記得加回去#
qsort {category:'etf_hq_fund'},(err, arr)->
  console.log arr

fsort {category:'etf_hq_fund'},(err, arr)->
  console.log arr
###
