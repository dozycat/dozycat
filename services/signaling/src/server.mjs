import http from 'node:http';
import { performance } from 'node:perf_hooks';
import { WebSocketServer, WebSocket } from 'ws';

const ROOM = /^[A-Za-z0-9_-]{22}$/;
const exact = (value, keys) => value && typeof value === 'object' && !Array.isArray(value)
  && Object.keys(value).length === keys.length && keys.every(k => Object.hasOwn(value, k));

// No persistence, offline queue, URL room identifiers or request logging.
export function createSignaling({ ttlMs = 120_000, maxClients = 512, perIP = 16,
  maxRooms = 256, sweepMs = 1_000, origins = [] } = {}) {
  const rooms = new Map();
  const clients = new Map();
  const addresses = new Map();
  const server = http.createServer((req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    if (req.method === 'GET' && req.url === '/healthz') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end('{"ok":true}');
    } else { res.writeHead(404); res.end(); }
  });
  const wss = new WebSocketServer({ noServer: true, maxPayload: 16_384,
    perMessageDeflate: false, clientTracking: false });
  const send = (socket, value) => {
    if (socket.readyState !== WebSocket.OPEN) return;
    if (socket.bufferedAmount > 32_768) { socket.terminate(); return; }
    socket.send(JSON.stringify(value));
  };
  function removeRoom(id, reason) {
    const room = rooms.get(id);
    if (!room) return;
    rooms.delete(id);
    for (const socket of [room.owner, room.guest]) {
      const client = clients.get(socket);
      if (client) client.room = undefined;
      if (socket) { send(socket, { type: 'closed', reason }); socket.close(1000); }
    }
  }
  function expire() {
    const now = performance.now();
    for (const [id, room] of rooms) if (room.expires <= now) removeRoom(id, 'expired');
    for (const [socket, client] of clients) {
      if ((!client.room && now - client.created > 10_000) || now - client.lastPong > 45_000) {
        socket.terminate();
      } else if (socket.readyState === WebSocket.OPEN) socket.ping();
    }
  }
  const sweep = setInterval(expire, sweepMs).unref();
  server.on('upgrade', (req, socket, head) => {
    // Forwarded headers are deliberately not trusted. A reverse proxy requires its own limits.
    const ip = req.socket.remoteAddress;
    const origin = req.headers.origin;
    if (req.url !== '/v1/signal' || clients.size >= maxClients
        || (addresses.get(ip) ?? 0) >= perIP
        || (origin && !origins.includes(origin))) {
      socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n'); return;
    }
    wss.handleUpgrade(req, socket, head, ws => wss.emit('connection', ws, ip));
  });
  wss.on('connection', (socket, ip) => {
    const now = performance.now();
    const client = { ip, created: now, window: now, count: 0, bytes: 0, lastPong: now };
    clients.set(socket, client);
    addresses.set(ip, (addresses.get(ip) ?? 0) + 1);
    socket.on('error', () => {}); // Never print frames, rooms or client identifiers.
    socket.on('pong', () => { client.lastPong = performance.now(); });
    socket.on('close', () => {
      clients.delete(socket);
      const count = (addresses.get(ip) ?? 1) - 1;
      if (count > 0) addresses.set(ip, count); else addresses.delete(ip);
      if (client.room) removeRoom(client.room, 'disconnected');
    });
    socket.on('message', (raw, binary) => {
      const now = performance.now();
      if (now - client.window >= 1_000) { client.window = now; client.count = 0; }
      client.bytes += raw.length;
      if (binary || ++client.count > 32 || client.bytes > 262_144) {
        socket.close(1008, 'limit'); return;
      }
      let msg;
      try { msg = JSON.parse(raw.toString('utf8')); } catch { socket.close(1008); return; }
      if (exact(msg, ['type', 'room']) && ['create', 'join'].includes(msg.type)
          && typeof msg.room === 'string' && ROOM.test(msg.room)) {
        if (client.room) { socket.close(1008); return; }
        const room = rooms.get(msg.room);
        if (room && room.expires <= now) { removeRoom(msg.room, 'expired'); send(socket, {type:'unavailable'}); return; }
        if (msg.type === 'create') {
          if (room || rooms.size >= maxRooms) { send(socket, {type:'unavailable'}); return; }
          rooms.set(msg.room, { owner: socket, expires: now + ttlMs });
          client.room = msg.room;
          send(socket, {type:'created', ttl_ms:ttlMs});
        } else {
          if (!room || room.guest || room.owner === socket) { send(socket, {type:'unavailable'}); return; }
          room.guest = socket;
          client.room = msg.room;
          send(socket, {type:'joined'});
          send(room.owner, {type:'peer_joined'});
        }
        return;
      }
      const room = rooms.get(client.room);
      if (!room) { socket.close(1008); return; }
      if (room.expires <= now) { removeRoom(client.room, 'expired'); return; }
      if (exact(msg, ['type']) && msg.type === 'close') { removeRoom(client.room, 'closed'); return; }
      // Only connection negotiation. There is no generic application-data forwarding endpoint.
      let valid = false;
      if (exact(msg, ['type', 'sdp']) && ['offer','answer'].includes(msg.type)) {
        valid = typeof msg.sdp === 'string' && msg.sdp.length <= 12_000 && msg.sdp.startsWith('v=0\r\n')
          && ((msg.type === 'offer' && socket === room.guest) || (msg.type === 'answer' && socket === room.owner));
      } else if (exact(msg, ['type', 'candidate', 'sdpMid', 'sdpMLineIndex']) && msg.type === 'ice') {
        valid = typeof msg.candidate === 'string' && msg.candidate.length <= 2_048
          && (msg.candidate === '' || msg.candidate.startsWith('candidate:'))
          && (msg.sdpMid === null || typeof msg.sdpMid === 'string' && msg.sdpMid.length <= 64)
          && (msg.sdpMLineIndex === null || Number.isInteger(msg.sdpMLineIndex) && msg.sdpMLineIndex >= 0 && msg.sdpMLineIndex <= 32);
      }
      if (!valid) { socket.close(1008); return; }
      const peer = socket === room.owner ? room.guest : room.owner;
      if (!peer) { send(socket, {type:'peer_unavailable'}); return; }
      send(peer, msg);
    });
  });
  return {
    server,
    async listen(port = 0, host = '127.0.0.1') {
      await new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, host, resolve); });
      return server.address();
    },
    async close() {
      clearInterval(sweep);
      for (const socket of clients.keys()) socket.terminate();
      rooms.clear(); addresses.clear();
      await new Promise(resolve => wss.close(resolve));
      if (server.listening) await new Promise(resolve => server.close(resolve));
    },
    // Aggregate counts only; no device identifiers or room inspection API.
    stats: () => ({rooms:rooms.size, clients:clients.size}),
  };
}
