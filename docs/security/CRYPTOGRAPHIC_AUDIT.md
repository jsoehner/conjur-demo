## 🛡️ Cryptographic Bill of Materials (CBOM) & PQC Migration Assessment

**Format**: CycloneDX (v1.7) | **First-Party Code Crypto Assets**: 59 | **Total Tracked Crypto Assets**: 23

### 📊 Post-Quantum Migration Scorecard

| Metric | Count | Migration Status |
|---|---|---|
| **Post-Quantum Ready (PQC)** | **3** | 🟢 Quantum-Resistant (NIST FIPS 203/204/205) |
| **Quantum-Vulnerable (Backlog)** | **9** | 🔴 At Risk of 'Harvest Now, Decrypt Later' |
| **Classical Symmetric / Digest** | **11** | 🟡 Classical Security (Requires AES-256 / SHA-256+) |
| **Asymmetric PQC Migration Progress** | **25.0%** | (3 of 12 asymmetric primitives migrated) |

### 🎯 Cryptographic Supply Chain Coverage & Confidence

| Evaluation Layer | Coverage / Status | Audit Confidence Assessment |
|---|---|---|
| **First-Party Code (`src/`, `scripts/`)** | **100% Audited** (59 Crypto Primitive(s) Inventoried) | 🟢 **HIGH** (Direct AST & SAST verified) |
| **Third-Party Supply Chain** | **49.0%** (24 of 49 dependencies cataloged) | 🟡 MEDIUM (Known profiles assimilated) |
| **Overall Audit Confidence Score** | **50.0%** | 🟡 MEDIUM (23 unassimilated supply chain dependencies) |

| **System OS Inventory** | **Pending Update** | 🟡 **Warning** (Local OS crypto components not yet inventoried) |

### ✅ Post-Quantum Ready Assets

| Component Name | Primitive | Key/Parameter Set | PQC Standard | Provenance / Location(s) |
|---|---|---|---|---|
| `ML-KEM-768` | kem | N/A | ML-KEM-768 (FIPS 203) | First-Party Code (SAST/AST)<br>`scripts/analyze_cbom.py:149` |
| `ML-DSA-65` | signature | N/A | ML-DSA-65 (FIPS 204) | First-Party Code (SAST/AST)<br>`scripts/analyze_cbom.py:150` |
| `SLH-DSA` | signature | N/A | ML-DSA-65 (FIPS 204) | First-Party Code (SAST/AST)<br>`scripts/analyze_cbom.py:151` |

### ⚠️ Quantum-Vulnerable Assets & Remediation Plan

| Component / Algorithm | Type / Primitive | Key Length / Curve | Recommended Target | Provenance / Context |
|---|---|---|---|---|
| **`RSA-2048`**<br><sub>RSA-2048</sub> | algorithm / signature | 2048 | **ML-KEM-768 / Kyber (FIPS 203)** | First-Party Code (SAST/AST)<br>`scripts/analyze_cbom.py:165` |
| **`ECDH-X25519`**<br><sub>ECDH-X25519</sub> | algorithm / key-agreement | 25519 | **ML-KEM-768 / Kyber (FIPS 203)** | First-Party Code (SAST/AST)<br>`scripts/analyze_cbom.py:165` |
| **`ECDSA-P256`**<br><sub>ECDSA-P256</sub> | algorithm / signature | secp256r1 | **ML-DSA-65 / Dilithium (FIPS 204)** | First-Party Code (SAST/AST)<br>`scripts/analyze_cbom.py:166` |
| **`Ed25519`**<br><sub>Ed25519</sub> | algorithm / signature | 25519 | **ML-DSA-65 / Dilithium (FIPS 204)** | First-Party Code (SAST/AST)<br>`scripts/analyze_cbom.py:166` |
| **`Diffie-Hellman`**<br><sub>Diffie-Hellman</sub> | algorithm / key-agreement | N/A | **ML-KEM (KEM) or ML-DSA (Signatures)** | First-Party Code (SAST/AST)<br>`scripts/scan_crypto_ast.py:32` |
| **`urllib3 (urllib3 TLS PoolManager & X.509 Peer Verification)`**<br><sub>TLS 1.2 / 1.3 (ECDHE / RSA / ECDSA)</sub> | protocol / protocol | 2048 / 256 | **Enable post-quantum hybrid TLS groups (X25519MLKEM768) in underlying Python ssl runtime** | Assimilated Upstream CBOM: urllib3 SSLContext & X.509 Verification Profile<br>`Dependency: urllib3@2.7.0` |
| **`certifi (Certifi Mozilla Root CA Bundle (RSA-2048/4096 & ECDSA P-256/P-384))`**<br><sub>RSA-2048 / ECDSA-P256</sub> | certificate / certificate | 2048-4096 | **Track Mozilla CA program transition to ML-DSA / SLH-DSA root trust anchors** | Assimilated Upstream CBOM: Certifi Mozilla CA Root Bundle<br>`Dependency: certifi@2026.5.20` |
| **`certifi (Certifi Mozilla Root CA Bundle (RSA-2048/4096 & ECDSA P-256/P-384))`**<br><sub>RSA-2048 / ECDSA-P256</sub> | certificate / certificate | 2048-4096 | **Track Mozilla CA program transition to ML-DSA / SLH-DSA root trust anchors** | Assimilated Upstream CBOM: Certifi Mozilla CA Root Bundle<br>`Dependency: certifi@2026.7.22` |
| **`urllib3 (urllib3 TLS PoolManager & X.509 Peer Verification)`**<br><sub>TLS 1.2 / 1.3 (ECDHE / RSA / ECDSA)</sub> | protocol / protocol | 2048 / 256 | **Enable post-quantum hybrid TLS groups (X25519MLKEM768) in underlying Python ssl runtime** | Assimilated Upstream CBOM: urllib3 SSLContext & X.509 Verification Profile<br>`Dependency: urllib3@2.8.0` |

