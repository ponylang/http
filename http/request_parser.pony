
primitive TooLarge
primitive UnknownMethod
primitive InvalidURI
primitive InvalidVersion
primitive InvalidContentLength
primitive InvalidTransferEncoding

"""
## How HTTP Requests need to be handled now

fun received(request) =>
  // look at method, url, headers
  // to determine what to do with coming body data.
  // set internal state for handling data

fun chunk(data) =>
  // determine based on internal state how to handle data.

## How they should be handled


interface RequestHandler
  fun received(request, session) =>
    do_sth_async(req_params, session as ResponseCallback) --> response_cb(response)

  fun chunk(data: Array[U8] val, session) => ...
  fun finished(session)
"""


type RequestParseError is ( TooLarge | UnknownMethod | InvalidURI | InvalidVersion | InvalidContentLength | InvalidTransferEncoding )

primitive NeedMore

type ParseReturn is (NeedMore | RequestParseError | None)
  """what is returned from `HTTP11RequestParser.parse(...)`"""

primitive _ExpectRequestLine
//primitive _ExpectHeaders
//primitive _ExpectBody

type _ParserState is (
  _ExpectRequestLine |
  _ExpectHeaders |
  _ExpectBody) // TODO: chunked stuff

interface HTTP11Handler
  """
  Downstream class that is notified of parse results,
  be it a valid `HTTPRequest` containing method, URL, headers and other metadata,
  or a specific `RequestParseError`.
  """
  fun ref apply(request: HTTPRequest val, session: HTTPSession)
    """
    Received parsed HTTPRequests
    """
  fun ref chunk(data: Array[U8] val, session: HTTPSession)
  fun ref finished(session: HTTPSession)

  fun ref failed(parse_error: RequestParseError, session: HTTPSession)

