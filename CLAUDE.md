# CLAUDE.md — iterm2_ruby

## What This Is

Ruby gem + CLI (`iterm2ctl`) for controlling iTerm2 via its native WebSocket+Protobuf API instead of osascript/JXA.

## Read First

- **`docs/architecture.md`** — connection/auth/dispatch design
- **`docs/api.md`** — complete API reference (all methods, signatures, return shapes)
- **`docs/cli.md`** — full `iterm2ctl` command reference

## Layout

```
lib/iterm2.rb                    # Entry point, ITerm2.connect, one-shot methods, error classes
lib/iterm2/version.rb            # VERSION constant
lib/iterm2/connection.rb         # WebSocket + auth + sync/dispatch RPC
lib/iterm2/client.rb             # High-level API (all public methods)
lib/iterm2/window.rb             # ITerm2::Window
lib/iterm2/tab.rb                # ITerm2::Tab
lib/iterm2/session.rb            # ITerm2::Session
lib/iterm2/proto/api_pb.rb       # protoc-generated bindings from proto/api.proto
bin/iterm2ctl                    # CLI entry point
```

## Protocol Notes

- Transport: WebSocket on `ws://localhost:1912` (TCP) or the Unix socket iTerm2 exposes; subprotocol `api.iterm2.com`
- Encoding: Protocol Buffers, hand-generated into `lib/iterm2/proto/api_pb.rb` from `proto/api.proto` (don't hand-write bindings; regenerate with `protoc --ruby_out` if the proto changes)
- Auth: one-time osascript call gets a cookie+key, then it's pure WebSocket
- Field numbers in `ClientOriginatedMessage`'s oneof matter — cross-check `proto/api.proto` when adding a request type

## Testing

- `bundle exec rspec` runs the default suite (CLI subprocess specs only — no live iTerm2 required, safe for CI)
- Specs tagged `:live` (client/connection behavior) are excluded by default; run them with a real iTerm2 running:
  ```bash
  ITERM2_LIVE_TESTS=1 bundle exec rspec
  ```
- This project tests against a real running iTerm2 rather than mocking the WebSocket — mocking the protocol would just test the mock

## Commands

```bash
bundle exec rspec                              # run tests
bundle exec iterm2ctl list                     # exercise the CLI
gem build iterm2_ruby.gemspec                  # verify the gem still packages cleanly
```
