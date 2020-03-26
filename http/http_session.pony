use "valbytes"

interface tag HTTPSession
  """
  An HTTP Session is the external API to the communication link
  between client and server.

  Every request is executed as part of a HTTP Session.
  An HTTP Session lives as long as the underlying TCP connection and receives
  request data from it and writes response data to it.

  Receiving data and parsing this data into [HTTPRequest](http-HTTPRequest.md)s is happening on
  the TCPConnection actor. The [HTTPSession](http-HTTPSession.md) actor is started when a new TCPConnection
  is accepted, and shut down, when the connection is closed.

  ### Receiving a Request

  As part of the Request-Response handling internal to this HTTP library,
  a HTTPSession is instantiated that forwards requests to a [HTTPHandler](http-HTTPHandler.md),
  to actual application code, which in turn sends Responses back to the HTTPSession instance
  it was instantiated with (See [HTTPHandlerFactory](http-HTTPHandlerFactory.md).

  See [HTTPHandler](http-HTTPHandler.md) on how requests are received by application code.

  ### Sending a Response


  """
  ////////////////////////
  // API THAT CALLS YOU //
  ////////////////////////
  be _receive_start(request: HTTPRequest val, request_id: RequestId)
    """
    Start receiving a request.

    This will be called when all headers of an incoming request have been parsed.
    [HTTPRequest](http-HTTPRequest.md) contains all information extracted from
    these parts.

    The [RequestId](http-RequestId.md) is passed in order for the HTTPSession
    implementation to maintain the correct request order in case of HTTP pipelining.
    Response handling can happen asynchronously at arbitrary times, so the RequestId
    helps us to get the responses back into the right order, no matter how they
    are received from the application.
    """

  be _receive_chunk(data: Array[U8] val, request_id: RequestId)
    """
    Receive a chunk of body data for the request identified by `request_id`.

    The body is split up into arbitrarily sized data chunks, whose size is determined by the
    underlying protocol mechanisms, not the actual body size.
    """

  be _receive_finished(request_id: RequestId)
    """
    Indicate that the current inbound request, including the body, has been fully received.
    """

  be _receive_failed(parse_error: RequestParseError, request_id: RequestId) =>
    """
    Nofitcation if the request parser failed to parse incoming data as HTTPRequest.

    Ignored by default.
    """
    None

  ///////////////////////
  // API THAT YOU CALL //
  ///////////////////////


  // verbose api
  be send_start(respone: HTTPResponse val, request_id: RequestId)
    """
    ### Verbose API

    Start sending a response, submitting the Response status and headers.

    Sending a response via the verbose API needs to be done in 2 or more steps:

    * HTTPSession.send_start    - exactly once    - submit status and headers
    * HTTPSession.send_chunk    - 0 or more times - submit body
    * HTTPSession.send_finished - exactly once    - clean up resources
    """

  be send_chunk(data: ByteSeq val, request_id: RequestId)
    """
    ### Verbose API

    Send a piece of body data of the request identified by `request_id`.
    This might be the whole body or just a piece of it.

    Notify the HTTPSession that the body has been fully sent, by calling `HTTPSession.send_finished`.
    """

  be send_finished(request_id: RequestId)
    """
    ### Verbose API

    Indicate that the response for `request_id` has been completed,
    that is, its status, headers and body have been sent.

    This will clean up resources on the session and
    might send pending pipelined responses in addition to this response.

    If this behaviour isnt called, the server might misbehave, especially
    with clients doing HTTP pipelining.
    """

  be send_cancel(request_id: RequestId)
    """
    Cancel sending an in-flight response.
    As the HTTPSession will be invalid afterwards, as the response might not have been sent completely,
    it is best to close the session afterwards using `HTTPSession.dispose()`.
    """

  // simple api
  be send_no_body(response: HTTPResponse val, request_id: RequestId)
    """
    ### Simple API

    Send a bodyless HTTPResponse in one call.

    This call will do all the work of sending the response and cleaning up resources.
    No need to call `HTTPSession.send_finished()` anymore for this request.
    """

  be send(response: HTTPResponse val, body: ByteArrays, request_id: RequestId)
    """
    ### Simple API

    Send an HTTPResponse with a body in one call.

    The body must be a [ByteArrays](valbytes-ByteArrays.md) instance.

    Example:

    ```pony
    // ...
    var bytes = ByteArrays
    bytes = bytes + "first line" + "\n"
    bytes = bytes + "second line" + "\n"
    bytes = bytes + "third line"

    session.send(response, bytes, request_id)
    // ...
    ```

    This call will do all the work of sending the response and cleaning up resources.
    No need to call `HTTPSession.send_finished()` anymore for this request.
    """

  // optimized raw api
  be send_raw(raw: ByteSeqIter, request_id: RequestId)
    """
    ### Optimized raw API

    Send raw bytes to the HTTPSession in form of a [ByteSeqIter](builtin-ByteSeqIter.md).

    These bytes may or may not include the response body.
    You can use `HTTPSession.send_chunk()` to send the response body piece by piece.

    To finish sending the response, it is required to call `HTTPSession.send_finished()`
    to wrap things up, otherwise the server might misbehave.

    This API uses the [TCPConnection.writev](net-TCPConnection.md#writev) method to
    optimize putting the given bytes out to the wire.

    To make this optimized path more usable, this library provides the [ResponseBuilder](http-ResponseBuilder.md),
    which builds up a response into a [ByteSeqIter](builtin-ByteSeqIter.md), thus taylored towards
    being used with this API.

    Example:

    ```pony
    class MyHTTPHandler is HTTPHandler
      let _session: HTTPSession

      new create(session: HTTPSession) =>
        _session = session

      fun ref apply(request: HTTPRequest val, request_id: RequestId): Any =>
        let body =
          match request.content_length()
          | let cl: USize =>
            "You've sent us " + cl.string() + " bytes! Thank you!"
          | None if request.transfer_coding() is Chunked =>
            "You've sent us some chunks! That's cool!"
          | None =>
            "Dunno how much you've sent us. Probably nothing. That's alright."
          end

        _session.send_raw(
          HTTPResponses.builder()
            .set_status(StatusOK)
            .add_header("Content-Type", "text/plain; charset=UTF-8")
            .add_header("Content-Length", body.size().string())
            .finish_headers()
            .add_chunk(body)
            .build(),
          request_id
        )
        // never forget !!!
        _session.send_finished(request_id)
    ```
    """

  be dispose()
    """
    Close the connection from this end.
    """

  be _mute()
    """
    Stop delivering *incoming* data to the handler. This may not
    be effective instantly.
    """

  be _unmute()
    """
    Resume delivering incoming data to the handler.
    """



