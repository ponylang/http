use "collections"
use "debug"

primitive HTTP11
primitive HTTP10
type HTTPVersion is (HTTP10 | HTTP11)


type Header is (String, String)

interface val HTTPRequest
  fun method(): HTTPMethod
  fun uri(): URL
  fun version(): HTTPVersion
  fun header(name: String): (String | None)
  fun headers(): Iterator[Header]
  fun transfer_coding(): (Chunked | None)
  fun content_length(): (USize | None)

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


class Headers
  // avoid reallocating new strings just because header names are case
  // insensitive.
  // handle insensitivity during add and get
  //  - TODO: find a way to do this with hashmap
  var _hl: Array[Header] = _hl.create(4)

  fun ref add(name: String, value: String) =>
    try
      match _find(name)
      | let i: USize =>
        let header = _hl(i)?
        match _compare(name, header._1)
        | Equal =>
          // append with comma
          let old_value = header._2
          let new_value = recover iso String(old_value.size() + 1 + value.size()) end
          new_value.>append(old_value)
                   .>append(",")
                   .>append(value)
          _hl(i)? = (header._1, consume new_value)
        else
          // either Less or Greater - we got the right insertion point
          _hl.insert(i, (name, value))?
        end
      | None =>
        // first node or last node, just push
        _hl.push((name, value))
      end
    else
      Debug("error Header.add")
    end

  fun get(name: String): (String | None) =>
    // binary search
    let s = _hl.size()
    if s == 0 then return None end

    var i = s / 2
    try
      while (i >= 0) and (i < s) do
        let header = _hl(i)?
        match _compare(name, header._1)
        | Less =>
          if i == 0 then return None end
          i = i / 2
        | Equal => return header._2
        | Greater =>
          if i == s then return None end
          let num_right = s - i
          i = i + (num_right / 2)
        end
      end
    end
    None

  fun ref clear() =>
    _hl.clear()

  fun values(): Iterator[Header] => _hl.values()

  fun _find(name: String): (USize | None) =>
    // binary search
    let s = _hl.size()
    if s == 0 then return None end

    var i = s / 2
    var last: (Compare, USize) = (Equal, 0)
    try
      while (i >= 0) and (i < s) do
        let header = _hl(i)?
        match _compare(name, header._1)
        | Less =>
          if (i == 0) or
            match last
            | (Greater, i - 1) => true // name was greater than prev node and is now less, no equal elem in list
            else
              false
            end
          then
            return i
          end
          last = (Less, i)
          i = i / 2
        | Equal   => return i
        | Greater =>
          let num_right = s - i
          if (num_right == 0) or
            match last
            | (Less, i + 1) => true // name was less than next node and is greater than this node, no equal elem in list
            else
              false
            end
          then
            return i + 1
          end
          last = (Greater, i)
          let right_half = if num_right == 1 then 1 else num_right / 2 end
          i = i + right_half
        end
      end
    end

  fun _compare(left: String, right: String): Compare =>
    """
    Less: left sorts lexicographically smaller than right
    Equal: same size, same content
    Greater: left sorts lexicographically higher than right

    _compare("A", "B") ==> Less
    _compare("AA", "A") ==> Greater
    _compare("A", "AA") ==> Less
    _compare("", "") ==> Equal
    """
    let ls = left.size()
    let rs = right.size()
    let min = ls.min(rs)

    var i = USize(0)
    while i < min do
      try
        let lc = _lower(left(i)?)
        let rc = _lower(right(i)?)
        if lc < rc then
          return Less
        elseif rc < lc then
          return Greater
        end
      else
        Less // should not happen, size checked
      end
      i = i + 1
    end
    // all characters equal up to min size
    if ls > min then
      // left side is longer, so considered greater
      Greater
    elseif rs > min then
      // right side is longer, so considered greater
      Less
    else
      // both sides equal size and content
      Equal
    end

  fun _lower(c: U8): U8 =>
    if (c >= 0x41) and (c <= 0x5A) then
      c + 0x20
    else
      c
    end



