require 'colors'
#{IBRealtimeBar} = require './databar'

api = (options,callback) ->
  ib = this
  {tickerId,contract,barSize=5,whatToShow='MIDPOINT',useRTH=false} = options
  ib.reqRealTimeBars(tickerId,contract, barSize, whatToShow, useRTH)


  ib.on('realtimeBar', (reqId, time, open, high, low, close, volume, wap, count) ->
    bar = # new IBRealtimeBar # 因electron 傳遞訊息時損失 functions 故到受方再轉換
      tickerId:reqId  # ib命名混淆,為統一改名為 tickerId
      time:time
      #date:time*1000
      #day:new Date(time*1000)
      open:open
      high:high
      low:low
      close:close
      volume:volume
      wap:wap
      count:count
    
    #ib.rtWebContents[reqId].send('IBSocket:realtime', bar)
    callback(reqId,bar)
    # console.log "[debug] realtime bar: ", bar
    return
  )
  

  ### 
  # Forex
  ib.reqRealTimeBars(1, ib.contract.forex('EUR'), 5, 'TRADES', false);
  ib.reqRealTimeBars(2, ib.contract.forex('GBP'), 5, 'BID', false);
  ib.reqRealTimeBars(3, ib.contract.forex('CAD'), 5, 'ASK', false);
  ib.reqRealTimeBars(4, ib.contract.forex('HKD'), 5, 'MIDPOINT', false);
  ib.reqRealTimeBars(5, ib.contract.forex('JPY'), 5, 'TRADES', false);
  ib.reqRealTimeBars(6, ib.contract.forex('KRW'), 5, 'BID', false);
  # Stock
  ib.reqRealTimeBars 11, ib.contract.stock('AAPL'), 5, 'TRADES', false
  ib.reqRealTimeBars 12, ib.contract.stock('AMZN'), 5, 'BID', false
  ib.reqRealTimeBars 13, ib.contract.stock('GOOG'), 5, 'ASK', false
  ib.reqRealTimeBars 14, ib.contract.stock('FB'), 5, 'MIDPOINT', false
  # Option
  ib.reqRealTimeBars 21, ib.contract.option('AAPL', '201407', 500, 'C'), 5, 'TRADES', false
  ib.reqRealTimeBars 22, ib.contract.option('AMZN', '201404', 350, 'P'), 5, 'BID', false
  ib.reqRealTimeBars 23, ib.contract.option('GOOG', '201406', 1000, 'C'), 5, 'ASK', false
  ib.reqRealTimeBars 24, ib.contract.option('FB', '201406', 50, 'P'), 5, 'MIDPOINT', false
  # Disconnect after 10 seconds.
  setTimeout (->
    console.log 'Cancelling real-time bars subscription...'.yellow
    # Forex
    ib.cancelRealTimeBars(1);
    ib.cancelRealTimeBars(2);
    ib.cancelRealTimeBars(3);
    ib.cancelRealTimeBars(4);
    ib.cancelRealTimeBars(5);
    ib.cancelRealTimeBars(6);
    #Stock
    ib.cancelRealTimeBars 11
    ib.cancelRealTimeBars 12
    ib.cancelRealTimeBars 13
    ib.cancelRealTimeBars 14
    # Option
    ib.cancelRealTimeBars 21
    ib.cancelRealTimeBars 22
    ib.cancelRealTimeBars 23
    ib.cancelRealTimeBars 24
    ib.disconnect()
    return
  ), 10000
  ###

module.exports = api