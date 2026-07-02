# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
