use "net"
use "collections"
use "valbytes"
use "debug"

actor _ServerConnection is HTTPSession
  """
  Manages a stream of requests coming into a server from a single client,
  dispatches those request to a back-end, and returns the responses back
  to the client.

  TODO: how to handle 101 Upgrade - set new notify for the connection
  """
  let _backend: HTTPHandler
  let _conn: TCPConnection
  var _keepalive: Bool = true

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
  let _max_request_handling_lag: USize = 100 // TODO: make configurable

  let _pending_responses: _PendingResponses = _PendingResponses.create()

  new create(
    handlermaker: HandlerFactory val,
    conn: TCPConnection)
  =>
    """
    Create a connection actor to manage communication with to a new
    client. We also create an instance of the application's back-end
    handler that will process incoming requests.
    """
    _backend = handlermaker(this)
    _conn = conn

  be _receive_start(request: HTTPRequest val, request_id: RequestId) =>
    """
    """
    _active_request = request_id
    _keepalive =
      match request.header("Connection")
      | "close" => false
      else
        // keepalive is the default in HTTP/1.1, not supported in HTTP/1.0
        request.version() isnt HTTP10
      end
    _backend(request, request_id)
    // TODO: handle wrap around
    if (_active_request - _sent_response).abs() >= _max_request_handling_lag then
      // Backpressure incoming requests if the queue grows too much.
      // The backpressure prevents filling up memory with queued
      // requests in the case of a runaway client.
      Debug("muting")
      _conn.mute()
    end

  be _receive_chunk(data: ByteSeq val, request_id: RequestId) =>
    """
    Receive some `request` body data, which we pass on to the handler.
    """
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

  be send_no_body(response: HTTPResponse val, request_id: RequestId) =>
    _send_start(response, request_id)
    _send_finished(request_id)

  be send(response: HTTPResponse val, body: ByteSeqIter, request_id: RequestId) =>
    _send_start(response, request_id)
    if request_id == _sent_response then
      _conn.writev(body)
      _send_finished(request_id)
    elseif RequestIds.gt(request_id, _active_request) then
      // TODO: optimize this case later on
      _pending_responses.add_pending(request_id, response.to_bytes())
      _pending_responses.append_iter(request_id, body)
    else
      None // latecomer, ignore
    end


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
      _pending_responses.add_pending(request_id, response.to_bytes())
    else
      // request_id < _active_request
      // latecomer - ignore
      None
    end

  fun ref _send(response: HTTPResponse val) =>
    """
    Send a single response.
    """
    //let okstatus = (response.status().apply() < 300)
    _conn.writev(response)

  be send_chunk(data: ByteSeq val, request_id: RequestId) =>
    """
    Write low level outbound raw byte stream.
    """
    if request_id == _sent_response then
      _conn.write(data)
    elseif RequestIds.gt(request_id, _active_request) then
      _pending_responses.append_data(request_id, data)
    else
      None // latecomer, ignore
    end

  be send_finished(request_id: RequestId) =>
    """
    We are done sending a response. We can close the connection if
    `keepalive` was not requested.
    """
    _send_finished(request_id)


  fun ref _send_finished(request_id: RequestId) =>
    // check if the next request_id is already in the pending list
    // if so, write it
    var rid = request_id
    while _pending_responses.has_pending() do
      match _pending_responses.pop(RequestIds.next(rid))
      | (let next_rid: RequestId, let response_data: ByteArrays) =>
        Debug("also sending next response for request: " + next_rid.string())
        rid = next_rid
        _sent_response = next_rid
        _conn.writev(response_data.byteseqiter())
      else
        // next one not available yet
        break
      end
    end
    if not _keepalive then
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

