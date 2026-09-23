# dozycat signaling

Runnable accountless WebSocket signaling service. It is **not deployed** to dozycat.ai.
The desktop/mobile apps do not yet connect to it. See [implementation status](../../docs/LINK-IMPLEMENTATION.md).

```sh
npm ci
npm test
npm start
```

Node 24+. Defaults to `127.0.0.1:8787`. `GET /healthz` returns only `{"ok":true}`.
Clients connect to `/v1/signal`. Room IDs are in frames, never URL paths/query strings.
Browser origins are denied unless explicitly listed in `DOZYCAT_SIGNAL_ORIGINS` (comma separated).
Native clients without an Origin can connect. This is admission control, not device authentication.

## Wire protocol

1. Desktop sends `{"type":"create","room":"<22 base64url characters>"}`.
2. Phone sends `{"type":"join","room":"<same room>"}`.
3. Desktop receives `peer_joined`; phone receives `joined`.
4. Phone sends `{type:"offer",sdp:"v=0\r\n..."}`; desktop sends `{type:"answer",sdp:"v=0\r\n..."}`.
5. Both can send `{type:"ice",candidate:"candidate:...",sdpMid:"0",sdpMLineIndex:0}`.
6. `{type:"close"}` destroys the room. Connection loss/expiry closes both sockets.

There is no generic data, model inference, file transfer or message inbox endpoint. Clients must
send only SDP/ICE here; application data travels over the separate authenticated Noise channel.
Room knowledge grants only signaling access. A malicious server/client can deny connectivity;
clients must pin keys from the QR/local ACL and authenticate independently.

## Bounds and privacy

- Hard room lifetime: 120 seconds, monotonic clock; traffic does not extend it.
- At most 2 participants; one room per socket, 256 rooms, 512 clients, 16 clients per source IP.
- 16 KiB WebSocket frame, 32 frames/second and 256 KiB lifetime input budget per connection.
- No compression, database, offline queue, analytics, request/body/IP/room logging.
- Slow peers are disconnected rather than accumulating an unbounded write buffer.
- Unregistered sockets expire; heartbeat detects dead connections.
- Restart loses all rooms. A peer disconnect ends its room; clients must start a new negotiation.

This service necessarily handles IPs and connection candidates in volatile memory. Schema
checks are not an information-flow proof: a malicious caller could hide arbitrary bytes inside
an SDP string. Conforming clients must never put user content in these fields.

## Deployment (not performed)

Build with `docker build -t dozycat-signaling .`. Run behind TLS/WSS with a read-only container,
no swap/core dumps, no persistent container/request logs, bounded memory/CPU/processes, and
limits on idle HTTP/upgrades at the ingress. The container listens on 8787 as an unprivileged user.
Do not persist proxy/CDN access logs, request bodies, room IDs, IPs, or APM payloads. Validate these
settings at every ingress layer before claiming server-side non-retention.

The application ignores forwarded IP headers. A trusted reverse proxy must enforce per-client
limits itself; all proxied connections otherwise share this process's conservative per-IP limit.
Do not run multiple independent replicas behind random routing: both peers need the same in-memory
room owner. A distributed shared/persistent room directory is deliberately absent.
