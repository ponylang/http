use "assert"
use "cli"
use "collections"
use "encode/base64"
use "files"
use "http"
use "net/ssl"

class val Config
  let user: String
  let pass: String
  let output: String
  let url: String
  let timeout: U64

  new val create(env: Env) ? =>
    let cs = CommandSpec.leaf("httpget", "", [
      OptionSpec.string("user", "Username for authenticated queries."
        where short' = 'u', default' = "")
      OptionSpec.string("pass", "Password for authenticated queries."
        where short' = 'p', default' = "")
      OptionSpec.string("output", "Name of file to write response body."
        where short' = 'o', default' = "")
      OptionSpec.u64("timeout", "TCP Keepalive timeout to detect broken communications link."
        where short' = 't', default' = U64(0))
    ],[
      ArgSpec.string("url", "Url to query." where default' = None)
    ])?.>add_help()?
    let cmd =
      match CommandParser(cs).parse(env.args, env.vars)
      | let c: Command => c
      | let ch: CommandHelp =>
        ch.print_help(env.out)
        env.exitcode(0)
        error
      | let se: SyntaxError =>
        env.out.print(se.string())
        env.exitcode(1)
        error
      end
    user = cmd.option("user").string()
    pass = cmd.option("pass").string()
    output = cmd.option("output").string()
    url = cmd.arg("url").string()
    timeout = cmd.option("timeout").u64()

actor Main
  """
  Fetch data from URLs on the command line.
  """
  new create(env: Env) =>
    // Get common command line options.
    let c = try Config(env)? else return end

    let url = try
      URL.valid(c.url)?
    else
      env.out.print("Invalid URL: " + c.url)
      env.exitcode(1)
      return
    end

    // Start the actor that does the real work.
    _GetWork.create(env, url, c.user, c.pass, c.output, c.timeout)

actor _GetWork
  """
  Do the work of fetching a resource
  """
  let _env: Env

  new create(env: Env, url: URL, user: String, pass: String, output: String, timeout: U64)
    =>
    """
    Create the worker actor.
    """
    _env = env

    // Get certificate for HTTPS links.
    let sslctx = try
      recover
        SSLContext
          .>set_client_verify(true)
          .>set_authority(FilePath(env.root as AmbientAuth, "cacert.pem")?)?
        end
      end

    try
      // The Client manages all links.
      let client = HTTPClient(env.root as AmbientAuth, consume sslctx where keepalive_timeout_secs = timeout.u32())
      // The Notify Factory will create HTTPHandlers as required.  It is
      // done this way because we do not know exactly when an HTTPSession
      // is created - they can be re-used.
      let dumpMaker = recover val NotifyFactory.create(this) end

      try
        // Start building a GET request.
        let req = Payload.request("GET", url)
        req("User-Agent") = "Pony httpget"

        // Add authentication if supplied.  We use the "Basic" format,
        // which is username:password in base64.  In a real example,
	      // you would only use this on an https link.
        if user.size() > 0 then
          let keyword = "Basic "
          let content = recover String(user.size() + pass.size() + 1) end
          content.append(user)
          content.append(":")
          content.append(pass)
          let coded = Base64.encode(consume content)
          let auth = recover String(keyword.size() + coded.size()) end
          auth.append(keyword)
          auth.append(consume coded)
          req("Authorization") = consume auth
        end

        // Submit the request
        let sentreq = client(consume req, dumpMaker)?

        // Could send body data via `sentreq`, if it was a POST
      else
        try env.out.print("Malformed URL: " + env.args(1)?) end
        env.exitcode(1)
      end
    else
      env.out.print("unable to use network")
      env.exitcode(1)
    end

  be cancelled() =>
    """
    Process cancellation from the server end.
    """
    _env.out.print("-- response cancelled --")

  be failed(reason: HTTPFailureReason) =>
    match reason
    | AuthFailed =>
      _env.err.print("-- auth failed --")
    | ConnectFailed =>
      _env.err.print("-- connect failed --")
    | ConnectionClosed =>
      _env.err.print("-- connection closed --")
    end
    _env.exitcode(1)

  be have_response(response: Payload val) =>
    """
    Process return the the response message.
    """
    if response.status == 0 then
      _env.out.print("Failed")
      _env.exitcode(1)
      return
    end

    // Print the status and method
    _env.out.print(
      "Response " +
      response.status.string() + " " +
      response.method)

    // Print all the headers
    for (k, v) in response.headers().pairs() do
      _env.out.print(k + ": " + v)
    end

    _env.out.print("")

    // Print the body if there is any.  This will fail in Chunked or
    // Stream transfer modes.
    try
      let body = response.body()?
      for piece in body.values() do
        _env.out.write(piece)
      end
    end

  be have_body(data: ByteSeq val)
    =>
    """
    Some additional response data.
    """
    _env.out.write(data)

  be finished() =>
    """
    End of the response data.
    """
    _env.out.print("-- end of body --")

class NotifyFactory is HandlerFactory
  """
  Create instances of our simple Receive Handler.
  """
  let _main: _GetWork

  new iso create(main': _GetWork) =>
    _main = main'

  fun apply(session: HTTPSession): HTTPHandler ref^ =>
    HttpNotify.create(_main, session)

class HttpNotify is HTTPHandler
  """
  Handle the arrival of responses from the HTTP server.  These methods are
  called within the context of the HTTPSession actor.
  """
  let _main: _GetWork
  let _session: HTTPSession

  new ref create(main': _GetWork, session: HTTPSession) =>
    _main = main'
    _session = session

  fun ref apply(response: Payload val) =>
    """
    Start receiving a response.  We get the status and headers.  Body data
    *might* be available.
    """
    _main.have_response(response)

  fun ref chunk(data: ByteSeq val) =>
    """
    Receive additional arbitrary-length response body data.
    """
    _main.have_body(data)

  fun ref finished() =>
    """
    This marks the end of the received body data.  We are done with the
    session.
    """
    _main.finished()
    _session.dispose()

  fun ref cancelled() =>
    _main.cancelled()

  fun ref failed(reason: HTTPFailureReason) =>
    _main.failed(reason)

