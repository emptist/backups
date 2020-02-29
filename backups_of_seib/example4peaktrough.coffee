### 檢測發現機會較多的品種
  思路:
    1. 根據成交金額排序,初篩出各類前20名的品種
    2. 以此法檢測谷底攀升頻率和幅度,主要是達到5%或4%漲幅的頻率
    3. 動態維護居於前10的品種,作為階段的目標品種
###
{Pool,TopBotProbabs} = require '../seyy'
{hists,qsort} = require '../sedata'

# 多參數目標檢測結果以第一個參數為基準排序,例如[5,7.5,3.5] 以 5 為基準
check = (options, callback)->
  symbols = options.symbols
  levels = options.levels ? null # TopBot庫有默認值
  units = options.days ? 300
  filter = options.filter ? null # Pool庫有默認值

  統計 = (symbol, 回執)->
    hists {symbol:symbol, type:'day', units:units}, (err,arr)->
      if err?
        throw err

      pool = new Pool({statsTag:'bor峰值統計',統計參數:options})


      pt = new TopBotProbabs('lory')
      pt.擬統計峰值頻率({基數:0,目標:levels})

      # 此過程可以通過改寫Pool,嵌入Pool,故不需要循環兩次
      pt.序列(pool.序列(arr).barArray)

      指標 = pt.峰值分佈
      指標.symbol = symbol
      console.log "指標, pool.borProbabs.峰值分佈:", 指標, pool.borProbabs.峰值分佈

      回執 null, 指標

  list = []
  test = (err, obj)->
    if err
      console.error err
      callback err, null
      return
    list.push obj

    #console.log "sefind >> 統計: ", obj.symbol

    if list.length is symbols.length
      callback err, list.sort (a,b)-> b[levels[0]] - a[levels[0]]

  for symbol in symbols
    統計(symbol, test)

find = (options, callback)->
  category = options.category
  n = options.top
  levels = options.levels
  units = options.days

  qsort {category: category, units: n}, (err, arr)->
    if err or not arr?
      console.error err
      return
    symbols = (each.code for each in arr) # sina的行情有symbol是指sz159915這種格式
    console.log symbols

    options =
      symbols: symbols
      levels: levels
      days: units
      #filter:
      #  計峰篩選:(燭)->燭.入選計峰 = (燭.low > 燭.bay) and (燭.high > 燭.ma_price10)

    check options, (err, list)->
      callback err, list[..5]

module.exports =
  check: check
  find: find

#symbols = ['159915','150153']
