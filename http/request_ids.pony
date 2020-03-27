

type RequestID is USize

primitive RequestIDs
  """
  Utilities for dealing with type RequestID
  in order to not assume anything about its actual implementation.
  """
  fun max_value(): RequestID =>
    USize.max_value()

  fun min(id1: RequestID, id2: RequestID): RequestID =>
    id1.min(id2)
  fun max(id1: RequestID, id2: RequestID): RequestID =>
    id1.max(id2)

  fun next(id: RequestID): RequestID =>
    id + 1

  fun gt(id1: RequestID, id2: RequestID): Bool =>
    id1 > id2

  fun gte(id1: RequestID, id2: RequestID): Bool =>
    id1 >= id2
