import ssl
import os
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

CERT_DIR = "/certs"
CERT_FILE = os.path.join(CERT_DIR, "tls.crt")
KEY_FILE = os.path.join(CERT_DIR, "tls.key")

class MTLSHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(b"Hello from Workload B! mTLS connection successful.\n")

def wait_for_certs():
    print("[Server] Waiting for sidecar to provision certificates...")
    while not (os.path.exists(CERT_FILE) and os.path.exists(KEY_FILE)):
        time.sleep(2)
    print("[Server] Certificates found. Starting mTLS server.")

def run_server():
    server_address = ('0.0.0.0', 8443)
    httpd = HTTPServer(server_address, MTLSHandler)
    
    context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    context.load_cert_chain(certfile=CERT_FILE, keyfile=KEY_FILE)
    
    # SECURITY FIX: Require client certificate and verify against CA
    context.verify_mode = ssl.CERT_REQUIRED
    context.load_verify_locations(cafile="/ca/ca.crt") 

    httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
    
    print("[Server] Listening on https://0.0.0.0:8443")
    httpd.serve_forever()

if __name__ == "__main__":
    wait_for_certs()
    run_server()
