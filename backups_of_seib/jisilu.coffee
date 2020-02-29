request = require "requestretry"

class JisiluData
  constructor:()->

  # 分级A的接口
  funda: "https://www.jisilu.cn/data/sfnew/funda_list/?___t="

  # 分级B的接口
  fundb: "https://www.jisilu.cn/data/sfnew/fundb_list/?___t="

  # 可交易母基金, 不明原因,出錯
  fundmt: "https://www.jisilu.cn/data/sfnew/arbitrage_mtrade_list/?___t="

  # 母基接口
  fundm: "https://www.jisilu.cn/data/sfnew/fundm_list/?___t="

  # 分级套利的接口
  fundarb: "http://www.jisilu.cn/data/sfnew/arbitrage_vip_list/?___t="

  # 集思录登录接口
  jsl_login: "https://www.jisilu.cn/account/ajax/login_process/"

  # 集思录 ETF 接口
  etf_index: "https://www.jisilu.cn/jisiludata/etf.php?___t="
  # 黄金 ETF
  etf_gold: "https://www.jisilu.cn/jisiludata/etf.php?qtype=pmetf&___t="
  etf_money: "https://www.jisilu.cn/data/money_fund/list/?___t="

  now: -> (new Date()).getTime()

  get: (urlname, callback)->
    url = @["#{urlname}"]
    options =
      url: "#{url}#{@now()}"
      json: true

    request options, (err,res, body)->
      callback(err, body) # unless err?
      #jj = (each for each in body.rows when each.id is "150152")
      #console.log res,body

  getSymbols: (category, callback)->
    @get category, (err, body)->
      if err?
        callback err,null
        return

      cell = switch category
        when 'fundmt' then "base_fund_id"
        else "#{category}_id"

      callback null, (each.cell[cell] for each in body.rows)


module.exports = JisiluData
###
(new JisiluData()).getSymbols 'fundmt', (err, symbols)->
  console.log symbols
###


# http://www.abcfund.cn/fund/share.php?code=164401 數據也許更好
