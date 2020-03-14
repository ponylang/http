use "time"

class val HTTPServerConfig

  let connection_timeout: U64
    """
    Timeout in seconds after which a connection will be closed.
    """

  let max_request_handling_lag: U64
    """
    Maximum number of requests that will be kept without a response generated
    before the connection is muted.
    """

  let max_concurrent_connections: USize
    """
    maximum number of concurrent TCP connections.
    Set to `0` to accept unlimited concurrent connections.
    """

  let timeout_heartbeat_interval: U64
    """
    INterval between heartbeat calls to all tcp connection
    the server keeps track of for them in order to determine
    if they should time out.
    """

  new val create(
    connection_timeout': U64 = 0,
    max_request_handling_lag': U64 = 10000,
    max_concurrent_connections': USize = 0,
    timeout_heartbeat_interval': U64 = Nanos.from_seconds(1)
   ) =>
     connection_timeout = connection_timeout'
     max_request_handling_lag = max_request_handling_lag'
     max_concurrent_connections = max_concurrent_connections'
     timeout_heartbeat_interval = timeout_heartbeat_interval'


