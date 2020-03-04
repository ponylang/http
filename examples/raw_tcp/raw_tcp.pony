"""
 Baseline for comparing benchmark results.

 This file is intende ot receive body-less HTTP requests
 and is writing out a pre-allocated response for each request it receives.

 There is no actual parsing happening, other than looking for a double CRLF,
 marking the request end.
"""
use "net"
use "valbytes"
use "../../http"


class MyTCPConnectionNotify is TCPConnectionNotify
  var buf: ByteArrays = ByteArrays()
  let _res: String
  var _handler: (ConnectionHandler | None) = None

  new iso create(res_str: String) =>
    _res = res_str

  fun ref accepted(conn: TCPConnection ref) =>
    let tag_conn: TCPConnection tag = conn
    _handler = ConnectionHandler(tag_conn, _res)


  fun ref received(
    conn: TCPConnection ref,
    data: Array[U8] iso,
    times: USize)
    : Bool
  =>
    buf = buf + consume data
    var carry_on = true
    while carry_on do
      match buf.find("\r\n\r\n")
      | (true, let req_end: USize) =>
        let req = buf.trim(0, req_end + 4)
        try
          let h = (_handler as ConnectionHandler)
          h.receive(req)
        end
        buf = buf.drop(req_end + 4)
      else
        carry_on = false
      end
    end
    true

  fun ref connect_failed(conn: TCPConnection ref) =>
    None

actor ConnectionHandler
  let _conn: TCPConnection tag
  let _res: String

  new create(conn: TCPConnection, res: String) =>
    _conn = conn
    _res = res

  be receive(array: Array[U8] val) =>
    _conn.write(_res)

class MyTCPListenNotify is TCPListenNotify

  let res: String = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 11\r\n\r\nHELLO WORLD"

  fun ref connected(listen: TCPListener ref): TCPConnectionNotify iso^ =>
    MyTCPConnectionNotify(res)

  fun ref not_listening(listen: TCPListener ref) =>
    None

actor Main
  new create(env: Env) =>
    try
      let limit = env.args(2)?.usize()?
      TCPListener(env.root as AmbientAuth,
        recover MyTCPListenNotify end, "127.0.0.1", env.args(1)? where limit = limit)
    end
