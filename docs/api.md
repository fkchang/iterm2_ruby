# API Reference

Complete reference for the `iterm2_ruby` Ruby API.

## Connection

### `ITerm2.connect(app_name: "iterm2_ruby") { |client| ... }` -> Client

Opens a connection, yields the client, auto-closes when the block returns. Without a block, returns an open client (you must call `close` yourself).

```ruby
# Block form (preferred)
ITerm2.connect do |client|
  puts client.topology.size
end

# Manual form
client = ITerm2.connect
client.topology
client.close
```

### `ITerm2::Client.new(app_name: "iterm2_ruby")` -> Client

Creates a persistent client with an open connection. Equivalent to `ITerm2.connect` without a block.

### `client.close` -> nil

Closes the connection. Unsubscribes all notification listeners and stops the dispatch thread if running.

---

## Topology

### `client.list_sessions` -> ListSessionsResponse

Returns the raw protobuf `ListSessionsResponse` from iTerm2. Includes the full window/tab/session tree with split pane hierarchy.

### `client.topology` -> Array\<Hash\>

Flattened session list. Each hash:

```ruby
{
  window_id: String,  # e.g. "pty-0B3C..."
  tab_id:    String,  # e.g. "4A7D..."
  session_id: String, # e.g. "E8F2..."
  title:     String   # e.g. "~/work/myproject"
}
```

### `client.topology_enriched` -> Array\<Hash\>

Same as `topology` but with additional keys from `session_info`:

```ruby
{
  window_id:, tab_id:, session_id:, title:,
  tty:  String,  # e.g. "/dev/ttys042"
  pid:  Integer, # e.g. 12345
  cwd:  String,  # e.g. "/Users/you/work/project"
  name: String,  # session name
  job:  String   # e.g. "ruby"
}
```

**Note:** Makes one `get_variables` RPC per session. For many sessions, this can be slow.

### `client.session_info(session_id)` -> Hash

```ruby
{
  tty:  String | nil,   # "/dev/ttys042"
  pid:  Integer | nil,  # 12345
  cwd:  String | nil,   # "/Users/you/work/project"
  name: String | nil,   # session name
  job:  String | nil    # foreground process name
}
```

### `client.topology_for_aggregator(mapping_file: nil)` -> Hash

JXA-compatible topology for `claude_code_history`'s SessionAggregator. Maps iTerm session GUIDs to Claude session IDs via `~/.claude/session-iterm-mapping.json`.

Returns nested `{ "windows" => [{ "tabs" => [...] }] }` matching the format from `get-iterm-topology.js`.

---

## Session Interaction

### `client.send_text(session_id, text, suppress_broadcast: false)` -> true | false

Sends text to a session as if typed. Returns `true` on success.

- **session_id** (String) -- target session identifier
- **text** (String) -- text to send
- **suppress_broadcast** (Boolean) -- if `true`, don't broadcast to other sessions in broadcast group

**Gotcha:** Does NOT auto-append `\n`. To execute a command, include `"\n"`:

```ruby
client.send_text(sid, "ls -la\n")
```

### `client.read_screen(session_id, trailing_lines: nil)` -> Hash

Reads visible screen contents (or scrollback).

- **session_id** (String) -- target session
- **trailing_lines** (Integer | nil) -- number of trailing scrollback lines. `nil` = visible screen only.

Returns:

```ruby
{
  lines:  Array<String>,         # each line of text
  cursor: { x: Integer, y: Integer } | nil
}
```

**Raises:** `RPCError` if the buffer request fails.

### `client.inject(session_id, data)` -> true | false

Injects data into a session as if it came from the running process (not as user input). The data appears in the terminal output without being sent to the shell.

- **session_id** (String) -- target session
- **data** (String) -- raw bytes to inject (will be encoded as BINARY)

---

## Window Management

### `client.activate_session(session_id, select_tab: true, order_window_front: true)` -> true | false

Raises and focuses a session. Selects its tab and brings the window to front by default.

### `client.activate_tab(tab_id, order_window_front: true)` -> true | false

Raises a tab by ID.

### `client.activate_window(window_id)` -> true | false

