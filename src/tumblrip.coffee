fs = require 'fs'
path = require 'path'
request = require 'request'
util = require 'util'
Q = require 'q'
mkdirp = require 'mkdirp'
URL = require 'url'

{ApiError, RejectError} = require './eh'
{log, pick, findInSubArray} = require './utils'
options = require './options'

# Some common redefinitions
readFile = Q.nfbind fs.readFile
writeFile = Q.nfbind fs.writeFile
statFile = Q.nfbind fs.stat

# Promises helpers
promiseRetry = (toRetry) ->
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
    return

  Q().then(->
    toRetry()
  ).then _succeed, _failed
  deferred.promise

get = (uri, method='GET') ->
  opts =
    uri: uri
    method: method

  promiseRetry ->
    log.info "#{method} #{uri} ...\n"
    Q.nfcall request, opts
    .spread (response, body) ->
      {statusCode} = response
      log.debug "Server status code: #{statusCode}\n"
      # A bit hacky but basically, if we got 4XX (and most notably 404), we skip the file.
      # If this is a 5XX we retry. Otherwise we keep going.
      switch statusCode / 100
        when 4
          log.info 'File not found, continuing...'
          Q.resolve statusCode
        when 5
          Q.reject new ApiError "Bad status code: #{statusCode}. Retrying..."

      # Strip everything before the first '{' ... '}'
      if body
        json = body.match /^[^\{]+(.*)\;/

        if json
          try
            return JSON.parse json[1]
          catch
            return Q.reject new ApiError 'Could not parse JSON.'
        else
          Q.reject new ApiError 'Could not parse response body.'
      else
        response

getPostsData = (blogname) ->
  # Build url and retrieve all data
  url = "http://#{blogname}.tumblr.com/api/read/json"
  @title ?= null
  @total ?= 0
  @posts ?= []
  self = @
  newPosts = []
  @nbNewPosts = 0

  process = (start, init=false) ->
    log.debug "Processing at #{start}...\n"
    # Get first round separately to know how many posts we will need to retrieve.
    get "#{url}?type=photo&num=50&start=#{start}"
    .then (parsed) ->
      # If we have a total number of posts and we are in the first loop, we are going to update..
      {total} = self
      if init
        # Should be positive unless we have less posts...
        self.nbNewPosts = parsed['posts-total'] - total
        # Whether we are updating or inserting, set these only once :)
        self.total = total = parsed['posts-total']
        self.title = parsed.tumblelog.title

      parsed.posts.forEach (post) ->
        photoUrl = post['photo-url-1280']
        timestamp = post['unix-timestamp']

        # We know for sure that the URL is a unique key to retrieve data.
        # File names are built by joining each part of the URL. This can make longer filenames though.
        outputFile = URL.parse(photoUrl).pathname.split('/').join ''

        # Again, URL are unique by definition. So we can safely use it as a PK.
        # But if we are creating the database, do not bother searching for anything.
        if total is 0
          found = -1
        else
          found = findInSubArray self.posts, 1, photoUrl

        if !!post.slug
          slugfile = "#{post.slug}#{path.extname photoUrl}"
          fileslug = findInSubArray self.posts, 0, slugfile, true

          if fileslug.length > 1 or (fileslug.length is 1 and fileslug[0] isnt found)
            log.info "Already got #{fileslug.length} of that name", slugfile, '. Using', outputFile, 'instead.\n'
          else
            outputFile = slugfile

        array = [outputFile, photoUrl, timestamp]

        if found is -1
          log.debug 'Record not found, creating', array, '\n'
          newPosts.push array
        else
          log.debug "Updating record #{found}", self.posts[found], 'with', array, '...\n'
          self.posts[found] = array

      if options['refresh-db'] or (self.nbNewPosts >= 50 and self.total - start >= 50)
        process start + 50
      else
        # We could enforce check below, it would check if Tumblr API is giving us
        # coherent results. But for testing purposes or if you want to tamper with
        # the database and forget about updating 'total posts' accordingly, then this will
        # raise an uncontinuable exception.
        if options.check and self.nbNewPosts isnt newPosts.length
          Q.reject new RejectError "BUG ? #{self.nbNewPosts} new posts but only got #{newPosts.length}"
        else
          # Prepend new posts (newest first like the API)
          self.posts = Array::concat.call [], newPosts, self.posts
          self

  process 0, true

downloadFile = (output, url, timestamp) ->
  file = "#{options.dest}/#{output}"
  try
    stats = fs.statSync(file)
    isFile = stats.isFile()
  catch
    isFile = false

  {size} = stats if isFile

  promiseRetry ->
    get url, 'HEAD'
    .then (response) ->
      contentLength = parseInt response.headers['content-length']
      if !options.force and (size is contentLength)
        log.notice '! Skipping', output, 'file has the same size (', size, 'bytes).\n'
        return Q.resolve 0

      statusCode = null
      log.debug 'Remote file size:', contentLength, 'local file:', size, '\n'
      req = request.get url
        .on 'error', (error) ->
          Q.reject new ApiError 'While downloading file', error
        .on 'response', (response) ->
          {statusCode} = response

          # A bit hacky but basically, everything not 2XX has to be retried.
          if statusCode / 100 isnt 2
            Q.reject new ApiError 'While downloading file, wrong statusCode returned', statusCode

          if /image/.test response.headers['content-type']
            outputStream = fs.createWriteStream file
            outputStream.on 'error', (error) ->
              Q.reject new RejectError 'While writing to file', error

            outputStream.on 'finish', ->
              log.info "✔ #{url} (#{statusCode}) -> #{file}\n"
              Q.resolve statusCode

            req.pipe outputStream

main = ->
  res = options.parse()
  # In that case, res is used as process exit code.
  return res if typeof res is 'number'

  {blogname, dest} = options

  # Promise to...
  Q.Promise (accept, reject, notify) ->
    # Create destination if not existing.
    try
      isDir = fs.statSync(dest).isDirectory()

    if isDir
      accept dest
    else
      mkdirp dest, (err) ->
        reject err if err
        accept dest
  .then (realDestination) ->
    log.debug 'Using output directory:', realDestination, '\n'
    options.dest = realDestination
    cacheFile = "#{options.dest}/.tumblrip"

    try
      if fs.statSync(cacheFile).isFile()
        readFile cacheFile
        .then (data) ->
          [cacheFile, JSON.parse data]
    catch e
      [cacheFile, {}]
  .spread (cacheFile, cache) ->
    [cacheFile, getPostsData.call cache, blogname]
  .spread (cacheFile, blog) ->
    {title, total, posts, nbNewPosts} = blog
    log.info 'Blog title:', title, '\n'
    log.info 'New posts since last update', nbNewPosts, '\n'
    log.info 'Blog total posts:', total, '\n'
    log.info 'Blog unique photos:', posts.length, '\n'
    log.info 'Duplicates:', total-posts.length, '\n'

    # Plain old JSON, should/can be optimized a bit..
    # We remove 'nbNewPosts' since it will change everytime.
    delete blog.nbNewPosts
    outputData = JSON.stringify blog

    # Write "database" to outputdir/.tumblrip
    if options.cache
      writeFile cacheFile, outputData
      .then ->
        log.info 'Cache written.\n'
        [blog.posts, total, nbNewPosts]
    else
      [blog.posts, total, nbNewPosts]
  .spread (posts, total, nbNewPosts) ->
    log.info "Processing #{nbNewPosts} photos on #{options.threads} threads.\n"

    threaded = (start) ->
      threads = posts[start...start+options.threads]
      log.debug "Starting at #{start}:", threads, '\n'
      # Turning the promise of an array into an array of promises
      Q.all threads.map (post) ->
        downloadFile.apply null, post
      .then -> Q.delay options.delay
      .then ->
        start += options.threads
        # Since the newest items are on the first indexes, we can stop when
        # we reach (or go beyond) the 'nbNewPosts' value.
        # This is incompatible with the use of 'startAt' argument.
        if start > total or (!options['refresh-photos'] and options.startAt is 0 and start > nbNewPosts)
          1
        else
          threaded start

    threaded options.startAt
  .then (exitCode) ->
    log.debug "Exit code: #{exitCode}\n"
    process.exit exitCode
  , (error) ->
    log.error error.message, '\n'
    log.debug error, '\n'
    process.exit 0
  , (notice) ->
    log.notice notice

exports.main = main
