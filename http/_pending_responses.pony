use "valbytes"


type _PendingResponse is (RequestId, ByteArrays)

class ref _PendingResponses
  embed _pending: Array[_PendingResponse] ref = _pending.create(0)

  fun ref add_pending(request_id: RequestId, response_data: ByteArrays) =>
    // - insort by request_id, descending, so that when we pop, we don't need to
    //   move the other entries, only when we receive entries with higher request-id
    try
      var i = USize(0)
      var l = USize(0)
      var r = _pending.size()
      while l < r do
        i = (l + r).fld(2)
        let entry = _pending(i)?
        match entry._1.compare(request_id)
        | Greater =>
          l = i + 1
        | Equal =>
          // already there, ignore
          // TODO: we should error here
          return
        else
          r = i
        end
      end
      _pending.insert(l, (request_id, response_data))?
    end

  fun ref append_data(request_id: RequestId, data: ByteSeq val) =>
    try
      var i = USize(0)
      var l = USize(0)
      var r = _pending.size()
      while l < r do
        i = (l + r).fld(2)
        let entry = _pending(i)?
        match entry._1.compare(request_id)
        | Greater =>
          l = i + 1
        | Equal =>
          _pending(i)? = (entry._1, entry._2 + data)
          return
        else
          r = i
        end
      end
    end

  fun ref pop(request_id: RequestId): (_PendingResponse | None) =>
    try
      let last_i = _pending.size() - 1
      let entry = _pending(last_i)?
      if entry._1 == request_id then
        _pending.delete(last_i)?
      end
    end

  fun debug(): String =>
    let size = _pending.size() * 3
    let s = recover trn String(size) end
    for k in _pending.values() do
      s.>append(k._1.string()).append(", ")
    end
    consume s
