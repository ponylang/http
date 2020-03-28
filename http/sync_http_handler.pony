use "valbytes"
use "debug"

interface SyncHandler
  """
  Use this handler, when you want to handle your requests without accessing other actors.
  """
  fun ref apply(request: Request val, body: (ByteArrays | None)): ByteSeqIter ?

  fun error_response(request: Request): (ByteSeqIter | None) => None

class SyncHandlerWrapper is Handler
  let _session: Session
  let _handler: SyncHandler
  var _request_id: (RequestID | None) = None
  var _request: Request = BuildableRequest.create()
  var _body_buffer: ByteArrays = ByteArrays

  var _sent: Bool = false

  new create(session: Session, handler: SyncHandler) =>
    _handler = handler
    _session = session

  fun ref apply(request: Request val, request_id: RequestID) =>
    _request_id = request_id
    _request = request
    _sent = false

    if not request.has_body() then
      _sent = true
      let res = _run_handler(request, None)
      _session.send_raw(res, request_id)
    end

  fun ref _run_handler(request: Request, body: (ByteArrays | None) = None): ByteSeqIter =>
    try
      _handler(request, None)?
    else
      // create 500 response
      match _handler.error_response(request)
      | let bsi: ByteSeqIter => bsi
      | None =>
        // default 500 response
        let message = "Internal Server Error"
        Responses
          .builder(request.version())
          .set_status(StatusInternalServerError)
          .add_header("Content-Length", message.size().string())
          .add_header("Content-Type", "text/plain")
          .finish_headers()
          .add_chunk(message.array())
          .build()
      end
    end

  fun ref chunk(data: ByteSeq val, request_id: RequestID) =>
    _body_buffer = _body_buffer + data

  fun ref finished(request_id: RequestID) =>
    if not _sent then
      // resetting _body_buffer
      let res = _run_handler(_request, _body_buffer = ByteArrays)
      _session.send_raw(res, request_id)
    end
    _session.send_finished(request_id)




