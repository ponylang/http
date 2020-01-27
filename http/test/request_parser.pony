use ".."
use "debug"
use "ponytest"

primitive RequestParserTests is TestList
  fun tag tests(test: PonyTest) =>
    test(NoDataTest)
    test(UnknownMethodTest)

actor _MockRequestHandler is HTTP11RequestHandler
  be _receive_start(request: HTTPRequest val, request_id: RequestId) =>
    Debug("_receive_start: " + request_id.string())

  be _receive_chunk(data: Array[U8] val, request_id: RequestId) =>
    Debug("_receive_chunk: " + request_id.string())

  be _receive_finished(request_id: RequestId) =>
    Debug("_receive_finished: " + request_id.string())

  be _receive_failed(parse_error: RequestParseError, request_id: RequestId) =>
    Debug("_receive_failed: " + request_id.string())


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
