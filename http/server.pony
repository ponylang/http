use "collections"
use "net"
use "net_ssl"
use "time"
use "debug"

interface tag _SessionRegistry
  be register_session(conn: _ServerConnection)
  be unregister_session(conn: _ServerConnection)

actor Server is _SessionRegistry
  """
  Runs an HTTP server.

  ### Server operation

  Information flow into the Server is as follows:

  1. `Server` listens for incoming TCP connections.

  2. `_ServerConnHandler` is the notification class for new connections. It creates
  a `_ServerConnection` actor and receives all the raw data from TCP. It uses
  the `HTTP11RequestParser` to assemble complete `Request` objects which are passed off
  to the `_ServerConnection`.

  3. The `_ServerConnection` actor deals with requests and their bodies
  that have been parsed by the `HTTP11RequestParser`. This is where requests get
  dispatched to the caller-provided Handler.
  """
  let _notify: ServerNotify
  var _handler_maker: HandlerFactory val
  let _config: ServerConfig
  let _sslctx: (SSLContext | None)
  let _listen: TCPListener
  var _address: NetAddress
  let _sessions: SetIs[_ServerConnection tag] = SetIs[_ServerConnection tag]
  let _timers: Timers = Timers
  var _timer: (Timer tag | None) = None

  new create(
    auth: TCPListenerAuth,
    notify: ServerNotify iso,
    handler: HandlerFactory val,
    config: ServerConfig,
    sslctx: (SSLContext | None) = None)
  =>
    """
    Create a server bound to the given host and service. To do this we
    listen for incoming TCP connections, with a notification handler
    that will create a server session actor for each one.
    """
    _notify = consume notify
    _handler_maker = handler
    _config = config
    _sslctx = sslctx
    Debug("starting server with config:\n" + config.to_json())

    _listen = TCPListener(auth,
        _ServerListener(this, config, sslctx, _handler_maker),
        config.host, config.port, config.max_concurrent_connections)

    _address = recover NetAddress end

  be register_session(conn: _ServerConnection) =>
    _sessions.set(conn)

    // only start a timer if we have a connection-timeout configured
    if _config.has_timeout() then
      match _timer
      | None =>
        let that: Server tag = this
        let timeout_interval = _config.timeout_heartbeat_interval
        let t = Timer(
          object iso is TimerNotify
            fun ref apply(timer': Timer, count: U64): Bool =>
              that._start_heartbeat()
              true
          end,
          Nanos.from_millis(timeout_interval),
          Nanos.from_millis(timeout_interval))
        _timer = t
        _timers(consume t)
      end
    end

  be _start_heartbeat() =>
    // iterate through _sessions and ping all connections
    let current_seconds = Time.seconds() // seconds resolution is fine
    for session in _sessions.values() do
      session._heartbeat(current_seconds)
    end

  be unregister_session(conn: _ServerConnection) =>
    _sessions.unset(conn)

  be set_handler(handler: HandlerFactory val) =>
    """
    Replace the request handler.
    """
    _handler_maker = handler
    _listen.set_notify(
      _ServerListener(this, _config, _sslctx, _handler_maker))

  be dispose() =>
    """
    Shut down the server gracefully. To do this we have to eliminate
    any source of further inputs. So we stop listening for new incoming
    TCP connections, and close any that still exist.
    """
    _listen.dispose()
    _timers.dispose()
    for conn in _sessions.values() do
      conn.dispose()
    end

  fun local_address(): NetAddress =>
    """
    Returns the locally bound address.
    """
    _address

  be _listening(address: NetAddress) =>
    """
    Called when we are listening.
    """
    _address = address
    _notify.listening(this)

  be _not_listening() =>
    """
    Called when we fail to listen.
    """
    _notify.not_listening(this)

  be _closed() =>
    """
    Called when we stop listening.
    """
    _notify.closed(this)

