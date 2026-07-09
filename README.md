<p align="center">
  <img src="AppIcon.iconset/icon_256x256.png" width="96" height="96" alt="RawSend app icon">
</p>

<h1 align="center">RawSend</h1>

<p align="center">
  <strong>A lightweight macOS workbench for raw HTTP replay.</strong>
</p>

<p align="center">
  Raw request in, precise replay out. No project setup, no heavyweight collections, no hidden mutation.
</p>

<p align="center">
  <a href="README.zh-CN.md">中文文档</a> ·
  <a href="https://github.com/MayMistery/RawSend/releases/latest">Latest release</a>
</p>

![RawSend main window](docs/images/rawsend-main.png)

## Why RawSend

Most HTTP tools are built around managed request collections. That is useful for long-lived API work, but it slows down security testing, incident debugging, and one-off reproduction work where the source of truth is already a raw request copied from a proxy, terminal, log, ticket, or report.

RawSend is deliberately smaller:

- **Raw-first**: edit the request exactly where you pasted it.
- **Local-first**: configuration, history, logs, and prompts stay on your machine.
- **Evidence-preserving**: sensitive fields can be struck and skipped without disappearing from the reproduction.

The result is a focused loop: paste a request, strike what should not be sent, replay it, search the response, compare HTTP/HTTPS, inspect redirects, and keep the whole exchange reproducible.

## Core Workflow

1. Paste a complete raw HTTP request.
2. Edit headers, URL parameters, and body in place.
3. Strike authentication or sensitive fields instead of deleting them.
4. Send over HTTP, HTTPS, or both.
5. Search, highlight, preview, and compare responses.
6. Reopen the full request/response pair from local history.

## Highlights

- **In-place raw editing**: operate directly on the original HTTP text. Headers and URL parameters do not move into a separate form that can drift from the raw request.
- **Sensitive-field strikeout**: manually strike headers and query parameters, or strike by configurable keywords. Struck fields stay visible but are skipped when sending and exporting cURL.
- **Full-text search without UI stalls**: request and response search use [FindFaster](https://github.com/finnvoor/FindFaster), with highlighted matches, next/previous navigation, and line/column positions.
- **Response readability**: status line, headers, JSON, and HTML are highlighted in the raw response view. HTML responses can also be opened in a built-in preview.
- **Focused metadata display**: important request headers are aggregated case-insensitively from a configurable list, so routing, trace, and request metadata are visible without cluttering the editor.
- **HTTP/HTTPS diffing**: replay the same raw request over both schemes and compare the results.
- **Redirects under control**: redirects are not followed by default. When a `3xx` response appears, RawSend exposes an explicit follow action near the send controls.
- **History with responses**: local history stores the request and the response pair, so a reproduced case can be reopened without resending.
- **Local Codex integration**: optional local `codex` CLI support can identify risky request/response fields and apply structured actions such as striking auth-related inputs.
- **Multilingual UI**: English by default, with Simplified Chinese and Spanish available in Settings.

## What It Is Not

RawSend is not a proxy, a team API workspace, or a replacement for browser DevTools. It is intentionally optimized for a narrow task: replaying and inspecting complete HTTP messages quickly, locally, and with minimal ceremony.

## Local Files

Runtime configuration is stored under:

```text
~/Library/Application Support/RawSend/
```

Logs are stored under:

```text
~/Library/Logs/RawSend/
```

Slow search, rendering, diff, and formatting operations over 200ms are written to:

```text
~/Library/Logs/RawSend/performance.jsonl
```

Send failures write copyable diagnostic records to:

```text
~/Library/Logs/RawSend/send-errors.jsonl
```

RawSend ships only generic product defaults. Organization-specific default headers, routing metadata, or User-Agent values belong in local configuration, not in the repository.

## Installation

Download the latest package from [GitHub Releases](https://github.com/MayMistery/RawSend/releases/latest).

Apple Silicon:

```bash
sudo installer -pkg RawSend-1.0.1-macos-arm64.pkg -target /
```

Intel Mac:

```bash
sudo installer -pkg RawSend-1.0.1-macos-x86_64.pkg -target /
```

The app is installed to:

```text
/Applications/RawSend.app
```

The release packages may be unsigned if no Developer ID certificate is available. If macOS blocks the package or app, remove quarantine explicitly:

```bash
sudo xattr -d com.apple.quarantine RawSend-1.0.1-macos-arm64.pkg
sudo installer -pkg RawSend-1.0.1-macos-arm64.pkg -target /
sudo xattr -dr com.apple.quarantine /Applications/RawSend.app
```

You can also Control-click the package or app in Finder and choose **Open**.

## Build From Source

Requirements:

- macOS 14 or newer
- Xcode Command Line Tools
- Swift 5.9 or newer

Common checks:

```bash
swift build
make check
make codex-check
```

Build and install locally:

```bash
make install
```

Build arm64 and x86_64 installer packages:

```bash
make release
```

Packages are written to:

```text
.build/packages/
```

For Developer ID signing:

```bash
make release \
  CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  PKG_SIGN_IDENTITY="Developer ID Installer: Your Name (TEAMID)"
```

Without those identities, RawSend uses ad-hoc app signing and unsigned installer packages.

## Codex Integration

RawSend can call the local `codex` CLI for structured analysis. It searches `PATH`, `/opt/homebrew/bin`, and `/usr/local/bin`. You can override the binary path with:

```bash
export RAWSEND_CODEX_PATH=/path/to/codex
```

Run the local end-to-end check:

```bash
make codex-check
```

The Settings page only asks for your user prompt. RawSend owns the system prompt and expects structured output for risk lines, suggested keywords, and executable strike actions.

## Privacy

RawSend is local-first. Configuration, history, diagnostics, and performance logs are stored on your Mac. Codex behavior depends on your local Codex CLI configuration. Struck headers and URL parameters remain visible for auditability, but RawSend omits them from actual sends and cURL export.

## License

RawSend is released under the [MIT License](LICENSE).
