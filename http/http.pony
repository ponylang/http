"""
This package includes all the support functions necessary to build client
applications for the HTTP protocol.

The important interfaces an application needs to deal with are:

* [HTTPSession](/http/http-HTTPSession/), the API to an HTTP connection.

* [HTTPHandler](/http/http-HTTPHandler/), the interface to a handler you
need to write that will receive notifications from the `HTTPSession`.

* [HandlerFactory](/http/http-HandlerFactory/), the interface to a class you
need to write that creates instances of your `HTTPHandler`.

* [Payload](/http/http-Payload/), the class that represents a single HTTP
message, with its headers.

If you are writing a client, you will need to deal with the
[HTTPClient](/http/http-HTTPClient/) class.

If you are writing a server, you should look at the
[Server](https://ponylang.github.io/http_server/http_server-Server/)
class in the [http_server](https://ponylang.github.io/http_server) package.

"""
