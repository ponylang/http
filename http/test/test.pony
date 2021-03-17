use "ponytest"
use ".."
use "regex"

actor Main is TestList
  new create(env: Env) => PonyTest(env, this)
  new make() => None

  fun tag tests(test: PonyTest) =>
    PrivateTests.tests(test)
    ClientErrorHandlingTests.tests(test)
    ClientTests.tests(test)

actor _TestStream is OutStream
  let _collector: Array[String] ref = Array[String]
  let _regex: Regex val

  new create(regex: Regex val) =>
    _regex = regex

  fun box to_string(bs: ByteSeq): String =>
    match bs
    | let s: String => s
    | let a: Array[U8] val => String.from_array(a)
    end

  be print(data: ByteSeq) =>
    _collector.push(to_string(data))
    _collector.push("\n")

  be write(data: ByteSeq) =>
    _collector.push(to_string(data))

  be printv(data: ByteSeqIter) =>
    for elem in data.values() do
      _collector.push(to_string(elem))
      _collector.push("\n")
    end

  be writev(data: ByteSeqIter) =>
    for elem in data.values() do
      _collector.push(to_string(elem))
    end

  be flush() => None

  be validate(h: TestHelper) =>
    let collected: String = "".join(_collector.values())
    h.assert_true(
      _regex.matches(collected).has_next(),
      collected + " did not match")
    h.complete(true)

