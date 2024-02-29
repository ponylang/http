use "pony_test"
use "net"

// Tests to verify that the ponylang/net_ssl #105 regression is fixed.
// https://github.com/ponylang/net_ssl/issues/105
// The expectation is that this test will pass if everything is good.
// Otherwise, the test will segfault when compiled in debug mode or it will
// hang if compled in release mode.
actor \nodoc\ _NetSSL105RegressionTests is TestList
  new make() =>
    None

  fun tag tests(test: PonyTest) =>
    test(_NetSSL105RegressionTest)

class \nodoc\ val _NetSSL105RegressionHandlerFactory is HandlerFactory
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h

  fun box apply(session: HTTPSession tag): HTTPHandler ref^ =>
    _NetSSL105RegressionHandler(_h)

class \nodoc\ val _NetSSL105RegressionHandler is HTTPHandler
  let _h: TestHelper

  new create(h: TestHelper) =>
     _h = h

  fun ref apply(payload: Payload val): None tag =>
    _h.complete(true)

class \nodoc\ iso _NetSSL105RegressionTest is UnitTest
  fun name(): String => "regression/net_ssl-105"

  fun apply(h: TestHelper) =>
    h.long_test(2_000_000_000)

    try
      let url = URL.build("https://example.com")?
      let auth = TCPConnectAuth(h.env.root)
      let client = HTTPClient(auth, _NetSSL105RegressionHandlerFactory(h))
      let payload = Payload.request("GET", url)
      client.apply(consume payload)?
    else
      h.fail("Unable to setup test")
    end
