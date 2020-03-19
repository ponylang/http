use "../../http"
use "time"
use "debug"
use "valbytes"

actor Main
  new create(env: Env) =>
    let port = try env.args(1)? else "50001" end
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
      {(session) =>
        SyncHTTPHandlerWrapper(
          session,
          object ref is SyncHTTPHandler

            var builder: (ResponseBuilder | None) = HTTPResponses.builder()

            fun ref apply(request: HTTPRequest val, body: (ByteArrays | None)): ByteSeqIter ? =>
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
                .add_chunk(consume array)
              match body
              | let ba: ByteArrays =>
                for chunk in ba.arrays().values() do
                  body_builder.add_chunk(chunk)
                end
              end
              let res = body_builder.build()
              builder = (consume body_builder).reset()
              res
          end
        )
      }
      where config = HTTPServerConfig(
        where host' = host,
              port' = port,
              max_concurrent_connections' = limit)
    )

class ListenHandler is ServerNotify
  let _env: Env

  new iso create(env: Env) =>
    _env = env

  fun ref listening(server: HTTPServer ref) =>
    try
      (let host, let service) = server.local_address().name()?
      Debug("connected: " + host + ":" + service)
    else
      _env.err.print("Couldn't get local address.")
      server.dispose()
      _env.exitcode(1)
    end

  fun ref not_listening(server: HTTPServer ref) =>
    _env.err.print("Failed to listen.")
    _env.exitcode(1)

  fun ref closed(server: HTTPServer ref) =>
    Debug("Shutdown.")

