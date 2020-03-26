use "ponytest"
use ".."
use "time"
use "net"

primitive ConnectionHandlingTests is TestList
  fun tag tests(test: PonyTest) =>
    test(ConnectionTimeoutTest)
    test(ConnectionCloseHeaderTest)
    test(ConnectionHTTP10Test)

class val _ClosedTestHandlerFactory is HandlerFactory
  let _h: TestHelper

  new val create(h: TestHelper) =>
    _h = h

  fun apply(session: HTTPSession): HTTPHandler ref^ =>
    object ref is HTTPHandler
      fun ref apply(request: HTTPRequest val, request_id: RequestId) =>
        _h.complete_action("request-received")

        // send response
        session.send_raw(
          HTTPResponses.builder()
            .set_status(StatusOK)
            .add_header("Content-Length", "0")
            .finish_headers()
            .build(),
          request_id
        )
        session.send_finished(request_id)

      fun ref closed() =>
        _h.complete_action("connection-closed")
    end


class iso ConnectionTimeoutTest is UnitTest
  """
  test that connection is closed when `connection_timeout` is set to `> 0`.
  """
  fun name(): String => "connection/timeout"

  fun apply(h: TestHelper) ? =>
    h.long_test(Nanos.from_seconds(5))
    h.expect_action("request-received")
    h.expect_action("connection-closed")
    h.dispose_when_done(
      HTTPServer(
        h.env.root as TCPListenerAuth,
        object iso is ServerNotify
          fun ref listening(server: HTTPServer ref) =>
            try
              (let host, let port) = server.local_address().name()?
              h.log("listening on " + host + ":" + port)
              TCPConnection(
                h.env.root as AmbientAuth,
                object iso is TCPConnectionNotify
                  fun ref connected(conn: TCPConnection ref) =>
                    conn.write("GET / HTTP/1.1\r\nContent-Length: 0\r\n\r\n")
                  fun ref connect_failed(conn: TCPConnection ref) =>
                    h.fail("connect failed")
                end,
                host,
                port
              )
            end
          fun ref closed(server: HTTPServer ref) =>
            h.fail("closed")
        end,
        _ClosedTestHandlerFactory(h),
        HTTPServerConfig(
          where connection_timeout' = 1,
                timeout_heartbeat_interval' = 500
        )
      )
    )

class iso ConnectionCloseHeaderTest is UnitTest
  """
  test that connection is closed when 'Connection: close' header
  was sent, even if we didn't specify a timeout.
  """

  fun name(): String => "connection/connection_close_header"

  fun apply(h: TestHelper) ? =>
    h.long_test(Nanos.from_seconds(5))
    h.expect_action("request-received")
    h.expect_action("connection-closed")
    h.dispose_when_done(
      HTTPServer(
        h.env.root as TCPListenerAuth,
        object iso is ServerNotify
          fun ref listening(server: HTTPServer ref) =>
            try
              (let host, let port) = server.local_address().name()?
              h.log("listening on " + host + ":" + port)
              TCPConnection(
                h.env.root as AmbientAuth,
                object iso is TCPConnectionNotify
                  fun ref connected(conn: TCPConnection ref) =>
                    conn.write("GET / HTTP/1.1\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                  fun ref connect_failed(conn: TCPConnection ref) =>
                    h.fail("connect failed")
                end,
                host,
                port
              )
            end
          fun ref closed(server: HTTPServer ref) =>
            h.fail("closed")
        end,
        _ClosedTestHandlerFactory(h),
        HTTPServerConfig()
      )
    )

class iso ConnectionHTTP10Test is UnitTest
  """
  test that connection is closed when HTTP version is 1.0
  and no 'Connection: keep-alive' is given.
  """
  fun name(): String => "connection/no_keep_alive"

  fun apply(h: TestHelper) ? =>
    h.long_test(Nanos.from_seconds(5))
    h.expect_action("request-received")
    h.expect_action("connection-closed")
    h.dispose_when_done(
      HTTPServer(
        h.env.root as TCPListenerAuth,
        object iso is ServerNotify
          fun ref listening(server: HTTPServer ref) =>
            try
              (let host, let port) = server.local_address().name()?
              h.log("listening on " + host + ":" + port)
              TCPConnection(
                h.env.root as AmbientAuth,
                object iso is TCPConnectionNotify
                  fun ref connected(conn: TCPConnection ref) =>
                    conn.write("GET / HTTP/1.0\r\nContent-Length: 0\r\nConnection: blaaa\r\n\r\n")
                  fun ref connect_failed(conn: TCPConnection ref) =>
                    h.fail("connect failed")
                end,
                host,
                port
              )
            end
          fun ref closed(server: HTTPServer ref) =>
            h.fail("closed")
        end,
        _ClosedTestHandlerFactory(h),
        HTTPServerConfig()
      )
    )

