# iterm2_ruby — Ruby Bindings for iTerm2's Native API

## Vision

A Ruby gem + CLI tool (`iterm2ctl`) that replaces all JXA/osascript iTerm2 automation with native WebSocket+Protobuf calls. Faster, more capable, no focus stealing.

## Why

- **20x faster** than osascript (persistent WebSocket vs process spawn per call)
- **No focus stealing** — API works in background
- **Screen reading** with cursor position (osascript can't do this)
- **Event streaming** — monitor focus, prompt state, output changes
- **Replaces 8+ JXA scripts** and osascript calls across multiple projects

---

## Prior Art (Already Built)

### StreamWeaver has a working WebSocket+Protobuf connection:
- `~/work/rstreamlit/stream_weaver/lib/stream_weaver/iterm_api.rb` — **Connection class with auth, WebSocket handshake, frame encoding/decoding, RPC method**
- `~/work/rstreamlit/stream_weaver/lib/stream_weaver/iterm_pb.rb` — Hand-written protobuf bindings (SplitPaneRequest, SetProfilePropertyRequest)
- `~/work/rstreamlit/stream_weaver/lib/stream_weaver/iterm.rb` — High-level wrapper with osascript fallback

**Start here. Lift the Connection class — it already works.**

### MCPretentious (Node.js reference):
- `github.com/oetiker/MCPretentious` — Node.js implementation of the same WebSocket+Protobuf protocol
- Useful for cross-referencing protobuf message field numbers

### iTerm2 source (protobuf definitions):
- `github.com/gnachman/iTerm2/blob/master/proto/api.proto` — The canonical proto file
- `github.com/gnachman/iTerm2/blob/master/api/library/python/iterm2/iterm2/` — Python API reference implementation

---

## Protocol Details

- **Transport:** WebSocket on `ws://localhost:1912` (TCP) or Unix socket at `~/Library/Application Support/iTerm2/private/socket`
- **Subprotocol:** `api.iterm2.com`
- **Encoding:** Protocol Buffers (binary WebSocket frames)
- **Auth:** Cookie+Key obtained via AppleScript: `tell application "iTerm2" to request cookie and key for app named "iterm2_ruby"`
- **Message pattern:** `ClientOriginatedMessage` (with `id` field) → `ServerOriginatedMessage` (matched by `id`)
- **Each request type is a field in `ClientOriginatedMessage`'s oneof, each response type is a field in `ServerOriginatedMessage`'s oneof**

---

## What Gets Replaced

| Current | File | Replacement |
|---------|------|-------------|
| `get-iterm-topology.js` | `~/jxa/get-iterm-topology.js` | `iterm2ctl list --json` |
| `iterm-raise3.js` | `~/jxa/iterm-raise3.js` | `iterm2ctl raise PATTERN` |
| `iterm-raise-by-path.js` | `~/jxa/iterm-raise-by-path.js` | `iterm2ctl raise --cwd PATH` |
| `show-tabs.js` | `~/jxa/show-tabs.js` | `iterm2ctl tabs` |
| `iterm-triage.js` | `~/jxa/iterm-triage.js` | `iterm2ctl list --triage` |
| StreamWeaver split/close | `stream_weaver/lib/.../iterm.rb` | `require 'iterm2'` |
| StreamWeaver navigate | `stream_weaver/lib/.../iterm_api.rb` | `ITerm2::Session#navigate(url)` |
| session_aggregator topology | `claude_code_history/lib/session_aggregator.rb` | `ITerm2::Client.topology` |
| session_monitor raise | `claude_code_history/lib/session_monitor.rb` | `ITerm2::Session#activate` |

---

## Gem Structure

```
iterm2_ruby/
├── lib/
│   ├── iterm2.rb                    # Entry point, convenience methods
│   ├── iterm2/
│   │   ├── connection.rb            # WebSocket+Protobuf (from StreamWeaver)
│   │   ├── client.rb                # High-level stateful client
│   │   ├── app.rb                   # App-level: list windows, activate, theme
│   │   ├── window.rb                # Window: create, close, tabs, frame, fullscreen
│   │   ├── tab.rb                   # Tab: select, close, sessions, index
│   │   ├── session.rb               # Session: send_text, read_screen, split, activate, profile
│   │   ├── screen.rb                # Screen contents parsing
│   │   ├── profile.rb               # Profile get/set
│   │   ├── focus.rb                 # Focus monitoring (event stream)
│   │   ├── notification.rb          # Subscribe to events
│   │   ├── topology.rb              # High-level: full window/tab/session map (replaces JXA)
│   │   └── proto/
│   │       └── api_pb.rb            # Generated or hand-written protobuf bindings
│   └── iterm2/version.rb
├── bin/
│   └── iterm2ctl                    # CLI tool
├── proto/
│   └── api.proto                    # Reference copy from iTerm2 source
├── spec/                            # RSpec tests
├── Gemfile
├── Rakefile
├── iterm2_ruby.gemspec
├── PLAN.md                          # This file
├── CLAUDE.md                        # Instructions for Claude Code
└── README.md
```

---

## Protobuf Messages to Implement

### Phase 1 — Core (replaces all JXA scripts)

These are the `ClientOriginatedMessage` oneof field numbers from api.proto:

```
# Listing & Discovery
ListSessionsRequest/Response           # Get all windows/tabs/sessions
  → field 14 in ClientOriginatedMessage
  → Returns window IDs, tab IDs, session IDs, titles

GetPropertyRequest/Response            # Get session properties (tty, cwd, title, pid)
  → field 33 in ClientOriginatedMessage
  → Identifiers: session_id, tab_id, window_id
  → Property names vary by scope

# Session Interaction
SendTextRequest/Response               # Send text to a session
  → field 5 in ClientOriginatedMessage
  → session field + text field + suppress_broadcast

GetScreenContentsRequest/Response      # Read screen (visible + scrollback)
  → Not a direct proto message; use GetBufferRequest
  → field 22 in ClientOriginatedMessage
  → Returns LineContents with text, colors, cursor

# Tab/Session Navigation
ActivateRequest/Response               # Activate session/tab/window
  → field 16 in ClientOriginatedMessage
  → Can activate session, tab, or window independently
  → select_tab, order_window_front options

# Already have from StreamWeaver:
SplitPaneRequest/Response              # field 109
SetProfilePropertyRequest/Response     # field 105
```

### Phase 2 — Window/Tab Management

```
CreateTabRequest/Response              # field 8
  → window_id, profile_name, command, custom_profile_properties

# Window creation is done via CreateTabRequest with no window_id
# (creates a new window automatically)

CloseRequest/Response                  # field 20
  → Can close sessions, tabs, or windows
  → force option to skip confirmation

SetVariableRequest/Response            # field 35
  → Set user-defined variables (session/tab/window/app scope)

GetVariableRequest/Response            # field 34
  → Get variables
```

### Phase 3 — Monitoring & Events

```
NotificationRequest/Response           # field 15
  → Subscribe to: session title change, screen update, prompt state,
    layout change, focus change, session terminated, new session

# Notification types (subscribe_to field):
  NOTIFY_ON_KEYSTROKE
  NOTIFY_ON_SCREEN_UPDATE
  NOTIFY_ON_PROMPT
  NOTIFY_ON_LOCATION_CHANGE
  NOTIFY_ON_CUSTOM_ESCAPE_SEQUENCE
  NOTIFY_ON_NEW_SESSION
  NOTIFY_ON_TERMINATE_SESSION
  NOTIFY_ON_LAYOUT_CHANGE
  NOTIFY_ON_FOCUS_CHANGE
  NOTIFY_ON_VARIABLE_CHANGE
```

### Phase 4 — Advanced

```
GetProfilePropertyRequest/Response     # field 107
SavedArrangementRequest/Response       # field 24
BroadcastDomainsRequest/Response       # field 36 (set broadcast domains)
InjectRequest/Response                 # field 19 (inject data as program output)
MenuItemRequest/Response               # field 38 (invoke menu items)
```

---

## CLI Design (`iterm2ctl`)

```bash
# === Topology (replaces get-iterm-topology.js) ===
iterm2ctl list                        # Pretty table of all windows/tabs/sessions
iterm2ctl list --json                 # JSON output (drop-in for JXA topology)
iterm2ctl list --window 2             # Filter to window
iterm2ctl list --with-cwd             # Include working directories (via GetProperty)
iterm2ctl list --with-pid             # Include PIDs

# === Session Interaction ===
iterm2ctl send TEXT [--session ID]    # Send text to session
iterm2ctl send TEXT [--tab N]         # Send text to tab N in current window
iterm2ctl read [--session ID]         # Read visible screen
iterm2ctl read --scrollback N         # Read N lines of scrollback
iterm2ctl is-at-prompt [--session ID] # Check if at shell prompt (needs shell integration)

# === Navigation (replaces iterm-raise3.js) ===
iterm2ctl raise PATTERN               # Raise first tab matching title pattern
iterm2ctl raise --session ID          # Raise by session ID
iterm2ctl raise --cwd PATH            # Raise by working directory
iterm2ctl raise --exact TITLE         # Exact match

# === Window/Tab/Pane Management ===
iterm2ctl create window [--profile P] [--command CMD]
iterm2ctl create tab [--profile P] [--command CMD] [--window W]
iterm2ctl split [--vertical|--horizontal] [--profile P] [--command CMD] [--url URL]
iterm2ctl close [--session ID] [--force]
iterm2ctl navigate SESSION_ID URL     # Change browser URL (profile property)

# === Profile ===
iterm2ctl profile [--session ID]      # Get profile properties
iterm2ctl set KEY VALUE [--session ID] # Set profile property

# === Monitoring (NEW — not possible with JXA) ===
iterm2ctl watch [--focus] [--prompt] [--screen] [--new-session]
iterm2ctl watch --session ID          # Watch specific session for changes

# === Variables ===
iterm2ctl var get NAME [--session ID]
iterm2ctl var set NAME VALUE [--session ID]
```

---

## Implementation Order

### Spike 1: Extract & Connect
1. Create gem skeleton (gemspec, Gemfile, lib structure)
2. Copy `connection.rb` from StreamWeaver (the WebSocket+auth+framing code)
3. Copy `iterm_pb.rb` from StreamWeaver (existing protobuf messages)
4. Verify connection works standalone: `ITerm2::Connection.new` → successful handshake
5. **Test:** `ruby -e "require 'iterm2'; puts ITerm2::Connection.new.class"`

### Spike 2: ListSessions (replaces topology JXA)
1. Add `ListSessionsRequest/Response` protobuf messages
2. Implement `ITerm2::Client.list_sessions` → returns windows/tabs/sessions
3. Build `iterm2ctl list` command
4. **Test:** Compare output with `get-iterm-topology.js` output

### Spike 3: SendText + ReadScreen
1. Add `SendTextRequest` protobuf
2. Add `GetBufferRequest` protobuf (screen reading)
3. Implement `ITerm2::Session#send_text(text)`
4. Implement `ITerm2::Session#read_screen(lines:)`
5. Build `iterm2ctl send` and `iterm2ctl read` commands
6. **Test:** Send a command, read the output back

### Spike 4: Activate (replaces raise JXA)
1. Add `ActivateRequest` protobuf
2. Implement `ITerm2::Session#activate(select_tab:, order_window_front:)`
3. Add `GetPropertyRequest` for getting session titles (for pattern matching)
4. Build `iterm2ctl raise` command with pattern matching
5. **Test:** `iterm2ctl raise "claude_code_history"` raises the right tab

### Spike 5: CLI Polish + Integration
1. Full CLI with all Phase 1 commands
2. JSON output mode for programmatic use
3. `--session`, `--tab`, `--window` targeting across all commands
4. Integration tests

### Spike 6: Integrate Back
1. **StreamWeaver:** Replace `iterm.rb`, `iterm_api.rb`, `iterm_pb.rb` with `require 'iterm2'`
2. **claude_code_history:** Replace `session_aggregator.rb`'s JXA call with `ITerm2::Client.topology`
3. **claude_code_history:** Replace `session_monitor.rb`'s osascript raise with `ITerm2::Session#activate`
4. Delete redundant `~/jxa/iterm-*.js` scripts

---

## Key Design Decisions

### Connection Lifecycle
- **Short-lived by default** — open, do work, close (like StreamWeaver does now)
- **Optional persistent mode** — for monitoring/watching (keep connection open)
- CLI uses short-lived; Ruby API supports both

### Error Handling
- `ITerm2::ConnectionError` — can't connect (iTerm2 not running, API disabled)
- `ITerm2::AuthError` — cookie/key rejected
- `ITerm2::RPCError` — request failed (session not found, etc.)
- `ITerm2::NotFoundError` — session/tab/window not found (subclass of RPCError)

### Protobuf Strategy
- **Hand-write the proto Ruby file** (like StreamWeaver does) rather than using protoc
- The proto file is stable and we only need a subset
- Avoids protoc dependency for gem users
- Reference `api.proto` from iTerm2 repo for field numbers

### Session Identification
- Support iTerm2 session IDs (GUIDs)
- Support `ITERM_SESSION_ID` env var format (`w0t0p0:GUID`)
- Support tab index (`--tab 3`)
- Support pattern matching on title (`--match PATTERN`)
- Support working directory (`--cwd PATH`)

### Topology Enrichment
The JXA topology script does extra work beyond what ListSessions provides:
- **Working directory** — via `lsof -p PID | grep cwd` (keep this, run after ListSessions)
- **Foreground process** — via `ps -t TTY` (keep this)
- **Claude session mapping** — via `~/.claude/session-iterm-mapping.json` (keep this)
- The gem provides raw API topology; enrichment happens in claude_code_history's aggregator

---

## Dependencies

```ruby
# iterm2_ruby.gemspec
spec.add_dependency 'google-protobuf', '~> 4.0'
# WebSocket is hand-rolled (already done in StreamWeaver) — no gem needed
# Auth uses osascript one-time call — no gem needed
```

---

## CLAUDE.md Notes

Create `~/work/iterm2_ruby/CLAUDE.md` with:
- Point to this PLAN.md
- Point to StreamWeaver source files to lift from
- Point to `~/jxa/get-iterm-topology.js` as the reference for topology output format
- Note: Use RVM (`source ~/.rvm/scripts/rvm`) for Ruby
- Note: Test against running iTerm2 instance
- Note: `api.proto` field numbers are critical — get them from the iTerm2 repo

---

## References

- iTerm2 Python API docs: https://iterm2.com/python-api/
- iTerm2 source (proto): https://github.com/gnachman/iTerm2/tree/master/proto
- iTerm2 Python connection.py: https://github.com/gnachman/iTerm2/blob/master/api/library/python/iterm2/iterm2/connection.py
- MCPretentious (Node.js impl): https://github.com/oetiker/MCPretentious
- StreamWeaver connection: `~/work/rstreamlit/stream_weaver/lib/stream_weaver/iterm_api.rb`
- StreamWeaver protobuf: `~/work/rstreamlit/stream_weaver/lib/stream_weaver/iterm_pb.rb`
- JXA topology: `~/jxa/get-iterm-topology.js`
- JXA raise: `~/jxa/iterm-raise3.js`
