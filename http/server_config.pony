use "time"
use "json"

class val ServerConfig

  let host: String
    """
    Hostname or IP to start listening on. E.g. `localhost` or `127.0.0.1`

    A value of `"0.0.0.0"` will make the server listen on all available interfaces.

    Default: `"localhost"`
    """

  let port: String
    """
    Numeric port (e.g. `"80"`) or service name (e.g. `"http"`)
    defining the port number to start listening on.

    Chosing `"0"` will let the server start on a random port, chosen by the OS.

    Default: `"0"`
    """

  let connection_timeout: USize
    """
    Timeout in seconds after which a connection will be closed.

    Using `0` will make the connection never time out.

    Default: `0`
    """

  let max_request_handling_lag: USize
    """
    Maximum number of requests that will be kept without a response generated
    before the connection is muted.

    Default: `100`
    """

  let max_concurrent_connections: USize
    """
    maximum number of concurrent TCP connections.
    Set to `0` to accept unlimited concurrent connections.

    Default: `0`
    """

  let timeout_heartbeat_interval: U64
    """
    Interval between heartbeat calls to all tcp connection
    in milliseconds
    the server keeps track of for them in order to determine
    if they should time out.

    Default: `(<connection_timeout> * 1000) / 4`
    """

  new val create(
    host': String = "localhost",
    port': String = "0",
    connection_timeout': USize = 0,
    max_request_handling_lag': USize = 100,
    max_concurrent_connections': USize = 0,
    timeout_heartbeat_interval': (U64 | None) = None
   ) =>
     host = host'
     port = port'
     connection_timeout = connection_timeout'
     max_request_handling_lag = max_request_handling_lag'
     max_concurrent_connections = max_concurrent_connections'
     timeout_heartbeat_interval =
     match timeout_heartbeat_interval'
     | None =>
       // use a quarter of the actual configured timeout
       // but at minimum 1 second
       ((connection_timeout.u64() * 1000) / 4).max(1)
     | let interval: U64 => interval
     end


  fun box has_timeout(): Bool =>
    connection_timeout > 0

  fun box to_json(): String =>
    let doc = JsonDoc
    let obj = JsonObject
    obj.data("host") = host
    obj.data("port") = port
    obj.data("connection_timeout") = connection_timeout.i64()
    obj.data("max_request_handling_lag") = max_request_handling_lag.i64()
    obj.data("max_concurrent_connections") = max_concurrent_connections.i64()
    obj.data("timeout_heartbeat_interval") = timeout_heartbeat_interval.i64()
    doc.data = obj
    doc.string(where indent = "  ", pretty_print = true)
