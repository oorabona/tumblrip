# Error handling
exports.RejectError = (message, data) ->
  @name = 'RejectError'
  @message = message
  @data = data
  @stack = (new Error).stack
  return

exports.ApiError = (message, data) ->
  @name = 'ApiError'
  @message = message
  @data = data
  @stack = (new Error).stack
  return

exports.RejectError.prototype = new Error
exports.ApiError.prototype = new Error

module.exports = exports
