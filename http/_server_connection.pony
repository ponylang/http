use "net"
use "collections"
use "valbytes"
use "debug"
use "time"

actor _ServerConnection is HTTPSession
  """
  Manages a stream of requests coming into a server from a single client,
  dispatches those request to a back-end, and returns the responses back
  to the client.

  TODO: how to handle 101 Upgrade - set new notify for the connection
  """
  let _backend: HTTPHandler
  let _config: HTTPServerConfig
  let _conn: TCPConnection
  var _close_after: (RequestId | None) = None

  var _active_request: RequestId = RequestIds.max_value()
    """
    keeps the request_id of the request currently active.
    That is, that has been sent to the backend last.
    """
  var _sent_response: RequestId = RequestIds.max_value()
    """
    Keeps track of the request_id for which we sent a response already
    in order to determine lag in request handling.
    """
  let _pending_responses: _PendingResponses = _PendingResponses.create()

  var _last_activity_ts: I64 = Time.seconds()

  new create(
    handlermaker: HandlerFactory val,
    config: HTTPServerConfig,
    conn: TCPConnection)
  =>
    """
    Create a connection actor to manage communication with to a new
    client. We also create an instance of the application's back-end
    handler that will process incoming requests.
    """
    _backend = handlermaker(this)
    _config = config
    _conn = conn


  fun ref _reset_timeout() =>
    _last_activity_ts = Time.seconds()

  be _receive_start(request: HTTPRequest val, request_id: RequestId) =>
    _reset_timeout()
    _active_request = request_id
    // detemine if we need to close the connection after this request
    match (request.version(), request.header("Connection"))
    | (HTTP11, "close") =>
      _close_after = request_id
    | (HTTP10, let connection_header: String) if connection_header != "Keep-Alive" =>
      _close_after = request_id
    end
    _backend(request, request_id)
    if _pending_responses.size() >= _config.max_request_handling_lag then
      // Backpressure incoming requests if the queue grows too much.
      // The backpressure prevents filling up memory with queued
      // requests in the case of a runaway client.
      _conn.mute()
    end

  be _receive_chunk(data: ByteSeq val, request_id: RequestId) =>
    """
    Receive some `request` body data, which we pass on to the handler.
    """
    _reset_timeout()
    _backend.chunk(data, request_id)

  be _receive_finished(request_id: RequestId) =>
    """
    Inidcates that the last *inbound* body chunk has been sent to
    `_chunk`. This is passed on to the back end.
    """
    _backend.finished(request_id)

  be _receive_failed(parse_error: RequestParseError, request_id: RequestId) =>
    _backend.failed(parse_error, request_id)
    // TODO: close the connection?

  be dispose() =>
    """
    Close the connection from the server end.
    """
    _conn.dispose()

  be closed() =>
    _backend.failed(ConnectionClosed, _active_request)
    _conn.unmute()

