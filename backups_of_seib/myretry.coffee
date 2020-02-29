module.exports = (err, res)->
  retry = err? or 500 <= res?.statusCode < 600
  #if retry then console.log "retry data request..."
  return retry
