# CLAUDE.md — iterm2_ruby

## What This Is

Ruby gem + CLI (`iterm2ctl`) for controlling iTerm2 via its native WebSocket+Protobuf API. Replaces all JXA/osascript automation.

## Read First

- **`docs/api.md`** — Complete API reference (all methods, signatures, return shapes)
- **`PLAN.md`** — Full architecture, implementation order, protobuf messages, CLI design

## Key Source Files to Reference

### Lift from StreamWeaver (working WebSocket+Protobuf code):
- `~/work/rstreamlit/stream_weaver/lib/stream_weaver/iterm_api.rb` — Connection class (auth, handshake, framing, RPC)
- `~/work/rstreamlit/stream_weaver/lib/stream_weaver/iterm_pb.rb` — Protobuf bindings (SplitPane, SetProfileProperty)
- `~/work/rstreamlit/stream_weaver/lib/stream_weaver/iterm.rb` — High-level wrapper

### JXA scripts being replaced (reference for expected behavior):
- `~/jxa/get-iterm-topology.js` — Full topology output format (windows → tabs → sessions with tty, cwd, pid)
- `~/jxa/iterm-raise3.js` — Tab raise with pattern matching

### iTerm2 protobuf definitions:
- `https://github.com/gnachman/iTerm2/blob/master/proto/api.proto` — Canonical proto file
- Field numbers in `ClientOriginatedMessage` oneof are critical — check the proto file

### Integration targets (will consume this gem later):
- `~/work/claude_code_history/lib/session_aggregator.rb` — Uses JXA topology
- `~/work/claude_code_history/lib/session_monitor.rb` — Uses osascript for raise

## Implementation Notes

- **Ruby version:** 3.3.5 (RVM: `source ~/.rvm/scripts/rvm`)
- **Protobuf strategy:** Hand-write proto Ruby bindings using `google-protobuf` gem DSL (like StreamWeaver does). Don't use protoc.
- **WebSocket:** Hand-rolled (StreamWeaver already has frame encode/decode). No websocket gem needed.
- **Auth:** One-time osascript call to get cookie+key, then pure WebSocket
- **Test against running iTerm2** — this is a local integration, no mocking needed for spikes
- **Protocol:** `ws://localhost:1912`, subprotocol `api.iterm2.com`

## Implementation Order

1. Gem skeleton + extract Connection from StreamWeaver
2. ListSessions (replaces topology JXA)
3. SendText + ReadScreen
4. Activate (replaces raise JXA)
5. CLI polish
6. Integrate back into StreamWeaver + claude_code_history

## Commands

```bash
# Run tests
bundle exec rspec

# Test connection
ruby -e "require 'iterm2'; c = ITerm2::Connection.new; puts 'connected!'; c.close"

# CLI
bundle exec iterm2ctl list
bundle exec iterm2ctl send "echo hello" --tab 1
bundle exec iterm2ctl raise "claude"
```
