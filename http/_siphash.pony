primitive SipHash24

  fun _sipround64(v0: U64, v1: U64, v2: U64, v3: U64): (U64, U64, U64, U64) =>
    var t0 = v0 + v1
    var t1 = v1.rotl(13)
    t1 = t1 xor t0
    t0 = t0.rotl(32)
    var t2 = v2 + v3
    var t3 = v3.rotl(16)
    t3 = t3 xor t2
    t0 = t0 + t3
    t3 = t3.rotl(21)
    t3 = t3 xor t0
    t2 = t2 + t1
    t1 = t1.rotl(17)
    t1 = t1 xor t2
    t2 = t2.rotl(32)


    (t0, t1, t2, t3)

  fun apply[T: ReadSeq[U8] #read](data: T): U64 =>
    let k0 = U64(0x8A109C6B22D309FE)
    let k1 = U64(0x9F923FCCB57235E1)

    let size = data.size()
    var b: U64  = (size << USize(56)).u64()

    var v0 = k0 xor 0x736f6d6570736575
    var v1 = k1 xor 0x646f72616e646f6d
    var v2 = k0 xor 0x6c7967656e657261
    var v3 = k1 xor 0x7465646279746573

    let endi: USize = size - (size % 8)

    try
      var i = USize(0)
      while i < endi do
        let m: U64 =
          iftype T <: Array[U8] then
            data.read_u64(i)?
          elseif T <: String val then
            data.array().read_u64(i)?
          else
            (data(i)?.u64()) or
            (data(i + 1)?.u64() << 8) or
            (data(i + 2)?.u64() << 16) or
            (data(i + 3)?.u64() << 24) or
            (data(i + 4)?.u64() << 32) or
            (data(i + 5)?.u64() << 40) or
            (data(i + 6)?.u64() << 48) or
            (data(i + 7)?.u64() << 56)
          end
        v3 = v3 xor m
        (v0, v1, v2, v3) = _sipround64(v0, v1, v2, v3)
        (v0, v1, v2, v3) = _sipround64(v0, v1, v2, v3)
        v0 = v0 xor m

        i = i + 8
      end

      // bad emulation of a C switch statement with  fallthrough
      let rest = size and 7
      if rest >= 1 then
        if rest >= 2 then
          if rest >= 3 then
            if rest >= 4 then
              if rest >= 5 then
                if rest >= 6 then
                  if rest == 7 then
                    b = b or (data(endi + 6)?.u64() << 48)
                  end
                  b = b or (data(endi + 5)?.u64() << 40)
                end
                b = b or (data(endi + 4)?.u64() << 32)
              end
              b = b or (data(endi + 3)?.u64() << 24)
            end
            b = b or (data(endi + 2)?.u64() << 16)
          end
          b = b or (data(endi + 1)?.u64() << 8)
        end
        b = b or data(endi)?.u64()
      end

      v3 = v3 xor b
      (v0, v1, v2, v3) = _sipround64(v0, v1, v2, v3)
      (v0, v1, v2, v3) = _sipround64(v0, v1, v2, v3)
      v0 = v0 xor b
      v2 = v2 xor 0xFF
      (v0, v1, v2, v3) = _sipround64(v0, v1, v2, v3)
      (v0, v1, v2, v3) = _sipround64(v0, v1, v2, v3)
      (v0, v1, v2, v3) = _sipround64(v0, v1, v2, v3)
      (v0, v1, v2, v3) = _sipround64(v0, v1, v2, v3)
      v0 xor v1 xor v2 xor v3
    else
      // should never happen, but we can't prove it to the compiler...
      -1
    end


primitive HalfSipHash24
  fun apply(data: ReadSeq[U8]): U32 => 1
