
primitive HTTP11 is (Equatable[HTTPVersion] & Stringable)
  fun string(): String iso^ => recover iso String(8).>append("HTTP/1.1") end
  fun eq(o: HTTPVersion): Bool => o is this
primitive HTTP10 is (Equatable[HTTPVersion] & Stringable)
  fun string(): String iso^ => recover iso String(8).>append("HTTP/1.0") end
  fun eq(o: HTTPVersion): Bool => o is this
primitive HTTP09 is (Equatable[HTTPVersion] & Stringable)
  fun string(): String iso^ => recover iso String(8).>append("HTTP/0.9") end
  fun eq(o: HTTPVersion): Bool => o is this

type HTTPVersion is (HTTP09 | HTTP10 | HTTP11)



interface val HTTPRequest
  """
  HTTP Request

  * Method
  * URI
  * HTTP-Version
  * Headers
  * Transfer-Coding
  * Content-Length

  Without body.
  """
  fun method(): HTTPMethod
  fun uri(): URL
  fun version(): HTTPVersion
  fun header(name: String): (String | None)
  fun headers(): Iterator[Header]
  fun transfer_coding(): (Chunked | None)
  fun content_length(): (USize | None)
  fun has_body(): Bool

class val BuildableHTTPRequest is HTTPRequest
  var _method: HTTPMethod
  var _uri: URL
  var _version: HTTPVersion
  embed _headers: Headers = _headers.create()
  var _transfer_coding: (Chunked | None)
  var _content_length: (USize | None)

  new trn create(
    method': HTTPMethod = GET,
    uri': URL = URL,
    version': HTTPVersion = HTTP11,
    transfer_coding': (Chunked | None) = None,
    content_length': (USize | None) = None) =>
    _method = method'
    _uri = uri'
    _version = version'
    _transfer_coding = transfer_coding'
    _content_length = content_length'

  fun method(): HTTPMethod => _method

  fun ref set_method(method': HTTPMethod): BuildableHTTPRequest ref =>
    _method = method'
    this

  fun uri(): URL => _uri

  fun ref set_uri(uri': URL): BuildableHTTPRequest ref =>
    _uri = uri'
    this

  fun version(): HTTPVersion => _version

  fun ref set_version(v: HTTPVersion): BuildableHTTPRequest ref =>
    _version = v
    this

  fun header(name: String): (String | None) =>
    """
    Case insensitive lookup of header value in this request.
    Returns `None` if no header with name exists in this request.
    """
    _headers.get(name)

  fun headers(): Iterator[Header] => _headers.values()

  fun ref add_header(name: String, value: String): BuildableHTTPRequest ref =>
    // TODO: check for special headers like Transfer-Coding
    _headers.add(name, value)
    this

  fun ref set_header(name: String, value: String): BuildableHTTPRequest ref =>
    _headers.set(name, value)
    this

  fun ref clear_headers(): BuildableHTTPRequest ref =>
    _headers.clear()
    this

  fun transfer_coding(): (Chunked | None) => _transfer_coding

  fun ref set_transfer_coding(te: (Chunked | None)): BuildableHTTPRequest ref =>
    // TODO: also update headers
    _transfer_coding = te
    this

  fun content_length(): (USize | None) => _content_length

  fun ref set_content_length(cl: USize): BuildableHTTPRequest ref =>
    _content_length = cl
    this

  fun has_body(): Bool =>
    (transfer_coding() is Chunked)
    or
    match content_length()
    | let x: USize if x > 0 => true
    else
      false
    end



