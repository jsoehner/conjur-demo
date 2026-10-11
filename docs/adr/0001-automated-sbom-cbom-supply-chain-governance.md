# ADR-0001: Automated SBOM and CBOM Supply Chain Governance Pipeline

## Metadata

| Field | Value |
|---|---|
| ADR ID | ADR-0001 |
| Status | Accepted |
| Created Date | 2026-10-11 |
| Decision Date | 2026-10-11 |
| Effective Date | 2026-10-11 |
| Architecture Domain | Security / Supply Chain Governance / Cryptography / DevOps |
| Scope | Software & Cryptographic Supply Chain Security (Repository & CI/CD) |
| Decision Owner | Lead DevSecOps Architect |
| Named Decision Maker | DevSecOps Engineering & Security Architecture Team |
| Approval Authority | Architecture Review Board (ARB) / Security Governance Committee |
| Approval Evidence ID | ARB-2026-10-SEC-002 |
| APM Code(s) | SEC-SUPPLYCHAIN-01 |
| NIRA Reference(s) | NIRA-SEC-2026-042 |
| Tags | sbom, cbom, cyclonedx, spdx, supply-chain, pqc, ast-analysis, conjur, mtls, devsecops |

---

## Business and Architecture Context

### Problem Statement

The `conjur-demo` repository demonstrates automated Zero Trust workload identity, certificate issuance, renewal, and mutual TLS (mTLS) backed by CyberArk Conjur. Workload sidecars generate local RSA private keys, submit Certificate Signing Requests (CSRs) with SPIFFE identities, and establish TLS channels.

Modern software supply chain and cryptographic governance mandates—including Executive Order 14028, NIST SP 800-218 (Secure Software Development Framework - SSDF), and NIST IR 8547 (Post-Quantum Cryptography transition guidance)—require organizations to maintain machine-readable inventories of software components via Software Bills of Materials (SBOMs) and cryptographic assets via Cryptographic Bills of Materials (CBOMs).

Without automated, continuous generation and verification embedded directly into continuous integration (CI):
1. Third-party library dependencies (Python Flask, cryptography, Docker base images) risk untracked vulnerabilities.
2. Cryptographic assets (RSA keys, X.509 certificates, hash algorithms, cipher suites) lack machine-readable cataloging.
3. As post-quantum cryptography standards evolve (NIST FIPS 203, 204, 205), identifying quantum-vulnerable public key algorithms (e.g., classical RSA-2048/4096 used in CSRs and mTLS) requires manual, error-prone audits.
4. Supply chain consumers lack verifiable SBOM and CBOM artifacts for downstream attestation.

### Current Situation

Prior to this decision, the `conjur-demo` repository had automated testing and docker publishing workflows, but:
1. No automated CI pipeline existed to continuously generate, validate, and publish SBOMs or CBOMs upon code commits or tag releases.
2. Cryptographic posture assessments were manual, lacking source code AST call-site analysis for cryptographic key generation and protocol usage.
3. No automated validation gates existed to detect schema invalidity or inventory drift.
4. Downstream artifacts lacked automated PQC migration readiness reporting published back into project governance documentation.

### Decision Drivers

- **Cryptographic Visibility & PQC Transition:** Continuous identification of quantum-vulnerable algorithms (e.g. RSA, classical DH/ECDH) in workload identity and mTLS services to plan PQC migration paths (e.g. ML-KEM, ML-DSA).
- **Regulatory & Compliance Alignment:** Adherence to EO 14028, NTIA minimum SBOM elements, NIST SSDF, and CycloneDX/SPDX industry standards.
- **Continuous Verification:** Strict gatekeeping in CI to ensure valid JSON schema, non-empty bills of materials, and verifiable component inventories.
- **Dual-Engine Standard Interoperability:** Support for both SPDX (v2.3) and CycloneDX (v1.5/1.6) formats to facilitate integration across diverse enterprise vulnerability scanners and policy engines.
- **Zero-Friction Developer Experience:** Automated scripts for local developer invocation mirroring CI workflows.

---

## Assumptions

- The repository contains container configurations, Python application source code, and shell scripts managing certificate lifecycles.
- The build environment supports Python 3.11+ and GitHub Actions runner environments executing Node 24 compliant actions.
- Post-Quantum Cryptography transition will require visibility across both software dependencies and internal source code call sites over the next multi-year migration window.

---

## Constraints

- GitHub Actions execution limits: CI workflows must run within standard runner resource constraints without adding prohibitive build latency (< 3-5 minutes).
- Minimal external infrastructure requirements: Tooling must execute locally via standard bash/python scripts without requiring paid proprietary SaaS scanners.
- Action pinning: All workflow actions must adhere to immutability standards with SHA-pinned actions running on Node 24 runtimes.

---

## Alternatives Considered

| Option | Advantages | Disadvantages / Risks | Disposition |
|---|---|---|---|
| **Option 1: Status Quo (Ad-hoc Manual Audits)** | Zero pipeline overhead; no additional CI execution time. | High operational risk; bills of materials drift out of sync; no automated regression blocking; zero compliance auditability. | **Rejected** |
| **Option 2: Single-Tool SBOM Generation (Syft Only)** | Simple workflow; fast generation of CycloneDX and SPDX SBOMs. | Fails to detect cryptographic assets, certificates, or protocol configurations; no CBOM generation; no PQC readiness assessment. | **Rejected** |
| **Option 3: cbomkit-only Generation** | Captures cryptographic assets in CycloneDX format. | Omits SPDX SBOM generation required by certain enterprise procurement systems; lacks semantic AST call-site correlation. | **Rejected** |
| **Option 4: Integrated Dual-Engine SBOM/CBOM + AST Analysis + Automated CI Harness (Selected)** | Comprehensive dual-engine coverage (Anchore/Syft CycloneDX & SPDX + cbomkit CBOM); deep AST semantic cryptographic call-site discovery (`scan_crypto_ast.py`); automated schema and gate verification (`test_boms.sh`); automatic PQC readiness dashboard generation (`analyze_cbom.py`); fully mirrored local execution scripts. | Slight increase in CI runtime (~60-90s); requires Python runtime setup in CI runner; generates artifacts that must be retained and versioned. | **Selected** |

