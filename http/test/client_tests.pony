use ".."
use "ponytest"
use "net"

primitive ClientTests is TestList
  fun tag tests(test: PonyTest) =>
    test(ClientStreamTransferTest)

class val StreamTransferHandlerFactory is HandlerFactory
  let _h: TestHelper
  var expected_length: USize = 0
  var received_size: USize = 0
  new val create(h: TestHelper) =>
    _h = h

  fun apply(session: HTTPSession): HTTPHandler ref^ =>
    object is HTTPHandler
      fun ref apply(payload: Payload val): Any =>
        _h.complete_action("receive response headers")
        expected_length =
          try
            payload("Content-Length")?.usize()?
          else
            _h.fail("failed to extract Content-Length")
            -1
          end
      fun ref chunk(data: ByteSeq val) =>
        // ensure we receive at least one chunk
        _h.complete_action("chunk")
        received_size = received_size + data.size()
      fun ref finished() =>
        _h.complete_action("finished")
        // ensure size equals
        _h.assert_eq[USize](expected_length, received_size)

      fun ref failed(reason: HTTPFailureReason) =>
        _h.fail("failed")
    end

class iso ClientStreamTransferTest is UnitTest
  fun name(): String => "client/stream-transfer"
  fun apply(h: TestHelper) ? =>
    h.long_test(2_000_000_000)

    h.expect_action("server listening")
    h.expect_action("server connection accepted")
    h.expect_action("receive response headers")
    h.expect_action("chunk")
    h.expect_action("finished")

    let listener = TCPListener.ip4(
      h.env.root as AmbientAuth,
      object iso is TCPListenNotify
        let _h: TestHelper = h

        fun ref listening(listen: TCPListener ref) =>
          _h.complete_action("server listening")
          try
            let client = HTTPClient(
              _h.env.root as AmbientAuth,
              None
              where keepalive_timeout_secs = U32(2)
            )
            (let host, let port) = listen.local_address().name()?
            _h.log("connecting to server at " + host + ":" + port)
            let req = Payload.request("GET", URL.build("http://" + host + ":" + port  + "/bla")?)
            client(
              consume req,
              StreamTransferHandlerFactory(_h)
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
          object iso is TCPConnectionNotify
            var written: Bool = false
            fun ref received(conn: TCPConnection ref, data: Array[U8] iso, times: USize): Bool =>
              _h.log("received stuff")
              if not written then
                conn.write("\r\n".join([
                  "HTTP/1.1 200 OK"
                  "Server: Bla"
                  "Content-Length: 10004"
                  "Content-Type: application/octet-stream"
                  ""
                  ""
                ].values()))
                conn.write(recover val Array[U8].init('a', 2501) end)
                conn.write(recover val Array[U8].init('b', 2501) end)
                conn.write(recover val Array[U8].init('c', 2501) end)
                conn.write(recover val Array[U8].init('d', 2501) end)
                written = true
              end
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
      "127.0.0.1"
      "0")
    h.dispose_when_done(listener)