Raises a window by ID. Always orders window to front.

### `client.raise_by_title(pattern)` -> true | false

Finds the first session whose title matches `pattern` (case-insensitive regex) and activates it.

**Raises:** `NotFoundError` if no session matches.

```ruby
client.raise_by_title("my-project")  # substring match
client.raise_by_title("^claude")     # regex anchor
```

### `client.raise_by_cwd(pattern)` -> true | false

Finds the first session whose working directory matches `pattern` (case-insensitive regex) and activates it.

**Raises:** `NotFoundError` if no session matches.

**Note:** Calls `topology_enriched` internally, so it makes one `get_variables` RPC per session.

### `client.create_tab(window_id: nil, profile_name: nil)` -> Hash

Creates a new tab (or window if `window_id` is nil and iTerm2 decides to).

- **window_id** (String | nil) -- create tab in this window, or new window if nil
- **profile_name** (String | nil) -- use this profile

Returns:

```ruby
{ window_id: String, tab_id: String, session_id: String }
```

**Raises:** `RPCError` on failure.

### `client.split_pane(session_id, vertical: true, profile_name: nil, profile_customizations: {})` -> String

Splits a pane. Returns the new session ID.

- **session_id** (String) -- session to split
- **vertical** (Boolean) -- `true` for vertical split, `false` for horizontal
- **profile_name** (String | nil) -- profile for the new pane
- **profile_customizations** (Hash) -- profile property overrides (key => value)

**Raises:** `RPCError` on failure.

### `client.close_session(session_id, force: false)` -> true | false

Closes a session. With `force: true`, skips the confirmation prompt.

**Gotcha:** iTerm2 does NOT fire `NOTIFY_ON_TERMINATE_SESSION` for API-initiated closes.

### `client.close_tab(tab_id, force: false)` -> true | false

Closes an entire tab. With `force: true`, skips the confirmation prompt.

---

## Profile & Properties

### `client.set_profile_property(session_id, key, value)` -> true | false

Sets a profile property on a session. The value is JSON-encoded automatically.

```ruby
client.set_profile_property(sid, "Background Color", { "Red Component" => 0.1, ... })
client.set_profile_property(sid, "Name", "My Custom Profile")
```

### `client.get_profile_property(session_id, *keys)` -> Hash

Gets profile properties. Returns a hash of `{ key => value }`. With no keys, returns all properties.

```ruby
client.get_profile_property(sid, "Name", "Guid")
# => {"Name" => "Default", "Guid" => "ABC-123"}
```

**Raises:** `RPCError` on failure.

### `client.list_profiles(properties: nil, guids: nil)` -> Array\<Hash\>

Lists all iTerm2 profiles. Each profile is a hash of `{ key => value }`.

- **properties** (Array\<String\> | nil) -- only include these property keys. `nil` = all.
- **guids** (Array\<String\> | nil) -- only include profiles with these GUIDs

```ruby
client.list_profiles(properties: ["Name", "Guid"])
# => [{"Name" => "Default", "Guid" => "..."}, ...]
```

### `client.get_property(name, session_id: nil, window_id: nil)` -> Object

Gets a named property from a session or window. Returns the JSON-decoded value.

```ruby
client.get_property("columns", session_id: sid)  # => 120
client.get_property("frame", window_id: wid)     # => {"origin" => {...}, "size" => {...}}
```

**Raises:** `RPCError` on failure.

### `client.get_variables(*names, session_id: nil, tab_id: nil, window_id: nil, app: nil)` -> varies

Gets variables from a scope (session, tab, window, or app).

- With `"*"` -- returns Hash of all variables
- With one name -- returns the value directly
- With multiple names -- returns Hash of `{ name => value }`

Scope is required -- pass exactly one of `session_id:`, `tab_id:`, `window_id:`, or `app: true`.

```ruby
client.get_variables("path", session_id: sid)        # => "/Users/you/work"
client.get_variables("*", app: true)                  # => {"effectiveTheme" => "dark", ...}
client.get_variables("tty", "pid", session_id: sid)  # => {"tty" => "/dev/ttys042", "pid" => 123}
```

