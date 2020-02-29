request = require 'request'
{recode,restring} = require '../../secode'
#https://www.npmjs.com/package/requestretry

### param:
      market: 默認 hs--滬深
      symbol: 代碼
      year: 年份
      type: day,week,month
###
history = (param, callback)->
  c = recode param.symbol, 6
  url = "http://img1.money.126.net/data/#{param.market}/kline/#{param.type.toLowerCase()}/history/#{param.year}/#{c}.json"
  options =
    url: url
    json: true

  request options, (err, res, json)->
    unless err?
      array2obj = (arr)->
        d = arr[0]
        時: new Date "#{d[..3]}-#{d[4..5]}-#{d[6..]}"
        開:arr[1]
        低:arr[2]
        高:arr[3]
        收:arr[4]
        量:arr[5]
        幅:arr[6]
      data = (array2obj each for each in json.data)
      json.data = data
      callback err, json

module.exports = history

### 在這行前面加或去一個#就可以測試,測試完記得加回去
history {market:'hs',symbol:'159915',year:'2016',type:'day'}, (err,json)->
  console.log json unless err?
###
