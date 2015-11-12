Tumblrip
========

Welcome Tumblr user ! I have longed search for a decent tool to backup/rip photos
from my favorites blogs and found no application to handle this nicely.

TumblrRipper exists on Windows. This tool aims to provide similar functionality
for command line fellows.

Installation
============

As usual with __NodeJS__ and __NPM__:

```bash
# npm i tumblrip -g
```

Usage
=====

```
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
```

Notes
=====

The first [Q.Promise](https://github.com/kriskowal/q)-based Tumblr download tool
I know of ! It shows different uses of ```Promise``` API.

License
=======

MIT

TODO
====

- Bug fixing
- Add full Tumblr backup capability
- Shrink database

Feedback/PR are of course most welcomed !

Enjoy :smile:
