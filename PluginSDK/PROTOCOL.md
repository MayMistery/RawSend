# RawSend Plugin Protocol v1

## Manifest

```json
{
  "manifest_version": 1,
  "id": "com.example.rawsend.plugin",
  "name": "Example",
  "version": "0.1.0",
  "host_api": {"major": 1, "minor": 0},
  "runtime": {
    "kind": "python",
    "entrypoint": "main.py",
    "interpreter": "python3"
  },
  "hooks": ["exchange.completed"],
  "permissions": ["response.read.raw", "findings.write"],
  "default_enabled": false,
  "settings": {}
}
```

Entrypoints must be relative and stay inside the plugin bundle. Native
manifests may map architecture names to entrypoints with
`runtime.architectures`.

## Process framing

stdin/stdout carry JSON-RPC 2.0 messages framed as:

```text
Content-Length: <UTF-8 byte count>\r\n
\r\n
<JSON document>
```

stdout is protocol-only. Diagnostics go to stderr. Maximum message size is
16 MiB.

The host starts with `initialize`. Hook methods currently are:

- `send.plan`
- `exchange.completed`
- `send.batch.completed`

Plugins return:

```json
{
  "variants": [],
  "annotations": [],
  "findings": [],
  "status_message": null
}
```

`send.plan` receives the effective request after variable resolution, default
headers, and struck-field filtering. `request.fields` contains stable
Query/Form/JSON locators. Plugins return declarative variants; RawSend performs
encoding, recomputes Content-Length, controls transport, and prevents recursive
active-plugin invocation.

`exchange.completed` receives the exact sent request plus raw and displayed
response forms. An annotation may specify an exact UTF-16 range, a value to
locate, or a fallback line.

`send.batch.completed` receives baseline and plugin-originated exchanges so an
active scanner can correlate asynchronous evidence.

## Host calls

Process plugins may issue JSON-RPC requests to the host while handling a hook.
v1 exposes:

- `host.info`
- `settings.get`
- `ui.status.set` with permission `ui.status.write`

Unknown calls fail closed. More Host APIs will be added with minor-version
negotiation. Plugins never receive Swift object pointers.

## Runtime safety

Process plugins are recommended. A native dylib shares RawSend's address space
and can crash or inspect the host. Native plugins are logically disabled but
not unloaded until process exit, because runtimes such as Go may retain
background threads.
