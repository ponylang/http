use "../../http"
use "valbytes"
use "debug"

actor Main
  """
  A simple HTTP Echo server, sending back the received request in the response body.
  """
  new create(env: Env) =>
    for arg in env.args.values() do
      if (arg == "-h") or (arg == "--help") then
        _print_help(env)
        return
      end
    end

    let port = try env.args(1)? else "50000" end
    let limit = try env.args(2)?.usize()? else 100 end
    let host = "localhost"

    // we need sufficient authority to listen on a TCP port for http traffic
    let auth = try
      env.root as AmbientAuth
    else
      env.out.print("unable to use network")
      return
    end

    // Start the top server control actor.
    let server = HTTPServer(
      auth,
      LoggingServerNotify(env),  // notify for server lifecycle events
      BackendMaker.create(env)   // factory for session-based application backend
      where config = HTTPServerConfig( // configuration of HTTPServer
        where host' = host,
              port' = port,
              max_concurrent_connections' = limit)
    )
    // everything is initialized, if all goes well
    // the server is listening on the given port
    // and thus kept alive by the runtime, as long its listening socket is not
    // closed.

  fun _print_help(env: Env) =>
    env.err.print(
      """
      Usage:

         httpserver [<PORT> = 50000] [<MAX_CONCURRENT_CONNECTIONS> = 100]

      """
    )


class LoggingServerNotify is ServerNotify
  """
  Notification class that is notified about
  important lifecycle events for the HTTPServer
  """
  let _env: Env

  new iso create(env: Env) =>
    _env = env

  fun ref listening(server: HTTPServer ref) =>
    """
    Called when the HTTPServer starts listening on its host:port pair via TCP.
    """
    try
      (let host, let service) = server.local_address().name()?
      _env.err.print("connected: " + host + ":" + service)
    else
      _env.err.print("Couldn't get local address.")
      _env.exitcode(1)
      server.dispose()
    end

  fun ref not_listening(server: HTTPServer ref) =>
    """
    Called when the HTTPServer was not able to start listening on its host:port pair via TCP.
    """
    _env.err.print("Failed to listen.")
    _env.exitcode(1)

  fun ref closed(server: HTTPServer ref) =>
    """
    Called when the HTTPServer is closed.
    """
    _env.err.print("Shutdown.")

class BackendMaker is HandlerFactory
  """
  Fatory to instantiate a new HTTP-session-scoped backend instance.
  """
  let _env: Env

  new val create(env: Env) =>
    _env = env

  fun apply(session: HTTPSession): HTTPHandler^ =>
    BackendHandler.create(_env, session)

class BackendHandler is HTTPHandler
  """
  Backend application instance for a single HTTP session.

  Executed on an actor representing the HTTP Session.
  That means we have 1 actor per TCP Connection
  (to be exact it is 2 as the TCPConnection is also an actor).
  """
  let _env: Env
  let _session: HTTPSession

  var _response_builder: ResponseBuilder
  var _body_builder: (ResponseBuilderBody | None) = None
  var _sent: Bool = false
  var _chunked: (Chunked | None) = None

  new ref create(env: Env, session: HTTPSession) =>
    _env = env
    _session = session
    _response_builder = HTTPResponses.builder()

  fun ref apply(request: HTTPRequest val, request_id: RequestID) =>
    """
    Start processing a request.

    Called when request-line and all headers have been parsed.
    Body is not yet parsed, not even received maybe.

    Here we already build the start of the response body and prepare
    the response as far as we can. If the request has no body, we send out the
    response already, as we have all information we need.

    """
    _sent = false
    _chunked = request.transfer_coding()

    // build the request-headers-array - we don't have the raw sources anymore
    let array: Array[U8] trn = recover trn Array[U8](128) end
    array.>append(request.method().repr())
         .>append(" ")
         .>append(request.uri().string())
         .>append(" ")
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
    // if request is chunked, we also send the response in chunked Transfer
    // Encoding
    header_builder =
      match _chunked
      | Chunked =>
        header_builder.set_transfer_encoding(Chunked)
      | None =>
        header_builder.add_header("Content-Length", content_length.string())
      end
    // The response builder has refcap iso, so we need to do some consume and
    // reassign dances here
    _body_builder =
      (consume header_builder)
        .finish_headers()
        .add_chunk(consume array) // add the request headers etc as response body here

    if not request.has_body() then
      match (_body_builder = None)
      | let builder: ResponseBuilderBody =>
        // already send the response if request has no body
        // use optimized HTTPSession API to send out all available chunks at
        // once using writev on the socket
        _session.send_raw(builder.build(), request_id)
        _response_builder = builder.reset() // reset the builder for later reuse within this session
        _sent = true
      end
    end

  fun ref chunk(data: ByteSeq val, request_id: RequestID) =>
    """
    Process the next chunk of data received.

    If we receive any data, we append it to the builder.
    We send stuff later, when we know we are finished.
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

  fun ref finished(request_id: RequestID) =>
    """
    Called when the last chunk has been handled and the full request has been received.

    Here we send out the full response, if the request had a body we needed to process first (see `fun chunk` above).
    We call `HTTPSession.send_finished(request_id)` to let the HTTP machinery finish sending and clena up resources
    connected to this request.
    """
    match (_body_builder = None)
    | let builder: ResponseBuilderBody =>
      match _chunked
      | Chunked =>
        builder.add_chunk(recover val Array[U8](0) end)
      end
      if not _sent then
        let resp = builder.build()
        _session.send_raw(consume resp, request_id)
      end
      _response_builder = builder.reset()
    end
    // Required call to finish request handling
    // if missed out, the server will misbehave
    _session.send_finished(request_id)

