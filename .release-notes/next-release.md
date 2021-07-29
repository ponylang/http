## Make Payload headers case insensitive

The HTTP spec says that headers are case-insensitve. That is, "Accept", "ACCEPT", "accept" etc are all the same thing. However, the http library was treating them as different headers.

All headers are now converted to lowercase for storage in a Payload and all lookups are done using the key converted to lowercase.

