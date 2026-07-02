# CLI Reference

Complete reference for `iterm2ctl`, the command-line interface.

## Global Options

These flags work with most commands:

| Flag | Description |
|---|---|
| `--session ID` | Target a specific session by ID |
| `--tab ID` | Target a specific tab by ID |
| `--window ID` | Target a specific window by ID |
| `--json` | Output as JSON (where supported) |

When no target is specified, most commands default to the first session.

---

## Commands

### `list`

List all windows, tabs, and sessions.

```bash
iterm2ctl list                  # table: window, tab, session, title
iterm2ctl list --with-cwd       # add working directory column
iterm2ctl list --with-pid       # add PID column
iterm2ctl list --with-cwd --with-pid  # both
iterm2ctl list --json           # JSON array output
```

`--with-cwd` and `--with-pid` trigger enriched topology (one RPC per session -- slower with many sessions).

### `send`

Send text to a session as if typed. Auto-appends `\n` if not present.

```bash
iterm2ctl send "echo hello"               # sends to first session
iterm2ctl send "ls -la" --session E8F2...  # sends to specific session
iterm2ctl send "make test"                 # newline auto-appended
```

### `read`

Read visible screen contents.

```bash
iterm2ctl read                          # visible screen, first session
iterm2ctl read --session E8F2...        # specific session
iterm2ctl read --scrollback 200         # include 200 lines of scrollback
iterm2ctl read --json                   # JSON with lines array + cursor
```

### `raise`

Raise (focus) a tab by title pattern or working directory.

```bash
iterm2ctl raise "my-project"              # title pattern (case-insensitive regex)
iterm2ctl raise --cwd "/work/myproject"   # match by working directory
iterm2ctl raise --session E8F2...         # raise specific session by ID
```

### `create`

Create a new tab or window.

```bash
iterm2ctl create tab                      # new tab in current window
iterm2ctl create window                   # new window
iterm2ctl create tab --window W123...     # new tab in specific window
iterm2ctl create tab --profile "Custom"   # new tab with profile
```

### `split`

Split the current pane.

```bash
iterm2ctl split                           # vertical split, first session
iterm2ctl split --session E8F2...         # split specific session
iterm2ctl split --horizontal              # horizontal split
```

### `close`

Close a session or tab.

```bash
iterm2ctl close                           # close first session
iterm2ctl close --session E8F2...         # close specific session
iterm2ctl close --tab T456...             # close entire tab
iterm2ctl close --force                   # skip confirmation
```

### `move`

Move a tab to another window.

```bash
iterm2ctl move --tab T456... --to-window W789...  # move tab to target window
```

Appends the tab to the end of the target window's tab bar. Uses `reorder_tabs` under the hood.

### `var`

Get and set iTerm2 variables.

```bash
iterm2ctl var get path --session E8F2...         # get a variable
iterm2ctl var set user.project myapp --session E8F2...  # set a user variable
iterm2ctl var all --session E8F2...              # dump all variables
iterm2ctl var all --json                         # JSON output
```

Variable scope defaults to the first session. Use `--tab` or `--window` for other scopes.

**Note:** Only `user.*` variables can be set.

### `info`

Show session details (tty, pid, cwd, name, job).

```bash
iterm2ctl info                            # first session
iterm2ctl info --session E8F2...          # specific session
iterm2ctl info --json                     # JSON output
```

### `focus`

Show current focus state (active session, tab, window, app status).

```bash
iterm2ctl focus                           # table output
iterm2ctl focus --json                    # JSON output
```

### `prompt`

Show shell prompt state (requires iTerm2 shell integration).

```bash
iterm2ctl prompt                          # first session
iterm2ctl prompt --session E8F2...        # specific session
iterm2ctl prompt --json                   # JSON output
```

States: `editing` (at prompt), `running` (command executing), `at_prompt` (idle), `unavailable` (no shell integration).

### `watch`

Watch for real-time events. Outputs one JSON object per line.

```bash
iterm2ctl watch                           # all events (focus + sessions + layout)
iterm2ctl watch focus                     # focus changes only
iterm2ctl watch sessions                  # new session + terminated events
iterm2ctl watch prompt --session E8F2...  # prompt state changes (requires session)
iterm2ctl watch screen --session E8F2...  # screen updates (requires session)
iterm2ctl watch layout                    # layout changes
```

Press `Ctrl+C` to stop watching.

### `profile`

Get profile properties for a session.

```bash
iterm2ctl profile --session E8F2...                # all properties
iterm2ctl profile Name Guid --session E8F2...      # specific keys
iterm2ctl profile --json                           # JSON output
```

### `profiles`

List all iTerm2 profiles.

```bash
iterm2ctl profiles                                 # name + GUID list
iterm2ctl profiles --properties Name,Guid          # specific properties only
iterm2ctl profiles --json                          # JSON output
```

### `inject`

Inject data into a session as if it came from the running process.

```bash
iterm2ctl inject "Hello from outside" --session E8F2...
```

### `version`

```bash
iterm2ctl version    # => iterm2ctl 0.1.0
```

### `help`

```bash
iterm2ctl help       # show usage summary
```

---

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Usage error or unknown command |
| 2 | Connection error (iTerm2 not running or API disabled) |
| 3 | Authentication error (osascript failed) |
| 4 | Not found (no session matching pattern) |
| 5 | RPC error (iTerm2 returned an error) |
