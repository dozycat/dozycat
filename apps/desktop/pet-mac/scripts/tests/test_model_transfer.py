"""Run the actual Swift downloader against a local HTTP fixture."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import tempfile
import threading

PAYLOAD = bytes(n % 256 for n in range(8193))
requests = []
failed = False
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
    def do_GET(self):
        global failed
        span = self.headers['Range'].removeprefix('bytes=')
        start, end = map(int, span.split('-'))
        requests.append((self.path, start))
        if self.path == '/resume' and start == 1024 and not failed:
            failed = True
            self.send_response(503)
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        assert self.path != '/must-not-request', 'Verified file should be reused'
        full = self.path == '/full'
        chunk = PAYLOAD if full else PAYLOAD[start:end+1]
        if self.path == '/corrupt':
            chunk = bytes([chunk[0] ^ 255]) + chunk[1:]
        self.send_response(200 if full else 206)
        self.send_header('Content-Length', str(len(chunk)))
        if not full:
            begin = start + 1 if self.path == '/wrong-range' else start
            self.send_header('Content-Range', f'bytes {begin}-{end}/{len(PAYLOAD)}')
        self.end_headers()
        self.wfile.write(chunk)

root = Path(__file__).resolve().parents[2]
server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with tempfile.TemporaryDirectory() as tmp:
        binary = str(Path(tmp) / 'transfer-tests')
        subprocess.run(['swiftc', '-parse-as-library', str(root/'Sources/LocalModelDownloadSource.swift'),
                        str(root/'Sources/LocalModelTransfer.swift'),
                        str(root/'scripts/tests/LocalModelTransferTests.swift'), '-o', binary], check=True)
        subprocess.run([binary, f'http://127.0.0.1:{server.server_port}'], check=True, timeout=60)
    offsets = [offset for path, offset in requests if path == '/resume']
    assert offsets[:3] == [0, 1024, 1024], offsets
    assert offsets.count(0) == 1, offsets
    print('PASS: server confirmed resume without redownloading the completed first chunk')
finally:
    server.shutdown()
