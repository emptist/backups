###
 Copyright(c) 2016- Jigme Ko <jigme1968@gmail.com>
 MIT Licensed
###

{restring,recode} = require '../../secode'
request = require 'request'
iconv = require 'iconv-lite'
hqstr2obj = require './sinaticks2obj'

hqstr2obj_hs = (代碼,tickstr,obj)->
  c = recode(代碼,0)
  #tickstr = eval("hq_str_#{代碼}")
  tick = "#{c},#{tickstr}".split(',')
  # 共有34項,最後一項不知何用
  obj[代碼] =
    代碼:tick[0]
    名稱:tick[1]
    開: Number(tick[2])
    前: Number(tick[3])
    現: Number(tick[4])
    高: Number(tick[5])
    低: Number(tick[6])
    買: Number(tick[7]) # 賣入報價
    賣: Number(tick[8]) # 賣出要價
    量: Number(tick[9])
    額: Number(tick[10])
    買量1: Number(tick[11])
    買1: Number(tick[12])
    買量2: Number(tick[13])
    買2: Number(tick[14])
    買量3: Number(tick[15])
    買3: Number(tick[16])
    買量4: Number(tick[17])
    買4: Number(tick[18])
    買量5: Number(tick[19])
    買5: Number(tick[20])
    賣量1: Number(tick[21])
    賣1: Number(tick[22])
    賣量2: Number(tick[23])
    賣2: Number(tick[24])
    賣量3: Number(tick[25])
    賣3: Number(tick[26])
    賣量4: Number(tick[27])
    賣4: Number(tick[28])
    賣量5: Number(tick[29])
    賣5: Number(tick[30])
    open: Number(tick[2]) # 即 開
    close: Number(tick[4]) # 應為現,便於監控計算
    high: Number(tick[5]) # 即 高,便於應用
    low: Number(tick[6]) # 即 低,便於應用

  obj[代碼].day = obj[代碼].時間 = new Date tick[31..32].join(' ')
  obj[代碼].備註 = tick[33]
  obj[代碼].市場代碼 = 代碼[..1]
  return obj

sinaticks = (string, callback)->

  # reformat the codes in string argument

  codes = restring(string, 'sina')
  obj = {}
  options =
    url:"http://hq.sinajs.cn/list=#{codes}"
    json: false
    encoding:null
    forever:true
    ###
    timeout: 1000
    maxAttempts: 1  #// (default) try 5 times
    retryDelay: 1000  #// (default) wait for 5s before trying again
    retryStrategy: myRetryStrategy
    ###

  request options, (err, res, data)->
    console.error "ticks >> ", err if err
    unless err?
      text=iconv.decode(data, 'GBK')

      # TODO: 替換掉 eval
      eval(text)
      for 代碼 in codes.split(',')
        tickstr = eval("hq_str_#{代碼}")
        hqstr2obj(代碼,tickstr,obj)

      callback obj

module.exports = sinaticks

###
sinaticks 'usdcny,usdjpy,brk.b,hseb', (data)->
  console.log data
###
