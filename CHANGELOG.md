# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.4.0] - 2026-10-23

### Added
- `client.split_browser_pane(session_id, url, vertical: true)` -- split a pane that shows a URL as a web view.
  Uses the `"Custom Command" => "Browser"` profile override, so no "Web Browser" profile is needed.
- `ITerm2::Browser` -- connection-free probes (`plugin_installed?`, `profiles_enabled?`, `available?`) and
  `pane_properties(url)`. The plugin check looks in the usual install folders first and asks Spotlight only
  as a fallback, so a plugin in those folders never depends on a Spotlight lookup. Probe commands run without a
  shell and are terminated on timeout.
- `ITerm2.current_session_id` -- the calling pane's session ID from `ITERM_SESSION_ID`, `nil` outside iTerm2.

## [0.3.1] - 2026-09-04

### Fixed
- `client.get_window_frame(window_id)` restored under its documented name. A local
  amend of the 0.3.0 commit (made before publish, after this method had already been
  verified) silently renamed it to `client.window_frame`; the published 0.3.0 gem on
  rubygems only exposes `window_frame` and lacks `get_window_frame`. Source is fixed
  here; the published artifact is fixed by the next release.

## [0.3.0] - 2026-09-03

### Added
- `client.set_property`/`get_property` counterpart -- `client.set_property(name, value, session_id:, window_id:)`
- `client.window_frame(window_id)` / `client.set_window_frame(window_id, x:, y:, width:, height:)` --
  windows created via `create_tab`/`split_pane` open at the profile's default size regardless of content;
  this is the only way to move/resize one afterward.
- `client.set_session_grid_size(session_id, columns:, rows:)` -- resize a session's character grid
- CLI: `set-window-frame WINDOW_ID X Y WIDTH HEIGHT`, `get-window-frame WINDOW_ID [--json]`

## [0.2.0] - 2026-07-02

### Added
- `ITerm2::Window`, `ITerm2::Tab`, `ITerm2::Session` — object wrappers over the
  flat client API (`client.windows`, `client.tabs`, `client.sessions`)
- `client.reorder_tabs(assignments)` — move/reorder tabs across windows
- CLI: `tabs`, `move`, `send-text`, `read-screen`, `activate-session`, `list --triage`

### Changed
- Dropped explicit `base64`/`ostruct` gemspec dependencies (stdlib on Ruby >= 3.1)

## [0.1.0] - 2026-02-12

### Added
- Initial release: `ITerm2::Connection` (auth, WebSocket handshake, binary framing)
- `ITerm2::Client`: session topology, send text, read screen, activate/raise,
  create tab, split pane, close, profile properties, variables, notifications
- `iterm2ctl` CLI
