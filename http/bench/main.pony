use ".."
use "buffered"
use "ponybench"
use "debug"

actor Main is BenchmarkList
  new create(env: Env) =>
    PonyBench(env, this)

  fun tag benchmarks(bench: PonyBench) =>
    PrivateBenchmarks.benchmarks(bench)