**Raises:** `RPCError` on failure, `ArgumentError` if no scope given.

### `client.set_variables(vars, session_id: nil, tab_id: nil, window_id: nil, app: nil)` -> true | false

Sets user-defined variables. Variable names must begin with `"user."`.

```ruby
client.set_variables({ "user.project" => "myapp" }, session_id: sid)
```

### `client.get_variable(name, **scope)` -> Object

Convenience wrapper for `get_variables` with a single name.

### `client.focus` -> Hash

Returns the current focus state:

```ruby
{
  active_session: String | nil,  # currently focused session ID
  active_tab:     String | nil,  # currently selected tab ID
  active_window:  String | nil,  # key window ID
  app_active:     Boolean        # whether iTerm2 is the frontmost app
}
```

### `client.get_prompt(session_id)` -> Hash

Gets the shell prompt state for a session (requires shell integration).

```ruby
{
  state:             Symbol,        # :editing, :running, :at_prompt, :unavailable
  command:           String | nil,  # last/current command
  working_directory: String | nil,  # shell's cwd
  exit_status:       Integer | nil  # last command's exit code
}
```

**Gotcha:** Returns `{ state: :unavailable, ... }` for sessions without iTerm2 shell integration installed.

---

## Notifications

Notifications use a background dispatch loop. The first call to any `subscribe` or `on_*` method starts the dispatch thread automatically.

### Lifecycle

1. Call `on_*` or `subscribe` -- dispatch thread starts
2. Events arrive and fire callbacks on the dispatch thread
3. Call `client.close` -- unsubscribes all, stops dispatch thread

### `client.subscribe(notification_type, session_id: nil, &callback)` -> token

Low-level subscribe. `notification_type` is a symbol like `:NOTIFY_ON_FOCUS_CHANGE`. Returns a token for `unsubscribe`.

- **session_id** (String | nil) -- scope to a specific session, or `nil` for global

**Raises:** `SubscriptionError` on failure.

### `client.unsubscribe(token)` -> nil

Unsubscribes a previously created subscription.

### `client.on_focus_change { |event| }` -> token

Fires when focus changes (session, tab, window, or app activation).

```ruby
# event shape:
{
  type:          :focus,
  app_active:    Boolean,        # optional
  window:        String,         # optional, window ID
  window_status: Symbol,         # optional, :terminal_window_became_key, etc.
  selected_tab:  String,         # optional, tab ID
  session:       String          # optional, session ID
}
```

### `client.on_new_session { |event| }` -> token

Fires when a new session is created.

```ruby
{ type: :new_session, session_id: String }
```

### `client.on_session_terminated { |event| }` -> token

Fires when a session terminates.

```ruby
{ type: :session_terminated, session_id: String }
```

**Gotcha:** Does NOT fire for sessions closed via the API (`close_session`/`close_tab`). Only fires for user-initiated closes or process exits.

### `client.on_prompt_change(session_id) { |event| }` -> token

Fires when prompt state changes in a session (requires shell integration).

```ruby
# event shapes (varies by state):
{ type: :prompt, session: String, state: :prompt, unique_prompt_id: String }
{ type: :prompt, session: String, state: :command_start, command: String }
{ type: :prompt, session: String, state: :command_end, exit_status: Integer }
```

### `client.on_screen_update(session_id) { |event| }` -> token

Fires when screen content changes in a session.

```ruby
{ type: :screen_update, session: String }
```

### `client.on_layout_change { |event| }` -> token

Fires when window/tab layout changes (splits, tab reorder, etc.).

```ruby
{ type: :layout_change }
```

**Gotcha:** iTerm2 sends duplicate notification events (each event arrives twice). This is server-side behavior, not a bug.

---

## One-Shot Module Methods

These class methods on `ITerm2` open a connection, run the command, and close. Convenient for single operations but inefficient for multiple calls (each opens a new connection).

