###
  process: renderer
###

# 通過ipcRenderer收發訊息
util = require 'util'
path = require 'path'
moment = require 'moment'
{ipcRenderer} = require('electron')
rx = require 'reactive-coffee'

SecurityWithGuardian = require './securitywithguardian'
{IBCode,nowTrading} = require '../secode'
{ticks} = require '../sedata'
createChart = require '../e_security_chart'
drawPool = require path.join(__dirname,'..', 'e_drawpool')

{e_security:{withMonth,withMinute,pools,forexAdd}} = require '../config'

{
  rxt:{
    bind 
    tags:{
      button, h1, ul, li
    }
  }
} = rx

$('body').append(
  button {id:'devtools'},['Open Devtools']
)

btn = document.getElementById('devtools')

btn.addEventListener('click', -> webview.openDevTools())

webview = null
addWebView = ->
  $('body').append('<webview id="foo" src="./wbv_pool.html" style="display:inline-flex; width:640px; height:480px"></webview>')

onload = -> 
  webview = document.getElementById('foo')
  indicator = document.querySelector('.indicator')

  loadstart = -> indicator.innerText = 'loading...' 
  loadstop = -> indicator.innerText = ''
  
  webview.addEventListener('did-start-loading', loadstart)
  webview.addEventListener('did-stop-loading', loadstop)
  
#addWebView()



security = null
# 證券(各池)完成生成,更新,判斷,計算倉位,生成和觸發信號.
ipcRenderer.on 'main:請生成證券', (event, secCode, contract) ->
  unless security?
    changeView({secCode,contract})
    webview = document.getElementById('webview')
    indicator = document.querySelector('.indicator')

    loadstart = -> return #indicator.innerText = 'loading...' 
    loadfinished = -> webview.send 'parent:createPool', secCode, 'day'
    
    webview.addEventListener('did-start-loading', loadstart)
    webview.addEventListener('did-finish-load', -> webview.send 'parent:createPool', secCode, 'day')

    

#window.changeView = ({secCode,contract}, researchDraw)->
changeView = ({secCode,contract}, researchDraw)->
  window.document.title = secCode
  # 若需要名稱,則用ticks下載即時行情即可取得
  ticks secCode,(err,jso)->
    # ticks 回答這樣的法: {代碼:{代碼,...}, 代碼:{代碼:,...}},由於此處只有一個,所以:
    ipcRenderer.send('security:新建證券窗口完畢', secCode)

    名稱 = tick.名稱 for code, tick of jso
    證券 = new SecurityWithGuardian(secCode, 名稱, contract) # 先生成,不需要再刪除
    開啟自耕(證券, researchDraw)
    #window.security = 證券 # 存起備用
    security = 證券

# 我關閉自己! 注意這裡的 window 是預設變量,直接用就可以了,就是console中的window吧?
# 每一個證券一個窗口,需要此法,關掉當期不勢或偏多品種
ipcRenderer.on 'main:通過關閉申請', (event, secCode)->
  if secCode is security.secCode
    window.close()
  else
    throw '同意關閉自耕窗口secCode不對'


# callback暫時充當雙重角色,將來亦可將信號回執取消,改成events
# 以下function若放在e_security,並實現各池分開副程
開啟自耕 = (證券, researchDraw)->
  {secCode} = 證券
  定制自耕 = (週期名)->
    p = 證券.定制池(週期名)

    # !注意!
    # 此處很特別, 不能這樣寫,省略掉p這個變量:
    #
    # {explorer,externalData,secCode} = p
    #
    # 有可能是池尚未完成,所以變量都還是未定義? (未有時間仔細看懂)
    # 總之,一度改錯了,從新改回來的
 
    for tracer in [p.explorer,p.explorer.guardian]
      tracer.on 'liveSignalEmerged', (signal)->
        ipcRenderer.send('tracer:liveSignalEmerged',signal)

    p.explorer.guardian.on '保本信號', (signal)->
      if signal?
        callback = (order)->
          if order?
            ipcRenderer.send('e_security:信號指令', signal, order)
            util.log('已廣播保本信號:',secCode, 週期名, signal.signalTag)

        if signal.isReOpenSignal
          p.secPosition.reOpenPosition(signal, callback)
        else
          p.secPosition.adjustPosition(signal, callback)


    p.explorer.on '策略信號', (signal)=>
      {day,emitTime,isOpenSignal} = signal

      # [或無必要?] 篩選當下的信號
      sameday = true #moment().utc().isSame(day,'day') or moment().isSame(day,'day')
      if sameday # 行情日期為當日,策略信號才需要操作
        if signal? # and rightime
          if isOpenSignal and IBCode.isForex(secCode)
            ipcRenderer.send('e_security:信號指令', signal)
            util.log('已廣播策略信號(外匯新開倉):',secCode, 週期名, emitTime, signal.signalTag)#,p.secPosition)
          else 
            if p.secPosition?
              p.secPosition.adjustPosition signal, (order)->
                if order?
                  ipcRenderer.send('e_security:信號指令', signal, order)
                  util.log('已廣播策略信號:',secCode, 週期名, emitTime, signal.signalTag)
            else
              ipcRenderer.send('e_security:信號指令', signal)
              util.log('已廣播策略信號(證券新開倉):',secCode, 週期名, emitTime, signal.signalTag,p.secPosition)


    p.externalData (firstLoad)->
      ipcRenderer.send('security:無益申請關閉', secCode) unless nowTrading(secCode)
      # 首次載入數據後繪圖. 注意: 證券.就緒()含後期設置
      if firstLoad and 證券.就緒()  # 根據下行,最後下載數據成功的那個 pool 傳來的 firstLoad 才會生效
        createChart(security,changeView)

  window.pools = pools
  if withMonth
    pools.push('week')
    pools.push('month')
  if withMinute and IBCode.isForex(證券.secCode)
    pools.push(forexAdd)

  for 週期名 in pools
    定制自耕(週期名)


ipcRenderer.on 'dbmanager:updateSecPosition', (event, position)->
  security?.newSecurityPositionState(position)

ipcRenderer.on 'IBSocket:openOrder',(event,openOrder)->
  security?.openOrderInfo(openOrder)

ipcRenderer.on 'main:Fwd:dbmanager:openOrder',(event,openOrder)->
  console.log '[debug]e_security: on main:Fwd:dbmanager:openOrder',openOrder, security
  security?.newOrderStatus(openOrder)

ipcRenderer.on 'main:開發測試',(event)->
  security.isTesting = true
