use "../../http"
use "valbytes"
use "debug"
use "time"
use "format"

actor Main
  """
  A simple HTTP Echo server, sending back the received request in the response body .
  """
  new create(env: Env) =>
    let service = try env.args(1)? else "50000" end
    let limit = try env.args(2)?.usize()? else 100 end
    let host = "localhost"
    let timers = Timers

    let auth = try
      env.root as AmbientAuth
    else
      env.out.print("unable to use network")
      return
    end

    // Start the top server control actor.
    let server = HTTPServer(
      auth,
      ListenHandler(env),
      BackendMaker.create(env)
      where service=service, host=host, limit=limit)

class ListenHandler is ServerNotify
  let _env: Env

  new iso create(env: Env) =>
    _env = env

  fun ref listening(server: HTTPServer ref) =>
    try
      (let host, let service) = server.local_address().name()?
      Debug("connected: " + host)
    else
      _env.err.print("Couldn't get local address.")
      _env.exitcode(1)
      server.dispose()
    end

  fun ref not_listening(server: HTTPServer ref) =>
    _env.err.print("Failed to listen.")
    _env.exitcode(1)

  fun ref closed(server: HTTPServer ref) =>
    Debug("Shutdown.")

class BackendMaker is HandlerFactory
  let _env: Env

  new val create(env: Env) =>
    _env = env

  fun apply(session: HTTPSession): HTTPHandler^ =>
    BackendHandler.create(_env, session)

class BackendHandler is HTTPHandler
  """
  Notification class for a single HTTP session.
  """
  let _env: Env
  let _session: HTTPSession
  var _response_builder: ResponseBuilder
  var _sent: Bool = false
  var _chunked: (Chunked | None) = None
  var _body_builder: (ResponseBuilderBody | None) = None

  new ref create(env: Env, session: HTTPSession) =>
    _env = env
    _session = session
    _response_builder = HTTPResponses.builder()

  fun ref apply(request: HTTPRequest val, request_id: RequestId) =>
    """
    Start processing a request.
    """
    _sent = false
    _chunked = request.transfer_coding()

    // build the request-headers-array - we don't have the raw sources anymore
    let array: Array[U8] trn = recover trn Array[U8](128) end
    array.>append(request.method().repr())
         .>append(" ")
         .>append(request.uri().string())
         .>append(request.version().to_bytes())
         .append("\r\n")
    for (name, value) in request.headers() do
      array.>append(name)
           .>append(": ")
           .>append(value)
           .>append("\r\n")
    end
    array.append("\r\n")
    let content_length =
      array.size() + match request.content_length()
      | let s: USize => s
      else
        USize(0)
      end
    var header_builder = _response_builder
      .set_status(StatusOK)
      .add_header("Content-Type", "text/plain")
    header_builder =
      match _chunked
      | Chunked =>
        header_builder.set_transfer_encoding(Chunked)
      | None =>
        header_builder = header_builder.add_header("Content-Length", content_length.string())
      end
    _body_builder =
      (consume header_builder)
        .finish_headers()
        .add_chunk(consume array)

    if not request.has_body() then
      match (_body_builder = None)
      | let builder: ResponseBuilderBody =>
        _session.send_raw(builder.build(), request_id)
        _response_builder = builder.reset()
        _sent = true
      end
    end

  fun ref chunk(data: ByteSeq val, request_id: RequestId) =>
    """
    Process the next chunk of data received.
    """
    match (_body_builder = None)
    | let builder: ResponseBuilderBody =>
      _body_builder = builder.add_chunk(
        match data
        | let adata: Array[U8] val => adata
        | let s: String => s.array()
        end
      )
    end

  fun ref finished(request_id: RequestId) =>
    """
    Called when the last chunk has been handled.
    """
    match (_body_builder = None)
    | let builder: ResponseBuilderBody =>
      match _chunked
      | Chunked =>
        builder.add_chunk(recover val Array[U8](0) end)
      end
      if not _sent then
        let resp = builder.build()
        _session.send_raw(resp, request_id)
      end
      _response_builder = builder.reset()
    end
    _session.send_finished(request_id)

