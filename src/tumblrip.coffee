# TumblRip -- Download photos from Tumblr
# Made by Olivier ORABONA
# Licence: MIT

# NodeJS imports
fs = require 'fs'
path = require 'path'
request = require 'request'
Q = require 'q'
mkdirp = require 'mkdirp'
URL = require 'url'
bhttp = require 'bhttp'

# My own imports
{ApiError, RejectError} = require './eh'
{log, pick, findInSubArray} = require './utils'
options = require './options'
{allDone, promiseRetry} = require './promise-helpers'

# Make these functions Promise-able.
readFile = Q.nfbind fs.readFile
writeFile = Q.nfbind fs.writeFile
statFile = Q.nfbind fs.stat

###*
@name api -- communicate with remote server API
@param uri (String): the URI to make call to
@param method (String): method to call (by default it is GET)
###
api = (uri, method='GET') ->
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

###*
@name getPostsData -- get all posts data from Tumblr blog
@param blogname (String) : the blog name (we construct the URL from it)
@param this (Object) : database read from / written to
###
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
    # We know we only want photos and the maximum item size is 50.
    # These are not variables for the purpose of this tool, but could easily be
    # modified to download other stuff from a Tumblr blog ! :)
    api "#{url}?type=photo&num=50&start=#{start}"
    .then (parsed) ->
      # Get total number of posts (when first time, this value is 0).
      {total} = self

      # Update these global variables only once
      if init
        self.title = parsed.tumblelog.title

        # If we have more posts on our cache than on remote site..
        if parsed['posts-total'] < total
          # .. We know that we might have (among probably those already downloaded)
          # at most parsed['posts-total'] new pictures to download.
          self.nbNewPosts = parsed['posts-total']
        else
          self.nbNewPosts = parsed['posts-total'] - total

        # We do not set local variable 'total' which will remain set to its
        # initial value. This will be used later for sub array find.
        self.total = parsed['posts-total']

      parsed.posts.forEach (post) ->
        photoUrl = post['photo-url-1280']
        timestamp = post['unix-timestamp']

        # We first build a filename from concatening URL pathname. That should be
        # unique enough but makes longer filenames.
        outputFile = URL.parse(photoUrl).pathname.split('/').join ''

        # Do not bother searching if the database (aka cache) is empty (creating db).
        # Otherwise search for this URL in the cache db.
        if total is 0
          found = -1
        else
          found = findInSubArray self.posts, 1, photoUrl

        # Sometimes we have a 'slug' attribute that might have a better (human readable)
        # filename (everything is better than a long hex string right ?)
        if !!post.slug
          slugfile = "#{post.slug}#{path.extname photoUrl}"
          fileslug = findInSubArray self.posts, 0, slugfile, true

          # If we already have more than one occurence or if that occurence does
          # not link to the same file (the long hex string one), we have a conflict.
          if fileslug.length > 1 or (fileslug.length is 1 and fileslug[0] isnt found)
            log.info "Already got #{fileslug.length} file(s) of that name '", slugfile, "'. Using '", outputFile, "' instead.\n"
          else
            outputFile = slugfile

        # We build our database record as an array where
        # outputFile: definitive file with name either slugfile || photoUrl
        # photoUrl: the remote photo endpoint URL
        # status: 'D' for 'delete', 'U' for 'update' (default action)
        array = [outputFile, photoUrl, 'U']

        if found is -1
          log.debug 'Record not found, creating', array, '\n'
          newPosts.push array
        else
          log.debug "Updating record #{found}", self.posts[found], 'with', array, '...\n'
          self.posts[found] = array
        return

      if options['refresh-db'] or (self.nbNewPosts >= 50 and self.total - start >= 50)
        process start + 50
      else
        # Make sure we have all expected new posts. This is to make sure we have
        # been given proper results from Tumblr API. Since this could also be a
        # consequence of cache db tampering, this check, if enforced (opt in),
        # will throw an ApiError, meaning we can retry.
        if options.check and self.nbNewPosts isnt newPosts.length
          Q.reject new ApiError "BUG ? #{self.nbNewPosts} new posts but we got only #{newPosts.length} records!"
        else
          # Prepend new posts (newest first like the API)
          self.posts = Array::concat.call [], newPosts, self.posts
          self

  process 0, true

###*
@name downloadFile -- Downloads a file but optimize by first issuing a HEAD request.
@param output (String): output file name
@param url (String): URL to download file from
@param timestamp (String): specified because of return value being spreaded. Unused here.

