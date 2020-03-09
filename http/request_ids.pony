primitive RequestIds
  """
  Utilities for dealing with type RequestId
  in order to not assume anything about its actual implementation.
  """
  fun max_value(): RequestId =>
    USize.max_value()

  fun min(id1: RequestId, id2: RequestId): RequestId =>
    id1.min(id2)
  fun max(id1: RequestId, id2: RequestId): RequestId =>
    id1.max(id2)

  fun next(id: RequestId): RequestId =>
    id + 1

  fun gt(id1: RequestId, id2: RequestId): Bool =>
    id1 > id2

  fun gte(id1: RequestId, id2: RequestId): Bool =>
    id1 >= id2
