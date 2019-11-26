use ".."

primitive ParseError
primitive NeedMore

primitive _ExpectRequestLine
primitive _ExpectHeaders
primitive _ExpectBody

type _ParserState is (
  _ExpectRequestLine |
  _ExpectHeaders |
  _ExpectBody) // TODO: chunked stuff

type ParseResult is (HTTPRequest val | NeedMore | ParseError)

class HTTP11RequestParser
  let crlf: String = "\r\n"
  let crlfcrlf: String = "\r\n\r\n"
  let _max_request_line_size: USize = 8192 // TODO make configurable

  var _state: _ParserState = _ExpectRequestLine
  var _buffer: ByteArrays = ByteArrays.create()
  var _current_request: HTTPRequest trn = HTTPRequest

  fun ref append(data: Array[U8] iso) =>
    _buffer = _buffer + (consume data)

  fun ref parse(): ParseResult =>
    match _state
    | _ExpectRequestLine =>
      _parse_request_line()
    | _ExpectHeaders =>
      _parse_headers()
    | _ExpectBody =>
      _parse_body()
    end

  fun tag _is_whitespace(ch: U8): Bool =>
    (ch == 0x09) or (ch == 0x0a) or (ch == 0x0d) or (ch == 0x20)

  fun tag _is_horizontal_space(ch: U8): Bool =>
    (ch == 0x09) or (ch == 0x20)

  fun _skip_whitespace(start: USize = 0): USize =>
    _buffer.skip_while(this~_is_whitespace(), start)

  fun _skip_horizontal_space(start: USize = 0): USize =>
    _buffer.skip_while(this~_is_horizontal_space(), start)

  fun _request_line_exhausted(): ParseResult =>
    if _buffer.size() > _max_request_line_size then
      ParseError
    else
      NeedMore
    end

  fun ref _parse_request_line(): ParseResult =>
    let start = _skip_whitespace(0)
    if start == USize.max_value() then
      return _request_line_exhausted()
    end

    match _buffer.find(" ", start)
    | (true, let method_end_idx: USize) =>
      let raw_method = _buffer.string(start, method_end_idx)
      let method = HTTPMethods.parse(raw_method)
      if method is None then
        return ParseError
      end
      _current_request.set_method(method)

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
          return ParseError
        end
        _current_request.set_uri(uri)

        let version_start = _skip_horizontal_space(url_end_idx + 1)
        if version_start == Usize.max_value() then
          return _request_line_exhausted()
        end
        if (_buffer.size() - version_start) >= 8 then
          if (_buffer(version_start)? == 'H') and
            (_buffer(version_start + 1)? == 'T') and
            (_buffer(version_start + 2)? == 'T') and
            (_buffer(version_start + 3)? == 'P') and
            (_buffer(version_start + 4)? == '/') and
            (_buffer(version_start + 5)? == '1') and
            (_buffer(version_start + 6)? == '.')
          then
            var http_minor_version = this(version_start + 7)?
            let http_version =
              match http_minor_version
              | '1' => HTTP11
              | '0' => HTTP10
              else
                // invalid http minor version
                return ParseError
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
            return ParseError
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

  fun ref _parse_headers(): ParseResult =>
    var header_start: USize = 0 // we expect the buffer to be cut off after the request line
    var eoh: Bool = false
    while not eoh do
      match _parse_header(header_start)
      | (let name: String, let value: String, let hend: USize) =>
        // TODO: lower-case header names
        _current_request.add_header(name, value)
        header_start = hend
      | let hend: USize =>
        header_start = hend
        eoh = true // break
      | NeedMore => return NeedMore
        end
    end

    _buffer.drop(header_start)
    _state = _ExpectBody
    _parse_body()


  fun ref _parse_header(start: USize): ((String, String, USize) | NeedMore | Usize) =>
    match _buffer.find(crlf, start)
    | (true, let header_end: USize) =>
      // TODO: handle continuation lines
      //while (_buffer.size() > (header_end + 3)) and _is_horizontal_space(_buffer(header_end + 3)?) do
      //end
      if header_end == start then
        // we reached end of headers
        return header_end + 2
      end
      match _buffer.find(":", start, header_end)
      | (true, let header_name_end: USize) =>
        let header_name = _buffer.string(start, header_name_end)
        let header_value_start = _skip_horizontal_space(header_name_end + 1)
        let header_value = _buffer.string(header_value_start, header_end)
        (header_name, header_value, header_end + 2)
      else
        NeedMore
      end
    else
      NeedMore
    end


  fun ref _parse_body(): ParseResult => NeedMore


