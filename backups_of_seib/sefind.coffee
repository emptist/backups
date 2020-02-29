### 檢測發現機會較多的品種
  思路:
    1. 根據成交金額排序,初篩出各類前20名的品種
    2. 以此法檢測谷底攀升頻率和幅度,主要是達到5%或4%漲幅的頻率
    3. 動態維護居於前10的品種,作為階段的目標品種
###
# 新浪數據可供篩選的查詢詞,可從網頁上看到:
# http://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/Market_Center.getHQNodeDataSimple?page=1&num=20&sort=changepercent&asc=0&node=sh_b&symbol=&_s_r_a=sort

{favorites} = require './config'

{Pool,TopBotProbabs} = require './seyy'
{hists,qsort,JisiluData,toplist} = require './sedata'
{EventEmitter} = require 'events'
jsl = new JisiluData()

find = (options, callback)->
  addSymbolsOfPrevious = (category, symbols)->
    pre = (obj.symbol for obj in options.previous when (obj.category is category) and not (obj.symbol in symbols))
    symbols = symbols.concat(pre)

  topn = options.topn
  全部 = options.categorys
  options.symbols = []

  結果 = []
  分析 = new EventEmitter()

  calc = (category, topn)->
    if category is 'favorites'
      symbols = favorites
      console.log "#{category} 排序前#{topn}: #{symbols}"
      options.symbols = addSymbolsOfPrevious(category, symbols)
      check options, (err, list)->
        unless err
          結果.push {"#{category}":list}
          分析.emit '完成一項', category
        else
          console.error "[debug] sefind >> check: ", category, list

    else if category is 'usRank'
      toplist {market:category,cate:'IMP',n:80,top:topn},(err,symbols)->
        unless err
          options.symbols = addSymbolsOfPrevious(category,symbols) #= symbols
          console.log "#{category} 排序前#{topn}: #{symbols}"

          check options, (err, list)->
            unless err
              結果.push {"#{category}":list}
              分析.emit '完成一項', category
            else
              console.error "[debug] sefind >> check: ", category, list

    else if category in ['funda','fundb','fundm']
      jsl.getSymbols category, (err,symbols)->
        if err?
          # 分析.emit '完成一項', category
          return

        #options.symbols = symbols
        options.symbols = addSymbolsOfPrevious(category,symbols) #= symbols

        check options, (err, list)->
          unless err
            結果.push {"#{category}":list}
            分析.emit '完成一項', category

    else
      # sort: 默認是 amount
      sort = 'changepercent' #'amount'
      qsort {category: category, sort:sort,topn: topn}, (err, arr)->
        if err or not arr?
          console.error("sefind >> qsort", err)

          # 試試直接往下走
          arr = []
          # 以上為臨時測試
          #return

        symbols = (each.code for each in arr) # sina的行情有symbol是指sz159915這種格式
        console.log "#{category} #{sort} 排序前#{topn}: #{symbols}"
        #options.symbols = symbols.concat(symbols)
        #options.symbols = symbols
        options.symbols = addSymbolsOfPrevious(category,symbols) #= symbols

        check options, (err, list)->
          unless err
            結果.push {"#{category}":list}
            分析.emit '完成一項', category
            #callback err, list[..5]


  分析.on '完成一項',(category)->
    console.log '已分析板塊: ', category
    逐個()

  逐個 = ->
    一個 = 全部.shift()

    unless 一個?
      console.log '分析完成'#, 結果
      callback 結果
      return

    calc(一個,topn)

  逐個() # return 為結果

  #callback(結果)




# 多參數目標檢測結果以第一個參數為基準排序,例如[5,7.5,3.5] 以 5 為基準
check = (options, callback)->
  symbols = options.symbols
  levels = options.levels ? null # TopBot庫有默認值
  pubdays = options.pubdays ? 10

  統計 = (symbol, 回執)->
    hists {symbol:symbol, type:'day', units: 300}, (err,arr)->
      #console.log "統計: ",symbol
      指標 = null
      意外 = null
      if err?
        console.error "sefind>>check/統計/hists: #{symbol} ", err
        意外 = err

      else
        if arr.length < pubdays
          #console.log "[debug] sefind >> 新股,忽略? #{symbol}: ", arr.length
          意外 = "#{symbol},新股,忽略"
        else
          pool = new Pool({statsTag:'bor峰值統計', 統計參數: options})
          try
            pool.序列(arr)
            指標 = pool.borProbabs.峰值分佈
            指標.symbol = symbol
            指標.close = (arr[arr.length - 1]).close
            指標.勢或偏多 = pool.勢或偏多
            #console.log "[debug] sefind >> 統計: ", pool
          catch error
            console.error "sefind>>check/統計: bor峰值統計出錯 #{symbol}", error
            意外 = error

      回執(意外, 指標)


  list = []
  i=0
  for symbol in symbols
    統計 symbol, (err, obj)->

      i++

      if err?
        console.error  "sefind>>check: #{obj?.symbol}:", err
        #callback err, null
      else
        list.push obj

      if i is symbols.length
        #console.log "[debug] sefind >> list is: ", list
        callback null,list.sort (a,b)-> b[levels[0]] - a[levels[0]]



module.exports =
  check: check
  find: find

#symbols = ['159915','150153']
