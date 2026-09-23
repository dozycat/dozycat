import {test} from 'node:test';
import assert from 'node:assert/strict';
import {once} from 'node:events';
import {WebSocket} from 'ws';
import {createSignaling} from '../src/server.mjs';
const room = 'abcdefghijklmnopqrstuv';
async function fixture(t, options) {
  const app = createSignaling(options);
  const {port} = await app.listen();
  t.after(() => app.close());
  async function connect() {
    const socket = new WebSocket(`ws://127.0.0.1:${port}/v1/signal`);
    const messages = []; const waiting = [];
    socket.on('message', raw => {
      const msg = JSON.parse(raw.toString());
      if(waiting.length) waiting.shift()(msg); else messages.push(msg);
    });
    await once(socket,'open');
    return { socket, send: v=>socket.send(JSON.stringify(v)), next:()=>messages.length?Promise.resolve(messages.shift()):new Promise(resolve=>waiting.push(resolve)) };
  }
  return {app,connect,port};
}
test('two online peers exchange negotiation, no third guest or room takeover', {timeout:3000}, async t=>{
  const {connect}=await fixture(t);
  const d=await connect(), m=await connect(), attacker=await connect();
  d.send({type:'create',room}); assert.equal((await d.next()).type,'created');
  attacker.send({type:'create',room}); assert.equal((await attacker.next()).type,'unavailable');
  m.send({type:'join',room}); assert.equal((await m.next()).type,'joined'); assert.equal((await d.next()).type,'peer_joined');
  attacker.send({type:'join',room}); assert.equal((await attacker.next()).type,'unavailable');
  const offer={type:'offer',sdp:'v=0\r\nm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\n'};
  m.send(offer); assert.deepEqual(await d.next(),offer);
  const answer={...offer,type:'answer'}; d.send(answer); assert.deepEqual(await m.next(),answer);
});
test('disconnect destroys room and does not queue data for offline peers', {timeout:3000}, async t=>{
  const {connect,app}=await fixture(t); const d=await connect(),m=await connect();
  d.send({type:'create',room}); await d.next(); m.send({type:'join',room}); await m.next(); await d.next();
  d.socket.close(); assert.equal((await m.next()).reason,'disconnected');
  assert.equal(app.stats().rooms,0);
  const n=await connect(); n.send({type:'join',room}); assert.equal((await n.next()).type,'unavailable');
});
test('room expires even while both peers remain online', {timeout:3000}, async t=>{
  const {connect,app}=await fixture(t,{ttlMs:60,sweepMs:10}); const d=await connect();
  d.send({type:'create',room}); await d.next(); assert.equal((await d.next()).reason,'expired'); assert.equal(app.stats().rooms,0);
});
test('application data and unknown fields are rejected', {timeout:3000}, async t=>{
  const {connect}=await fixture(t); const d=await connect();
  d.send({type:'create',room}); await d.next();
  const closed=once(d.socket,'close'); d.send({type:'data',text:'private moment'});
  assert.equal((await closed)[0],1008);
});
test('binary and oversized frames close the connection', {timeout:3000}, async t=>{
  const {connect}=await fixture(t);
  for (const payload of [Buffer.from('secret'), 'x'.repeat(20_000)]) {
    const d=await connect(); const closed=once(d.socket,'close'); d.socket.send(payload);
    assert.ok([1008,1009].includes((await closed)[0]));
  }
});
test('browser origins are denied unless explicitly allowed', {timeout:3000}, async t=>{
  const {port}=await fixture(t);
  const ws=new WebSocket(`ws://127.0.0.1:${port}/v1/signal`,{origin:'https://evil.example'});
  const [error]=await once(ws,'error'); assert.match(error.message,/403/);
});
test('health endpoint has no room identifiers and is not cacheable', async t=>{
  const {port}=await fixture(t); const res=await fetch(`http://127.0.0.1:${port}/healthz`);
  assert.equal(res.headers.get('cache-control'),'no-store'); assert.deepEqual(await res.json(),{ok:true});
});
test('room capacity is bounded and a socket cannot register multiple rooms', {timeout:3000}, async t=>{
  const {connect}=await fixture(t,{maxRooms:1}); const a=await connect(),b=await connect();
  a.send({type:'create',room});await a.next();
  b.send({type:'create',room:'zyxwvutsrqponmlkjihgfe'});assert.equal((await b.next()).type,'unavailable');
  const closed=once(a.socket,'close');a.send({type:'create',room:'zyxwvutsrqponmlkjihgfe'});assert.equal((await closed)[0],1008);
});
test('per-socket traffic limits terminate repeated attempts', {timeout:3000}, async t=>{
  const {connect}=await fixture(t);const a=await connect();const closed=once(a.socket,'close');
  for(let i=0;i<40;i++)a.send({type:'join',room});
  assert.equal((await closed)[0],1008);
});
test('offer direction is checked and extra fields are never forwarded', {timeout:3000}, async t=>{
  const {connect}=await fixture(t);const a=await connect();a.send({type:'create',room});await a.next();
  const closed=once(a.socket,'close');a.send({type:'offer',sdp:'v=0\r\n',secret:'not signaling'});
  assert.equal((await closed)[0],1008);
});
