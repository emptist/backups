c = 0
tick = ()->
  c++
  document.getElementById('stepsDone').value = c
  moveWall() #//move wall to the left

runSim = (state)->
  switch state
    when 1 # //run simulation
      if c > 100
        runSim('0') #//force stop
      else
        tickInterval = setInterval("tick();", 100)    
    when 0 # //stop simulation
      clearInterval(tickInterval)
      c = 0
      document.getElementById('stepsDone').value = c
      document.getElementById('wall').style.left = null
      document.getElementById('wall').style.right = '0px'

moveWall = () ->
  wallX = document.getElementById('wall').offsetLeft  
  document.getElementById('debugTextarea').innerHTML += "["+c+"] Wall PosX: "+wallX+"\n"
  document.getElementById('debugTextarea').scrollTop = document.getElementById('debugTextarea').scrollHeight
  if wallX <= 0
    document.getElementById('wall').style.left = null
    document.getElementById('wall').style.right = '0px'
  else
    wallX = wallX - 40
    document.getElementById('wall').style.left = wallX + 'px'