use "collections/persistent"
use "itertools"

class val _ByteSeqsWrapper is ByteSeqIter
  var byteseqs: Vec[_ByteSeqs]

  new val create(bs: Vec[_ByteSeqs]) =>
    byteseqs = bs

  fun values(): Iterator[ByteSeq] ref^ =>
    Iter[_ByteSeqs](byteseqs.values())
      .flat_map[ByteSeq](
        {(bs) =>
          match bs
          | let b: ByteSeq =>
            object ref is Iterator[ByteSeq]
              var returned: Bool = false
              fun has_next(): Bool =>
                not returned
              fun next(): ByteSeq =>
                b
            end
          | let bsi: ByteSeqIter => bsi.values()
          end
        })

type _ByteSeqs is (ByteSeq | ByteSeqIter)
type _PendingResponse is (RequestId, Vec[_ByteSeqs])

class ref _PendingResponses
  // TODO: find out what is the most efficient way to
  //       keep and acucmulate a pending response
  //       from ByteSeq and ByteSeqIter
  embed _pending: Array[_PendingResponse] ref = _pending.create(0)

  new ref create() => None // forcing ref refcap

  fun ref add_pending(request_id: RequestId, response_data: Array[U8] val) =>
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
      _pending.insert(
        l,
        (
          request_id,
          Vec[_ByteSeqs].>push(response_data)
        )
      )?
    end

  fun ref add_pending_arrays(request_id: RequestId, data: ByteSeqIter) =>
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
      _pending.insert(l, (request_id, Vec[_ByteSeqs].>push(data)))?
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
          _pending(i)? = (entry._1, entry._2.push(data))
          return
        else
          r = i
        end
      end
    end


  fun ref pop(request_id: RequestId): ((RequestId, ByteSeqIter) | None) =>
    try
      let last_i = _pending.size() - 1
      let entry = _pending(last_i)?
      if entry._1 == request_id then
        (let id, let byteseqs) = _pending.delete(last_i)?
        (id, _ByteSeqsWrapper(byteseqs))
      end
    end

  fun has_pending(): Bool => size() > 0
  fun size(): USize => _pending.size()

  fun debug(): String =>
    let ps = _pending.size() * 3
    let s = recover trn String(ps) end
    for k in _pending.values() do
      s.>append(k._1.string()).append(", ")
    end
    consume s
