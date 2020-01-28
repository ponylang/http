use ".."
use "debug"
use "ponytest"
use "valbytes"
use "itertools"

primitive RequestParserTests is TestList
  fun tag tests(test: PonyTest) =>
    test(NoDataTest)
    test(UnknownMethodTest)
    test(
      ParserTestBuilder.parse_success(
        "simple",
        _R(
          """
          GET /url HTTP/1.1
          Connection: Close
          Content-Length: 2

          XX"""),
        {
          (h: TestHelper, request: HTTPRequest, chunks: ByteArrays)? =>
            h.assert_eq[HTTPMethod](GET, request.method())
            h.assert_eq[HTTPVersion](HTTP11, request.version())
            h.assert_eq[String]("/url", request.uri().string())
            h.assert_eq[String]("Close", request.header("Connection") as String)
            h.assert_eq[USize](2, request.content_length() as USize)
            h.assert_eq[String]("2", request.header("Content-Length") as String)
            h.assert_eq[String]("XX", chunks.string())
        }
      )
    )

primitive _R
  fun apply(s: String): String =>
    "\r\n".join(
      Iter[String](s.split_by("\n").values())
        .map[String]({(s) => s.clone().>strip("\r") })
    )

actor _MockRequestHandler is HTTP11RequestHandler
  be _receive_start(request: HTTPRequest val, request_id: RequestId) =>
    Debug("_receive_start: " + request_id.string())

  be _receive_chunk(data: Array[U8] val, request_id: RequestId) =>
    Debug("_receive_chunk: " + request_id.string())

  be _receive_finished(request_id: RequestId) =>
    Debug("_receive_finished: " + request_id.string())

  be _receive_failed(parse_error: RequestParseError, request_id: RequestId) =>
    Debug("_receive_failed: " + request_id.string())

primitive ParserTestBuilder
  fun parse_success(
    name': String,
    request': String,
    callback: {(TestHelper, HTTPRequest val, ByteArrays)? } val)
    : UnitTest iso^
  =>
    object iso is UnitTest
      let cb: {(TestHelper, HTTPRequest val, ByteArrays)? } val = callback
      let req_str: String = request'
      fun name(): String => "request_parser/success/" + name'
      fun apply(h: TestHelper) =>
        h.long_test(1_000_000_000)
        let parser = HTTP11RequestParser(
          object is HTTP11RequestHandler
            var req: (HTTPRequest | None) = None
            var chunks: ByteArrays = ByteArrays
            be _receive_start(request: HTTPRequest val, request_id: RequestId) =>
              h.log("received request")
              req = request

            be _receive_chunk(data: Array[U8] val, request_id: RequestId) =>
              h.log("received chunk")
              chunks = chunks + data

            be _receive_finished(request_id: RequestId) =>
              h.log("received finished")
              try
                cb(h, req as HTTPRequest, chunks)?
                h.complete(true)
              else
                h.complete(false)
                h.fail("callback failed.")
              end
              chunks = ByteArrays
              req = None

            be _receive_failed(parse_error: RequestParseError, request_id: RequestId) =>
              h.complete(false)
              h.fail("FAILED WITH " + parse_error.string() + " FOR REQUEST:\n\n" + req_str)
          end
        )
        h.assert_eq[String]("None", parser.parse(_ArrayHelpers.iso_array(req_str)).string())
    end

class iso NoDataTest is UnitTest
  fun name(): String => "request_parser/no_data"
  fun apply(h: TestHelper) =>
    let parser = HTTP11RequestParser(
      object is HTTP11RequestHandler
        be _receive_start(request: HTTPRequest val, request_id: RequestId) =>
          h.fail("request delivered from no data.")
        be _receive_chunk(data: Array[U8] val, request_id: RequestId) =>
          h.fail("chunk delivered from no data.")
        be _receive_finished(request_id: RequestId) =>
          h.fail("finished called from no data.")
        be _receive_failed(parse_error: RequestParseError, request_id: RequestId) =>
          h.fail("failed called from no data.")
      end
    )
    h.assert_is[ParseReturn](NeedMore, parser.parse(recover Array[U8](0) end))

class iso UnknownMethodTest is UnitTest
  fun name(): String => "request_parser/unknown_method"
  fun apply(h: TestHelper) =>
    let parser = HTTP11RequestParser(
      object is HTTP11RequestHandler
        be _receive_start(request: HTTPRequest val, request_id: RequestId) =>
          h.fail("request delivered from no data.")
        be _receive_chunk(data: Array[U8] val, request_id: RequestId) =>
          h.fail("chunk delivered from no data.")
        be _receive_finished(request_id: RequestId) =>
          h.fail("finished called from no data.")
        be _receive_failed(parse_error: RequestParseError, request_id: RequestId) =>
          h.assert_is[RequestParseError](UnknownMethod, parse_error)
      end
    )
    h.assert_is[ParseReturn](
      UnknownMethod,
      parser.parse(_ArrayHelpers.iso_array("ABC /"))
    )

primitive _ArrayHelpers
  fun tag iso_array(s: String): Array[U8] iso^ =>
    (recover iso String(s.size()).>append(s) end).iso_array()
