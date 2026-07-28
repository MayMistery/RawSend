# RawSend External Plugin SDK

RawSend discovers plugins only from external plugin directories:

- `~/Library/Application Support/RawSend/Plugins`
- `/Library/Application Support/RawSend/Plugins`

The public application bundle never contains or searches for plugin payloads.

Each plugin is a directory ending in `.rawsendplugin` and containing a
`plugin.json`. Runtime kinds:

- `process`: an executable using framed JSON-RPC 2.0
- `python`: a Python entrypoint using framed JSON-RPC 2.0
- `native`: a trusted macOS dylib exposing the C ABI in
  `include/rawsend_plugin.h`

Go authors should normally build an executable and use `process`. A native Go
plugin must use `go build -buildmode=c-shared`; Go's `-buildmode=plugin` is not
compatible with a Swift host.

See `PROTOCOL.md`, `python/rawsend_plugin.py`, and `go/rawsendplugin/client.go`.
