import { createSignaling } from './server.mjs';
const port = Number(process.env.PORT ?? 8787);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid PORT');
const app = createSignaling({ origins: (process.env.DOZYCAT_SIGNAL_ORIGINS ?? '').split(',').filter(Boolean) });
await app.listen(port, process.env.DOZYCAT_SIGNAL_HOST ?? '127.0.0.1');
console.log(`dozycat signaling ready on port ${port}`);
for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => { void app.close(); });
