use "ponytest"
use "net"
use "collections"
use "buffered"
use "time"

primitive PrivateTests is TestList
  fun tag tests(test: PonyTest) =>
    test(_Encode)
    test(_EncodeBad)
    test(_EncodeIPv6)
    test(_EncodeClean)

    test(_Check)
    test(_CheckBad)
    test(_CheckScheme)
    test(_CheckIPv6)

    test(_Decode)
    test(_DecodeBad)

    test(_BuildBasic)
    test(_BuildMissingParts)
    test(_BuildBad)
    test(_BuildNoEncoding)
    test(_Valid)
    test(_ToStringFun)

    test(_HTTPConnTest)
    test(_HTTPParserNoBodyTest)
    test(_HTTPParserOneshotBodyTest)
    test(_HTTPParserStreamedBodyTest)

class iso _Encode is UnitTest
  fun name(): String => "http/URLEncode.encode"

  fun apply(h: TestHelper) ? =>
    // Unreserved chars, decoded.
    h.assert_eq[String]("Aa4-._~Aa4-._~",
      URLEncode.encode("Aa4-._~%41%61%34%2D%2E%5F%7E", URLPartUser)?)

    h.assert_eq[String]("F_12x", URLEncode.encode("F_1%32x", URLPartPassword)?)
    h.assert_eq[String]("F_12x", URLEncode.encode("F_1%32x", URLPartHost)?)
    h.assert_eq[String]("F_12x", URLEncode.encode("F_1%32x", URLPartPath)?)
    h.assert_eq[String]("F_12x", URLEncode.encode("F_1%32x", URLPartQuery)?)
    h.assert_eq[String]("F_12x", URLEncode.encode("F_1%32x", URLPartFragment)?)

    // Sub-delimiters, left encoded or not as original.
    h.assert_eq[String]("!$&'()*+,;=%21%24%26%27%28%29%2A%2B%2C%3B%3D",
      URLEncode.encode("!$&'()*+,;=%21%24%26%27%28%29%2A%2B%2C%3B%3D",
        URLPartUser)?)

    h.assert_eq[String](",%2C", URLEncode.encode(",%2C", URLPartPassword)?)
    h.assert_eq[String](",%2C", URLEncode.encode(",%2C", URLPartHost)?)
    h.assert_eq[String](",%2C", URLEncode.encode(",%2C", URLPartPath)?)
    h.assert_eq[String](",%2C", URLEncode.encode(",%2C", URLPartQuery)?)
    h.assert_eq[String](",%2C", URLEncode.encode(",%2C", URLPartFragment)?)

    // Misc characters, encoded.
    h.assert_eq[String]("%23%3C%3E%5B%5D%7B%7D%7C%5E%20" +
      "%23%3C%3E%5B%5D%7B%7D%7C%5E%25",
      URLEncode.encode("#<>[]{}|^ %23%3C%3E%5B%5D%7B%7D%7C%5E%25",
        URLPartUser)?)

    h.assert_eq[String]("%23%23", URLEncode.encode("#%23", URLPartPassword)?)
    h.assert_eq[String]("%23%23", URLEncode.encode("#%23", URLPartHost)?)
    h.assert_eq[String]("%23%23", URLEncode.encode("#%23", URLPartPath)?)
    h.assert_eq[String]("%23%23", URLEncode.encode("#%23", URLPartQuery)?)
    h.assert_eq[String]("%23%23", URLEncode.encode("#%23", URLPartFragment)?)

    // Delimiters, whether encoded depends on URL part.
    h.assert_eq[String]("%3A%40%2F%3F", URLEncode.encode(":@/?", URLPartUser)?)
    h.assert_eq[String](":%40%2F%3F",
      URLEncode.encode(":@/?", URLPartPassword)?)
    h.assert_eq[String]("%3A%40%2F%3F", URLEncode.encode(":@/?", URLPartHost)?)
    h.assert_eq[String](":@/%3F", URLEncode.encode(":@/?", URLPartPath)?)
    h.assert_eq[String](":@/?", URLEncode.encode(":@/?", URLPartQuery)?)
    h.assert_eq[String](":@/?", URLEncode.encode(":@/?", URLPartFragment)?)