### 🔒 Classical Symmetric & Digest Assets

| Component Name | Primitive | Key Length | Quantum Resistance Assessment | Provenance / Location(s) |
|---|---|---|---|---|
| `ca.key` | unknown | N/A | Review key length for Grover resistance | First-Party Code (SAST/AST)<br>Dependencies / External |
| `cacert.pem` | unknown | N/A | Review key length for Grover resistance | First-Party Code (SAST/AST)<br>Dependencies / External |
| `cacert.pem` | unknown | N/A | Review key length for Grover resistance | First-Party Code (SAST/AST)<br>Dependencies / External |
| `SHA-256` | hash | 256 | Quantum-Resistant (Grover's proof) | First-Party Code (SAST/AST)<br>`workloads/ca-signer/signer.py:47` |
| `AES-256-GCM` | block-cipher | 256 | Quantum-Resistant (Grover's proof) | First-Party Code (SAST/AST)<br>`scripts/analyze_cbom.py:30` |
| `ChaCha20-Poly1305` | stream-cipher | 256 | Quantum-Resistant (Grover's proof) | First-Party Code (SAST/AST)<br>`scripts/analyze_cbom.py:30` |
| `SHA-384` | hash | 384 | Quantum-Resistant (Grover's proof) | First-Party Code (SAST/AST)<br>`scripts/analyze_cbom.py:30` |
| `SHA-512` | hash | 512 | Quantum-Resistant (Grover's proof) | First-Party Code (SAST/AST)<br>`scripts/analyze_cbom.py:30` |
| `Stateful-Hash-Signature` | signature | N/A | Review key length for Grover resistance | First-Party Code (SAST/AST)<br>`scripts/analyze_cbom.py:152` |
| `TLS-1.3` | protocol | v1.3 | TLS 1.3 Transport (Enable hybrid X25519MLKEM768 via OpenSSL 3.5+) | First-Party Code (SAST/AST)<br>`workloads/mtls-server/app.py:69` |
| `requests (Requests HTTPS Session TLS 1.2 / 1.3 Client)` | protocol | 256 | Quantum-Resistant (Grover's proof) | Assimilated Upstream CBOM: Python Requests HTTPS/TLS Transport Profile<br>`Dependency: requests@2.34.2` |

### ⚠️ Unassimilated Third-Party Binaries & Cryptographic Blind Spots

> ℹ️ *The following third-party dependencies do not have verified upstream CBOM attestations in the catalog. They lower the audit confidence score until explicit CBOMs or attestations are published.* 

| Dependency Name | Version | Package URL (purl) | Status |
|---|---|---|---|
| `conjur-demo` | N/A | `N/A` | 🟡 Unassimilated (No upstream CBOM) |
| `conjur-demo` | latest | `pkg:pypi/conjur-demo@latest` | 🟡 Unassimilated (No upstream CBOM) |
| `Werkzeug` | 3.1.8 | `pkg:pypi/werkzeug@3.1.8` | 🟡 Unassimilated (No upstream CBOM) |
| `stevedore` | 5.8.0 | `pkg:pypi/stevedore@5.8.0` | 🟡 Unassimilated (No upstream CBOM) |
| `PyYAML` | 6.0.3 | `pkg:pypi/pyyaml@6.0.3` | 🟡 Unassimilated (No upstream CBOM) |
| `pip` | 26.1.1 | `pkg:pypi/pip@26.1.1` | 🟡 Unassimilated (No upstream CBOM) |
| `MarkupSafe` | 3.0.3 | `pkg:pypi/markupsafe@3.0.3` | 🟡 Unassimilated (No upstream CBOM) |
| `Jinja2` | 3.1.6 | `pkg:pypi/jinja2@3.1.6` | 🟡 Unassimilated (No upstream CBOM) |
| `itsdangerous` | 2.2.0 | `pkg:pypi/itsdangerous@2.2.0` | 🟡 Unassimilated (No upstream CBOM) |
| `Flask` | 3.1.3 | `pkg:pypi/flask@3.1.3` | 🟡 Unassimilated (No upstream CBOM) |
| `docker` | 7.1.0 | `pkg:pypi/docker@7.1.0` | 🟡 Unassimilated (No upstream CBOM) |
| `click` | 8.4.1 | `pkg:pypi/click@8.4.1` | 🟡 Unassimilated (No upstream CBOM) |
| `blinker` | 1.9.0 | `pkg:pypi/blinker@1.9.0` | 🟡 Unassimilated (No upstream CBOM) |
| `bandit` | 1.9.4 | `pkg:pypi/bandit@1.9.4` | 🟡 Unassimilated (No upstream CBOM) |
| `click` | 8.5.0 | `pkg:pypi/click@8.5.0` | 🟡 Unassimilated (No upstream CBOM) |
| *... and 8 more unassimilated dependencies* | | | |
