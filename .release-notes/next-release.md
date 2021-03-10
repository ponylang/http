## Use buffered write for Payload - improves perf by ~200x

Serialize the `Payload` using a `Writer` and then send a single message
to the `TCPConnection`.

This improves performance of `HTTPClient` by factor 200 on my system.  Before
this change, I got 17 req/s. After the change it's 3333 req/s.

