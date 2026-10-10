## 🛡️ Cryptographic Bill of Materials (CBOM) & PQC Migration Assessment

**Format**: CycloneDX (v1.7) | **First-Party Code Crypto Assets**: 58 | **Total Tracked Crypto Assets**: 17

### 📊 Post-Quantum Migration Scorecard

| Metric | Count | Migration Status |
|---|---|---|
| **Post-Quantum Ready (PQC)** | **3** | 🟢 Quantum-Resistant (NIST FIPS 203/204/205) |
| **Quantum-Vulnerable (Backlog)** | **5** | 🔴 At Risk of 'Harvest Now, Decrypt Later' |
| **Classical Symmetric / Hashing** | **9** | 🟡 Classical Security (Requires AES-256 / SHA-256+) |
| **Asymmetric PQC Migration Progress** | **37.5%** | (3 of 8 asymmetric primitives migrated) |

### 🎯 Cryptographic Supply Chain Coverage & Confidence

| Evaluation Layer | Coverage / Status | Audit Confidence Assessment |
|---|---|---|
| **First-Party Code (`src/`)** | **100% Audited** (0 Custom Primitives) | 🟢 **HIGH** (Direct AST & SAST verified clean) |
| **Third-Party Supply Chain** | **0.0%** (0 of 49 dependencies cataloged) | 🔴 LOW (Known profiles assimilated) |
| **Overall Audit Confidence Score** | **2.0%** | **🔴 LOW** (49 unassimilated supply chain dependencies) |

### ✅ Post-Quantum Cryptography Migrated Assets

| Component Name | Primitive | Key/Parameter Set | PQC Standard | Provenance / Location(s) |
|---|---|---|---|---|
| `ML-KEM-768` | kem | N/A | NIST FIPS 203 (ML-KEM) | First-Party Code (SAST/AST)<br>`scripts/analyze_cbom.py:149` |
| `ML-DSA-65` | signature | N/A | NIST FIPS 204 (ML-DSA) | First-Party Code (SAST/AST)<br>`scripts/analyze_cbom.py:150` |
| `SLH-DSA` | signature | N/A | NIST FIPS 204 (ML-DSA) | First-Party Code (SAST/AST)<br>`scripts/analyze_cbom.py:151` |

### ⚠️ Quantum-Vulnerable Assets & Remediation Plan

| Component / Algorithm | Type / Primitive | Key Length / Curve | Recommended Target | Provenance / Context |
|---|---|---|---|---|
| **`RSA-2048`**<br><sub>RSA-2048</sub> | algorithm / signature | 2048 | **ML-KEM-768 / Kyber (FIPS 203)** | First-Party Code (SAST/AST)<br>`scripts/analyze_cbom.py:165` |
| **`ECDH-X25519`**<br><sub>ECDH-X25519</sub> | algorithm / key-agreement | 25519 | **ML-KEM-768 / Kyber (FIPS 203)** | First-Party Code (SAST/AST)<br>`scripts/analyze_cbom.py:165` |
| **`ECDSA-P256`**<br><sub>ECDSA-P256</sub> | algorithm / signature | secp256r1 | **ML-DSA-65 / Dilithium (FIPS 204)** | First-Party Code (SAST/AST)<br>`scripts/analyze_cbom.py:166` |
| **`Ed25519`**<br><sub>Ed25519</sub> | algorithm / signature | 25519 | **ML-DSA-65 / Dilithium (FIPS 204)** | First-Party Code (SAST/AST)<br>`scripts/analyze_cbom.py:166` |
| **`Diffie-Hellman`**<br><sub>Diffie-Hellman</sub> | algorithm / key-agreement | N/A | **ML-KEM (KEM) or ML-DSA (Signatures)** | First-Party Code (SAST/AST)<br>`scripts/scan_crypto_ast.py:32` |

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

### ⚠️ Unassimilated Third-Party Binaries & Cryptographic Blind Spots

> ℹ️ *The following third-party dependencies do not have verified upstream CBOM attestations in the catalog. They lower the audit confidence score until explicit CBOMs or attestations are published.* 

| Dependency Name | Version | Package URL (purl) | Status |
|---|---|---|---|
| `conjur-demo` | N/A | `N/A` | 🟡 Unassimilated (No upstream CBOM) |
| `conjur-demo` | latest | `pkg:pypi/conjur-demo@latest` | 🟡 Unassimilated (No upstream CBOM) |
| `Werkzeug` | 3.1.8 | `pkg:pypi/werkzeug@3.1.8` | 🟡 Unassimilated (No upstream CBOM) |
| `urllib3` | 2.7.0 | `pkg:pypi/urllib3@2.7.0` | 🟡 Unassimilated (No upstream CBOM) |
| `stevedore` | 5.8.0 | `pkg:pypi/stevedore@5.8.0` | 🟡 Unassimilated (No upstream CBOM) |
| `rich` | 15.0.0 | `pkg:pypi/rich@15.0.0` | 🟡 Unassimilated (No upstream CBOM) |
| `requests` | 2.34.2 | `pkg:pypi/requests@2.34.2` | 🟡 Unassimilated (No upstream CBOM) |
| `PyYAML` | 6.0.3 | `pkg:pypi/pyyaml@6.0.3` | 🟡 Unassimilated (No upstream CBOM) |
| `Pygments` | 2.20.0 | `pkg:pypi/pygments@2.20.0` | 🟡 Unassimilated (No upstream CBOM) |
| `pip` | 26.1.1 | `pkg:pypi/pip@26.1.1` | 🟡 Unassimilated (No upstream CBOM) |
| `mdurl` | 0.1.2 | `pkg:pypi/mdurl@0.1.2` | 🟡 Unassimilated (No upstream CBOM) |
| `MarkupSafe` | 3.0.3 | `pkg:pypi/markupsafe@3.0.3` | 🟡 Unassimilated (No upstream CBOM) |
| `markdown-it-py` | 4.2.0 | `pkg:pypi/markdown-it-py@4.2.0` | 🟡 Unassimilated (No upstream CBOM) |
| `Jinja2` | 3.1.6 | `pkg:pypi/jinja2@3.1.6` | 🟡 Unassimilated (No upstream CBOM) |
| `itsdangerous` | 2.2.0 | `pkg:pypi/itsdangerous@2.2.0` | 🟡 Unassimilated (No upstream CBOM) |
| *... and 34 more unassimilated dependencies* | | | |
