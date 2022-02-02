# http

Ponylang package to build clients for the HTTP protocol.

## Status

`http` is beta quality software that will change frequently. Expect breaking changes. That said, you should feel comfortable using it in your projects.

## Installation

* Add `http` to your build dependencies using [corral](https://github.com/ponylang/corral):

```bash
corral add github.com/ponylang/http.git --version 0.5.0
```

* Execute `corral fetch` to fetch your dependencies.
* Include this package by adding `use "http"` to your Pony sources.
* Execute `corral run -- ponyc` to compile your application

Note: The `net-ssl` transitive dependency requires a C SSL library to be installed. Please see the [net-ssl installation instructions](https://github.com/ponylang/net-ssl#installation) for more information.

## API Documentation

[https://ponylang.github.io/http](https://ponylang.github.io/http)
