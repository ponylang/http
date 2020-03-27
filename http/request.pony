
interface val _HTTPVersion is (Equatable[HTTPVersion] & Stringable)
  fun to_bytes(): Array[U8] val

primitive HTTP11 is _HTTPVersion
  """
  HTTP/1.1
  """
  fun string(): String iso^ => recover iso String(8).>append("HTTP/1.1") end
  fun to_bytes(): Array[U8] val => [as U8: 'H'; 'T'; 'T'; 'P'; '/'; '1'; '.'; '1']
  fun eq(o: HTTPVersion): Bool => o is this

primitive HTTP10 is _HTTPVersion
  """
  HTTP/1.0
  """
  fun string(): String iso^ => recover iso String(8).>append("HTTP/1.0") end
  fun to_bytes(): Array[U8] val => [as U8: 'H'; 'T'; 'T'; 'P'; '/'; '1'; '.'; '0']
  fun eq(o: HTTPVersion): Bool => o is this

primitive HTTP09 is _HTTPVersion
  """
  HTTP/0.9
  """
  fun string(): String iso^ => recover iso String(8).>append("HTTP/0.9") end
  fun to_bytes(): Array[U8] val => [as U8: 'H'; 'T'; 'T'; 'P'; '/'; '0'; '.'; '9']
  fun eq(o: HTTPVersion): Bool => o is this

type HTTPVersion is ((HTTP09 | HTTP10 | HTTP11) & _HTTPVersion)
  """
  union of supported HTTP Versions

  See: https://tools.ietf.org/html/rfc2616#section-3.1
  """


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
  """
  A HTTP Request that is created with `trn` refcap
  in order to be mutable, and then, when done, be consumed into
  a `val` reference. This is the way, the `HTTP11RequestParser` is handling this class and so should you.
  """
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

  fun method(): HTTPMethod =>
    """
    The Request Method.

    See: https://tools.ietf.org/html/rfc2616#section-5.1.1
    """
    _method

  fun ref set_method(method': HTTPMethod): BuildableHTTPRequest ref =>
    _method = method'
    this

  fun uri(): URL =>
    """
    The request URI

    See: https://tools.ietf.org/html/rfc2616#section-5.1.2
    """
    _uri

  fun ref set_uri(uri': URL): BuildableHTTPRequest ref =>
    _uri = uri'
    this

  fun version(): HTTPVersion =>
    """
    The HTTP version as given on the Request Line.

    See: https://tools.ietf.org/html/rfc2616#section-3.1 and https://tools.ietf.org/html/rfc2616#section-5.1
    """
    _version

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
    """
    Add a header with name and value to this request.
    If a header with this name already exists, the given value will be appended to it,
    with a separating comma.
    """
    // TODO: check for special headers like Transfer-Coding
    _headers.add(name, value)
    this

  fun ref set_header(name: String, value: String): BuildableHTTPRequest ref =>
    """
    Set a header in this request to the given value.

    If a header with this name already exists, the previous value will be overwritten.
    """
    _headers.set(name, value)
    this

  fun ref clear_headers(): BuildableHTTPRequest ref =>
    """
    Remove all previously set headers from this request.
    """
    _headers.clear()
    this

  fun transfer_coding(): (Chunked | None) =>
    """
    If `Chunked` the request body is encoded with Chunked Transfer-Encoding:

    See: https://tools.ietf.org/html/rfc2616#section-3.6.1

    If `None`, no Transfer-Encoding is applied. A Content-Encoding might be applied
    to the body.
    """
    _transfer_coding

  fun ref set_transfer_coding(te: (Chunked | None)): BuildableHTTPRequest ref =>
    _transfer_coding = te
    this

  fun content_length(): (USize | None) =>
    """
    The content-length of the body of the request, counted in number of bytes.

    If the content-length is `None`, the request either has no content-length set
    or it's transfer-encoding is `Chunked`: https://tools.ietf.org/html/rfc2616#section-3.6.1
    """
    _content_length

  fun ref set_content_length(cl: USize): BuildableHTTPRequest ref =>
    _content_length = cl
    this

  fun has_body(): Bool =>
    """
    Returns `true` if either we have Chunked Transfer-Encoding
    or a given Content-Length. In those cases we can expect a body.
    """
    (transfer_coding() is Chunked)
    or
    match content_length()
    | let x: USize if x > 0 => true
    else
      false
    end



