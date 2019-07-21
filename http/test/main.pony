use "ponytest"
use ".."
use "regex"

actor Main is TestList
  new create(env: Env) => PonyTest(env, this)
  new make() => None

  fun tag tests(test: PonyTest) =>
    PrivateTests.tests(test)
    ClientErrorHandlingTests.tests(test)
    ServerErrorHandlingTests.tests(test)
    test(CommonLogTest)
    ClientTests.tests(test)

actor _TestStream is OutStream
  let _collector: Array[String] ref = Array[String]
  let _regex: Regex val

  new create(regex: Regex val) =>
    _regex = regex

  fun box to_string(bs: ByteSeq): String =>
    match bs
    | let s: String => s
    | let a: Array[U8] val => String.from_array(a)
    end

  be print(data: ByteSeq) =>
    _collector.push(to_string(data))
    _collector.push("\n")

  be write(data: ByteSeq) =>
    _collector.push(to_string(data))

  be printv(data: ByteSeqIter) =>
    for elem in data.values() do
      _collector.push(to_string(elem))
      _collector.push("\n")
    end

  be writev(data: ByteSeqIter) =>
    for elem in data.values() do
      _collector.push(to_string(elem))
    end

  be flush() => None

  be validate(h: TestHelper) =>
    let collected: String = "".join(_collector.values())
    h.assert_true(
      _regex.matches(collected).has_next(),
      collected + " did not match")
    h.complete(true)

class iso CommonLogTest is UnitTest
  fun name(): String => "http/common_log"

  fun apply(h: TestHelper)? =>
    h.long_test(10_000_000)

    let ip = "127.0.0.1"
    let regex =
      recover val
        Regex(ip + " - - \\[\\d{2}/[a-zA-Z]{3}/\\d{4}:\\d{2}:\\d{2}:\\d{2} \\+0000\\] \"GET /path\\?query=1#fragment HTTP/1\\.1\" 200 1024 \"\" \"\"")?
      end
    let stream = _TestStream(regex)
    let req: Payload val = Payload.request(
      "GET",
      URL.build("http://localhost:65535/path?query=1#fragment")?
    )
    let res: Payload val = Payload.response()
    let log = CommonLog(stream)
    log.apply(
      ip,
      USize(1024),
      req,
      res
    )
    stream.validate(h)


