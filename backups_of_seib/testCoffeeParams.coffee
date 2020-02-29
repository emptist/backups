class TestParam
  constructor:({@p1, @p2})->

  pone:(p=@p1, callback)=>
    console.log "p is #{p}"
    callback?()

  ptwo:(x,callback)->
    p = (p1=@p1)=>
      console.log('p1 is ', p1, @p1)
      callback()
    p(x)
  
module.exports = TestParam