use "valbytes"

interface tag HTTPSession
  """
  An HTTP Session is the external API to the communication link
  between client and server.

  Every request is executed as part of a HTTP Session.
  A HTTP Session lives as long as the underlying TCP connection and receives
  request data from it and writes response data to it.

  Receiving data and parsing this data to HTTP requests is happening on
  the TCPConnection actor. The HTTPSession actor, started when a new TCPConnection
  is accepted, is called with request results.

  ### Receiving a Request

  ### Sending a Response

  """
  ////////////////////////
  // API THAT CALLS YOU //
  ////////////////////////
  be _receive_start(request: HTTPRequest val, request_id: RequestId)
    """
    receive a request...


    The appropriate Payload Builder will call this from the `TCPConnection`
    actor to start delivery of a new *inbound* message. If the `Payload`s
    `transfer_mode` is `OneshotTransfer`, this is the only notification
    that will happen for the message. Otherwise there will be one or more

    """

  be _receive_chunk(data: Array[U8] val, request_id: RequestId)
    """
    """

  be _receive_finished(request_id: RequestId)
    """
    Indicate that the current inbound request has been fully received.
    """

  be _receive_failed(parse_error: RequestParseError, request_id: RequestId) =>
    """ignored by default."""
    None

  ///////////////////////
  // API THAT YOU CALL //
  ///////////////////////


  // verbose api
  be send_start(respone: HTTPResponse val, request_id: RequestId)
    """
    Start sending a response.
    """

  be send_chunk(data: ByteSeq val, request_id: RequestId)

  be send_finished(request_id: RequestId)

  be send_cancel(request_id: RequestId)

  // simple api
  be send_no_body(response: HTTPResponse val, request_id: RequestId)
  be send(response: HTTPResponse val, body: ByteArrays, request_id: RequestId)

  // optimized raw api
  be send_raw(raw: ByteSeqIter, request_id: RequestId)

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



