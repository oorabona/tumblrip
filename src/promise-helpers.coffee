Q = require 'q'
{ApiError, RejectError} = require './eh'
{log} = require './utils'
options = require './options'

# Promises helpers
exports.promiseRetry = (toRetry) ->
  deferred = Q.defer()
  {retries, delay} = options
  factor = options['retry-factor']

  userRejectError = options.rejectError or RejectError
  randomizeRetry = options.retryRandom or false

  _succeed = (returned) ->
    deferred.resolve returned

  _failed = (error) ->
    if error instanceof RejectError or error instanceof userRejectError or --retries <= 0
      log.error error.message, '\n'
      log.error error.stack, '\n' if options.debug
      deferred.reject error
    else
      timeToWait = if randomizeRetry then Math.random() * delay / 2 + delay / 2 else delay
      log.warning error.message, '\n'
      log.warning error.stack, '\n' if options.debug

      Q.delay timeToWait
      .then(->
        toRetry()
      ).then _succeed, _failed
      delay *= factor
    return

  Q().then(->
    toRetry()
  ).then _succeed, _failed
  deferred.promise

###*
# A combination of q.allSettled and q.all. It works like q.allSettled in the sense that
# the promise is not rejected until all promises have finished and like q.all in that it
# is rejected with the first encountered rejection and resolves with an array of "values".
#
# The rejection is always an Error.
# @param promises
# @returns {*|promise}
###
exports.allDone = (promises) ->
  deferred = Q.defer()
  Q.allSettled(promises).then (results) ->
    values = []
    i = 0
    while i < results.length
      if results[i].state == 'rejected'
        deferred.reject new Error(results[i].reason)
        return
      else if results[i].state == 'fulfilled'
        values.push results[i].value
      else
        deferred.reject new Error('Unexpected promise state ' + results[i].state)
        return
      i++
    deferred.resolve values
    return
  deferred.promise
