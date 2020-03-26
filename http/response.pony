use "valbytes"
use "format"

interface val HTTPResponse is ByteSeqIter
  """
  Representing a HTTP response minus the body.
  """
  fun version(): HTTPVersion
  fun status(): Status
  fun header(name: String): (String | None)
  fun headers(): Iterator[Header]
  fun transfer_coding(): (Chunked | None)
  fun content_length(): (USize | None)
  fun to_bytes(): ByteArrays
  fun array(): Array[U8] iso^

primitive HTTPResponses // TODO: better naming
  """
  The entry-point into building HTTPResponses.
  """
  fun builder(version: HTTPVersion = HTTP11): ResponseBuilder =>
    """
    Official way to get a reusable [ResponseBuilder](http-ResponseBuilder.md)
    to build your responses efficiently.
    """
    _FullResponseBuilder._create(version)

interface ResponseBuilder
  """
  Basic interface for a ResponseBuilder that can be used with chaining method calls.
  It enforces a strict order of build steps by only making the next step available
  as a return to a function required to transition. E.g. You must call `set_status(...)`
  in order to get back a [ResponseBuilderHeaders](http-ResponseBuilderHeaders.md) to add
  headers to the response. You need to call `finish_headers()` in order to
  be able to add body data with [ResponseBuilderBody](http-ResponseBuilderBody.md).

  You can always reset the builder to start out fresh from the beginning.
  Implementations may take advantage of `reset()` by returning itself here,
  allowing for object reuse.

  Use [ResponseBuilderBody.build()](http-ResponseBuilderBody.md#build) to finally build the
  response into a [ByteSeqIter](builtin-ByteSeqIter.md),
  taylored for use with [HTTPSession.send_raw()](http-HTTPSession.md#send_raw).

  Example usage:

  ```pony
  let builder: ResponseBuilder = HTTPResponses.builder()
  builder.set_status(StatusOK)
         .add_header("Content-Length", "4")
         .add_header("Content-Type", "text/plain; charset=UTF-8")
         .add_header("Server", "pony-http")
         .finish_headers()
         .add_chunk("COOL")
         .build()
  ```
  """
  fun ref set_status(status: Status): ResponseBuilderHeaders
  fun ref reset(): ResponseBuilder

interface ResponseBuilderHeaders
  fun ref add_header(name: String, value: String): ResponseBuilderHeaders
  fun ref set_transfer_encoding(chunked: (Chunked | None)): ResponseBuilderHeaders
  fun ref finish_headers(): ResponseBuilderBody
  fun ref reset(): ResponseBuilder

interface ResponseBuilderBody
  fun ref add_chunk(data: Array[U8] val): ResponseBuilderBody
    """
    Add some body data.

    If Transfer-Encoding is set to [Chunked](http-Chunked.md) in [ResponseBuilderHeaders](http-ResponseBuilderHeaders.md)
    each call to this function will take care of encoding every added array here in Chunked encoding.
    Add an empty array to add the finishing chunk..
    """
  fun ref build(): ByteSeqIter
    """
    Serialize the accumulated response data into a [ByteSeqIter](builtin-ByteSeqIter.md).
    """
  fun ref reset(): ResponseBuilder
    """
    Reset the builder to a fresh state, only use the returned builder for further actions.
    """