class iso _EncodeBad is UnitTest
  fun name(): String => "http/URLEncode.encode_bad"

  fun apply(h: TestHelper) =>
    h.assert_error({() ? => URLEncode.encode("%2G", URLPartUser)? })
    h.assert_error({() ? => URLEncode.encode("%xx", URLPartUser)? })
    h.assert_error({() ? => URLEncode.encode("%2", URLPartUser)? })

class iso _EncodeIPv6 is UnitTest
  fun name(): String => "http/URLEncode.encode_ipv6"

  fun apply(h: TestHelper) ? =>
    // Allowed hex digits, '.' and ':' only, between '[' and ']'.
    h.assert_eq[String]("[1::A.B]", URLEncode.encode("[1::A.B]", URLPartHost)?)
    h.assert_error({() ? => URLEncode.encode("[G]", URLPartHost)? })
    h.assert_error({() ? => URLEncode.encode("[/]", URLPartHost)? })
    h.assert_error({() ? => URLEncode.encode("[%32]", URLPartHost)? })
    h.assert_error({() ? => URLEncode.encode("[1]2", URLPartHost)? })
    h.assert_error({() ? => URLEncode.encode("[1", URLPartHost)? })
    h.assert_eq[String]("1%5D", URLEncode.encode("1]", URLPartHost)?)

class iso _EncodeClean is UnitTest
  fun name(): String => "http/URLEncode.encode_clean"

  fun apply(h: TestHelper) ? =>
    // No percent encoding in source string.
    h.assert_eq[String]("F_1x", URLEncode.encode("F_1x", URLPartQuery, false)?)
    h.assert_eq[String]("%2541", URLEncode.encode("%41", URLPartQuery, false)?)
    h.assert_eq[String]("%25", URLEncode.encode("%", URLPartQuery, false)?)