---

## Decision

### Selected Option

Adopt **Option 4: Integrated Dual-Engine SBOM/CBOM + AST Analysis + Automated CI Harness** across the repository.

Specifically:
1. **GitHub Actions Workflow (`.github/workflows/sbom-cbom.yml`):**
   - Configured with Node 24 pinned actions (`actions/checkout@v7.0.1`, `anchore/sbom-action@v0.24.2`, `cbomkit/cbomkit-action@v2.3.0`, `actions/setup-python@v5.6.0`, `actions/upload-artifact@v4.6.2`).
   - Generates both CycloneDX JSON (`oss/sbom.cyclonedx.json`) and SPDX JSON (`oss/sbom.spdx.json`) SBOMs via Anchore / Syft.
   - Generates CycloneDX CBOM (`oss/cbom.json`) via `cbomkit`.
   - Runs dual-engine semantic AST cryptographic analysis via `scripts/scan_crypto_ast.py`.
   - Executes validation and test harness via `scripts/test_boms.sh`.
   - Assesses Post-Quantum Cryptography (PQC) readiness and outputs dashboard summaries via `scripts/analyze_cbom.py`.
   - Automatically maintains `docs/security/CRYPTOGRAPHIC_AUDIT.md` and archives BOM artifacts.
2. **Local Tooling Suite (`scripts/`):**
   - `scripts/generate_boms.sh`: Portable CLI script for local generation across source trees or Docker images.
   - `scripts/test_boms.sh`: Strict verification harness testing syntax, CycloneDX schema conformance, and component counts.
   - `scripts/scan_crypto_ast.py`: Python AST walker identifying cryptographic call-sites, key generation, and cipher instantiations.
   - `scripts/analyze_cbom.py`: PQC readiness analysis, algorithm categorization, and Markdown/JSON report generator.
   - `scripts/attach_oci_bom.sh` & `scripts/fetch_oci_cbom.py`: OCI artifact publishing and retrieval utilities.

### Rationale

For a demonstration centered on automated certificate lifecycles and workload identity security, transparent cryptographic governance is essential. By coupling dependency-level SBOM inventory with cryptographic-level CBOM asset tracking and AST call-site analysis, the repository provides end-to-end visibility into all active cryptographic primitives (e.g. RSA keys, X.509 certificates, TLS configurations). Automated testing in CI ensures corrupt, incomplete, or drifting BOMs fail fast prior to release.

---

## Consequences

### Benefits

- **Continuous Compliance:** Instant audit readiness for modern SBOM/CBOM standards across both SPDX and CycloneDX specifications.
- **PQC Migration Visibility:** Real-time visibility into quantum-vulnerable algorithms (RSA, ECC, Diffie-Hellman) across software packages and source code.
- **Automated Verification:** The `test_boms.sh` harness prevents empty or schema-invalid BOMs from being published.
- **Dual Developer & CI Experience:** Developers can run identical verification locally prior to pushing code.

### Trade-offs and Negative Consequences

- **CI Pipeline Latency:** Adds approximately 60-90 seconds to workflow execution time.
- **Maintenance Overhead:** Periodic updates to tool action SHAs and known algorithm catalogs (`known_cbom_catalog.json`) are required as cryptographic standards evolve.
- **Artifact Storage:** Retention of BOM artifacts in GitHub Actions consumes artifact storage quota (mitigated with 90-day retention policy).

### New Constraints

- Repository CI runners must provide Python 3.11+ runtime for AST and analysis scripts.
- GitHub Actions token permissions must grant `contents: write` for automated cryptographic audit report synchronization on `main` branch pushes.

### Follow-on Decisions and Activities

- Configure pull request checks to fail if high-risk deprecated algorithms (e.g., MD5 for digital signatures, DES, RC4) are newly introduced in source call-sites.
- Establish an automated schedule for nightly container image baseline scans (`scripts/generate_boms.sh --scan-os`).
- Integrate OCI cosign / notation attestation signing for generated BOM artifacts in release workflows.

---

## Security, Privacy, and Risk Considerations

- **Integrity & Authenticity:** All workflow dependencies use immutable SHA-256 commit pins to mitigate supply chain tampering of actions.
- **Confidentiality:** Scans inspect public dependencies and cryptographic declarations; no secret keys, private keys, or credentials are embedded in generated BOM artifacts.
- **Supply Chain Traceability:** BOMs link directly to commit SHAs and repository metadata.

---

## Technical Debt Assessment

- **Catalog Maintenance:** The static cryptographic catalog in `scripts/known_cbom_catalog.json` must be reviewed annually against NIST PQC standardization updates.

---

## Review and Lifecycle

- **Review Schedule:** Annual or upon major NIST PQC milestone release.
- **Supersedes:** None (Initial baseline governance record).
- **Superseded By:** None.