class iso _FullResponseBuilder
  """
  Efficient HTTP response builder
  backed by a byte array to which we only append.

  Will write multiple chunks into separate arrays only if
  they exceed 65535 bytes (arbitrary choice).
  Otherwise appends to the same array, in order to not bog up
  writev calls with tiny arrays, which makes it very much inefficient.

  Keep your arrays decently sized at all times!

  This instance is `iso`, so you can safely send it around amongst your actors.
  """
  let _version: HTTPVersion
  let _empty_placeholder: Array[U8] val = recover val _empty_placeholder.create(0) end
  let _crlf: Array[U8] val = [as U8: '\r'; '\n']
  let _header_sep: Array[U8] val = [as U8: ':'; ' ']

  var _array: Array[U8] iso
  var _chunks: Array[Array[U8] val] iso
  var _transfer_coding: (Chunked | None)
  var _needs_reset: Bool = false

  new iso _create(version: HTTPVersion = HTTP11) =>
    _version = version
    _array = (recover iso Array[U8].create(128) end)
      .>append(_version.to_bytes())
      .>append(" ")
    _chunks = (recover iso Array[Array[U8] val](1) end)
      .>push(_empty_placeholder)
    _transfer_coding = None

  fun ref reset(): ResponseBuilder =>
    if _needs_reset then
      _array = (recover iso Array[U8].create(128) end)
        .>append(_version.to_bytes())
        .>append(" ")
      _chunks = (recover iso Array[Array[U8] val](1) end)
        .>push(_empty_placeholder)
      _transfer_coding = None
    end
    _needs_reset = false
    this

  fun ref set_status(status: Status): ResponseBuilderHeaders =>
    _array.>append(status.string())
         .>append(_crlf)
    _needs_reset = true
    this

  fun ref finish_headers(): ResponseBuilderBody =>
    _array.append(_crlf)
    _needs_reset = true
    this

  fun ref add_header(name: String, value: String): ResponseBuilderHeaders =>
    _array
        .>append(name)
        .>append(_header_sep)
        .>append(value)
        .>append(_crlf)
    _needs_reset = true
    this

  fun ref _set_transfer_coding(chunked: (Chunked | None)) =>
    _transfer_coding = chunked

  fun ref set_transfer_encoding(chunked: (Chunked | None)): ResponseBuilderHeaders =>
    """
    this will also add the Transfer-Encoding header if set to `Chunked`.
    """
    match chunked
    | Chunked =>
      add_header("Transfer-Encoding", "chunked")
    end
    _set_transfer_coding(chunked)
    _needs_reset = true
    this

  fun ref add_chunk(data: Array[U8] val): ResponseBuilderBody =>
    """
    content-length needs to be set before this happens.
    In case of chunked transfer-encoding this will be encoded into proper chunks.
    """
    if (data.size() < 65535) and (_chunks.size() == 1) then
      // we can only append to the response array if we have no chunk yet added
      // to chunks (1 means 0 as we always put a placeholder)
      if _transfer_coding is Chunked then
        _array
          .>append(
            (recover val Format.int[USize](data.size() where fmt = FormatHexBare).>append(_crlf) end).array())
          .>append(data)
          .append(_crlf)
      else
        _array.append(data)
      end
    else
      if _transfer_coding is Chunked then
        _chunks
          .>push(
            (recover val Format.int[USize](data.size() where fmt = FormatHexBare).>append(_crlf) end).array())
          .>push(data)
          .push(_crlf)
      else
        _chunks.push(data)
      end
    end
    _needs_reset = true
    this

  fun ref build(): ByteSeqIter =>
    """
    This will not add the final chunk
    Do this manually by calling:

    ```pony
    builder.add_chunk(recover val Array[U8](0) end)
    ```
    """
    let response =
      (_array = (recover iso Array[U8].create(128) end)
                 .>append(_version.to_bytes())
                 .>append(" "))
    try
      // should never fail. is always initialized with empty_placeholder at
      // index 0
      _chunks(0)? = consume response
    end
    let byteseqs = (_chunks = (recover iso Array[Array[U8] val](1) end)
      .>push(_empty_placeholder))
    _transfer_coding = None
    _needs_reset = false
    consume byteseqs


// TODO: make internal state a ByteArrays instance and only keep track of
// indices pointing to values
class val BuildableHTTPResponse is (HTTPResponse & ByteSeqIter)
  """
  Build your own HTTP Responses (minus the body) and turn them into immutable
  things to send around.

  This class can be serialized in the following ways:

  * to Array[U8]: BuildableHTTPResponse.array()
  * to ByteArrays: BuildableHTTPResponse.to_bytes()

  or by using it as a ByteSeqIter.

  This class exists if you want to use the verbose API of [HTTPSession](http-HTTPSession.md)
  and brings lots of convenience, like getters and setters for all common properties.

  If you are looking for a more efficient way to build responses, use a [ResponseBuilder](http-ResponseBuilder.md)
  as it is returned from [HTTPResponses.builder()](http-HTTPResponses.md#builder), this class is not introspectable
  and only allows adding properties the way they are put on the serialized form in the request. E.g. you must first
  set the status and then the headers, not the other way around. But it makes for a more efficient API.
  """
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
    match cl
    | let clu: USize =>
      set_header("Content-Length", cl.string())
    // | None =>
    // TODO: drop header
    end
    this

  fun array(): Array[U8] iso^ =>
    let sp: Array[U8] val =   [as U8: ' ']
    let crlf: Array[U8] val = [as U8: '\r'; '\n']
    let header_sep: Array[U8] val = [as U8: ':'; ' ']
    let version_bytes = _version.to_bytes()
    let status_bytes = _status.string()
    let header_size = _headers.byte_size()
    let arr =
      recover iso
        Array[U8](
          version_bytes.size() + 1 + status_bytes.size() + 2 + header_size + 2)
      end
    arr.>append(version_bytes)
       .>append(sp)
       .>append(status_bytes)
       .append(crlf)

    for (hname, hvalue) in headers() do
      arr.>append(hname)
         .>append(header_sep)
         .>append(_format_multiline(hvalue))
         .>append(crlf)
    end
    arr.append(crlf)
    consume arr

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
    """
    Make this a very inefficient ByteSeqIter.
    Rather use `array()` if you care about performance.
    """
    to_bytes().arrays().values()

  fun tag _format_multiline(header_value: String): String =>
    // TODO
    header_value