class iso _Check is UnitTest
  fun name(): String => "http/URLEncode.check"

  fun apply(h: TestHelper) =>
    // Unreserved chars, legal encoded or not.
    h.assert_eq[Bool](true,
      URLEncode.check("Aa4-._~%41%61%34%2D%2E%5F%7E", URLPartUser))

    h.assert_eq[Bool](true, URLEncode.check("F_1%32x", URLPartPassword))
    h.assert_eq[Bool](true, URLEncode.check("F_1%32x", URLPartHost))
    h.assert_eq[Bool](true, URLEncode.check("F_1%32x", URLPartPath))
    h.assert_eq[Bool](true, URLEncode.check("F_1%32x", URLPartQuery))
    h.assert_eq[Bool](true, URLEncode.check("F_1%32x", URLPartFragment))

    // Sub-delimiters, legal encoded or not.
    h.assert_eq[Bool](true,
      URLEncode.check("!$&'()*+,;=%21%24%26%27%28%29%2A%2B%2C%3B%3D",
        URLPartUser))

    h.assert_eq[Bool](true, URLEncode.check(",%2C", URLPartPassword))
    h.assert_eq[Bool](true, URLEncode.check(",%2C", URLPartHost))
    h.assert_eq[Bool](true, URLEncode.check(",%2C", URLPartPath))
    h.assert_eq[Bool](true, URLEncode.check(",%2C", URLPartQuery))
    h.assert_eq[Bool](true, URLEncode.check(",%2C", URLPartFragment))

    // Misc characters, must be encoded.
    h.assert_eq[Bool](true,
      URLEncode.check("%23%3C%3E%5B%5D%7B%7D%7C%5E%25", URLPartUser))
    h.assert_eq[Bool](false, URLEncode.check("<", URLPartUser))
    h.assert_eq[Bool](false, URLEncode.check(">", URLPartUser))
    h.assert_eq[Bool](false, URLEncode.check("|", URLPartUser))
    h.assert_eq[Bool](false, URLEncode.check("^", URLPartUser))

    h.assert_eq[Bool](true, URLEncode.check("%23%3C", URLPartPassword))
    h.assert_eq[Bool](false, URLEncode.check("<", URLPartPassword))
    h.assert_eq[Bool](true, URLEncode.check("%23%3C", URLPartHost))
    h.assert_eq[Bool](false, URLEncode.check("<", URLPartHost))
    h.assert_eq[Bool](true, URLEncode.check("%23%3C", URLPartPath))
    h.assert_eq[Bool](false, URLEncode.check("<", URLPartPath))
    h.assert_eq[Bool](true, URLEncode.check("%23%3C", URLPartQuery))
    h.assert_eq[Bool](false, URLEncode.check("<", URLPartQuery))
    h.assert_eq[Bool](true, URLEncode.check("%23%3C", URLPartFragment))
    h.assert_eq[Bool](false, URLEncode.check("<", URLPartFragment))

    // Delimiters, whether need to be encoded depends on URL part.
    h.assert_eq[Bool](true, URLEncode.check("%3A%40%2F%3F", URLPartUser))
    h.assert_eq[Bool](false, URLEncode.check(":", URLPartUser))
    h.assert_eq[Bool](false, URLEncode.check("@", URLPartUser))
    h.assert_eq[Bool](false, URLEncode.check("/", URLPartUser))
    h.assert_eq[Bool](false, URLEncode.check("?", URLPartUser))
    h.assert_eq[Bool](true, URLEncode.check(":%40%2F%3F", URLPartPassword))
    h.assert_eq[Bool](false, URLEncode.check("@", URLPartPassword))
    h.assert_eq[Bool](false, URLEncode.check("/", URLPartPassword))
    h.assert_eq[Bool](false, URLEncode.check("?", URLPartPassword))
    h.assert_eq[Bool](true, URLEncode.check("%3A%40%2F%3F", URLPartHost))
    h.assert_eq[Bool](false, URLEncode.check(":", URLPartHost))
    h.assert_eq[Bool](false, URLEncode.check("@", URLPartHost))
    h.assert_eq[Bool](false, URLEncode.check("/", URLPartHost))
    h.assert_eq[Bool](false, URLEncode.check("?", URLPartHost))
    h.assert_eq[Bool](true, URLEncode.check(":@/%3F", URLPartPath))
    h.assert_eq[Bool](false, URLEncode.check("?", URLPartPath))
    h.assert_eq[Bool](true, URLEncode.check(":@/?", URLPartQuery))
    h.assert_eq[Bool](true, URLEncode.check(":@/?", URLPartFragment))

class iso _CheckBad is UnitTest
  fun name(): String => "http/URLEncode.check_bad"

  fun apply(h: TestHelper) =>
    h.assert_eq[Bool](false, URLEncode.check("%2G", URLPartUser))
    h.assert_eq[Bool](false, URLEncode.check("%xx", URLPartUser))
    h.assert_eq[Bool](false, URLEncode.check("%2", URLPartUser))

class iso _CheckScheme is UnitTest
  fun name(): String => "http/URLEncode.check_scheme"

  fun apply(h: TestHelper) =>
    h.assert_eq[Bool](true, URLEncode.check_scheme("Aa4-+."))
    h.assert_eq[Bool](false, URLEncode.check_scheme("_"))
    h.assert_eq[Bool](false, URLEncode.check_scheme(":"))
    h.assert_eq[Bool](false, URLEncode.check_scheme("%41"))

class iso _CheckIPv6 is UnitTest
  fun name(): String => "http/URLEncode.check_ipv6"

  fun apply(h: TestHelper) =>
    // Allowed hex digits, '.' and ':' only, between '[' and ']'.
    h.assert_eq[Bool](true, URLEncode.check("[1::A.B]", URLPartHost))
    h.assert_eq[Bool](false, URLEncode.check("[G]", URLPartHost))
    h.assert_eq[Bool](false, URLEncode.check("[/]", URLPartHost))
    h.assert_eq[Bool](false, URLEncode.check("[%32]", URLPartHost))
    h.assert_eq[Bool](false, URLEncode.check("[1]2", URLPartHost))
    h.assert_eq[Bool](false, URLEncode.check("[1", URLPartHost))
    h.assert_eq[Bool](false, URLEncode.check("1]", URLPartHost))

