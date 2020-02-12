use "../../http"
use "valbytes"
use "debug"

actor Main
  """
  A simple HTTP server.
  """
  new create(env: Env) =>
    let service = try env.args(1)? else "50000" end
    let limit = try env.args(2)?.usize()? else 100 end
    let host = "localhost"


    let auth = try
      env.root as AmbientAuth
    else
      env.out.print("unable to use network")
      return
    end

    // Start the top server control actor.
    HTTPServer(
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
      _env.out.print("connected: " + host)
    else
      _env.out.print("Couldn't get local address.")
      server.dispose()
    end

  fun ref not_listening(server: HTTPServer ref) =>
    _env.out.print("Failed to listen.")

  fun ref closed(server: HTTPServer ref) =>
    _env.out.print("Shutdown.")

class BackendMaker is HandlerFactory
  let _env: Env

  new val create(env: Env) =>
    _env = env

  fun apply(session: HTTPSession): HTTPHandler^ =>
    BackendHandler.create(_env, session)

class BackendHandler is HTTPHandler
  """
  Notification class for a single HTTP session.  A session can process
  several requests, one at a time.  Data recieved using OneshotTransfer
  transfer mode is echoed in the response.
  """
  let _env: Env
  let _session: HTTPSession
  var _response: BuildableHTTPResponse trn = BuildableHTTPResponse.create()
  var _response_body: ByteArrays = ByteArrays.create()
  var _already_sent: Bool = false

  new ref create(env: Env, session: HTTPSession) =>
    """
    Create a context for receiving HTTP requests for a session.
    """
    _env = env
    _session = session

  fun ref apply(request: HTTPRequest val, request_id: RequestId) =>
    """
    Start processing a request.
    """
    _response.set_status(StatusOK)
    _response.set_header("Content-Type", "text/plain")

    _response_body = _response_body + "You asked for "
    _response_body = _response_body + request.uri().string()
    _response_body = _response_body + "\n\n"
    if not request.has_body() then
      _response.set_content_length(_response_body.size())
      _session.send(
        _response = BuildableHTTPResponse.create(),
        (_response_body = ByteArrays.create()).byteseqiter(),
        request_id
      )
    end

  fun ref chunk(data: ByteSeq val, request_id: RequestId) =>
    """
    Process the next chunk of data received.
    """
    _response_body = _response_body + data

  fun ref finished(request_id: RequestId) =>
    """
    Called when the last chunk has been handled.
    """
    if not _already_sent then
      _already_sent = false
      _response.set_content_length(_response_body.size())

      _session.send(
        _response = BuildableHTTPResponse.create(),
        (_response_body = ByteArrays.create()).byteseqiter(),
        request_id
      ) // TODO: this can be improved
    end
