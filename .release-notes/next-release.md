## Remove HTTP server code from repository

It is obsolete and defect by now. For HTTP servers [ponylang/http_server][1]
should be used.

[1]: https://github.com/ponylang/http_server

## Dont export test related classes

Prior to this change, internal test related classes were being exported when `use "http"` was done.

