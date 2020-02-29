class Option

  speculativePrenium: -> 
    @currentPrice - @intrinsicValue()
  inTheMoney: ->
    # the larger, the "deeper" in the money
    @intrinsicValue() > 0
  outOfTheMoney: ->
    @intrinsicValue() is 0

class CallOption extends Option
  intrinsicValue: -> 
    Math.max(@stockPrice - @strikePrice, 0)

class PutOption extends Option
  intrinsicValueOfPut: ->
    Math.max(@strikePrice - @stockPrice, 0)
