use "valbytes"
use "debug"

primitive TooLarge is Stringable
  fun string(): String iso^ => "TooLarge".clone()

primitive UnknownMethod is Stringable
  fun string(): String iso^ => "UnknownMethod".clone()

primitive InvalidURI is Stringable
  fun string(): String iso^ =>
    "InvalidURI".clone()
primitive InvalidVersion is Stringable
  fun string(): String iso^ =>
    "InvalidVersion".clone()
primitive InvalidContentLength is Stringable
  fun string(): String iso^ =>
    "InvalidContentLength".clone()
primitive InvalidTransferCoding is Stringable
  fun string(): String iso^ =>
    "InvalidTransferCoding".clone()
primitive InvalidChunk is Stringable
  fun string(): String iso^ =>
    "InvalidChunk".clone()

type RequestParseError is ( TooLarge | UnknownMethod | InvalidURI | InvalidVersion | InvalidContentLength | InvalidTransferCoding | InvalidChunk )

primitive NeedMore is Stringable
  fun string(): String iso^ => "NeedMore".clone()

type ParseReturn is (NeedMore | RequestParseError | None)
  """what is returned from `HTTP11RequestParser.parse(...)`"""

primitive _ExpectRequestLine
primitive _ExpectHeaders
primitive _ExpectBody
primitive _ExpectChunkStart
primitive _ExpectChunk
primitive _ExpectChunkEnd

type _ParserState is (
  _ExpectRequestLine |
  _ExpectHeaders |
  _ExpectBody |
  _ExpectChunkStart |
  _ExpectChunk |
  _ExpectChunkEnd)


primitive Chunked

interface tag HTTP11RequestHandler
  """
  Downstream actor that is notified of parse results,
  be it a valid `HTTPRequest` containing method, URL, headers and other metadata,
  or a specific `RequestParseError`.
  """
  be _receive_start(request: HTTPRequest val, request_id: RequestID)
    """
    Receive parsed HTTPRequest
    """

  be _receive_chunk(data: Array[U8] val, request_id: RequestID)
  be _receive_finished(request_id: RequestID)

  be _receive_failed(parse_error: RequestParseError, request_id: RequestID)

