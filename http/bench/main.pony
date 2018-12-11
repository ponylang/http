use ".."
use "buffered"
use "ponybench"
use "debug"
use "format"

actor Main is BenchmarkList
  new create(env: Env) =>
    PonyBench(env, this)

  fun tag benchmarks(bench: PonyBench) =>
    bench(_SimpleGetRequestBenchmark)
    bench(_FormSubmissionRequestBenchmark)
    bench(_SplitFormSubmissionRequestBenchmark)
    bench(_MultipartFileUploadBenchmark)
    bench(_ChunkedRequestBenchmark)

actor _TestHTTPSession is HTTPSession
  var _c: (AsyncBenchContinue | None) = None

  be set_continue(c: AsyncBenchContinue) =>
    _c = c

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
    match payload.transfer_mode
    | OneshotTransfer =>
      try
        (_c as AsyncBenchContinue).complete()
      else
        Debug("no benchcontinue set")
      end
    else
      Debug("_deliver chunk|stream")
    end

  be _chunk(data: ByteSeq val) =>
    Debug("_chunk")

  be _finish() => None
    Debug("_finish")
    try
      (_c as AsyncBenchContinue).complete()
    else
      Debug("_finish None")
    end

class _ParseRequestBenchmark
  let _data: Array[String]
  let _reader: Reader = Reader
  let _session: _TestHTTPSession = _TestHTTPSession.create()
  let _parser: HTTPParser = HTTPParser.request(_session)

  new create(data: Array[String]) =>
    _data = data

  fun ref apply(c: AsyncBenchContinue) ? =>
    _session.set_continue(c)
    _parser.restart()
    _reader.clear()
    let data_iter = _data.values()
    while data_iter.has_next() do
      let chunk = data_iter.next()?
      _reader.append(chunk)
      match _parser.parse(_reader)
      | ParseError =>
        Debug("parsing failed.")
        if not data_iter.has_next() then
          c.fail()
        end
      end
    end

class iso _SimpleGetRequestBenchmark is AsyncMicroBenchmark

  let data: Array[String] = [
    "\r\n".join(
      [
        "GET /get HTTP/1.1"
        "Host: httpbin.org"
        "User-Agent: curl/7.58.0"
        "Accept: */*"
        ""
        ""
      ].values())
  ]

  let _bench: _ParseRequestBenchmark = _ParseRequestBenchmark(data)

  fun config(): BenchConfig => BenchConfig(
    where max_iterations' = 100)

  fun name(): String => "request/simple"

  fun ref apply(c: AsyncBenchContinue)? =>
    Debug("running bench")
    _bench.apply(c)?


class iso _FormSubmissionRequestBenchmark is AsyncMicroBenchmark
  let data: Array[String] = [
    "\r\n".join([
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
        "custname=Pony+Mc+Ponyface&custtel=%2B490123456789&custemail=pony%40ponylang.org&size=large&topping=bacon&topping=cheese&topping=onion&delivery=&comments=This+is+a+stupid+test"
        ].values())
  ]
  let _bench: _ParseRequestBenchmark = _ParseRequestBenchmark(data)

  fun config(): BenchConfig => BenchConfig(
    where max_iterations' = 100)

  fun name(): String => "request/form-submission"

  fun ref apply(c: AsyncBenchContinue)? =>
    _bench.apply(c)?

class iso _SplitFormSubmissionRequestBenchmark is AsyncMicroBenchmark
  let data: Array[String] = [
    "\r\n".join([
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
      "Upgrade-Insecure-Req"
      ].values())
    "\r\n".join([
      "uests: 1"
      ""
      "custname=Pony+Mc+Ponyface&custtel=%2B490123456789&custemail=pony%40ponylang.org&size=large&topping=bacon&topping=cheese&topping=onion&delivery=&comments=This+is+a+stupid+test"
      ].values())
  ]
  let _bench: _ParseRequestBenchmark = _ParseRequestBenchmark(data)

  fun config(): BenchConfig => BenchConfig(
    where max_iterations' = 100)

  fun name(): String => "request/form-submission/split"

  fun ref apply(c: AsyncBenchContinue)? =>
    _bench.apply(c)?

class iso _MultipartFileUploadBenchmark is AsyncMicroBenchmark
  let data: Array[String] = [
    "\r\n".join([
      "POST /cgi-bin/request HTTP/1.1"
      "Host: localhost"
      "User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:61.0) Gecko/20100101 Firefox/61.0"
      "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
      "Accept-Language: en-GB,en;q=0.5"
      "Accept-Encoding: gzip, deflate"
      "Connection: keep-alive"
      "Content-Type: multipart/form-data; boundary=abcdef123456"
      "Content-Length: 10001" // forcing streaming
      ""
      "--abcdef123456"
      "Content-Disposition: form-data; name=\"random_stuff1\""
      String.from_array(recover val Array[U8].init('a', 5000) end)
      "Content-Disposition: form-data; name=\"random_stuff2\""
      String.from_array(recover val Array[U8].init('b', 4867) end)
      "--abcdef123456--"
      ].values())]
  let _bench: _ParseRequestBenchmark = _ParseRequestBenchmark(data)

  fun config(): BenchConfig => BenchConfig(
    where max_iterations' = 100)

  fun name(): String => "request/multipart-file-upload"

  fun ref apply(c: AsyncBenchContinue)? =>
    _bench.apply(c)?

class iso _ChunkedRequestBenchmark is AsyncMicroBenchmark
  let data: Array[String] = [
    "\r\n".join([
      "GET /get HTTP/1.1"
      "Host: localhost:8888"
      "User-Agent: curl/7.58.0"
      "Accept: */*"
      "Transfer-Encoding: chunked"
      "Content-Type: application/x-www-form-urlencoded"
      ""
      Format.int[U64](100 where fmt=FormatHexBare)
      String.from_array(recover val Array[U8].init('a', 100) end)
      Format.int[U64](500 where fmt=FormatHexBare)
      String.from_array(recover val Array[U8].init('b', 500) end)
      "0"
      ""
      ""
      ].values())
    ]
  let _bench: _ParseRequestBenchmark = _ParseRequestBenchmark(data)

  fun config(): BenchConfig => BenchConfig(
    where max_iterations' = 100)

  fun name(): String => "request/chunked"

  fun ref apply(c: AsyncBenchContinue)? =>
    _bench.apply(c)?

