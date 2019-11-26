use ".."
use "debug"
use "ponytest"

primitive RequestParserTests is TestList
  fun tag tests(test: PonyTest) =>
    test(NoDataTest)
    test(UnknownMethodTest)

actor _MockHTTPSession is HTTPSession
  be apply(payload: Payload val) =>
    Debug("apply")

  be finish() =>
    Debug("finish")

  be dispose() =>
    Debug("dispose")

  be write(data: ByteSeq val) => None

  be cancel(msg: Payload val) => None

  be _mute() => None

  be _unmute() => None

  be _deliver(payload: Payload val) =>
    Debug("_deliver")

  be _chunk(data: ByteSeq val) =>
    Debug("_chunk")

  be _finish() => None
    Debug("_finish")


class iso NoDataTest is UnitTest
  fun name(): String => "request_parser/no_data"
  fun apply(h: TestHelper) =>
    let parser = HTTP11RequestParser(
      object is HTTP11Handler
        fun ref apply(request: HTTPRequest val, session: HTTPSession) =>
          h.fail("request delivered from no data.")
        fun ref chunk(data: Array[U8] val, session: HTTPSession) =>
          h.fail("chunk delivered from no data.")
        fun ref finished(session: HTTPSession) =>
          h.fail("finished called from no data.")
        fun ref failed(parse_error: RequestParseError, session: HTTPSession) =>
          h.fail("failed called from no data.")
      end,
      _MockHTTPSession
    )
    h.assert_is[ParseReturn](NeedMore, parser.parse(recover Array[U8](0) end))

class iso UnknownMethodTest is UnitTest
  fun name(): String => "request_parser/unknown_method"
  fun apply(h: TestHelper) =>
    let parser = HTTP11RequestParser(
      object is HTTP11Handler
        fun ref apply(request: HTTPRequest val, session: HTTPSession) =>
          h.fail("request delivered from no data.")
        fun ref chunk(data: Array[U8] val, session: HTTPSession) =>
          h.fail("chunk delivered from no data.")
        fun ref finished(session: HTTPSession) =>
          h.fail("finished called from no data.")
        fun ref failed(parse_error: RequestParseError, session: HTTPSession) =>
          h.assert_is[RequestParseError](UnknownMethod, parse_error)
      end,
      _MockHTTPSession
    )
    h.assert_is[ParseReturn](
      UnknownMethod,
      parser.parse(_ArrayHelpers.iso_array("ABC /"))
    )

primitive _ArrayHelpers
  fun tag iso_array(s: String): Array[U8] iso^ =>
    (recover iso String(s.size()).>append(s) end).iso_array()
