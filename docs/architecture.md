# Architecture

How `iterm2_ruby` connects to and communicates with iTerm2.

## Connection Lifecycle

```
osascript (one-time auth)
    |
    v
Unix socket (~/.../iTerm2/private/socket)  --or-->  TCP localhost:1912
    |
    v
WebSocket upgrade (RFC 6455, subprotocol: api.iterm2.com)
    |
    v
Protobuf RPC over binary WebSocket frames
```

1. **Authentication**: A single `osascript` call asks iTerm2 for a cookie and key pair. This triggers an iTerm2 confirmation dialog on first use for each `app_name`.

2. **Socket**: Prefers the Unix domain socket at `~/Library/Application Support/iTerm2/private/socket`. Falls back to TCP on `127.0.0.1:1912` if the socket file doesn't exist.

3. **WebSocket handshake**: Standard HTTP upgrade with custom iTerm2 headers (`x-iterm2-cookie`, `x-iterm2-key`, `x-iterm2-library-version`, `x-iterm2-advisory-name`). The framing is hand-rolled per RFC 6455 -- no external WebSocket gem.

4. **Ready**: After the `101 Switching Protocols` response, the connection is ready for protobuf RPCs.

## Protobuf Protocol

All messages use Google Protocol Buffers, defined in iTerm2's [`api.proto`](https://github.com/gnachman/iTerm2/blob/master/proto/api.proto).

- **Client -> Server**: `ClientOriginatedMessage` with an `id` field and a oneof request field (e.g., `list_sessions_request`, `send_text_request`)
- **Server -> Client**: `ServerOriginatedMessage` with a matching `id` and a oneof response field, OR a `notification` field for async events

Ruby bindings are generated with `protoc --ruby_out` from `api.proto`. The generated module is `Iterm2` (lowercase t), aliased as `ITerm2::Proto` in `lib/iterm2.rb`.

## Sync vs Dispatch Mode

The connection has two operating modes:

### Sync Mode (default)

Simple request-response. `rpc_sync` sends a frame and blocks reading the next frame as the response. Used when no notifications are active.

```
Thread:  send(request) --> recv(response) --> return
```

### Dispatch Mode (activated by first notification subscription)

A background reader thread runs continuously, routing incoming frames:

```
Main thread:     send(request) --> wait on Queue --> return response
Reader thread:   recv(frame) --> RPC response?  --> push to request's Queue
                              --> notification?  --> fire subscriber callbacks
```

The dispatch loop starts automatically on the first `subscribe` or `on_*` call. It stops when `client.close` is called.

## Threading Model

| Mutex | Protects |
|---|---|
| `@mutex` | `@pending_responses` hash (request ID -> Queue) and `@id_counter` |
| `@write_mutex` | Socket writes (only one thread writes at a time) |
| `@subscriber_mutex` | `@subscribers` hash (callbacks for each notification type) |

The reader thread (`dispatch_loop`) is the only thread that reads from the socket in dispatch mode. RPC responses are delivered to the calling thread via a per-request `Queue`.

## Notification Dispatch

Subscribers are keyed by `[session_id, notification_type]`:

- **Session-specific**: `[session_id, :NOTIFY_ON_PROMPT]` -- only fires for that session
- **Global**: `[nil, :NOTIFY_ON_FOCUS_CHANGE]` -- fires for all events of that type

When a notification arrives, the dispatch loop checks session-specific subscribers first, then global. Both are called if both exist.

Notification type detection uses `has_*?` methods on the protobuf `Notification` message (e.g., `has_focus_changed_notification?`) rather than checking `submessage`, because the protobuf oneof accessor is more reliable.

## File Layout

```
lib/iterm2.rb                    # Entry point, ITerm2.connect, one-shot methods, error classes
lib/iterm2/version.rb            # VERSION constant
lib/iterm2/connection.rb         # WebSocket + auth + sync/dispatch RPC
lib/iterm2/client.rb             # High-level API (all public methods)
lib/iterm2/proto/api_pb.rb       # protoc-generated bindings from api.proto
bin/iterm2ctl                    # CLI entry point
```
