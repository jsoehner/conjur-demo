import os
import tempfile
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

CA_CERT_PATH = os.getenv("CA_CERT_PATH", "/ca/ca.crt")
CA_KEY_PATH = os.getenv("CA_KEY_PATH", "/ca/ca.key")
PORT = int(os.getenv("LISTEN_PORT", "8000"))


class SignHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/sign":
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not found")
            return

        content_length = int(self.headers.get("Content-Length", 0))
        if content_length <= 0:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"Missing CSR body")
            return

        san_header = self.headers.get("X-SAN", "").strip()
        if not san_header:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"Missing X-SAN header")
            return

        csr_data = self.rfile.read(content_length)

        with tempfile.NamedTemporaryFile(delete=False, suffix=".pem") as csr_file:
            csr_file.write(csr_data)
            csr_file_path = csr_file.name

        with tempfile.NamedTemporaryFile(delete=False, suffix=".pem") as cert_file:
            cert_file_path = cert_file.name

        extfile_path = None
        cmd = [
            "openssl",
            "x509",
            "-req",
            "-in",
            csr_file_path,
            "-CA",
            CA_CERT_PATH,
            "-CAkey",
            CA_KEY_PATH,
            "-set_serial",
            str(int.from_bytes(os.urandom(8), "big")),
            "-out",
            cert_file_path,
            "-days",
            "1",
            "-sha256",
        ]

        if san_header:
            with tempfile.NamedTemporaryFile(delete=False, mode="w", suffix=".cnf") as ext_file:
                ext_file.write(f"subjectAltName={san_header}\n")
                extfile_path = ext_file.name
            cmd.extend(["-extfile", extfile_path])

        try:
            subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            with open(cert_file_path, "rb") as f:
                cert_data = f.read()
        except subprocess.CalledProcessError as exc:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(exc.stderr or b"Certificate signing failed")
            return
        finally:
            for path in [csr_file_path, cert_file_path, extfile_path]:
                if path and os.path.exists(path):
                    try:
                        os.unlink(path)
                    except OSError:
                        pass

        self.send_response(200)
        self.send_header("Content-Type", "application/x-pem-file")
        self.end_headers()
        self.wfile.write(cert_data)

    def log_message(self, format, *args):
        return


if __name__ == "__main__":
    print(f"[Signer] Starting CA signer service on port {PORT}")
    server = HTTPServer(("0.0.0.0", PORT), SignHandler)
    server.serve_forever()
