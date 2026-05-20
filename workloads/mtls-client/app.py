import ssl
import time
import requests
import os

CERT_DIR = "/certs"
CERT_FILE = os.path.join(CERT_DIR, "tls.crt")
KEY_FILE = os.path.join(CERT_DIR, "tls.key")

def wait_for_certs():
    print("[Client] Waiting for sidecar to provision certificates...")
    while not (os.path.exists(CERT_FILE) and os.path.exists(KEY_FILE)):
        time.sleep(2)
    print("[Client] Certificates found. Starting mTLS client.")

def make_request():
    # SECURITY FIX: Ensure the client verifies the server certificate against the CA
    ca_cert = "/ca/ca.crt"

    while True:
        try:
            print("[Client] Attempting mTLS connection to Workload B...")
            response = requests.get("https://workload-b:8443/", cert=(CERT_FILE, KEY_FILE), verify=ca_cert)
            print(f"[Client] Response: {response.status_code} - {response.text}")
        except Exception as e:
            print(f"[Client] Connection failed: {e}")
        
        time.sleep(10)

if __name__ == "__main__":
    wait_for_certs()
    make_request()
