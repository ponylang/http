trait val HTTPMethod is (Equatable[HTTPMethod] & Stringable)
  """
  HTTP method

  See: https://tools.ietf.org/html/rfc2616#section-5.1.1
  """
  fun repr(): String val
  fun string(): String iso^
  fun eq(o: HTTPMethod): Bool

primitive CONNECT is HTTPMethod
  fun repr(): String val => "CONNECT"
  fun string(): String iso^ => repr().clone()
  fun eq(o: HTTPMethod): Bool => o is this

primitive GET is HTTPMethod
  fun repr(): String val => "GET"
  fun string(): String iso^ => repr().clone()
  fun eq(o: HTTPMethod): Bool => o is this

primitive DELETE is HTTPMethod
  fun repr(): String => "DELETE"
  fun string(): String iso^ => repr().clone()
  fun eq(o: HTTPMethod): Bool => o is this

primitive HEAD is HTTPMethod
  fun repr(): String => "HEAD"
  fun string(): String iso^ => repr().clone()
  fun eq(o: HTTPMethod): Bool => o is this

primitive OPTIONS is HTTPMethod
  fun repr(): String => "OPTIONS"
  fun string(): String iso^ => repr().clone()
  fun eq(o: HTTPMethod): Bool => o is this

primitive PATCH is HTTPMethod
  fun repr(): String => "PATCH"
  fun string(): String iso^ => repr().clone()
  fun eq(o: HTTPMethod): Bool => o is this

primitive POST is HTTPMethod
  fun repr(): String => "POST"
  fun string(): String iso^ => repr().clone()
  fun eq(o: HTTPMethod): Bool => o is this

primitive PUT is HTTPMethod
  fun repr(): String => "PUT"
  fun string(): String iso^ => repr().clone()
  fun eq(o: HTTPMethod): Bool => o is this

primitive TRACE is HTTPMethod
  fun repr(): String => "TRACE"
  fun string(): String iso^ => repr().clone()
  fun eq(o: HTTPMethod): Bool => o is this

primitive HTTPMethods
  fun parse(maybe_method: ReadSeq[U8]): (HTTPMethod | None) =>
    if _Equality.readseqs(maybe_method, GET.repr()) then GET
    elseif _Equality.readseqs(maybe_method, PUT.repr()) then PUT
    elseif _Equality.readseqs(maybe_method, PATCH.repr()) then PUT
    elseif _Equality.readseqs(maybe_method, POST.repr()) then POST
    elseif _Equality.readseqs(maybe_method, HEAD.repr()) then HEAD
    elseif _Equality.readseqs(maybe_method, DELETE.repr()) then DELETE
    elseif _Equality.readseqs(maybe_method, CONNECT.repr()) then CONNECT
    elseif _Equality.readseqs(maybe_method, OPTIONS.repr()) then OPTIONS
    elseif _Equality.readseqs(maybe_method, TRACE.repr()) then TRACE
    end


primitive _Equality
  fun readseqs(left: ReadSeq[U8], right: ReadSeq[U8]): Bool =>
    let size = left.size()
    if size != right.size() then
      false
    else
      var ri: USize = 0
      try
        // TODO: vectorize if possible
        while ri < size do
          if left(ri)? != right(ri)? then
            return false
          end
          ri = ri + 1
        end
        true
      else
        false
      end
    end

