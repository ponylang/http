use "ponytest"
use ".."
use "time"
use "net"
use "random"
use "valbytes"

primitive PipeliningTests is TestList
  fun tag tests(test: PonyTest) =>
    test(PipeliningOrderTest)
    test(PipeliningCloseTest)


class val _PipeliningOrderHandlerFactory is HandlerFactory
  let _h: TestHelper
  let _timers: Timers

  new val create(h: TestHelper) =>
    _h = h
    _timers = Timers

  fun apply(session: Session): Handler ref^ =>
    let random = Rand(Time.seconds().u64())
    object ref is Handler
      let _session: Session = session

      fun ref finished(request_id: RequestID) =>
        let rid = request_id.string()
        let res = Responses.builder()
          .set_status(StatusOK)
          .add_header("Content-Length", rid.size().string())
          .finish_headers()
          .add_chunk(rid.string().array())
          .build()
        // wait a random time (max 100 milliseconds)
        // then send a response with the given request_id as body
        _timers(
          Timer(
            object iso is TimerNotify
              fun ref apply(timer: Timer, count: U64): Bool =>
                _session.send_raw(res, request_id)
                _session.send_finished(request_id)
                false
            end,
            Nanos.from_millis(random.int[U64](U64(100))),
            0
          )
        )
    end

class iso PipeliningOrderTest is UnitTest
  let requests: Array[String] val = [
    "GET / HTTP/1.1\r\nContent-Length: 1\r\n\r\n1"
    "POST /path?query=param%20eter HTTP/1.1\r\nContent-Length: 1\r\n\r\n2"
    "GET /bla HTTP/1.1\r\nContent-Length: 1\r\nAccept: */*\r\n\r\n3"
    "GET / HTTP/1.1\r\nContent-Length: 1\r\n\r\n4"
    "GET / HTTP/1.1\r\nContent-Length: 1\r\n\r\n5"
  ]
  fun name(): String => "pipelining/order"

  fun apply(h: TestHelper) ? =>
    h.long_test(Nanos.from_seconds(5))
    h.expect_action("all received")
    h.dispose_when_done(
      Server(
        h.env.root as AmbientAuth,
        object iso is ServerNotify
          let reqs: Array[String] val = requests
          fun ref listening(server: Server ref) =>
            try
              (let host, let port) = server.local_address().name()?
              h.log("listening on " + host + ":" + port)
              TCPConnection(
                h.env.root as AmbientAuth,
                object iso is TCPConnectionNotify
                  var buffer: ByteArrays = ByteArrays
                  var order: Array[USize] iso = recover iso Array[USize](5) end

                  fun ref connected(conn: TCPConnection ref) =>
                    h.log("connected")
                    // pipeline all requests out
                    conn.write("".join(reqs.values()))
                  fun ref received(
                    conn: TCPConnection ref,
                    data: Array[U8 val] iso,
                    times: USize)
                  : Bool  =>
                    buffer = buffer + (consume data)
                    while buffer.size() > 5 do
                      match buffer.find("\r\n\r\n")
                      | (true, let idx: USize) =>
                        if buffer.size() >= idx then
                          buffer = buffer.drop(idx + 4)
                          try
                            let id = buffer.take(1).string().usize()?
                            buffer = buffer.drop(1)
                            h.log("received response: " + id.string())
                            order.push(id)
                          else
                            h.fail("incomplete request")
                          end
                        else
                          break
                        end
                      else
                        break
                      end
                    end
                    if order.size() == 5 then
                      h.complete_action("all received")
                      // assert that we receive in sending order,
                      // no matter which response was processed first
                      // by the server
                      h.assert_array_eq[USize](
                        [as USize: 0; 1; 2; 3; 4],
                        order = recover iso Array[USize](0) end
                      )
                    end
                    true

                  fun ref connect_failed(conn: TCPConnection ref) =>
                    h.fail("connect failed")
                end,
                host,
                port
              )
            end
          fun ref closed(server: Server ref) =>
            h.fail("closed")
        end,
        _PipeliningOrderHandlerFactory(h),
        ServerConfig()
      )
    )


class iso PipeliningCloseTest is UnitTest
  """
  Test that connection is closed after handling a request
  with "Connection: close" header, not earlier, not later.
  """
  fun name(): String => "pipelining/close"

  fun apply(h: TestHelper) ? =>
    h.long_test(Nanos.from_seconds(5))
    h.expect_action("connected")
    h.expect_action("all received")
    h.dispose_when_done(
      Server(
        h.env.root as AmbientAuth,
        object iso is ServerNotify
          fun ref listening(server: Server ref) =>
            try
              (let host, let port) = server.local_address().name()?
              h.log("listening on " + host + ":" + port)
              TCPConnection(
                h.env.root as AmbientAuth,
                object iso is TCPConnectionNotify
                  var buffer: ByteArrays = ByteArrays
                  var order: Array[USize] iso = recover iso Array[USize](5) end
                  let reqs: Array[String] val = [
                    "GET / HTTP/1.1\r\n\r\n"
                    "GET /path?query=param HTTP/1.1\r\nHeader: value\r\nContent-Length: 1\r\n\r\n "
                    "PATCH / HTTP/1.1\r\nConnection: Close\r\n\r\n"
                    "GET /ignore-me HTTP/1.1\r\nContent-Length: 0\r\n\r\n"
                  ]

                  fun ref connected(conn: TCPConnection ref) =>
                    h.complete_action("connected")
                    // pipeline all requests out
                    conn.write("".join(reqs.values()))

                  fun ref connect_failed(conn: TCPConnection ref) =>
                    h.fail("couldn't connect to server")

                  fun ref received(conn: TCPConnection ref, data: Array[U8 val] iso, times: USize): Bool  =>
                    buffer = buffer + (consume data)
                    while buffer.size() > 5 do
                      match buffer.find("\r\n\r\n")
                      | (true, let idx: USize) =>
                        if buffer.size() >= idx then
                          buffer = buffer.drop(idx + 4)
                          try
                            let id = buffer.take(1).string().usize()?
                            buffer = buffer.drop(1)
                            h.log("received response: " + id.string())
                            order.push(id)
                          else
                            h.fail("incomplete request")
                          end
                        else
                          break
                        end
                      else
                        break
                      end
                    end

                    // assert we receive at least the three first elements
                    if order.size() >= 3 then
                      h.complete_action("all received")
                      let o = (order = recover iso Array[USize](0) end)
                      let res = recover val consume o end
                      try
                        h.assert_eq[USize](0, res(0)?)
                        h.assert_eq[USize](1, res(1)?)
                        h.assert_eq[USize](2, res(2)?)
                      end
                    end
                    true
                end,
                host,
                port
              )
            end
          fun ref closed(server: Server ref) =>
            h.fail("closed")
        end,
        _PipeliningOrderHandlerFactory(h),
        ServerConfig()
      )
    )


