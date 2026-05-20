import ssl
import os
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

CERT_DIR = "/certs"
CERT_FILE = os.path.join(CERT_DIR, "tls.crt")
KEY_FILE = os.path.join(CERT_DIR, "tls.key")


class MTLSHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        # Extract peer certificate from the underlying SSL socket
        peer_cert = self.connection.getpeercert()
        client_identity = self._extract_identity(peer_cert)

        print(f"[Server] Authenticated connection from: {client_identity}")

        body = (
            f"Hello from Workload B! mTLS connection successful.\n"
            f"Your identity: {client_identity}\n"
        ).encode()

        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _extract_identity(self, peer_cert):
        """Parse CN and SAN URI from the peer's DER-decoded certificate dict."""
        if not peer_cert:
            return "UNKNOWN (no cert provided)"

        # Extract CN from subject
        cn = None
        for field in peer_cert.get("subject", []):
            for key, value in field:
                if key == "commonName":
                    cn = value

        # Extract SPIFFE URI SAN
        san_uri = None
        for san_type, san_value in peer_cert.get("subjectAltName", []):
            if san_type == "URI":
                san_uri = san_value
                break

        parts = []
        if cn:
            parts.append(f"CN={cn}")
        if san_uri:
            parts.append(f"SAN={san_uri}")

        return ", ".join(parts) if parts else "UNKNOWN"

    def log_message(self, fmt, *args):
        # Override to add [Server] prefix for consistent log formatting
        print(f"[Server] {fmt % args}")


class MTLSServer(HTTPServer):
    """HTTPServer subclass that makes the SSL socket available to handlers."""

    def get_request(self):
        request, client_address = self.socket.accept()
        try:
            # Hot-reload certificates: read from disk on every connection
            context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
            context.load_cert_chain(certfile=CERT_FILE, keyfile=KEY_FILE)
            context.verify_mode = ssl.CERT_REQUIRED
            context.load_verify_locations(cafile="/ca/ca.crt")
            
            ssl_socket = context.wrap_socket(request, server_side=True)
            return ssl_socket, client_address
        except Exception as e:
            print(f"[Server] SSL Handshake Failed: {e}")
            request.close()
            # Return a dummy closed socket to prevent crash
            import socket
            dummy = socket.socket()
            dummy.close()
            return dummy, client_address


def wait_for_certs():
    print("[Server] Waiting for sidecar to provision certificates...")
    while not (os.path.exists(CERT_FILE) and os.path.exists(KEY_FILE)):
        time.sleep(2)
    print("[Server] Certificates found. Starting mTLS server.")


def run_server():
    server_address = ("0.0.0.0", 8443)
    httpd = MTLSServer(server_address, MTLSHandler)
    # The socket is not wrapped globally anymore. 
    # It will be wrapped per-connection in get_request() for hot-reloading.

    print("[Server] Listening on https://0.0.0.0:8443")
    httpd.serve_forever()


if __name__ == "__main__":
    wait_for_certs()
    run_server()
