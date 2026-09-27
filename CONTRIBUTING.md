# Contributing to Conjur Demo

Thank you for your interest in contributing to the **Conjur Demo** project! This repository demonstrates identity-based workload security, mutual TLS (mTLS), automated secrets retrieval via CyberArk Conjur, and cryptographic supply chain governance (SBOM/CBOM).

---

## Code of Conduct
Please ensure a respectful, collaborative, and inclusive environment for all contributors.

---

## How to Contribute

### Reporting Bugs
1. **Check existing issues** to confirm the bug hasn't already been reported.
2. **Open a new issue** with:
   - Reproduction steps
   - Expected vs actual behavior
   - Container logs (`docker compose logs`)
   - Operating system and Docker versions

### Proposing Enhancements
1. Check existing issues and discussions.
2. Open a feature request detailing the security, architectural, or demonstration use case.

### Contributing Code
1. Fork or branch from `main`:
   ```bash
   git checkout -b feat/your-feature-name
   ```
2. Make your changes adhering to style guides and defensive scripting patterns.
3. Test locally with `./docker-run.sh` or `bash init.sh`.
4. Verify supply chain and cryptographic bill of materials:
   ```bash
   bash scripts/generate_boms.sh .
   bash scripts/test_boms.sh oss
   ```
5. Follow **Conventional Commits** for commit messages.
6. Submit a Pull Request targeting `main`.

---

## Development Setup

### Prerequisites
- **Docker Engine** & **Docker Compose** (v2+)
- **Bash 4+**
- **OpenSSL 1.1.1+**
- **Python 3.11+**
- (Optional for local BOM generation) **Syft** and **@cyclonedx/cdxgen**

### Local Quickstart
1. **Clone the repository**:
   ```bash
   git clone https://github.com/jsoehner/conjur-demo.git
   cd conjur-demo
   ```
2. **Initialize and run stack**:
   ```bash
   ./docker-run.sh
   # or
   bash init.sh
   ```
3. **Verify running containers**:
   ```bash
   docker compose ps
   ```

---

## Commit Message Guidelines
We strictly enforce **Conventional Commits**. PRs will be validated via automated CI linting:
- `feat:` A new feature or demonstration capability
- `fix:` A bug fix or security patch
- `docs:` Documentation improvements
- `refactor:` Code refactoring without behavioral changes
- `perf:` Performance optimizations
- `test:` Adding or updating tests and verification suites
- `chore:` Maintenance, dependency bumps, or CI/CD workflow updates

*Example*: `feat(mtls): add dual-engine post-quantum cryptography audit`

---

## Pull Request Process
1. Verify that all container builds succeed without regressions.
2. Ensure cryptographic call sites and dependencies pass `bash scripts/test_boms.sh oss`.
3. Complete all sections of the [Pull Request Template](.github/PULL_REQUEST_TEMPLATE.md).
4. Ensure commits are signed and follow Conventional Commits formatting.
