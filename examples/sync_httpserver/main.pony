use "../../http"
use "time"
use "valbytes"

actor Main
  """
  A simple HTTP Echo server, sending back the received request in the response body.

  This time using a synchronous interface to the http library.
  """
  new create(env: Env) =>
    for arg in env.args.values() do
      if (arg == "-h") or (arg == "--help") then
        _print_help(env)
        return
      end
    end

    let port = try env.args(1)? else "50001" end
    let limit = try env.args(2)?.usize()? else 100 end
    let host = "localhost"

    let auth = try
      env.root as AmbientAuth
    else
      env.err.print("unable to use network")
      return
    end

    // Start the top server control actor.
    let server = Server(
      auth,
      LoggingServerNotify(env),
      // HandlerFactory - used to instantiate the session-scoped Handler
      {(session) =>
        SyncHandlerWrapper(
          session,
          object ref is SyncHandler


            var builder: (ResponseBuilder | None) = Responses.builder()
              """
              response builder - reused within a session
              """

            fun ref apply(request: Request val, body: (ByteArrays | None)): ByteSeqIter ? =>
              """
              Handle a new full HTTP Request including body.
              Return a ByteSeqIter representing the Response.

              This is made easy using the ResponseBuilder returned from

              ```pony
              Responses.builder()
              ```

              This handler allows for failing, but must return a result synchronously.
              That means calling other actors is possible for side-effects (like e.g. logging),
              but the response ust be constructed when this function returns.
              In return the API is much simpler that the threefold cascade of receiving requests:

                * Handler.apply(request, request_id)
                * Handler.chunk(data, request_id)
                * Handler.finished(request_id)

              And the (at maximum) threefold API to send responses:

                * Session.send_start(response, request_id)
                * Session.send_chunk(data, request_id)
                * Session.send_finished(request_id)

              The API is much simpler, but the request body is aggregated into a `ByteArrays` instance,
              which is suboptimal for big requests and might not perform as well as the more verbose API listed above,
              especially for streaming contexts.
              """

              // serialize Request for sending it back
              // TODO: have a good api for that on the request class itself
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

              var header_builder = ((builder = None) as ResponseBuilder)
                              .set_status(StatusOK)
                              .set_transfer_encoding(request.transfer_coding())
                              .add_header("Content-Type", "text/plain")
              // add a Content-Length header if we have no chunked Transfer
              // Encoding
              match request.transfer_coding()
              | None =>
                let content_length =
                array.size() + match request.content_length()
                | let s: USize => s
                else
                  USize(0)
                end
                header_builder.add_header("Content-Length", content_length.string())
              end
              let body_builder = (consume header_builder)
                .finish_headers()
                .add_chunk(consume array) // write request headers etc to response body
              match body
              | let ba: ByteArrays =>
                // write request body to response body
                for chunk in ba.arrays().values() do
                  body_builder.add_chunk(chunk)
                end
              end
              let res = body_builder.build()
              builder = (consume body_builder).reset() // enable reuse
              res // return the built response as ByteSeqIter synchronously
          end
        )
      }
      where config = ServerConfig(
        where host' = host,
              port' = port,
              max_concurrent_connections' = limit)
    )

  fun _print_help(env: Env) =>
    env.err.print(
      """
      Usage:

         sync_httpserver [<PORT> = 50001] [<MAX_CONCURRENT_CONNECTIONS> = 100]

      """
    )


class LoggingServerNotify is ServerNotify
  let _env: Env

  new iso create(env: Env) =>
    _env = env

  fun ref listening(server: Server ref) =>
    try
      (let host, let service) = server.local_address().name()?
      _env.err.print("connected: " + host + ":" + service)
    else
      _env.err.print("Couldn't get local address.")
      server.dispose()
      _env.exitcode(1)
    end

  fun ref not_listening(server: Server ref) =>
    _env.err.print("Failed to listen.")
    _env.exitcode(1)

  fun ref closed(server: Server ref) =>
    _env.err.print("Shutdown.")

