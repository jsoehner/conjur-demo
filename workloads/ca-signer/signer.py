import os
import tempfile
import stat
import subprocess
import urllib.parse
import base64
import json
import requests
import logging
import time
import ssl
from http.server import BaseHTTPRequestHandler, HTTPServer

# Structured JSON logging for audit trail
logging.basicConfig(
    level=logging.INFO, 
    format='{"timestamp": "%(asctime)s", "level": "%(levelname)s", "service": "ca-signer", "message": "%(message)s"}'
)

RATE_LIMITS = {}

CA_CERT_PATH = os.getenv("CA_CERT_PATH", "/ca/ca.crt")
CA_KEY_PATH = os.getenv("CA_KEY_PATH", "/ca/ca.key")
PORT = int(os.getenv("LISTEN_PORT", "8000"))
CONJUR_URL = os.getenv("CONJUR_APPLIANCE_URL", "http://conjur:80")

# Initialize CA directory for openssl ca
os.makedirs("/tmp/ca/newcerts", exist_ok=True)
if not os.path.exists("/tmp/ca/index.txt"):
    open("/tmp/ca/index.txt", "w").close()
with open("/tmp/ca/index.txt.attr", "w") as f:
    f.write("unique_subject = no\n")
if not os.path.exists("/tmp/ca/serial"):
    with open("/tmp/ca/serial", "w") as f:
        f.write("01\n")

CA_CNF = f"""
[ ca ]
default_ca = CA_default
[ CA_default ]
dir = /tmp/ca
database = /tmp/ca/index.txt
new_certs_dir = /tmp/ca/newcerts
certificate = {CA_CERT_PATH}
private_key = {CA_KEY_PATH}
serial = /tmp/ca/serial
default_md = sha256
policy = policy_any
[ policy_any ]
countryName = optional
stateOrProvinceName = optional
organizationName = optional
organizationalUnitName = optional
commonName = supplied
emailAddress = optional
"""
with open("/tmp/ca/ca.cnf", "w") as f:
    f.write(CA_CNF)

class SignHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path not in ["/sign", "/revoke"]:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not found")
            return

        # 1. Authentication
        token = self.headers.get("X-Auth-Token", "").strip()
        if not token:
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b"Missing X-Auth-Token header")
            return

        b64_token = base64.b64encode(token.encode("utf-8")).decode("utf-8")
        parsed = urllib.parse.urlparse(CONJUR_URL)
        if parsed.scheme not in ("http", "https") or not parsed.netloc:
            raise ValueError("CONJUR_URL must be a valid http(s) URL")
        req_url = urllib.parse.urljoin(CONJUR_URL, "/whoami")
        headers = {"Authorization": f'Token token="{b64_token}"'}

        try:
            response = requests.get(req_url, headers=headers, timeout=10, verify=False)
            response.raise_for_status()
            whoami_data = response.json()
        except requests.exceptions.HTTPError:
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b"Invalid token or authentication failed")
            return
        except requests.exceptions.RequestException:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b"Error communicating with Conjur")
            return

        username = whoami_data.get("username", "")
        if not username.startswith("host/demo/"):
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b"Unauthorized identity")
            return

        workload_name = username.split("/")[-1]
        allowed_san = f"URI:spiffe://demo/{workload_name}"

        # 2. Authorization
        san_header = self.headers.get("X-SAN", "").strip()
        if san_header != allowed_san:
            logging.warning(f"Forbidden SAN attempted by {workload_name}. Expected {allowed_san}, got {san_header}")
            self.send_response(403)
            self.end_headers()
            self.wfile.write(f"Forbidden SAN. Expected {allowed_san}".encode("utf-8"))
            return

        # 3. Rate Limiting (Max 10 requests per minute per workload)
        now = time.time()
        history = RATE_LIMITS.get(workload_name, [])
        history = [t for t in history if now - t < 60]
        if len(history) >= 10:
            logging.warning(f"Rate limit exceeded for {workload_name}")
            self.send_response(429)
            self.end_headers()
            self.wfile.write(b"Rate limit exceeded")
            return
        history.append(now)
        RATE_LIMITS[workload_name] = history

        content_length = int(self.headers.get("Content-Length", 0))
        if content_length <= 0 or content_length > 16384:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"Invalid or missing request body (must be >0 and <=16KB)")
            return

        req_data = self.rfile.read(content_length)

        if self.path == "/revoke":
            with tempfile.NamedTemporaryFile(delete=False, suffix=".pem", prefix="conjur_") as cert_file:
                cert_file.write(req_data)
                cert_file.flush()
                os.chmod(cert_file.name, stat.S_IRUSR | stat.S_IWUSR)
                cert_file_path = cert_file.name

            cmd_revoke = ["openssl", "ca", "-batch", "-config", "/tmp/ca/ca.cnf", "-revoke", cert_file_path]
            cmd_crl = ["openssl", "ca", "-batch", "-config", "/tmp/ca/ca.cnf", "-gencrl", "-out", "/tmp/ca/crl.pem"]

            try:
                subprocess.run(cmd_revoke, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                subprocess.run(cmd_crl, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            except subprocess.CalledProcessError as exc:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(b"Certificate revocation failed")
                if exc.stderr:
                    logging.error(f"Certificate revocation error for {workload_name}: {exc.stderr.decode('utf-8', errors='ignore')}")
                return
            finally:
                if os.path.exists(cert_file_path):
                    try:
                        os.unlink(cert_file_path)
                    except OSError:
                        pass

            logging.info(f"Certificate successfully revoked for {workload_name} (SAN: {san_header})")
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Revoked successfully")
            return

        csr_data = req_data

        with tempfile.NamedTemporaryFile(delete=False, suffix=".pem", prefix="conjur_") as csr_file:
            csr_file.write(csr_data)
            csr_file.flush()
            os.chmod(csr_file.name, stat.S_IRUSR | stat.S_IWUSR)
            csr_file_path = csr_file.name

        with tempfile.NamedTemporaryFile(delete=False, suffix=".pem", prefix="conjur_") as cert_file:
            os.chmod(cert_file.name, stat.S_IRUSR | stat.S_IWUSR)
            cert_file_path = cert_file.name

        extfile_path = None
        with tempfile.NamedTemporaryFile(delete=False, mode="w", suffix=".cnf", prefix="conjur_") as ext_file:
            ext_file.write(f"[v3_req]\nsubjectAltName={san_header},DNS:{workload_name}\n")
            ext_file.flush()
            os.chmod(ext_file.name, stat.S_IRUSR | stat.S_IWUSR)
            extfile_path = ext_file.name

        cmd_date = subprocess.run(["date", "-u", "-d", "+24 hours", "+%y%m%d%H%M%SZ"], capture_output=True, text=True)
        enddate = cmd_date.stdout.strip()

        cmd = [
            "openssl",
            "ca",
            "-batch",
            "-config",
            "/tmp/ca/ca.cnf",
            "-subj",
            f"/CN={workload_name}",
            "-in",
            csr_file_path,
            "-out",
            cert_file_path,
            "-enddate",
            enddate,
            "-extensions",
            "v3_req",
            "-extfile",
            extfile_path
        ]

        try:
            subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            with open(cert_file_path, "rb") as f:
                cert_data = f.read()
        except subprocess.CalledProcessError as exc:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b"Certificate signing failed")
            if exc.stderr:
                logging.error(f"Certificate signing error for {workload_name}: {exc.stderr.decode('utf-8', errors='ignore')}")
            return
        finally:
            for path in [csr_file_path, cert_file_path, extfile_path]:
                if path and os.path.exists(path):
                    try:
                        os.unlink(path)
                    except OSError:
                        pass

        logging.info(f"Certificate successfully issued for {workload_name} (SAN: {san_header})")
        self.send_response(200)
        self.send_header("Content-Type", "application/x-pem-file")
        self.end_headers()
        self.wfile.write(cert_data)

    def log_message(self, format, *args):
        # Suppress default BaseHTTPRequestHandler logging to prevent leaking secrets and to use our structured JSON logging instead
        return

if __name__ == "__main__":
    logging.info(f"Starting CA signer service on port {PORT}")
    server = HTTPServer(("0.0.0.0", PORT), SignHandler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=CA_CERT_PATH, keyfile=CA_KEY_PATH)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    server.serve_forever()
