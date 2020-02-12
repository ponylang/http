primitive RequestIds
  fun max_value(): RequestId => USize.max_value()

  fun min(id1: RequestId, id2: RequestId): RequestId =>
    id1.min(id2)
  fun max(id1: RequestId, id2: RequestId): RequestId =>
    id1.max(id2)

  fun next(id: RequestId): RequestId =>
    id + 1

  fun gt(id1: RequestId, id2: RequestId): Bool =>
    id1 > id2
