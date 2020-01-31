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
    version': HTTPVersion = HTTP11,
    status': Status = StatusOK,
    transfer_coding': (Chunked | None) = None,
    content_length': (USize | None) = None) =>
    _version = version'
    _status = status'
    _transfer_coding = transfer_coding'
    _content_length = content_length'

  // TODO: mutating methods
  fun version(): HTTPVersion => _version
  fun status(): Status => _status
  fun header(name: String): (String | None) => _headers.get(name)
  fun headers(): Iterator[Header] => _headers.values()
  fun transfer_coding(): (Chunked | None) => _transfer_coding
  fun content_length(): (USize | None) => _content_length
