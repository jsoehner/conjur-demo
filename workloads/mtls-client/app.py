import ssl
import time
import requests
import os

CERT_DIR = "/certs"
CERT_FILE = os.path.join(CERT_DIR, "tls.crt")
KEY_FILE = os.path.join(CERT_DIR, "tls.key")

# Backoff settings for connection retries
INITIAL_BACKOFF = 2       # seconds
MAX_BACKOFF = 60          # seconds
REQUEST_INTERVAL = 10     # seconds between successful requests


def wait_for_certs():
    print("[Client] Waiting for sidecar to provision certificates...")
    while not (os.path.exists(CERT_FILE) and os.path.exists(KEY_FILE)):
        time.sleep(2)
    print("[Client] Certificates found. Starting mTLS client.")


def make_request():
    ca_cert = "/ca/ca.crt"
    backoff = INITIAL_BACKOFF

    while True:
        try:
            print("[Client] Attempting mTLS connection to Workload B...")
            response = requests.get(
                "https://workload-b:8443/",
                cert=(CERT_FILE, KEY_FILE),
                verify=ca_cert,
                timeout=10,
            )
            print(f"[Client] Response: {response.status_code} - {response.text.strip()}")
            # Reset backoff on success
            backoff = INITIAL_BACKOFF
            time.sleep(REQUEST_INTERVAL)

        except requests.exceptions.SSLError as e:
            print(f"[Client] TLS/mTLS error (identity or cert rejected): {e}")
            print(f"[Client] Retrying in {backoff}s...")
            time.sleep(backoff)
            backoff = min(backoff * 2, MAX_BACKOFF)

        except requests.exceptions.ConnectionError as e:
            print(f"[Client] Connection error (server may not be ready): {e}")
            print(f"[Client] Retrying in {backoff}s...")
            time.sleep(backoff)
            backoff = min(backoff * 2, MAX_BACKOFF)

        except Exception as e:
            print(f"[Client] Unexpected error: {e}")
            print(f"[Client] Retrying in {backoff}s...")
            time.sleep(backoff)
            backoff = min(backoff * 2, MAX_BACKOFF)


if __name__ == "__main__":
    wait_for_certs()
    make_request()
