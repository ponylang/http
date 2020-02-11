use "valbytes"

interface val HTTPResponse is ByteSeqIter
  fun version(): HTTPVersion
  fun status(): Status
  fun header(name: String): (String | None)
  fun headers(): Iterator[Header]
  fun transfer_coding(): (Chunked | None)
  fun content_length(): (USize | None)
  fun to_bytes(): ByteArrays

// TODO: make internal state a ByteArrays instance and only keep track of
// indices pointing to values
class val BuildableHTTPResponse
  var _version: HTTPVersion
  var _status: Status
  embed _headers: Headers = _headers.create()
  var _transfer_coding: (Chunked | None)
  var _content_length: (USize | None)

  new trn create(
    status': Status = StatusOK,
    version': HTTPVersion = HTTP11,
    transfer_coding': (Chunked | None) = None,
    content_length': (USize | None) = None) =>
    _status = status'
    _version = version'
    _transfer_coding = transfer_coding'
    _content_length = content_length'

  fun version(): HTTPVersion => _version
  fun ref set_version(v: HTTPVersion): BuildableHTTPResponse ref =>
    _version = v
    this

  fun status(): Status => _status
  fun ref set_status(s: Status): BuildableHTTPResponse ref =>
    _status = s
    this

  fun header(name: String): (String | None) => _headers.get(name)
  fun headers(): Iterator[Header] => _headers.values()
  fun ref add_header(name: String, value: String): BuildableHTTPResponse ref =>
    _headers.add(name, value)
    this
  fun ref set_header(name: String, value: String): BuildableHTTPResponse ref =>
    _headers.set(name, value)
    this
  fun ref clear_headers(): BuildableHTTPResponse ref =>
    _headers.clear()
    this

  fun transfer_coding(): (Chunked | None) => _transfer_coding
  fun ref set_transfer_coding(c: (Chunked | None)): BuildableHTTPResponse ref =>
    _transfer_coding = c
    this

  fun content_length(): (USize | None) => _content_length
  fun ref set_content_length(cl: (USize | None)): BuildableHTTPResponse ref =>
    _content_length = cl
    this

  fun to_bytes(): ByteArrays =>
    let sp: Array[U8] val =   [as U8: ' ']
    let crlf: Array[U8] val = [as U8: '\r'; '\n']
    let header_sep: Array[U8] val = [as U8: ':'; ' ']
    var acc = ByteArrays(version().to_bytes(), sp) + status().string() + crlf
    for (hname, hvalue) in headers() do
      acc = acc + hname + header_sep + _format_multiline(hvalue) + crlf
    end
    (acc + crlf)


  fun values(): Iterator[this->ByteSeq box] =>
    to_bytes().byteseqiter().values()

  fun tag _format_multiline(header_value: String): String =>
    // TODO
    header_value


