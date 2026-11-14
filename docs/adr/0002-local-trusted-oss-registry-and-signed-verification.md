# ADR-0002: Local Trusted OSS Registry Integration and Signed Artifact Verification

## Metadata

| Field | Value |
|---|---|
| ADR ID | ADR-0002 |
| Status | Accepted |
| Created Date | 2026-11-14 |
| Decision Date | 2026-11-14 |
| Effective Date | 2026-11-14 |
| Architecture Domain | Security / Supply Chain Governance / Cryptography / DevOps |
| Scope | Local Developer Builds, Container Builds, and Python OSS Dependency Verification |
| Decision Owner | Lead DevSecOps Architect |
| Named Decision Maker | DevSecOps Engineering & Security Architecture Team |
| Tags | oss-registry, supply-chain, gpg, ml-dsa-65, pqc, signature-verification, docker, uv, pip |

---

## Context and Problem Statement

While [ADR-0001](0001-automated-sbom-cbom-supply-chain-governance.md) established automated SBOM/CBOM generation and PQC auditing, local Python and Docker builds still pulled third-party open-source software (OSS) dependencies directly from public upstream registries without verifying cryptographic signatures against an organization-controlled trust anchor.

At the same time, GitHub Actions CI runners do not yet have confirmed external network access to the self-hosted Trusted OSS registry, so any local registry integration must:
1. Work seamlessly for local development and container builds when configured.
2. Never commit or upload private internal registry endpoints or local cache state to GitHub.
3. Preserve standard upstream PyPI fallback in Dockerfiles and CI workflows until external GitHub runner access is confirmed.
4. Handle transient failures gracefully when the Trusted OSS registry is actively fetching, scanning, and signing a newly requested artifact.

---

## Decision

1. **Gitignored Local Registry & Caching Configuration:**
   - Local endpoint configurations (`uv.toml`, `pip.conf`, `.oss/`, `.oss-cache/`, and `docker-compose.override.yml`) are excluded via `.gitignore` so private internal registry URLs and cached artifacts/keys are never committed or pushed.
   - Local developer environments configure `uv`, `pip`, and `docker compose` to pull Python OSS components exclusively from the local trusted PyPI index (`/pypi/trusted/simple`).

2. **Non-Intrusive Dockerfile Build-Arg Support:**
   - `dashboard/Dockerfile`, `workloads/ca-signer/Dockerfile`, and `workloads/mtls-client/Dockerfile` accept optional `OSS_PIP_INDEX_URL` and `OSS_PIP_TRUSTED_HOST` build arguments.
   - When set locally (e.g., via `docker-compose.override.yml`), `pip install` routes through the trusted registry. When unset (e.g., in GitHub Actions or standard builds), Dockerfiles fall back to default upstream PyPI without requiring internal network access.

3. **Client-Side Signed Verification with Retry Support (`scripts/verify_oss_signatures.py`):**
   - `scripts/verify_oss_signatures.py` resolves the local OSS registry URL from `--oss-url`, `OSS_REGISTRY_URL`, `.oss/oss.env`, `uv.toml`, or `pip.conf` without hardcoding internal hostnames in tracked source code.
   - Public keys (`trusted-oss-pubkey.asc` and `trusted-oss-mldsa65.pub`) are cached locally in `.oss-cache/keys/` and imported into an isolated GPG keyring (`.oss-cache/gnupg/`).
   - Every Python dependency wheel is downloaded from `/pypi/trusted/simple` and verified against its detached `.asc` GPG signature (and `.mldsa65` NIST FIPS 204 ML-DSA-65 signature when `dilithium-py` is installed).
   - Transient failures during key fetch, `pip download`, or `.asc`/`.mldsa65` retrieval trigger a configurable retry loop (`--retries`, `--retry-delay`) to accommodate asynchronous scanning and signing on the registry.

---

## Consequences

### Positive
- Local builds and verification gates enforce cryptographic provenance (GPG + ML-DSA-65) on all OSS Python dependencies before use.
- Zero private hostnames, endpoints, or cached artifacts are exposed in Git history or GitHub.
- GitHub Actions workflows remain unaffected until external connectivity to the Trusted OSS registry is confirmed.

### Negative / Trade-offs
- Local developers must create gitignored config files (`.oss/oss.env`, `uv.toml`, `pip.conf`, `docker-compose.override.yml`) to opt into the local trusted registry.
- Client-side ML-DSA-65 verification requires `dilithium-py`; when absent, the script still enforces GPG verification and checks for `.mldsa65` signature presence.
