###
kind:
  hsa:'shsza'
  hsb:'shszb'
  hslof:'shszlof' # no data?
  shb:'shb'
  szb:'szb'
  shlof:'shlof' # no data?
  szlof:'szlof'
  shetf:'shetf'
  szetf:'szetf'
###

request = require 'request'

# quote sort by ammount

module.exports = (kind, tx, 回執)->
  host = "http://hq.htsc.com.cn"
  random = Math.random()
  url = "#{host}/cssweb?type=GET_GRID_QUOTE_SORT&kind=#{kind}&field=cjje&asc=desc&from=1&to=#{tx}&radom=#{random}"
  options =
    url: url
    json: true

  array = []
  callback = (err, res, json)->
    if err
      #console.error err
      回執 'failed', null
      return

    if json.cssweb_code is 'success'
      json.data = ({symbol:each[18],name:each[19],amount:each[0]} for each in json.data)
      回執 null, json
    else
      回執 'failed', null


  request options, callback


###
qsa 'shsza', 30, (err, json)->
  unless err
    console.log json#.data.length
###
