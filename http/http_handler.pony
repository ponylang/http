interface Handler
  """
  This is the interface through which HTTP requests are delivered *to*
  application code and through which HTTP responses are sent to the underlying connection.

  Instances of a Handler are executed in the context of the `Session` actor so most of them should be
  passing data on to a processing actor.

  Each `Session` must have a unique instance of the handler. The
  application code does not necessarily know when an `Session` is created,
  so the application must provide an instance of `HandlerFactory` that
  will be called at the appropriate time.

  ### Receiving Requests

  When an [Request](http-Request.md) is received on an [Session](http-Session.md) actor,
  the corresponding [Handler.apply](http-Handler.md#apply) method is called
  with the request and a [RequestID](http-RequestID). The [Request](http-Request.md)
  contains the information extracted from HTTP Headers and the Request Line, but it does not
  contain any body data. It is sent to [Handler.apply](http-Handler.md#apply) before the body
  is fully received.

  If the request has a body, its raw data is sent to the [Handler.chunk](http-Handler.md#chunk) method
  together with the [RequestID](http-RequestID.md) of the request it belongs to.

  Once all body data is received, [Handler.finished](http-Handler.md#finished) is called with the
  [RequestID](http-RequestID.md) of the request it belongs to. Now is the time to act on the full body data,
  if it hasn't been processed yet.

  The [RequestID](http-Requestid.md) must be kept around for sending the response for this request.
  This way the session can ensure, all responses are sent in the same order as they have been received,
  which is required for HTTP pipelining. This way processing responses can be passed to other actors and
  processing can take arbitrary times. The [Session](http-Session.md) will take care of sending
  the responses in the correct order.

  It is guaranteed that the call sequence is always:

  - exactly once:       `apply(request_n, requestid_n)`
  - zero or more times: `chunk(data, requestid_n)`
  - exactly once:       `finished(requestid_n)`

  And so on for `requestid_(n + 1)`. Only after `finished` has been called for a
  `RequestID`, the next request will be received by the Handler instance, there will
  be no interleaving. So it is save to keep state for the given request in a Handler between calls to `apply`
  and `finished`.

  #### Failures and Cancelling

  If a [Session](http-Session.md) experienced faulty requests, the [Handler](http-Handler.md)
  is notified via [Handler.failed](http-Handler.md#failed).

  If the underlying connection to a [Session](http-Session.md) has been closed,
  the [Handler](http-Handler.md) is notified via [Handler.closed](http-Handler.md#closed).

  ### Sending Responses

  A handler is instantiated using a [HandlerFactory](http-HandlerFactory.md), which passes an instance of
  [Session](http-Session.md) to be used in constructing a handler.

  A Session is required to be able to send responses.
  See the docs for [Session](http-Session.md) for ways to send responses.

  Example Handler:

  ```pony
  use "http"
  use "valbytes"

  class MyHandler is Handler
    let _session: Session

    var _path: String = ""
    var _body: ByteArrays = ByteArrays

    new create(session: Session) =>
      _session = session

    fun ref apply(request: Request val, request_id: RequestID): Any =>
      _path = request.uri().path

    fun ref chunk(data: ByteSeq val, request_id: RequestID) =>
      _body = _body + data

    fun ref finished(request_id: RequestID) =>
      _session.send_raw(
        Responses.builder()
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
  fun ref apply(request: Request val, request_id: RequestID): Any =>
    """
    Notification of an incoming message.

    Only one HTTP message will be processed at a time, and that starts
    with a call to this method.
    """

  fun ref chunk(data: ByteSeq val, request_id: RequestID) =>
    """
    Notification of incoming body data. The body belongs to the most
    recent `Request` delivered by an `apply` notification.
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
  `Session` is created, giving the application a chance to create
  an instance of its own `Handler`. This happens on both
  client and server ends.
  """

  fun apply(session: Session): Handler ref^
    """
    Called by the [Session](http-Session.md) when it needs a new instance of the
    application's [Handler](http-Handler.md). It is suggested that the
    `session` value be passed to the constructor for the new
    [Handler](http-Handler.md), you will need it for sending stuff back.

    This part must be implemented, as there might be more paramaters
    that need to be passed for creating a Handler.
    """

interface HandlerWithoutContext is Handler
  """
  Simple [Handler](http-Handler.md) that can be constructed
  with only a Session.
  """
  new create(session: Session)


primitive SimpleHandlerFactory[T: HandlerWithoutContext]
  """
  HandlerFactory for a HandlerWithoutContext.

  Just create it like:

  ```pony
  let server =
    Server(
      ...,
      SimpleHandlerFactory[MySimpleHandler],
      ...
    )
  ```

  """
  fun apply(session: Session): Handler ref^ =>
    T.create(session)
