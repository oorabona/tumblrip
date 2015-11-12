nopt = require 'nopt'
path = require 'path'
{log, deepExtend} = require './utils'

exports.VERSION = VERSION = require('../package.json').version

exports.DEFAULT_OPTIONS = DEFAULT_OPTIONS =
  verbose: false
  debug: false
  force: false
  cache: true
  check: false
  colors: true
  delay: 500
  threads: 5
  retries: 3
  startAt: 0
  'retry-factor': 2
  'refresh-db': false
  'refresh-photos': false

longOptions =
  version: Boolean
  help: Boolean
  verbose: Boolean
  debug: Boolean
  colors: Boolean
  cache: Boolean
  check: Boolean
  force: Boolean
  delay: Number
  retries: Number
  threads: Number
  startAt: Number
  'retry-factor': Number
  'refresh-db': Boolean
  'refresh-photos': Boolean

shortOptions =
  v: [ '--version' ]
  h: [ '--help' ]
  d: [ '--delay' ]
  D: [ '--debug' ]
  c: [ '--cache' ]
  C: [ '--check' ]
  f: [ '--force' ]
  r: [ '--retries' ]
  s: [ '--startAt' ]
  t: [ '--threads' ]
  nc: [ '--no-colors' ]
  rf: [ '--retry-factor' ]
  rd: [ '--refresh-db' ]
  rp: [ '--refresh-photos' ]

showVersion = ->
  log "tumblrip version #{VERSION}"
  0

showHelp = ->
  log HELP
  0

HELP = """
tumblrip #{VERSION}
usage: tumblrip [options] blogname [destination]

http://<blogname>.tumblr.com/ will have photos retrieved to destination.
If a `destination` is supplied and the path does not exist, it will be created.
If no destination set, current directory is assumed.

options:
  --version [-v]            : display version/build
  --help [-h]               : this help
  --delay [-d]              : add a delay (in ms) between requests
                            : (default: 500, empty: random)
  --debug [-D]              : enable more debug output (default: false)
  --cache [-c]              : enable/disable cache (default: true)
  --check [-C]              : enforce additional consistency checks (slower)
  --force [-f]              : force overwrite if file exists (default: false)
  --retries [-r]            : number of retries before giving up (default: 3)
  --threads [-t]            : maximum simultaneous connections to tumblr.com
                            : (default: 5)
  --retry-factor [-rf]      : if throttling, multiply delay by this factor
                            : (default: 2)
  --refresh-db [-rd]        : update database
  --refresh-photos [-rp]    : update photos
  --startAt [-s]            : start at a specific index in the posts database
                            : (default: 0)

"""

exports.parse = ->
  args = nopt longOptions, shortOptions

  options = deepExtend {}, DEFAULT_OPTIONS, args
  deepExtend exports, options

  log.verbose = options.verbose
  log.DEBUG = options.debug
  log.colors = options.colors

  return showHelp() if options.help
  return showVersion() if options.version

  {remain} = options.argv

  switch remain.length
    when 1
      exports.blogname = remain[0]
      exports.dest = '.'
    when 2
      exports.blogname = remain[0]
      exports.dest = remain[1]
    else
      return showHelp()

  options