| One-shot method | Equivalent |
|---|---|
| `ITerm2.topology` | `client.topology` |
| `ITerm2.topology_enriched` | `client.topology_enriched` |
| `ITerm2.list_sessions` | `client.list_sessions` |
| `ITerm2.session_info(sid)` | `client.session_info(sid)` |
| `ITerm2.send_text(sid, text)` | `client.send_text(sid, text)` |
| `ITerm2.read_screen(sid)` | `client.read_screen(sid)` |
| `ITerm2.inject(sid, data)` | `client.inject(sid, data)` |
| `ITerm2.activate_session(sid)` | `client.activate_session(sid)` |
| `ITerm2.raise_by_title(pat)` | `client.raise_by_title(pat)` |
| `ITerm2.raise_by_cwd(pat)` | `client.raise_by_cwd(pat)` |
| `ITerm2.focus` | `client.focus` |
| `ITerm2.get_prompt(sid)` | `client.get_prompt(sid)` |
| `ITerm2.get_variable(name, **scope)` | `client.get_variable(name, **scope)` |
| `ITerm2.get_profile_property(sid, *keys)` | `client.get_profile_property(sid, *keys)` |
| `ITerm2.list_profiles(...)` | `client.list_profiles(...)` |

**Note:** Notifications (`on_*`) are NOT available in one-shot mode. They require a persistent client.

---

## Common Patterns

### Get active session and read its screen

```ruby
ITerm2.connect do |client|
  active = client.focus[:active_session]
  screen = client.read_screen(active)
  puts screen[:lines].join("\n")
end
```

### Find session by title and send a command

```ruby
ITerm2.connect do |client|
  match = client.topology.find { |s| s[:title] =~ /my-project/i }
  client.send_text(match[:session_id], "make test\n") if match
end
```

### Monitor sessions for changes

```ruby
ITerm2.connect do |client|
  client.on_new_session { |e| puts "New: #{e[:session_id]}" }
  client.on_session_terminated { |e| puts "Gone: #{e[:session_id]}" }
  client.on_focus_change { |e| puts "Focus: #{e}" }
  sleep
end
```

### Batch query all session details

```ruby
ITerm2.connect do |client|
  client.topology_enriched.each do |s|
    puts "#{s[:session_id]} | #{s[:title]} | #{s[:cwd]} | #{s[:job]}"
  end
end
```

### Wait for a command to finish (shell integration required)

```ruby
ITerm2.connect do |client|
  sid = client.focus[:active_session]
  client.send_text(sid, "sleep 3\n")

  done = Queue.new
  token = client.on_prompt_change(sid) do |e|
    done.push(e) if e[:state] == :command_end
  end

  result = done.pop
  puts "Exit status: #{result[:exit_status]}"
  client.unsubscribe(token)
end
```

---

## Error Classes

All errors inherit from `ITerm2::Error`.

| Class | When |
|---|---|
| `ITerm2::Error` | Base class |
| `ITerm2::ConnectionError` | Can't connect to iTerm2 (not running, API disabled) |
| `ITerm2::AuthError` | osascript authentication failed |
| `ITerm2::RPCError` | iTerm2 returned an error status for an RPC |
| `ITerm2::NotFoundError` | `raise_by_title`/`raise_by_cwd` found no match (subclass of RPCError) |
| `ITerm2::SubscriptionError` | Notification subscription failed |

---

## Gotchas

1. **`send_text` does not append `\n`** -- you must include it to execute a command. The CLI auto-appends it.

2. **Duplicate notifications** -- iTerm2 sends each notification event twice. This is server-side behavior.

3. **One-shot mode opens a new connection per call** -- use `ITerm2.connect { |c| ... }` for multiple operations.

4. **`close_session` doesn't fire termination notifications** -- iTerm2 only fires `NOTIFY_ON_TERMINATE_SESSION` for user-initiated closes and process exits.

5. **`get_prompt` returns `:unavailable`** -- sessions without iTerm2 shell integration return `{ state: :unavailable }`.

6. **`topology_enriched` is slow with many sessions** -- makes one RPC per session. Use plain `topology` when you only need IDs and titles.

7. **Variable scope is required** -- `get_variables`/`set_variables` raise `ArgumentError` if you don't specify `session_id:`, `tab_id:`, `window_id:`, or `app: true`.