class HTTP11RequestParser
  let _max_request_line_size: USize = 8192 // TODO make configurable
  let _max_headers_size: USize      = 8192 // TODO make configurable
  let _max_chunk_size_line_length: USize = 128 // TODO: make configurable

  let _handler: HTTP11RequestHandler

  var _state: _ParserState = _ExpectRequestLine
  var _buffer: ByteArrays = ByteArrays.create()
  var _request_counter: RequestID = 0
  var _current_request: BuildableHTTPRequest trn = BuildableHTTPRequest.create()

  var _expected_body_length: USize = 0
  var _persistent_connection: Bool = true
  var _transfer_coding: (Chunked | None) = None

  new create(handler: HTTP11RequestHandler) =>
    _handler = handler

  fun ref parse(data: Array[U8] val): ParseReturn =>
    _buffer = _buffer + (consume data)
    let ret =
      match _state
      | _ExpectRequestLine =>
        _parse_request_line()
      | _ExpectHeaders =>
        _parse_headers()
      | _ExpectBody =>
        _parse_body()
      | _ExpectChunkStart =>
        _parse_chunk_start()
      | _ExpectChunk =>
        _parse_chunk()
      | _ExpectChunkEnd =>
        _parse_chunk_end()
      end
    // signal errors to result receiver
    match ret
    | let rpe: RequestParseError =>
      _handler._receive_failed(rpe, _request_counter)
      reset(where reset_request = true) // TODO: drop data here?
    end
    ret

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

  fun _chunk_size_line_exhausted(): (InvalidChunk | NeedMore) =>
    if _buffer.size() > _max_chunk_size_line_length then
      InvalidChunk
    else
      NeedMore
    end

  fun _chunk_trailers_exhausted(): (InvalidChunk | NeedMore) =>
    if _buffer.size() > _max_headers_size then
      InvalidChunk
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

              // expect CRLF
              if (_buffer(version_start + 8)? != '\r') and (_buffer(version_start + 9)? != '\n') then
                return InvalidVersion
              end
              // trim the buffer
              _buffer = _buffer.drop(version_start + 10)
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
    _send_request()

    _state = _ExpectBody
    _parse_body()

  fun ref _send_request() =>
    // send it down to the handler
    _handler._receive_start(
      // resetting the request here already, to pass down a trn
      _current_request = BuildableHTTPRequest.create(),
      _request_counter
    )

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
        _transfer_coding = Chunked
        _current_request.set_transfer_coding(Chunked)
      else
        return InvalidTransferCoding
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
    match _transfer_coding
    | Chunked =>
      _state = _ExpectChunkStart
      _parse_chunk_start()
    else
      if _expected_body_length > 0 then
        let available = _expected_body_length.min(_buffer.size())
        if available > 0 then
          let data = _buffer.trim(0, available)
          _buffer = _buffer.drop(data.size())
          _expected_body_length = _expected_body_length - data.size()
          _handler._receive_chunk(data, _request_counter)
        end
      end
      if _expected_body_length == 0 then

        _handler._receive_finished(_request_counter)
        reset()
        if _buffer.size() > 0 then
          _parse_request_line()
        end
      else
        NeedMore
      end
    end

  fun ref _parse_chunk_start(): ParseReturn =>
    match _buffer.find("\r\n", 0)
    | (true, let chunk_start_line_end: USize) =>
      let chunk_length_end =
        match _buffer.find(";", 0, chunk_start_line_end)
        | (true, let cle: USize) =>
          // we found some chunk extensions
          // don't care, YOLO
          cle
        else
          chunk_start_line_end
        end
      let chunk_length_str = _buffer.string(0, chunk_length_end)
      _buffer = _buffer.drop(chunk_start_line_end + 2)
      try
        match chunk_length_str.read_int[USize](0, 16)?
        | (0, 0) =>
          return InvalidChunk // chunk-size is not a hex number
        | (0, _) =>
          // last chunk
          _state = _ExpectChunkEnd
          _parse_chunk_end()
        | (let chunk_length: USize, _) =>
           Debug("chunk-length: " + chunk_length.string())
           // set valid chunk length
           _expected_body_length = chunk_length
          _state = _ExpectChunk
          _parse_chunk()
        end
      else
        return InvalidChunk // HEX chunk-size integer out of range
      end
    else
      _chunk_size_line_exhausted() // no CRLF found
    end

  fun ref _parse_chunk_end(): ParseReturn =>
    """
    handle possible trailer headers (by skipping them) and verify the finishing CRLF.
    """
    // search for CRLF ending chunked request
    match _buffer.find("\r\n", 0)
    | (true, 0) =>
      // immediate CRLF --> no trailers
      _buffer = _buffer.drop(2) // skip final CRLF
    | (true, let line_end: USize) =>
      // data before CRLF --> trailers
      match _buffer.find("\r\n\r\n", line_end)
      | (true, let trailer_end: USize) =>
        // skip trailers and final CRLF
        _buffer = _buffer.drop(trailer_end + 4)
      else
        return _chunk_trailers_exhausted() // trailer line too long or we need more
      end
    else
      return _chunk_trailers_exhausted() // trailer line too long or we need more
    end
    // we got a final CRLF for this chunked request
    _handler._receive_finished(_request_counter)
    reset()
    if _buffer.size() > 0 then
      _parse_request_line()
    end

  fun ref _parse_chunk(): ParseReturn =>
    """
    This will not be called for the last-chunk with length 0.
    See _parse_chunk_start.
    """
    if _expected_body_length > 0 then
      let available = _expected_body_length.min(_buffer.size())
      if available > 0 then
        let data = _buffer.trim(0, available)
        _buffer = _buffer.drop(data.size())
        _expected_body_length = _expected_body_length - data.size()
        //Debug("send chunk of size " + data.size().string())
        _handler._receive_chunk(data, _request_counter)
      end
    end
    if _expected_body_length == 0 then
      // end of chunk, expect CRLF, otherwise fail
      try
        if (_buffer(0)? == '\r') and (_buffer(1)? == '\n') then
          _buffer = _buffer.drop(2)
        else
          return InvalidChunk // no CRLF after chunk
        end
      else
        return NeedMore // not enough data for reading a CRLF
      end
      // expect next chunk
      _state = _ExpectChunkStart
      _parse_chunk_start()
    else
      NeedMore
    end

  fun ref reset(
    drop_data: Bool = false,
    reset_request: Bool = false)
  =>
    if reset_request then
      _current_request = BuildableHTTPRequest.create()
    end
    _request_counter = _request_counter + 1
    _state = _ExpectRequestLine
    _expected_body_length = 0
    _persistent_connection = true
    _transfer_coding = None
    if drop_data then
      _buffer = ByteArrays.create()
    end

// TODO: handle closed event


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


