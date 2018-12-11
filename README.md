# http

Ponylang package to build client and server applications for the HTTP protocol.

[![CircleCI](https://circleci.com/gh/ponylang/http/tree/master.svg?style=svg)](https://circleci.com/gh/ponylang/http/tree/master)

## Status

This is the Pony HTTP/1 library from the standard library, formerly known as `net/http`.
It contains both an HTTP client to issue HTTP requests against HTTP servers, and
an HTTP server. It also contains a library for handling and parsing URLs.

It was removed from the stdlib with [0.24.0](https://github.com/ponylang/ponyc/releases/tag/0.24.0) as a result of
[RFC 55](https://github.com/ponylang/rfcs/blob/master/text/0055-remove-http-server-from-stdlib.md).
The Pony Team decided to remove it from the stdlib as is did not meet their quality standards.
Given the familiarity of most people with HTTP and thus the attention this library gets,
it was considered wiser to remove it from the stdlib and give it a new home as a separate
package, where it will not be subject to RFCs in order to rework its innarts.

### Help us improve

It is considered established knowledge that this library needs a complete rework.
If you would like to contribute turning this http library into the shape it should be in
for representing the power of Ponylang, drop us a note on any of the issues marked as
[Help Wanted](https://github.com/ponylang/http/labels/help%20wanted).


## Installation

* Add `http` to your build dependencies using [pony-stable](https://github.com/ponylang/pony-stable):

```bash
stable add github ponylang/http
```

* Execute `stable fetch` to fetch your dependencies.
* Include this package by adding `use "http"` to your Pony sources.
* Execute `stable env ponyc` to compile your application

