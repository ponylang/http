interface HTTPHandler
  """
  This is the interface through which HTTP requests are delivered *to*
  application code and through which HTTP responses are sent to the underlying connection.

  Instances of a HTTPHandler are executed in the context of the `HTTPSession` actor so most of them should be
  passing data on to a processing actor.

  Each `HTTPSession` must have a unique instance of the handler. The
  application code does not necessarily know when an `HTTPSession` is created,
  so the application must provide an instance of `HandlerFactory` that
  will be called at the appropriate time.

  ### Receiving Requests

  When an [HTTPRequest](http-HTTPRequest.md) is received on an [HTTPSession](http-HTTPSession.md) actor,
  the corresponding [HTTPHandler.apply](http-HTTPHandler.md#apply) method is called
  with the request and a [RequestID](http-RequestID). The [HTTPRequest](http-HTTPRequest.md)
  contains the information extracted from HTTP Headers and the Request Line, but it does not
  contain any body data. It is sent to [HTTPHandler.apply](http-HTTPHandler.md#apply) before the body
  is fully received.

  If the request has a body, its raw data is sent to the [HTTPHandler.chunk](http-HTTPHandler.md#chunk) method
  together with the [RequestID](http-RequestID.md) of the request it belongs to.

  Once all body data is received, [HTTPHandler.finished](http-HTTPHandler.md#finished) is called with the
  [RequestID](http-RequestID.md) of the request it belongs to. Now is the time to act on the full body data,
  if it hasn't been processed yet.

  The [RequestID](http-Requestid.md) must be kept around for sending the response for this request.
  This way the session can ensure, all responses are sent in the same order as they have been received,
  which is required for HTTP pipelining. This way processing responses can be passed to other actors and
  processing can take arbitrary times. The [HTTPSession](http-HTTPSession.md) will take care of sending
  the responses in the correct order.

  It is guaranteed that the call sequence is always:

  - exactly once:       `apply(request_n, requestid_n)`
  - zero or more times: `chunk(data, requestid_n)`
  - exactly once:       `finished(requestid_n)`

  And so on for `requestid_(n + 1)`. Only after `finished` has been called for a
  `RequestID`, the next request will be received by the HTTPHandler instance, there will
  be no interleaving. So it is save to keep state for the given request in a Handler between calls to `apply`
  and `finished`.

  #### Failures and Cancelling

  If a [HTTPSession](http-HTTPSession.md) experienced faulty requests, the [HTTPHandler](http-HTTPHandler.md)
  is notified via [HTTPHandler.failed](http-HTTPHandler.md#failed).

  If the underlying connection to a [HTTPSession](http-HTTPSession.md) has been closed,
  the [HTTPHandler](http-HTTPHandler.md) is notified via [HTTPHandler.closed](http-HTTPHandler.md#closed).

  ### Sending Responses

  A handler is instantiated using a [HandlerFactory](http-HandlerFactory.md), which passes an instance of
  [HTTPSession](http-HTTPSession.md) to be used in constructing a handler.

  A HTTPSession is required to be able to send responses.
  See the docs for [HTTPSession](http-HTTPSession.md) for ways to send responses.

  Example Handler:

  ```pony
  use "http"
  use "valbytes"

  class MyHTTPHandler is HTTPHandler
    let _session: HTTPSession

    var _path: String = ""
    var _body: ByteArrays = ByteArrays

    new create(session: HTTPSession) =>
      _session = session

    fun ref apply(request: HTTPRequest val, request_id: RequestID): Any =>
      _path = request.uri().path

    fun ref chunk(data: ByteSeq val, request_id: RequestID) =>
      _body = _body + data

    fun ref finished(request_id: RequestID) =>
      _session.send_raw(
        HTTPResponses.builder()
          .set_status(StatusOk)
          .add_header("Content-Length", (_body.size() + _path.size() + 13).string())
          .add_header("Content-Type", "text/plain")
          .finish_headers()
          .add_chunk("received ")
          .add_chunk((_body = ByteArrays).array())
          .add_chunk(" at ")
          .add_chunk(_path)
          .build(),
        request_id
      )
      _session.send_finished(request_id)
  ```

  """
  fun ref apply(request: HTTPRequest val, request_id: RequestID): Any =>
    """
    Notification of an incoming message.

    Only one HTTP message will be processed at a time, and that starts
    with a call to this method.
    """

  fun ref chunk(data: ByteSeq val, request_id: RequestID) =>
    """
    Notification of incoming body data. The body belongs to the most
    recent `HTTPRequest` delivered by an `apply` notification.
    """

  fun ref finished(request_id: RequestID) =>
    """
    Notification that no more body chunks are coming. Delivery of this HTTP
    message is complete.
    """

  fun ref cancelled(request_id: RequestID) =>
    """
    Notification that sending a response has been cancelled locally,
    e.g. by closing the server or manually cancelling a single request.
    """

  fun ref failed(reason: RequestParseError, request_id: RequestID) =>
    """
    Notification about failure parsing HTTP requests.
    """

  fun ref closed() =>
    """
    Notification that the underlying connection has been closed.
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
    Called by the [HTTPSession](http-HTTPSession.md) when it needs a new instance of the
    application's [HTTPHandler](http-HTTPHandler.md). It is suggested that the
    `session` value be passed to the constructor for the new
    [HTTPHandler](http-HTTPHandler.md), you will need it for sending stuff back.

    This part must be implemented, as there might be more paramaters
    that need to be passed for creating a HTTPHandler.
    """

interface HTTPHandlerWithoutContext is HTTPHandler
  """
  Simple [HTTPHandler](http-HTTPHandler.md) that can be constructed
  with only a HTTPSession.
  """
  new create(session: HTTPSession)


primitive SimpleHandlerFactory[T: HTTPHandlerWithoutContext]
  """
  HandlerFactory for a HTTPHandlerWithoutContext.

  Just create it like:

  ```pony
  let server =
    HTTPServer(
      ...,
      SimpleHandlerFactory[MySimpleHandler],
      ...
    )
  ```

  """
  fun apply(session: HTTPSession): HTTPHandler ref^ =>
    T.create(session)
