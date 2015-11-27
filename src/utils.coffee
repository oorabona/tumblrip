# Some useful toolset :)
util = require 'util'

exports.appStartTime = appStartTime = Date.now()

# Logging
# =======
# Handles basic logging with colors.. or not!
exports.colors = colors =
  yellow: "38;5;11"
  orange: "33"
  red: "31"
  purple: "35"
  blue: "34"
  brightBlue: "38;5;12"
  brightCyan: "38;5;14"
  cyan: "36"
  green: "32"
  black: "30"
  gray: "37"
  white: "38;5;15"
  off: "0"

inColor = (color, args...) ->
  if exports.log.colors
    text = "\u001b[#{colors[color]}m"
  else
    text = ''

  for arg in args
    if typeof arg is 'object'
      text += "#{util.inspect arg} "
    else
      text += "#{arg} "

  if exports.log.colors
    text += '\u001b[0m'

  text

exports.log = (args...)->
  process.stdout.write args...

exports.log.colors = true
exports.log.verbose = false
exports.log.DEBUG = false

exports.log.config =
  error: 'red'
  warning: 'orange'
  notice: 'yellow'
  info: 'green'
  debug: 'gray'
exports.log.error = (args...) ->
  process.stderr.write inColor @config.error, 'ERROR:', args...
exports.log.warning = (args...) ->
  process.stderr.write inColor @config.warning, 'WARNING:', args...
exports.log.notice = (args...) ->
  process.stdout.write inColor @config.notice, 'LOG:', args...
exports.log.info = (args...) ->
  if @verbose or @DEBUG
    process.stdout.write inColor @config.info, 'INFO:', args...
exports.log.debug = (args...) ->
  return unless @DEBUG
  now = (Date.now() - appStartTime) / 1000.0
  process.stdout.write inColor @config.debug, 'DEBUG:', args...

exports.pick = (from, what) ->
  obj = {}
  if typeof what is 'string'
    w = [ what ]
  else w = what

  unless Array.isArray w
    throw new TypeError "pick(from: Object, what: String or Array of Strings)"

  for k, v of from
    obj[k] = v if k in w

  obj

# http://zurb.com/forrst/posts/Deep_Extend_an_Object_in_CoffeeScript-DWu
exports.deepExtend = (object, extenders...) ->
  return {} if not object?
  for other in extenders
    for own key, val of other
      if not object[key]? or typeof val isnt 'object'
        object[key] = val
      else
        object[key] = deepExtend object[key], val

  object

###*
# Finds value in an Array of Arrays
# @param input: Array of Arrays like [[1,2,3],[4,5,6]]
# @param index: Index (Integer) in the subarray to check value against
# @param value: Value to look for
# @param all: Boolean (default false), return first match or all matches
# @returns {index|[indexes]} depending on the 'all' param (-1 means no match)
###
exports.findInSubArray = (input, index, value, all=false) ->
  {length} = input

  # It is easier to think looping backwards (from last index down to 0)
  inner = (_index) ->
    loop
      _index--
      break if _index < 0
      i = input[_index]
      break if i and i[index] is value
    _index

  # If we need all occurrences, return an array instead
  if all
    res = []
    i = length
    loop
      i = inner i
      break if i < 0
      res.push i
    res
  else
    inner length

module.exports = exports
