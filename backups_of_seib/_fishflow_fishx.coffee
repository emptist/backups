assert = require '../assert'
{YinFishBase,YangFishBase} = require './fishflow_base'

# FishX 之特點為,適應盤整需要,上半開陰魚,下半開陽魚
# 如果需要,還可以此作為fishy之home,其組合效果應可覆蓋幾乎全部行情變化
# level [0..10], level5 在中間
class YinFishX extends YinFishBase
  anotherFish:(pool)->
    super(pool) or (@_jump(pool) and (@bar[@rawDataName] > pool.barBefore(@bar)?[@tbaName]))

  _jump: (pool) ->
    {level3,level4,level5,level6,level7,level8,level9} = @bar
    levels = [
      #level4, 試過不如不要,會令趨勢模糊
      level5,
      #level6,
      level7,
      #level8,
      #level9
    ]
    for level in levels when @bar[@rawDataName] > level > pool.barBefore(@bar)?[@rawDataName]
      return true
    return false


# 陽魚比較長而完整,很好看,留著或許有獨特價值
class YangFishX extends YangFishBase
  anotherFish:(pool)->
    super(pool) or (@_drop(pool) and (@bar[@rawDataName] < pool.barBefore(@bar)?[@tbaName]))

  _drop:(pool) ->
    {level5,level4,level3,level2,level1} = @bar
    levels = [
      level1,
      #level2,
      level3,
      #level4,
      level5
    ]
    for level in levels when @bar[@rawDataName] < level < pool.barBefore(@bar)?[@rawDataName]
      return true
    return false






# FishXL 之特點為,適應盤整需要,上半開陰魚,下半開陽魚
# 如果需要,還可以此作為fishy之home,其組合效果應可覆蓋幾乎全部行情變化
# level [0..10], level5 在中間
class YinFishXM extends YinFishBase
  anotherFish:(pool)->
    {high,level5,level7} = @bar
    super(pool) or ((@_jump(pool,level7) or @_jump(pool,level5)) and (high > pool.barBefore(@bar)?[@tbaName]))

  _jump: (pool,level) ->
    @bar.high > level > pool.barBefore(@bar)?.high


# 陽魚比較長而完整,很好看,留著或許有獨特價值
class YangFishXM extends YangFishBase
  anotherFish:(pool)->
    {low,level5,level3} = @bar
    super(pool) or ((@_drop(pool,level3) or @_drop(pool,level5)) and (low < pool.barBefore(@bar)?[@tbaName]))
  
  _drop: (pool,level) ->
    @bar.low < level < pool.barBefore(@bar)?.low







# 這樣寫,焦點就變成 tba, 反而不如 x 的寫法,焦點在於 level
# level [0..10], level5 在中間
class YinFishXA extends YinFishBase
  anotherFish:(pool)->
    {bar:{high,level5,level7}, previousBar} = pool
    jump = (level,tbaName) ->
      (high > previousBar?[tbaName] > previousBar?.high) and high > level
    super(pool) or jump(level5,@tbaName)

class YangFishXA extends YangFishBase
  anotherFish:(pool)->
    {bar:{low,level5,level3,level1},previousBar} = pool
    drop = (level,tbaName) ->
      (low < previousBar?[tbaName] < previousBar?.low) and low < level
    super(pool) or drop(level5,@tbaName)




module.exports = {YinFishX, YangFishX}