//// SEND RESPONSE API ////
//// STANDARD API

  be send_start(response: HTTPResponse val, request_id: RequestId) =>
    """
    Initiate transmission of the HTTP Response message for the current
    Request.
    """
    _send_start(response, request_id)


  fun ref _send_start(response: HTTPResponse val, request_id: RequestId) =>
    _conn.unmute()
    let expected_id = RequestIds.next(_sent_response)
    if request_id == expected_id then
      // just send it through. all good
      _sent_response = request_id
      _send(response)
    elseif RequestIds.gt(request_id, expected_id) then
      Debug("received response out of order. store it for later.")
      // add serialized response to pending requests
      _pending_responses.add_pending(request_id, response.array())
    else
      // request_id < _active_request
      // latecomer - ignore
      None
    end

  fun ref _send(response: HTTPResponse val) =>
    """
    Send a single response to the underlying TCPConnection.
    """
    _reset_timeout()
    _conn.write(response.array())

  be send_chunk(data: ByteSeq val, request_id: RequestId) =>
    """
    Write low level outbound raw byte stream.
    """
    if request_id == _sent_response then
      _reset_timeout()
      _conn.write(data)
    elseif RequestIds.gt(request_id, _active_request) then
      _pending_responses.append_data(request_id, data)
    else
      None // latecomer, ignore
    end

  be send_finished(request_id: RequestId) =>
    """
    We are done sending a response. We close the connection if
    `keepalive` was not requested.
    """
    _send_finished(request_id)


  fun ref _send_finished(request_id: RequestId) =>
    // check if the next request_id is already in the pending list
    // if so, write it
    var rid = request_id
    while _pending_responses.has_pending() do
      match _pending_responses.pop(RequestIds.next(rid))
      | (let next_rid: RequestId, let response_data: ByteSeqIter) =>
        Debug("also sending next response for request: " + next_rid.string())
        rid = next_rid
        _sent_response = next_rid
        _reset_timeout()
        _conn.writev(response_data)
      else
        // next one not available yet
        break
      end
    end
    match _close_after
    | let close_after_me: RequestId if RequestIds.gte(request_id, close_after_me) =>
      // only close after a request that requested it
      // in case of pipelining, we might receive a response for another, later
      // request earlier and would close prematurely.
      _conn.dispose()
    end

  be send_cancel(request_id: RequestId) =>
    """
    Cancel the current response.

    TODO: keep this???
    """
    _cancel(request_id)

  fun ref _cancel(request_id: RequestId) =>
    if (_active_request - _sent_response) != 0 then
      // we still have some stuff in flight at the backend
      _backend.cancelled(request_id)
    end

//// CONVENIENCE API

  be send_no_body(response: HTTPResponse val, request_id: RequestId) =>
    """
    Start and finish sending a response without a body.

    This function calls `send_finished` for you, so no need to call it yourself.
    """
    _send_start(response, request_id)
    _send_finished(request_id)

  be send(response: HTTPResponse val, body: ByteArrays, request_id: RequestId) =>
    """
    Start and finish sending a response with body.
    """
    _send_start(response, request_id)
    if request_id == _sent_response then
      _reset_timeout()
      _conn.writev(body.arrays())
      _send_finished(request_id)
    elseif RequestIds.gt(request_id, _active_request) then

      _pending_responses.add_pending_arrays(
        request_id,
        body.arrays().>unshift(response.array())
      )
    else
      None // latecomer, ignore
    end

//// OPTIMIZED API

  be send_raw(raw: ByteSeqIter, request_id: RequestId) =>
    """
    If you have your response already in bytes, and don't want to build an expensive
    [HTTPResponse](http-HTTPResponse) object, use this method to send your [ByteSeqIter](builtin-ByteSeqIter).
    This `raw` argument can contain only the response without body,
    in which case you can send the body chunks later on using `send_chunk`,
    or, to further optimize your writes to the network, it might already contain
    the response body.

    In each case, finish sending your raw response using `send_finished`.
    """
    _conn.unmute()
    let expected_id = RequestIds.next(_sent_response)
    if request_id == expected_id then
      _sent_response = request_id
      _reset_timeout()
      _conn.writev(raw)
    elseif RequestIds.gt(request_id, expected_id) then
      _pending_responses.add_pending_arrays(request_id, raw)
    end

  be throttled() =>
    """
    TCP connection can not accept data for a while.
    """
    _backend.throttled()

  be unthrottled() =>
    """
    TCP connection can not accept data for a while.
    """
    _backend.unthrottled()

  be _mute() =>
    _conn.mute()

  be _unmute() =>
    _conn.unmute()

  be _heartbeat(current_seconds: I64) =>
    let timeout = _config.connection_timeout.i64()
    //Debug("current_seconds=" + current_seconds.string() + ", last_activity=" + _last_activity_ts.string())
    if (timeout > 0) and ((current_seconds - _last_activity_ts) >= timeout) then
      //Debug("Connection timed out.")
      // backend is notified asynchronously when the close happened
      dispose()
    end