class iso _Decode is UnitTest
  fun name(): String => "http/URLEncode.decode"

  fun apply(h: TestHelper) ? =>
    h.assert_eq[String]("Aa4-._~Aa4-._~",
      URLEncode.decode("Aa4-._~%41%61%34%2D%2E%5F%7E")?)

    h.assert_eq[String]("F_12x", URLEncode.decode("F_1%32x")?)

    h.assert_eq[String]("!$&'()* ,;=!$&'()*+,;=",
      URLEncode.decode("!$&'()*+,;=%21%24%26%27%28%29%2A%2B%2C%3B%3D")?)

    h.assert_eq[String]("#<>[]{}|^ #<>[]{}|^ %",
      URLEncode.decode("#<>[]{}|^ %23%3C%3E%5B%5D%7B%7D%7C%5E%20%25")?)

class iso _DecodeBad is UnitTest
  fun name(): String => "http/URLEncode.decode_bad"

  fun apply(h: TestHelper) =>
    h.assert_error({() ? => URLEncode.decode("%2G")? })
    h.assert_error({() ? => URLEncode.decode("%xx")? })
    h.assert_error({() ? => URLEncode.decode("%2")? })

class iso _BuildBasic is UnitTest
  fun name(): String => "http/URL.build_basic"

  fun apply(h: TestHelper) ? =>
    _Test(h,
      URL.build("https://user:password@host.name:12345/path?query#fragment")?,
      "https", "user", "password", "host.name", 12345, "/path", "query",
      "fragment")

    _Test(h,
      URL.build("http://rosettacode.org/wiki/Category]Pony")?,
      "http", "", "", "rosettacode.org", 80, "/wiki/Category%5DPony", "", "")

    _Test(h,
      URL.build("https://en.wikipedia.org/wiki/Polymorphism_" +
        "(computer_science)#Parametric_polymorphism")?,
      "https", "", "", "en.wikipedia.org", 443,
      "/wiki/Polymorphism_(computer_science)", "",
      "Parametric_polymorphism")

    _Test(h, URL.build("http://user@host")?,
      "http", "user", "", "host", 80, "/", "", "")

class iso _BuildMissingParts is UnitTest
  fun name(): String => "http/URL.build_missing_parts"

  fun apply(h: TestHelper) ? =>
    _Test(h, URL.build("https://user@host.name/path#fragment")?,
      "https", "user", "", "host.name", 443, "/path", "", "fragment")

    _Test(h, URL.build("https://user@host.name#fragment")?,
      "https", "user", "", "host.name", 443, "/", "", "fragment")

    _Test(h, URL.build("//host.name/path")?,
      "", "", "", "host.name", 0, "/path", "", "")

    _Test(h, URL.build("/path")?,
      "", "", "", "", 0, "/path", "", "")

    _Test(h, URL.build("?query")?,
      "", "", "", "", 0, "/", "query", "")

    _Test(h, URL.build("#fragment")?,
      "", "", "", "", 0, "/", "", "fragment")

    _Test(h, URL.build("https://host.name/path#frag?ment")?,
      "https", "", "", "host.name", 443, "/path", "", "frag?ment")

    _Test(h, URL.build("https://user@host.name?quer/y#fragment")?,
      "https", "user", "", "host.name", 443, "/", "quer/y", "fragment")

class iso _BuildBad is UnitTest
  fun name(): String => "http/URL.build_bad"

  fun apply(h: TestHelper) =>
    h.assert_error({() ? =>
      URL.build("htt_ps://user@host.name/path#fragment")?
    })

    h.assert_error({() ? =>
      URL.build("https://[11::24_]/path")?
    })

    h.assert_error({() ? =>
      URL.build("https://[11::24/path")?
    })

    h.assert_error({() ? =>
      URL.build("https://host%2Gname/path")?
    })

    h.assert_error({() ? =>
      URL.build("https://hostname/path%")?
    })

class iso _BuildNoEncoding is UnitTest
  fun name(): String => "http/URL.build_no_encoding"

  fun apply(h: TestHelper) ? =>
    _Test(h, URL.build("https://host.name/path%32path", false)?,
      "https", "", "", "host.name", 443, "/path%2532path", "", "")