NOTE: We compare files not by their timestamp but by their file sizes.
###
downloadFile = (output, url, timestamp) ->
  file = "#{options.dest}/#{output}"
  try
    stats = fs.statSync(file)
    isFile = stats.isFile()
  catch
    isFile = false

  {size} = stats if isFile

  promiseRetry ->
    api url, 'HEAD'
    .then (response) ->
      contentLength = parseInt response.headers['content-length']
      if !options.force and (size is contentLength)
        log.notice '! Skipping', output, 'file has the same size (', size, 'bytes).\n'
        return false

      log.debug 'Remote file size:', contentLength, 'local file:', size, '\n'

      bhttp.get url, stream:true
    .then (stream) ->
      if stream
        stream.on 'progress', (completed, total) ->
          log.info 'Download progress', path.basename(file), ':', ((completed / total) * 100).toFixed(2), '%\r'
        stream.on 'error', (error) ->
          log.error 'While writing to file', error
        stream.on 'response', (response) ->
          {statusCode} = response
          log.info 'in response', statusCode, '\n'

          # A bit hacky but basically, everything not 2XX will be retried.
          if statusCode / 100 isnt 2
            Q.reject new ApiError 'While downloading file, wrong statusCode returned', statusCode

          unless /image/.test response.headers['content-type']
            Q.reject new ApiError 'Content-Type mismatch:', response.headers['content-type']
        stream.on 'finish', ->
          if fileSize is expectedSize
            log.info "✔ #{url} (#{statusCode}) -> #{file}\n"
            Q(true)
          else
            Q.reject new ApiError 'Connection reset. Retrying.'
        stream.pipe fs.createWriteStream file

###*
@name main -- this starts here!
###
main = ->
  # Parse options first
  res = options.parse()

  # If we have a number, we should stop right away (error code).
  return res if typeof res is 'number'

  {blogname, dest} = options

  # Promise to...
  Q.Promise (accept, reject, notify) ->
    # Create destination if it does not exist.
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

    # See if we already have a cache (.tumblrip file) in our destination directory.
    # If so, load it, otherwise we initialize an empty 'database'.
    try
      if fs.statSync(cacheFile).isFile()
        readFile cacheFile
        .then (data) ->
          [cacheFile, JSON.parse data]
    catch e
      [cacheFile, {}]
  .spread (cacheFile, cache) ->
    # Populate cache with fresh data (insert/update)
    [cacheFile, getPostsData.call cache, blogname]
  .spread (cacheFile, blog) ->
    {title, total, posts, nbNewPosts} = blog
    log.info 'Blog title:', title, '\n'
    log.info 'New posts since last update', nbNewPosts, '\n'
    log.info 'Blog total posts:', total, '\n'
    log.info 'Blog unique photos:', posts.length, '\n'
    log.info 'Duplicates:', total-posts.length, '\n'

    # We remove 'nbNewPosts' as it is going to change and not relevant to store.
    delete blog.nbNewPosts

    # We store the 'database' as a plain old JSON, should/can be optimized a bit probably..
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
    # If we want to refresh photos we can only count those we know they exist
    # in the blog. Any other file previously stored will never have a chance to
    # be downloaded again!
    {startAt} = options
    if options['refresh-photos']
      if total < startAt
        throw new Error "Starting at #{startAt} is above maximum blog photos #{total}!"
      else
        nbNewPosts = total - startAt

    # If user wants to limit the number of downloaded images, make sure it is not
    # more than the maximum expected from Tumblr API.
    nbNewPosts = options.limit if options.limit > 0 and options.limit < nbNewPosts

    if nbNewPosts > 0
      log.info "Processing #{nbNewPosts} photos on #{options.threads} threads.\n"

      threaded = (start) ->
        threads = posts[start...start+options.threads]
        log.debug "Starting at #{start}:", threads, '\n'
        # Turning the promise of an array into an array of promises
        allDone threads.map (post) ->
          downloadFile.apply null, post
        .then -> Q.delay options.delay
        .then ->
          start += options.threads
          # Since posts array is sorted from the newest items, we can stop when
          # we reach (or go beyond) the 'nbNewPosts' value.
          if start > total or start >= nbNewPosts
            nbNewPosts
          else
            threaded start

      threaded startAt
    else
      log.info 'No new picture. If you want to force update, add --refresh-photos [-rp].\n'
      1
  .then (nbNewPosts) ->
    log.info "Processed #{nbNewPosts} images.\n"
    process.exit nbNewPosts
  , (error) ->
    log.error error.message, '\n'
    log.debug error, '\n'
    process.exit 0
  , (notice) ->
    log.notice notice

exports.main = main
