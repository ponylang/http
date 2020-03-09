use "collections"

type Header is (String, String)
  """
  Defining a HTTP header as Tuple Strings for name and value.
  """

class Headers
  """
  Collection for headers
  based on a sorted array we use bisect to insert and get values.
  We compare the strings case-insensitive when sorting, inserting and getting headers.

  We want to use the bytes we get to build the headers as is without changing them, in order to avoid allocation.

  This isn't using a hashmap because getting the hash in a case-insensitive manner
  would require to iterate over single bytes, which isn't as fast as it could be.
  Also the amount of headers in a request is usually small, so the penalty of doing
  a binary search isn't as bad.

  Getting a header is case insensitive, so you don't need to care about header name casing
  when asking for a header.

  ### Usage

  ```pony
  let headers = Headers
  header.set("Connection", "Close") // setting a header, possibly overwriting previous values
  header.add("Multiple", "1")       // adding a header, concatenating previous and this value with a comma.
  header.add("Multiple", "2")

  // getting a header is case-insensitive
  match header.get("cOnNeCTiOn")
  | let value: String => // do something with value
  else
    // not found
  end

  // iterating over headers
  for (name, value) in headers.values() do
    env.out.print(name + ": " + value)
  end

  // remove all headers from this structure
  headers.clear()
  ```

  """
  // avoid reallocating new strings just because header names are case
  // insensitive.
  // handle insensitivity during add and get
  //  - TODO: find a way to do this with hashmap
  var _hl: Array[Header]

  new ref create() =>
    _hl = _hl.create(4)

  new ref from_map(headers: Map[String, String]) =>
    _hl = _hl.create(headers.size())
    for header in headers.pairs() do
      add(header._1, header._2)
    end

  new ref from_seq(headers: ReadSeq[Header]) =>
    _hl = _hl.create(headers.size())
    for header in headers.values() do
      add(header._1, header._2)
    end

  new ref from_iter(headers: Iterator[Header], size: USize = 4) =>
    _hl = _hl.create(size)
    for header in headers do
      add(header._1, header._2)
    end

  fun ref set(name: String, value: String) =>
    """
    if a header with name already exists, its value will be overriden with this value.
    """
    // binary search
    try
      var i = USize(0)
      var l = USize(0)
      var r = _hl.size()
      while l < r do
        i = (l + r).fld(2)
        let header = _hl(i)?
        match _compare(header._1, name)
        | Less =>
          l = i + 1
        | Equal =>
          _hl(i)? = (name, value)
          return
        else
          r = i
        end
      end
      _hl.insert(l, (name, value))?
    end

  fun ref add(name: String, value: String) =>
    """
    If a header with this name already exists, value will be
    appended after a separating comma.
    """
    // binary search
    try
      var i = USize(0)
      var l = USize(0)
      var r = _hl.size()
      while l < r do
        i = (l + r).fld(2)
        let header = _hl(i)?
        match _compare(header._1, name)
        | Less =>
          l = i + 1
        | Equal =>
          let old_value = header._2
          let new_value = recover iso String(old_value.size() + 1 + value.size()) end
          new_value.>append(old_value)
                   .>append(",")
                   .>append(value)
          _hl(i)? = (header._1, consume new_value)
          return
        else
          r = i
        end
      end
      _hl.insert(l, (name, value))?
    end

  fun get(name: String): (String | None) =>
    // binary search
    var l = USize(0)
    var r = _hl.size()
    var i = USize(0)
    try
      while l < r do
        i = (l + r).fld(2)
        let header = _hl(i)?
        match _compare(header._1, name)
        | Less =>
          l = i + 1
        | Equal =>
          return header._2
        | Greater =>
          r = i
        end
      end
    end
    None

  fun ref clear() =>
    _hl.clear()

  fun values(): Iterator[Header] => _hl.values()

  fun byte_size(): USize =>
    """
    size of the given headers including header-separator and crlf.
    """
    var s = USize(0)
    for (k, v) in _hl.values() do
      s + k.size() + 2 + v.size() + 2
    end
    s

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