class iso _Valid is UnitTest
  fun name(): String => "http/URL.valid"

  fun apply(h: TestHelper) ? =>
    _Test(h,
      URL.valid("https://user:password@host.name:12345/path?query#fragment")?,
      "https", "user", "password", "host.name", 12345, "/path", "query",
      "fragment")

    h.assert_error({() ? =>
      URL.valid("http://rosettacode.org/wiki/Category[Pony]")?
    })

    h.assert_error({() ? =>
      URL.valid("https://en.wikipedia|org/wiki/Polymorphism_" +
        "(computer_science)#Parametric_polymorphism")?
    })

    _Test(h, URL.valid("http://user@host")?,
      "http", "user", "", "host", 80, "/", "", "")

class iso _ToStringFun is UnitTest
  fun name(): String => "http/URL.to_string"

  fun apply(h: TestHelper) ? =>
    h.assert_eq[String](
      "https://user:password@host.name:12345/path?query#fragment",
      URL.build("https://user:password@host.name:12345/path?query#fragment")?
        .string())

    h.assert_eq[String]("http://rosettacode.org/wiki/Category%5DPony",
      URL.build("http://rosettacode.org/wiki/Category]Pony")?.string())

    h.assert_eq[String]("http://user@host/",
      URL.build("http://user@host")?.string())

    // Default ports should be omitted.
    h.assert_eq[String]("http://host.name/path",
      URL.build("http://host.name:80/path")?.string())

primitive _Test
  fun apply(
    h: TestHelper,
    url: URL,
    scheme: String,
    user: String,
    password: String,
    host: String,
    port: U16,
    path: String,
    query: String,
    fragment: String)
  =>
    h.assert_eq[String](scheme, url.scheme)
    h.assert_eq[String](user, url.user)
    h.assert_eq[String](password, url.password)
    h.assert_eq[String](host, url.host)
    h.assert_eq[U16](port, url.port)
    h.assert_eq[String](path, url.path)
    h.assert_eq[String](query, url.query)
    h.assert_eq[String](fragment, url.fragment)

