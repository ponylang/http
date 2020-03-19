"""
This package includes all the support functions necessary to build client
and server applications for the HTTP protocol.

The important interfaces an application needs to deal with are:

* [HTTPSession](http-HTTPSession), the API to an HTTP connection.

* [HTTPHandler](http-HTTPHandler), the interface to a handler you
need to write that will receive notifications from the `HTTPSession`.

* [HandlerFactory](http-HandlerFactory), the interface to a class you
need to write that creates instances of your `HTTPHandler`.

* [Payload](http-Payload), the class that represents a single HTTP
message, with its headers.

If you are writing a client, you will need to deal with the
[HTTPClient](http-HTTPClient) class.

If you are writing a server, you will need to deal with the
[HTTPServer](http-HTTPServer) class.

"""

primitive AuthFailed
  """
  HTTP failure reason for when SSL Authentication failed.

  This failure reason is only reported to HTTP client HTTPHandler instances.
  """

primitive ConnectionClosed
  """
  HTTP failure reason for when the connection was closed
  either from the other side (detectable when using TCP keepalive)
  or locally (e.g. due to an error).
  """
primitive ConnectFailed
  """
  HTTP failure reason for when a connection could not be established.

  This failure reason is only valid for HTTP client HTTPHandlers.
  """

type HTTPFailureReason is (
  AuthFailed |
  ConnectionClosed |
  ConnectFailed |
  RequestParseError
  )
  """
  HTTP failure reason reported to `HTTPHandler.failed()`.
  """

interface HTTPHandler
  """
  This is the interface through which HTTP messages are delivered *to*
  application code. On the server, this will be HTTP Requests (GET,
  HEAD, DELETE, POST, etc) sent from a client. On the client, this will
  be the HTTP Responses coming back from the server. The protocol is largely
  symmetrical and the same interface definition is used, though what
  processing happens behind the interface will of course vary.

  This interface delivers asynchronous events when receiving an HTTP
  message (called a `Payload`). Calls to these methods are made in
  the context of the `HTTPSession` actor so most of them should be
  passing data on to a processing actor.

  Each `HTTPSession` must have a unique instance of the handler. The
  application code does not necessarily know when an `HTTPSession` is created,
  so the application must provide an instance of `HandlerFactory` that
  will be called at the appropriate time.
  """
  fun ref apply(request: HTTPRequest val, request_id: RequestId): Any =>
    """
    Notification of an incoming message.

    Only one HTTP message will be processed at a time, and that starts
    with a call to this method.
    """

  fun ref chunk(data: ByteSeq val, request_id: RequestId) =>
    """
    Notification of incoming body data. The body belongs to the most
    recent `HTTPRequest` delivered by an `apply` notification.
    """

  fun ref finished(request_id: RequestId) =>
    """
    Notification that no more body chunks are coming. Delivery of this HTTP
    message is complete.
    """

  fun ref cancelled(request_id: RequestId) =>
    """
    Notification that transferring the payload has been cancelled locally,
    e.g. by disposing the client, closing the server or manually cancelling a single request.
    """

  fun ref failed(reason: HTTPFailureReason, request_id: RequestId) =>
    """
    Notification about failure to transfer the payload
    (e.g. connection could not be established, authentication failed, connection was closed prematurely, ...)
    """

  fun ref throttled() =>
    """
    Notification that the session temporarily can not accept more data.
    """

  fun ref unthrottled() =>
    """
    Notification that the session can resume accepting data.
    """


interface HandlerFactory
  """
  The TCP connections that underlie HTTP sessions get created within
  the `http` package at times that the application code can not
  predict. Yet, the application code has to provide custom hooks into
  these connections as they are created. To accomplish this, the
  application code provides an instance of a `class` that implements
  this interface.

  The `HandlerFactory.apply` method will be called when a new
  `HTTPSession` is created, giving the application a chance to create
  an instance of its own `HTTPHandler`. This happens on both
  client and server ends.
  """

  fun apply(session: HTTPSession): HTTPHandler ref^
    """
    Called by the `HTTPSession` when it needs a new instance of the
    application's `HTTPHandler`. It is suggested that the
    `session` value be passed to the constructor for the new
    `HTTPHandler` so that it is available for making
    `throttle` and `unthrottle` calls.
    """