class HTTP11RequestParser
  let _max_request_line_size: USize = 8192 // TODO make configurable
  let _max_headers_size: USize      = 8192 // TODO make configurable

  let _handler: HTTP11Handler
  let _session: HTTPSession

  var _state: _ParserState = _ExpectRequestLine
  var _buffer: ByteArrays = ByteArrays.create()
  var _current_request: BuildableHTTPRequest trn = BuildableHTTPRequest

  var _expected_body_length: USize = 0
  var _persistent_connection: Bool = true
  var _transfer_encoding: (Chunked | None) = None

  new create(handler: HTTP11Handler, session: HTTPSession) =>
    _handler = handler
    _session = session

  fun ref parse(data: Array[U8] iso): ParseReturn =>
    _buffer = _buffer + (consume data)
    let ret =
      match _state
      | _ExpectRequestLine =>
        _parse_request_line()
      | _ExpectHeaders =>
        _parse_headers()
      | _ExpectBody =>
        _parse_body()
      end
    // signal errors to result receiver
    match ret
    | let rpe: RequestParseError => _handler.failed(rpe, _session)
    end

  fun _skip_whitespace(start: USize = 0): USize =>
    _buffer.skip_while(_HTTP11Parsing~is_whitespace(), start)

  fun _skip_horizontal_space(start: USize = 0): USize =>
    _buffer.skip_while(_HTTP11Parsing~is_horizontal_space(), start)

  fun _request_line_exhausted(): (TooLarge | NeedMore) =>
    if _buffer.size() > _max_request_line_size then
      TooLarge
    else
      NeedMore
    end

  fun _headers_exhausted(): (TooLarge | NeedMore) =>
    if _buffer.size() > _max_headers_size then
      TooLarge
    else
      NeedMore
    end

  fun ref _parse_request_line(): ParseReturn =>
    let start = _skip_whitespace(0)
    if start == USize.max_value() then
      return _request_line_exhausted()
    end

    match _buffer.find(" ", start)
    | (true, let method_end_idx: USize) =>
      let raw_method = _buffer.string(start, method_end_idx)
      let method = HTTPMethods.parse(raw_method)
      match method
      | None => return UnknownMethod
      | let m: HTTPMethod =>
        _current_request.set_method(m)
      end

      let uri_start = _skip_horizontal_space(method_end_idx + 1)
      if uri_start == USize.max_value() then
        return _request_line_exhausted()
      end
      match _buffer.find(" ", uri_start)
      | (true, let url_end_idx: USize) =>
        let raw_uri = _buffer.string(uri_start, url_end_idx)
        let uri = try
          URL.valid(raw_uri)?
        else
          return InvalidURI
        end
        _current_request.set_uri(uri)

        let version_start = _skip_horizontal_space(url_end_idx + 1)
        if version_start == USize.max_value() then
          return _request_line_exhausted()
        end
        if (_buffer.size() - version_start) >= 8 then
          try
            if (_buffer(version_start)? == 'H') and
              (_buffer(version_start + 1)? == 'T') and
              (_buffer(version_start + 2)? == 'T') and
              (_buffer(version_start + 3)? == 'P') and
              (_buffer(version_start + 4)? == '/') and
              (_buffer(version_start + 5)? == '1') and
              (_buffer(version_start + 6)? == '.')
            then
              var http_minor_version = _buffer(version_start + 7)?
              let http_version =
                match http_minor_version
                | '1' => HTTP11
                | '0' => HTTP10
                else
                  // invalid http minor version
                  return InvalidVersion
                end
              _current_request.set_version(http_version)

              let start_headers = _skip_whitespace(version_start + 8)
              if start_headers == USize.max_value() then
                return _request_line_exhausted()
              end
              // trim the buffer
              _buffer = _buffer.drop(start_headers)
              _state = _ExpectHeaders
              _parse_headers()

            else
              // invalid http version string
              return InvalidVersion
            end
          else
            _request_line_exhausted()
          end
        else
          // not enough space for http version
          _request_line_exhausted()
        end
      else
        // no whitespace after uri found
        _request_line_exhausted()
      end
    else
      // no whitespace after method found
      _request_line_exhausted()
    end

  fun ref _parse_headers(): ParseReturn =>
    var header_start: USize = 0 // we expect the buffer to be cut off after the request line
    var eoh: Bool = false
    while not eoh do
      match _parse_header(header_start)
      | (let name: String, let value: String, let hend: USize) =>
        _handle_special_headers(name, value)
        _current_request.add_header(name, value)
        _buffer = _buffer.drop(hend) // drop after successfully parsing a header
        header_start = hend
      | let hend: USize => // EOH
        header_start = hend
        eoh = true // break
      | NeedMore => return NeedMore
      end
    end
    // EOH
    // drop headers after reaching EOH
    _buffer = _buffer.drop(header_start)

    // send request downstream
    _handler.apply(_current_request = BuildableHTTPRequest, _session)

    _state = _ExpectBody
    _parse_body()

  fun ref _handle_special_headers(name: String, value: String): ParseReturn =>
    if CompareCaseInsensitive(name, "content-length") then
      let cl =
        try
          value.usize()?
        else
          return InvalidContentLength
        end
      _current_request.set_content_length(cl)
      _expected_body_length = cl
    elseif CompareCaseInsensitive(name, "transfer-encoding") then
      try
        value.find("chunked")?
        _transfer_encoding = Chunked
        _current_request.set_transfer_encoding(Chunked)
      else
        return InvalidTransferEncoding
      end
    elseif CompareCaseInsensitive(name, "connection") then
      _persistent_connection = if value == "close" then false else true end
    end
    None

  fun ref _parse_header(start: USize): ((String, String, USize) | NeedMore | RequestParseError | USize) =>
    match _buffer.find("\r\n", start)
    | (true, let header_line_end: USize) =>
      if header_line_end == start then
        // we reached end of headers
        return header_line_end + 2
      end

      match _buffer.find(":", start, header_line_end)
      | (true, let header_name_end: USize) =>

        let header_name = _buffer.string(start, header_name_end)
        let header_value_start = _skip_horizontal_space(header_name_end + 1)

        try
          (let header_value, let header_end) =
            if (_buffer.size() > (header_line_end + 3)) and _HTTP11Parsing.is_horizontal_space(_buffer(header_line_end + 3)?) then
              // we have a header spanning multiple lines
              let multi_line_value: String trn = recover trn String((header_line_end - header_value_start) * 2) end
              multi_line_value.append(_buffer.string(header_value_start, header_line_end))

              var hend: USize = header_line_end
              var line_start = hend + 3
              while (_buffer.size() > (line_start)) and _HTTP11Parsing.is_horizontal_space(_buffer(line_start)?) do
                let line_value_start = _skip_horizontal_space(line_start)
                match _buffer.find("\r\n", line_value_start)
                | (true, let line_end: USize) =>
                  multi_line_value.append(_buffer.string(line_value_start, line_end))
                  hend = line_end
                  line_start = hend + 3
                else
                  return _headers_exhausted()
                end
              end
              (multi_line_value, hend)

            else
              // single line header, simple processing, in best case no
              // additional allocation
              (_buffer.string(header_value_start, header_line_end), header_line_end)
            end
          (header_name, header_value, header_end + 2)
        else
          // should never happen, guarded _buffer.apply calls
          return _headers_exhausted()
        end
      else
        // no ':' found
        _headers_exhausted()
      end
    else
      // no CRLF found
      _headers_exhausted()
    end


  fun ref _parse_body(): ParseReturn =>
    match _transfer_encoding
    | Chunked =>
      // TODO
      NeedMore
    else
      if _expected_body_length > 0 then
        let available = _expected_body_length.min(_buffer.size() - 1)
        let data = _buffer.trim(0, available)
        _buffer = _buffer.drop(data.size())
        _expected_body_length = _expected_body_length - data.size()
        _handler.chunk(data, _session)
      end
      if _expected_body_length == 0 then
        _handler.finished(_session)

        _state = _ExpectRequestLine
        _parse_request_line()
      else
        NeedMore
      end
    end


primitive _HTTP11Parsing
  """
  Common stuff for parsing HTTP/1.1
  """
  fun tag is_whitespace(ch: U8): Bool =>
    (ch == 0x09) or (ch == 0x0a) or (ch == 0x0d) or (ch == 0x20)

  fun tag is_horizontal_space(ch: U8): Bool =>
    (ch == 0x09) or (ch == 0x20)


primitive CompareCaseInsensitive
  fun _lower(c: U8): U8 =>
    if (c >= 0x41) and (c <= 0x5A) then
      c + 0x20
    else
      c
    end

  fun apply(left: String, right: String): Bool =>
    """
    Returns true if both strings compare equal
    when compared case insensitively
    """
    if left.size() != right.size() then
      false
    else
      var i: USize = 0
      while i < left.size() do
        try
          if _lower(left(i)?) != _lower(right(i)?) then
            return false
          end
        else
          return false
        end
        i = i + 1
      end
      true
    end