// Actor and classes to test the HTTPClient and modified _HTTPConnection.
class _HTTPConnTestHandler is HTTPHandler
  var n_received: U32 = 0
  let h: TestHelper

  new create(h': TestHelper) =>
    h = h'
    h.complete_action("client handler create called")

  fun ref apply(payload: Payload val): Any =>
    n_received = n_received + 1
    h.complete_action("client handler apply called " + n_received.string())

  fun ref chunk(data: ByteSeq val) =>
    h.log("_HTTPConnTestHandler.chunk called")

class val _HTTPConnTestHandlerFactory is HandlerFactory
  let h: TestHelper

  new val create(h': TestHelper) =>
    h = h'

  fun apply(session: HTTPSession): HTTPHandler ref^ =>
    h.dispose_when_done(session)
    h.complete_action("client factory apply called")
    _HTTPConnTestHandler(h)

class iso _HTTPConnTest is UnitTest
  fun name(): String => "http/_HTTPConnection._new_conn"
  fun label(): String => "conn-fix"

  fun ref apply(h: TestHelper) ? =>
    // Set expectations.
    h.expect_action("client factory apply called")
    h.expect_action("client handler create called")
    h.expect_action("client handler apply called 1")
    h.expect_action("client handler apply called 2")
    h.expect_action("server writing reponse 1")
    h.expect_action("server writing reponse 2")
    h.expect_action("server listening")
    h.expect_action("server listen connected")
    h.expect_action("server connection accepted")
    h.expect_action("server connection closed")

    let worker = object
      var client: (HTTPClient iso | None) = None

      be listening(service: String) =>
        try
          // Need two or more request to check if the fix works.
          let loops: USize = 2
          // let service: String val = "12345"
          h.log("received service: [" + service + "]")
          let us = "http://localhost:" + service
          h.log("URL: " + us)
          let url = URL.build(us)?
          h.log("url.string()=" + url.string())
          let hf = _HTTPConnTestHandlerFactory(h)
          client = recover iso HTTPClient(h.env.root as TCPConnectionAuth) end

          for _ in Range(0, loops) do
            let payload: Payload iso = Payload.request("GET", url)
            payload.set_length(0)
            try
              (client as HTTPClient iso)(consume payload, hf)?
            end
          end
        else
          h.log("Error in worker.listening")
          h.complete(false)
        end // try
    end // object

    // Start the fake server.
    h.dispose_when_done(
      TCPListener.ip4(
        h.env.root as AmbientAuth,
        _FixedResponseHTTPServerNotify(
          h,
          {(p: String val) =>
            worker.listening(p)
            None
          },
          recover
            [ as String val:
              "HTTP/1.1 200 OK"
              "Server: pony_fake_server"
              "Content-Length: 0"
              "Status: 200 OK"
              ""
            ]
          end
        ),
        "", // all interfaces
        "0" // random service
      )
    )

    // Start a long test for 5 seconds.
    h.long_test(5_000_000_000)

primitive _FixedResponseHTTPServerNotify
  """
  Test http server that spits out fixed responses.
  apply returns a TCPListenNotify object.
  """

  fun apply(
    h': TestHelper,
    f: {(String val)} iso,
    r: Array[String val] val)
    : TCPListenNotify iso^
  =>
    recover
      object iso is TCPListenNotify
        let h: TestHelper = h'
        let listen_cb: {(String val)} iso = consume f
        let response: Array[String val] val = r

        fun ref listening(listen: TCPListener ref) =>
          try
            // Get the service as numeric.
            let name = listen.local_address().name()?
            h.log("listening on: " + name._1 + ":" + name._2)
            listen_cb(name._2)
            h.dispose_when_done(listen)
            h.complete_action("server listening")
          end

        fun ref not_listening(listen: TCPListener ref) =>
          h.fail_action("server listening")
          h.log("not_listening")

        fun ref closed(listen: TCPListener ref) =>
          h.log("closed")

        fun ref connected(listen: TCPListener ref): TCPConnectionNotify iso^ =>
          h.complete_action("server listen connected")
          recover
            object iso is TCPConnectionNotify
            // let response': Array[String val] val = response
            let reader: Reader iso = Reader
            var nr: USize = 0

            fun ref received(
              conn: TCPConnection ref,
              data: Array[U8] iso,
              times: USize)
              : Bool
            =>
              reader.append(consume data)
              while true do
                var blank = false
                try
                  let l = reader.line()?
                  let l_size = l.size()
                  h.log("received line: " + consume l)
                  if l_size == 0 then
                    // Write the response.
                    nr = nr + 1
                    for r in response.values() do
                      h.log("[" + r + "]")
                      conn.write(r + "\r\n")
                    end
                    h.complete_action(
                      "server writing reponse " + nr.string())
                  end
                else
                  h.log("breaking")
                  break
                end

              end // while
              true

            fun ref accepted(conn: TCPConnection ref) =>
              h.complete_action("server connection accepted")
              h.dispose_when_done(conn)

            fun ref closed(conn: TCPConnection ref) =>
              h.complete_action("server connection closed")

            fun ref connecting(conn: TCPConnection ref, count: U32) =>
              h.log("connecting")
              None

            fun ref connect_failed(conn: TCPConnection ref) =>
              h.log("connect_failed")
              None

            fun ref throttled(conn: TCPConnection ref) =>
              h.log("throttled")

            fun ref unthrottled(conn: TCPConnection ref) =>
              h.log("unthrottled")
          end // object
        end // recover

      end // object
    end // recover

class iso _HTTPParserNoBodyTest is UnitTest
  fun name(): String => "http/HTTPParser.NoBody"
  fun ref apply(h: TestHelper) =>
    let test_session =
      object is HTTPSession
        be apply(payload: Payload val) => None
        be finish() => None
        be dispose() => None
        be write(byteseq: ByteSeq val) => None
        be _mute() => None
        be _unmute() => None
        be cancel(msg: Payload val) => None
        be _deliver(payload: Payload val) =>
          h.complete_action("_deliver")
          try
            h.assert_eq[USize](payload.body()?.size(), 0)
          else
            h.fail("failed to get empty oneshot body.")
          end

        be _chunk(data: ByteSeq val) =>
          h.fail("HTTPSession._chunk called.")
        be _finish() =>
          h.fail("HTTPSession._finish called.")
      end
    let parser = HTTPParser.request(test_session)
    let payload: String = "\r\n".join([
      "GET /get HTTP/1.1"
      "Host: httpbin.org"
      "User-Agent: curl/7.58.0"
      "Accept: */*"
      ""
      ""
      ].values())

    h.long_test(2_000_000_000)
    h.expect_action("_deliver")
    let reader: Reader = Reader
    reader.append(payload)
    match parser.parse(reader)
    | ParseError => h.fail("parser failed to parse request")
    end

class iso _HTTPParserOneshotBodyTest is UnitTest
  fun name(): String => "http/HTTPParser.OneshotBody"
  fun ref apply(h: TestHelper) =>
    let body = "custname=Pony+Mc+Ponyface&custtel=%2B490123456789&custemail=pony%40ponylang.org&size=large&topping=bacon&topping=cheese&topping=onion&delivery=&comments=This+is+a+stupid+test"
    let test_session =
      object is HTTPSession
        be apply(payload: Payload val) => None
        be finish() => None
        be dispose() => None
        be write(byteseq: ByteSeq val) => None
        be _mute() => None
        be _unmute() => None
        be cancel(msg: Payload val) => None
        be _deliver(payload: Payload val) =>
          h.complete_action("_deliver")
          try
            let received_body: String =
              recover val
                let tmp = payload.body()?
                let buf = String(body.size())
                for chunk in tmp.values() do
                  buf.append(chunk)
                end
                buf
              end
            h.assert_eq[String](received_body, body)
          else
            h.fail("failed to get oneshot body.")
          end
        be _chunk(data: ByteSeq val) =>
          h.fail("HTTPSession._chunk called.")
        be _finish() =>
          h.fail("HTTPSession._finish called.")
      end
    let parser = HTTPParser.request(test_session)
    let payload: String = "\r\n".join([
        "POST /post HTTP/1.1"
        "Host: httpbin.org"
        "User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:61.0) Gecko/20100101 Firefox/61.0"
        "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        "Accept-Language: en-GB,en;q=0.5"
        "Accept-Encoding: gzip, deflate"
        "Referer: http://httpbin.org/forms/post"
        "Content-Type: application/x-www-form-urlencoded"
        "Content-Length: 174"
        "Cookie: _gauges_unique_hour=1; _gauges_unique_day=1; _gauges_unique_month=1; _gauges_unique_year=1; _gauges_unique=1"
        "Connection: keep-alive"
        "Upgrade-Insecure-Requests: 1"
        ""
        body
      ].values())
    h.long_test(2_000_000_000)
    h.expect_action("_deliver")
    let reader: Reader = Reader
    reader.append(payload)
    match parser.parse(reader)
    | ParseError => h.fail("parser failed to parse request.")
    end

class iso _HTTPParserStreamedBodyTest is UnitTest
  fun name(): String => "http/HTTPParser.StreamedBody"
  fun apply(h: TestHelper) =>
    let test_session =
      object is HTTPSession
        be apply(payload: Payload val) => None
        be finish() => None
        be dispose() => None
        be write(byteseq: ByteSeq val) => None
        be _mute() => None
        be _unmute() => None
        be cancel(msg: Payload val) => None
        be _deliver(payload: Payload val) =>
          h.complete_action("_deliver")
        be _chunk(data: ByteSeq val) =>
          h.complete_action("session._chunk")
        be _finish() =>
          h.complete_action("session._finish")
      end
    let parser = HTTPParser.response(test_session)
    let payload: String = "\r\n".join([
      "HTTP/1.1 200 OK"
      "Content-Length: 10001"
      "Content-Type: application/octet-stream"
      ""
      String.from_array(recover val Array[U8].init('a', 10001) end)
    ].values())
    h.long_test(2_000_000_000)
    h.expect_action("_deliver")
    h.expect_action("session._chunk")
    h.expect_action("session._finish")
    let reader: Reader = Reader
    reader.append(payload)
    match parser.parse(reader)
    | ParseError => h.fail("parser failed to parse request.")
    end
