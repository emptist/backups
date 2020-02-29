# 數據源分析
# use chrome 訪問 www.investing.com devtools>>network, filter: paramCode
# request header 等資料可用chrome 以上方式查看到,不在此複製了
# cfd realtime
#https://tvc4.forexpros.com/59e52a82492301bee610145dc0cfbbe2/1489092957/1/1/8/history?symbol=8984&resolution=15&from=1487796971&to=1489093032
#https://tvc4.forexpros.com/59e52a82492301bee610145dc0cfbbe2/1489092957/1/1/8/quotes?symbols=8984%2C%20%3AHK50
#https://tvc4.forexpros.com/59e52a82492301bee610145dc0cfbbe2/1489092957/1/1/8/symbols?symbol=%20%3AHK50
#https://tvc4.forexpros.com/50f600ed539e4196f5340b3166b358c2/1489094530/1/1/8/history?symbol=8984&resolution=1&from=1489009234&to=1489095694
# hong kong delayed
#https://tvc4.forexpros.com/c91584e27937e18fc913beea83ef64e3/1489096229/1/1/8/history?symbol=101813&resolution=5&from=1488664280&to=1489096340
#https://tvc4.forexpros.com/c91584e27937e18fc913beea83ef64e3/1489096229/1/1/8/history?symbol=101813&resolution=60&from=1483912929&to=1489096989
#https://tvc4.forexpros.com/1966be10fe3a6b4d99d67f624841520e/1489153722/1/1/8/history?symbol=101813&resolution=15&from=1487858063&to=1489154124
#https://tvc4.forexpros.com/1966be10fe3a6b4d99d67f624841520e/1489153722/1/1/8/history?symbol=101813&resolution=1&from=1487858063&to=1489154124



# 由於國內網絡封鎖,速度太慢,放棄

util = require 'util'
{fetchUrl} = require 'fetch'
moment = require 'moment'
{ExternDataBar} =  require '../../databar'

options =
  method: 'GET'

code = (string)->
  time = new Date().getTime() // 1000
  switch string
    when 'hs50'
      paramCode:'8984'
      hash:'59e52a82492301bee610145dc0cfbbe2'
      time:time
    when 'hsi'
      paramCode:'101813'
      hash:'1966be10fe3a6b4d99d67f624841520e'
      time: time
    else
      console.log "symbol is incorrect: ", string

fromTo = (type)->
  switch type
    when 'minute'
      from: moment().subtract(1,'day').valueOf()//1000
      to: moment().valueOf()//1000
    when 'hour'
      from: moment().subtract(60,'day').valueOf()//1000
      to: moment().valueOf()//1000      

hsidata = (param, callback)->
  {symbol,type,units=0} = param
  {paramCode,hash,time} = code(symbol)
  {from,to} = fromTo(type)
  if type?
    base = "https://tvc4.forexpros.com"
    if type in ['minute01','minute05','minute15','minute30','minute60']
      t = Number(type[-2..])
    else if type is 'minute'
      t = 1
    else if type is 'hour'
      t = 60

    qs = "/#{hash}/#{time}/1/1/8/history?symbol=#{paramCode}&resolution=#{t}&from=#{from}&to=#{to}" 
    url = "#{base}#{qs}"
    #console.log 'url:',url


    fetchUrl url, options, (err,meta, body) ->
      if err
        #console.error "qqdata >> ", err
        callback err, meta, null
      else
        callback meta, body
        return


module.exports = hsidata


hsidata {symbol: 'hs50', type:'minute'}, (err, meta, body)->
  console.log err, meta.toString, body?.toString()

###
[ 'YHOO.OQ',
    'YHOO',
    '雅虎',
    '37.26',
    '1.62',
    '0.60',
    '37.26',
    '37.27',
    '3962335',
    '7.48',
    '36.85',
    '36.66',
    '37.30',
    '36.77' ],
###
### warrant data is different. I will do it later
# 數據應該有的,但是格式不對.分鐘數據格式也不對.
paramCode = '00001'#'20166'
#paramCode = 'IBB'
type = 'day'
#type = 'minute01'
qqdata {paramCode:paramCode,type:type, units: 0}, (err, arr, meta, pandata)->
  console.log err, arr[-1..], meta, pandata
###
###
stocklist {market:'usRank',cate:'TEC',n:40, top:20},(err, data)->
  console.log data
###
###
http://web.ifzq.gtimg.cn/appstock/app/hkMinute/query?_var=min_data_hk00001&code=hk00001&r=0.00662685480223657
http://web.ifzq.gtimg.cn/appstock/app/day/query?_var=fdays_data_hk00001&code=hk00001&r=0.07990345369043417
http://web.ifzq.gtimg.cn/appstock/app/hkfqkline/get?_var=kline_dayqfq&param=hk00001,day,,,320,qfq&r=0.9686581656974285
http://web.ifzq.gtimg.cn/appstock/app/hkfqkline/get?_var=kline_weekqfq&param=hk00001,week,,,320,qfq&r=0.07801260070851113
http://web.ifzq.gtimg.cn/appstock/app/hkfqkline/get?_var=kline_monthqfq&param=hk00001,month,,,320,qfq&r=0.1357514276145262
###
