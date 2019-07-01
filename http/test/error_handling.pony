use "ponytest"
use ".."
use "net"

primitive ClientErrorHandlingTests is TestList
  fun tag tests(test: PonyTest) =>
    test(ConnectionClosedTest)

class val _TestHandlerFactory is HandlerFactory
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

class iso ConnectionClosedTest is UnitTest
  fun name(): String => "client/error-handling/connection-closed"

  fun apply(h: TestHelper) ? =>
    h.long_test(10_000_000_000)
    h.expect_action("server listening")
    h.expect_action("server listen connected")
    h.expect_action("server connection accepted")
    h.expect_action("server connection closed")
    h.expect_action("client failed with ConnectionClosed")

    let listener = TCPListener.ip4(
        h.env.root as AmbientAuth,
        object iso is TCPListenNotify
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
              let req = Payload.request("GET", URL.build("http://" + host + ":" + port  + "/bla")?)
              req.add_chunk("CHUNK")
              client(
                consume req,
                _TestHandlerFactory(_h)
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
              fun ref received(conn: TCPConnection ref, data: Array[U8] iso, times: USize): Bool =>
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
        end,
        "127.0.0.1",
        "0")
    h.dispose_when_done(listener)

class iso ConnectFailed is UnitTest
  fun name(): String => "client/error-handling/connect-failed"


  fun apply(h: TestHelper) ? =>
    h.long_test(10_000_000_000)

