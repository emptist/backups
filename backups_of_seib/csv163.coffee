request = require 'request'
iconv = require 'iconv-lite'
{recode,restring} = require '../../secode'

{csv2json} = require './csvjson'

quotes = (param, callback) ->
  host = 'http://quotes.money.163.com/service/chddata.html?code='
  # 日期，代碼，名稱，收盤，最高，最低，開盤，前收，漲跌，幅度，換手率，成交量，成交金額，總市值，流通市值
  fields = 'TOPEN;HIGH;LOW;TCLOSE;LCLOSE;CHG;PCHG;TURNOVER;VOTURNOVER;VATURNOVER;TCAP;MCAP'
  headers = 'DATE;CODE;NAME;' + fields
  id = recode param.symbol, 6
  url = host + "#{id}&start=#{param.start}&end=#{param.end}&fields=#{fields}"
  options =
    url: url
    json: false
    encoding:null

  request options, (err, res, data)->
    unless err?
      text = iconv.decode(data, 'GBK')
      cnt = text #res.content#.toString 'utf8'
      csvlines = cnt.split "\n"
      csvrows = (csvlines.slice 1, csvlines.length).reverse()
      rows =  []
      for r in csvrows
        unless r.length is 0
          row = r.split ','
          date = [(new Date row[0]).getTime()]
          res = row.map((l)-> Number(l))
          unless (res[3] is 0) or (res[4] is 0) or (res[5] is 0) or res[6] is 0
            rows.push date.concat res[3..6], res[11..11]
      console.log cnt
      callback csv2json cnt, {delim: ',', textdelim:'\r', headers: headers.split(';')} #cnt #rows #url


module.exports = quotes

### test:
date = new Date()
end = date.year * 1000 + date.hour * 100 + date.day
module.exports {symbol: '000002', start:20080801, end:end}, (data)->
  console.log data
###
