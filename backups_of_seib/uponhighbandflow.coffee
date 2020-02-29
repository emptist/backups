BaseDataFlow = require './dataflow_base'

# 用於牛初識別策略,特點是找下跌或盤整之後,布林線從新展開,而收盤或最高在布林線上軌上方向上貼軌道上行的時機,一旦脫離之後即結束
# 做好後,像其他 flow 法類一樣使用,例如放置於 pool 內, 應用或者參照 trendFlowSignal
class UponHighBandFlowBase extends BaseDataFlow




module.exports = UponHighBandFlowBase