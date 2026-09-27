## Summary
<!-- Provide a concise description of the purpose of this PR -->

## Type of Change
- [ ] 🚀 `feat`: New feature or capability
- [ ] 🐛 `fix`: Bug fix
- [ ] 🛡️ `security`: Security patch, vulnerability mitigation, or secret handling
- [ ] ♻️ `refactor`: Code refactoring without behavior modification
- [ ] 📝 `docs`: Documentation updates
- [ ] 🧪 `test`: New or updated tests / verification scripts
- [ ] 🔧 `chore`: CI/CD, build, dependency, or repository governance update

---

## Detailed Description
<!-- Explain what was changed, architectural reasoning, and trade-offs considered -->

---

## Testing & Verification Performed
<!-- Detail tests executed locally or in containerized environments -->
- [ ] Local build and startup tested (`bash init.sh` or `./docker-run.sh`)
- [ ] Dual-engine BOM verification passed (`bash scripts/test_boms.sh oss`)
- [ ] Container log inspection (`docker compose logs -f`)

---

## Security & Cryptographic Impact
<!-- Declare any cryptographic or security-sensitive changes -->
- **Cryptographic Primitives Touched**: (e.g., RSA, ECDSA, AES-256, ML-KEM, None)
- **PQC Migration Impact**: (e.g., Classical asymmetric retained, Post-quantum hybrid introduced, N/A)
- **Secret Management**: Does this introduce, access, or rotate any credentials/tokens in Conjur?

---

## Checklist
- [ ] My commits conform to [Conventional Commits](CONTRIBUTING.md#commit-message-guidelines).
- [ ] My code adheres to defensive scripting practices.
- [ ] I have updated documentation and comments where relevant.
- [ ] All CI checks and security gates pass without warnings.
