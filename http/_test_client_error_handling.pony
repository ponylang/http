use "ponytest"

use "net"
use "net_ssl"
use "files"

actor _ClientErrorHandlingTests is TestList
  new make() =>
    None

  fun tag tests(test: PonyTest) =>
    test(_ConnectionClosedTest)
    ifdef not windows then
      // Server sockets on Windows can be connected to long after they are dead
      test(_ConnectFailedTest)
    end
    test(_SSLAuthFailedTest)

class val _ConnectionClosedHandlerFactory is HandlerFactory
  let _h: TestHelper
  new val create(h: TestHelper) =>
    _h = h

  fun apply(session: HTTPSession): HTTPHandler ref^ =>
    object is HTTPHandler
      fun ref failed(reason: HTTPFailureReason) =>
        match reason
        | ConnectionClosed =>
          _h.complete_action("client failed with ConnectionClosed")
        else
          _h.fail_action("failed with sth else")
        end
    end

class iso _ConnectionClosedTest is UnitTest
  fun name(): String => "client/error-handling/connection-closed"

  fun apply(h: TestHelper) ? =>
    h.long_test(5_000_000_000)

    h.expect_action("server listening")
    h.expect_action("server listen connected")
    h.expect_action("server connection accepted")
    h.expect_action("server connection closed")
    h.expect_action("client failed with ConnectionClosed")

    let notify = object iso is TCPListenNotify
      let _h: TestHelper = h
      fun ref listening(listen: TCPListener ref) =>
        _h.complete_action("server listening")
        _h.log("listening")

        try
          let client = HTTPClient(
            _h.env.root as AmbientAuth,
            None
            where keepalive_timeout_secs = U32(2)
          )
          (let host, let port) = listen.local_address().name()?
          let req = Payload.request("GET",
            URL.build("http://" + host + ":" + port  + "/bla")?)
          req.add_chunk("CHUNK")
          client(
            consume req,
            _ConnectionClosedHandlerFactory(_h)
          )?
        else
          _h.fail("request building failed")
        end

      fun ref not_listening(listen: TCPListener ref) =>
        _h.fail_action("server listening")
        _h.log("not_listening")

      fun ref closed(listen: TCPListener ref) =>
        _h.log("TCP listener closed")

      fun ref connected(listen: TCPListener ref): TCPConnectionNotify iso^ =>
        _h.complete_action("server listen connected")
        // server code
        object iso is TCPConnectionNotify
          fun ref received(conn: TCPConnection ref, data: Array[U8] iso,
            times: USize): Bool
          =>
            conn.close() // trigger the error condition
            true

          fun ref accepted(conn: TCPConnection ref) =>
            _h.complete_action("server connection accepted")
            _h.dispose_when_done(conn)

          fun ref connect_failed(conn: TCPConnection ref) =>
            _h.fail("connection failed")

          fun ref closed(conn: TCPConnection ref) =>
            _h.complete_action("server connection closed")
        end
    end

    let host = "127.0.0.1"
    let service = "0"

    let listener = TCPListener.ip4(h.env.root as AmbientAuth, consume notify,
      host, service)
    h.dispose_when_done(listener)

