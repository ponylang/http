use "net"
use "net_ssl"

class _ServerListener is TCPListenNotify
  """
  Manages the listening socket for an HTTP server. Incoming requests
  are assembled and dispatched.
  """
  let _server: Server
  let _config: ServerConfig
  let _sslctx: (SSLContext | None)
  let _handlermaker: HandlerFactory val

  new iso create(
    server: Server,
    config: ServerConfig,
    sslctx: (SSLContext | None),
    handler: HandlerFactory val)  // Makes a unique session handler
  =>
    """
    Creates a new listening socket manager.
    """
    _server = server
    _config = config
    _sslctx = sslctx
    _handlermaker = handler

  fun ref listening(listen: TCPListener ref) =>
    """
    Inform the server of the bound IP address.
    """
    _server._listening(listen.local_address())

  fun ref not_listening(listen: TCPListener ref) =>
    """
    Inform the server we failed to listen.
    """
    _server._not_listening()

  fun ref closed(listen: TCPListener ref) =>
    """
    Inform the server we have stopped listening.
    """
    _server._closed()

  fun ref connected(listen: TCPListener ref): TCPConnectionNotify iso^ ? =>
    """
    Create a notifier for a specific HTTP socket. A new instance of the
    back-end Handler is passed along so it can be used on each `Payload`.
    """
    match _sslctx
    | None =>
      _ServerConnHandler(_handlermaker, _server, _config)
    | let ctx: SSLContext =>
      let ssl = ctx.server()?
      SSLConnection(
        _ServerConnHandler(_handlermaker, _server, _config),
        consume ssl)
    end
