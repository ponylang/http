## Fix bug triggered by OpenSSL 3.2

Making HTTPClient calls over SSL when using OpenSSL 3.2.0 would encounter a nasty bug. When executed in a program compiled in release mode, the program would hang. When executed in a program compiled in debug mode, the program would segfault due to infinite recursion.

