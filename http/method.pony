trait val HTTPMethod
  fun repr(): String val

primitive CONNECT is HTTPMethod
  fun repr(): String val => "CONNECT"

primitive GET is HTTPMethod
  fun repr(): String val => "GET"

primitive DELETE is HTTPMethod
  fun repr(): String => "DELETE"

primitive HEAD is HTTPMethod
  fun repr(): String => "HEAD"

primitive OPTIONS is HTTPMethod
  fun repr(): String => "OPTIONS"

primitive PATCH is HTTPMethod
  fun repr(): String => "PATCH"

primitive POST is HTTPMethod
  fun repr(): String => "POST"

primitive PUT is HTTPMethod
  fun repr(): String => "PUT"

primitive TRACE is HTTPMethod
  fun repr(): String => "TRACE"

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

