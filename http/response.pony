interface val HTTPResponse
  fun version(): HTTPVersion
  fun status(): Status
  fun header(name: String): (String | None)
  fun headers(): Iterator[Header]
  fun transfer_coding(): (Chunked | None)
  fun content_length(): (USize | None)

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
