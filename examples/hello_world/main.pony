use "../../http"
use "valbytes"
use "debug"

actor Main
  """
  A simple HTTP server, that responds with a simple "hello world" in the response body.
  """
  new create(env: Env) =>
    for arg in env.args.values() do
      if (arg == "-h") or (arg == "--help") then
        _print_help(env)
        return
      end
    end

    let port = try env.args(1)? else "9292" end
    let limit = try env.args(2)?.usize()? else 10000 end
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
      BackendMaker // factory for session-based application backend
      where config = HTTPServerConfig( // configuration of HTTPServer
        where host' = host,
              port' = port,
              max_concurrent_connections' = limit)
    )

  fun _print_help(env: Env) =>
    env.err.print(
      """
      Usage:

         hello_world [<PORT> = 9292] [<MAX_CONCURRENT_CONNECTIONS> = 10000]

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

class val BackendMaker

  let _msg: String = "hello world"
  let _response: ByteSeqIter = HTTPResponses.builder()
    .set_status(StatusOK)
    .add_header("Content-Type", "text/plain")
    .add_header("Content-Length", _msg.size().string())
    .finish_headers()
    .add_chunk(_msg.array())
    .build()

  fun apply(session: HTTPSession): HTTPHandler ref^ =>
    BackendHandler(session, _response)

class BackendHandler is HTTPHandler
  let _session: HTTPSession
  let _response: ByteSeqIter

  new ref create(session: HTTPSession, response: ByteSeqIter) =>
    _session = session
    _response = response

  fun ref apply(request: HTTPRequest val, request_id: RequestId) =>
    _session.send_raw(_response, request_id)
    _session.send_finished(request_id)

  fun ref finished(request_id: RequestId) => None

