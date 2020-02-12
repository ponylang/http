use "net"
use "collections"
use "valbytes"

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
  var _body_bytes_sent: USize = 0

  var _active_request: RequestId = 0
    """
    keeps the request_id of the request currently active.
    That is, that has been sent to the backend last.
    """
  var _sent_response: RequestId = 0
    """
    Keeps track of the request_id for which we sent a response already
    in order to determine lag in request handling.
    """
  let _max_request_handling_lag: USize = 100 // TODO: make configurable

  // when the request_id in a send call matches the _active_request
  // - directly send it
  // if it is bigger than _active_request
  // - insert it at index `send_request_id - _active_request`
  // TBD
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
    Dispatch requests. At the time this behavior is called for StreamTransfer
    and ChunkTransfer encodings, only the headers of the request may have
    been received. Receiving and dealing with the body, which could be
    quite large in POST methods, is up to the chosen application handler.

    The client can send several requests without waiting for a response,
    but they are only passed to the back end one at a time. Only when all
    of the response to a processed request has been sent is the next request
    processed.
    """
    _active_request = request_id
    _keepalive =
      match request.header("Connection")
      | "close" => false
      else
        // keepalive is the default in HTTP/1.1, not supported in HTTP/1.0
        request.version() isnt HTTP10
      end
    _body_bytes_sent = 0
    _backend(request, request_id)
    // TODO: handle wrap around
    if (_active_request - _sent_response).abs() >= _max_request_handling_lag then
      // Backpressure incoming requests if the queue grows too much.
      // The backpressure prevents filling up memory with queued
      // requests in the case of a runaway client.
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

  be dispose() =>
    """
    Close the connection from the server end.
    """
    _conn.dispose()


  be closed() =>
    _backend.failed(ConnectionClosed, _active_request)
    _conn.unmute()

  be send_start(response: HTTPResponse val, request_id: RequestId) =>
    """
    Initiate transmission of the HTTP Response message for the current
    Request.
    """
    _conn.unmute()
    if request_id == _active_request then
      // just send it through. all good
      _sent_response = request_id
      _send(response)
    elseif request_id > _active_request then
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
    if request_id == _active_request then
      _body_bytes_sent = _body_bytes_sent + data.size()
      _conn.write(data)
    elseif request_id > _active_request then
      _pending_responses.append_data(request_id, data)
      // TODO
      None
    else
      None // latecomer, ignore
    end

  be send_finished(request_id: RequestId) =>
    """
    We are done sending a response. We can close the connection if
    `keepalive` was not requested.
    """
    // check if the next request_id is already in the pending list
    // if so, write it
    var rid = request_id
    while true do
      match _pending_responses.pop(rid + 1)
      | (let next_rid: RequestId, let response_data: ByteArrays) =>
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

