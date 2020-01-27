interface tag HTTPSession
  """
  An HTTP Session is the external API to the communication link
  between client and server. A session can only transfer one message
  at a time in each direction. The client and server each have their
  own ways of implementing this interface, but to application code (either
  in the client or in the server 'back end') this interface provides a
  common view of how information is passed *into* the `http` package.
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
  be send_start(respone: HTTPResponse val, request_id: RequestId)
    """
    Start sending a response.
    """

  be send_chunk(data: ByteSeq val, request_id: RequestId)

  be send_cancel(request_id: RequestId)

  be send_finished(request_id: RequestId)

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