actor _Connecter
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h

  be connect(host: String, port: String) =>
    let port' =
      ifdef windows then
        port
      else
        port
      end

    _h.log("connecting to " + host + ":" + port')
    _h.complete_action("client trying to connect")
    try
      let client = HTTPClient(
        _h.env.root as AmbientAuth,
        None
        where keepalive_timeout_secs = U32(2)
      )
      let req = Payload.request("GET",
        URL.build("http://" + host + ":" + port' + "/bla")?)
      req.add_chunk("CHUNK")
      client(consume req, _ConnectFailedHandlerFactory(_h))?
    else
      _h.fail("request building failed")
    end

class val _ConnectFailedHandlerFactory is HandlerFactory
  let _h: TestHelper

  new val create(h: TestHelper) =>
    _h = h

  fun apply(session: HTTPSession): HTTPHandler ref^ =>
    object is HTTPHandler
      fun ref finished() =>
        _h.fail("failed by finishing")
        _h.complete(false)
      fun ref failed(reason: HTTPFailureReason) =>
        match reason
        | AuthFailed =>
          _h.fail("failed with AuthFailed")
          _h.complete(false)
        | ConnectionClosed =>
          _h.fail("failed with ConnectionClosed")
          _h.complete(false)
        | ConnectFailed =>
          _h.complete_action("client failed with ConnectFailed")
        end
    end

class iso _ConnectFailedTest is UnitTest
  fun name(): String => "client/error-handling/connect-failed"

  fun apply(h: TestHelper) ? =>
    h.long_test(5_000_000_000)

    h.expect_action("server listening")
    h.expect_action("server closed")
    h.expect_action("client trying to connect")
    h.expect_action("client failed with ConnectFailed")

    let notify = object iso is TCPListenNotify
      let _h: TestHelper = h
      var host: String = ""
      var port: String = ""

      fun ref listening(listen: TCPListener ref) =>
        _h.complete_action("server listening")
        try
          (host, port) = listen.local_address().name()?
        else
          _h.fail("unable to get port")
        end
        listen.close()

      fun ref not_listening(listen: TCPListener ref) =>
        _h.fail_action("server listening")

      fun ref closed(listen: TCPListener ref) =>
        _h.complete_action("server closed")
        let connecter = _Connecter(_h)
        connecter.connect(host, port)

      fun ref connected(listen: TCPListener ref): TCPConnectionNotify iso^ =>
        object iso is TCPConnectionNotify
          fun ref received(conn: TCPConnection ref, data: Array[U8] iso,
            times: USize): Bool => true
          fun ref accepted(conn: TCPConnection ref) => None
          fun ref connect_failed(conn: TCPConnection ref) => None
          fun ref closed(conn: TCPConnection ref) => None
        end
    end

    let host = "127.0.0.1"
    let service = "0"

    let listener = TCPListener.ip4(h.env.root as AmbientAuth, consume notify,
      host, service)
    h.dispose_when_done(listener)


primitive _Paths
  fun join(paths: Array[String] box): String =>
    var p = ""
    for path in paths.values() do
      p = Path.join(p, path)
    end
    p

class val _SSLAuthFailedHandlerFactory is HandlerFactory
  let _h: TestHelper
  new val create(h: TestHelper) =>
    _h = h

  fun apply(session: HTTPSession): HTTPHandler ref^ =>
    object is HTTPHandler
      fun ref failed(reason: HTTPFailureReason) =>
        match reason
        | AuthFailed =>
          _h.complete_action("client failed with AuthFailed")
        end
    end

class iso _SSLAuthFailedTest is UnitTest
  var cert_path: (FilePath | None) = None
  var key_path: (FilePath | None) = None
  var ca_path: (FilePath | None) = None

  fun name(): String => "client/error-handling/ssl-auth-failed"

  fun ref set_up(h: TestHelper) ? =>
    // this shit is tightly coupled to
    // how the tests are called from the Makefile
    // which is not the nicest thing in the world
    let cwd = Path.cwd()
    cert_path = FilePath(
      h.env.root as AmbientAuth,
      _Paths.join([
        cwd
        "http"
        "test"
        "cert.pem"])
    )?
    if not (cert_path as FilePath).exists() then
      h.log("cert path: " + (cert_path as FilePath).path + " does not exist!")
      error
    end
    key_path = FilePath(
      h.env.root as AmbientAuth,
      _Paths.join([
        cwd
        "http"
        "test"
        "key.pem"])
    )?
    if not (key_path as FilePath).exists() then
      h.log("key path: " + (key_path as FilePath).path + " does not exist!")
      error
    end
    ifdef not windows then
      ca_path = FilePath(h.env.root as AmbientAuth,
          "/usr/share/ca-certificates/mozilla")?
      if not (ca_path as FilePath).exists() then
        h.log("ca path: " + (ca_path as FilePath).path + " does not exist!")
        error
      end
    end

  fun apply(h: TestHelper) ? =>
    h.long_test(5_000_000_000)

    h.expect_action("server listening")
    h.expect_action("client failed with AuthFailed")

    let notify = object iso is TCPListenNotify
      let _h: TestHelper = h
      var host: String = ""
      var port: String = ""

      fun ref listening(listen: TCPListener ref) =>
        _h.complete_action("server listening")
        _h.log("listening")
        try
          (host, port) = listen.local_address().name()?
          try
            let ssl_ctx: SSLContext val = recover
              ifdef windows then
                SSLContext.>set_authority(None, None)?
              else
                SSLContext.>set_authority(
                  None
                  where path = ca_path as FilePath)?
              end
            end
            let client = HTTPClient(
              _h.env.root as AmbientAuth,
              ssl_ctx
              where keepalive_timeout_secs = U32(2)
            )
            let req = Payload.request(
              "GET",
              URL.build("https://" + host + ":" + port  + "/bla")?)
            req.add_chunk("CHUNK")
            client(
              consume req,
              _SSLAuthFailedHandlerFactory(_h)
            )?
          else
            _h.fail("request building failed")
          end
        else
          _h.fail("unable to get port")
        end

      fun ref not_listening(listen: TCPListener ref) =>
        _h.fail_action("server listening")
        _h.log("not_listening")

      fun ref closed(listen: TCPListener ref) =>
        _h.log("TCP listener closed")

      fun ref connected(listen: TCPListener ref): TCPConnectionNotify iso^ ? =>
        _h.log("server listen connected.")
        let tcp_notify =
          object iso is TCPConnectionNotify
            fun ref received(conn: TCPConnection ref, data: Array[U8] iso,
              times: USize): Bool
            =>
              _h.log("received on server")
              conn.write(consume data)
              true
            fun ref accepted(conn: TCPConnection ref) =>
              _h.log("accepted on server")
            fun ref connect_failed(conn: TCPConnection ref) =>
              _h.log("connect failed on server")
            fun ref closed(conn: TCPConnection ref) =>
              _h.log("closed on server")
            fun ref auth_failed(conn: TCPConnection ref) =>
              _h.log("auth failed on server")
          end
        let server_ssl_ctx = SSLContext.>set_cert(
          cert_path as FilePath,
          key_path as FilePath)?
        SSLConnection(consume tcp_notify, server_ssl_ctx.server()?)
    end

    let host = "127.0.0.1"
    let service = "0"

    let listener = TCPListener.ip4(h.env.root as AmbientAuth, consume notify,
      host, service)
    h.dispose_when_done(listener)
