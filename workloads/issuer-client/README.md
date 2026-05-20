# Issuer Client (CSR + Renewal Sidecar)

## Purpose
This workload:
- Generates a private key locally
- Builds a PKCS#10 CSR with a constrained SAN
- Requests certificate signing from Conjur
- Automatically renews the certificate before expiry

Private keys never leave the workload.

---

## CSR Generation (Example)

```bash
openssl genrsa -out key.pem 2048

openssl req -new \
  -key key.pem \
  -out csr.pem \
  -subj "/CN=workload-a" \
  -addext "subjectAltName=URI:spiffe://demo/workload-a"