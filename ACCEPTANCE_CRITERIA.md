# Acceptance Criteria – Conjur Certificate Lifecycle Demo

## Overall Objective

The demo is considered successful if it demonstrates **secure, policy‑controlled certificate issuance and automated renewal** using Conjur, with clear evidence of control, failure handling, and auditability.

---

## Functional Acceptance Criteria

### Certificate Issuance
- [ ] A workload can authenticate to Conjur using its assigned identity
- [ ] The workload generates its private key locally
- [ ] The workload submits a PKCS#10 CSR to Conjur
- [ ] Conjur evaluates policy before signing the CSR
- [ ] A signed X.509 certificate and chain are returned
- [ ] The private key is never transmitted to Conjur

---

### Policy Enforcement
- [ ] Certificates are issued only to authorised identities
- [ ] SAN values are restricted by policy
- [ ] Requests with unauthorised SANs are denied
- [ ] Denied requests are logged and auditable

---

### Mutual TLS
- [ ] Two workloads successfully establish an mTLS connection
- [ ] The server validates the client certificate chain
- [ ] The server validates the client SAN identity
- [ ] Connections fail if the certificate is invalid or expired

---

### Certificate Lifetime and Renewal
- [ ] Certificates are issued with a short, clearly visible TTL
- [ ] A renewal process exists and runs automatically
- [ ] Renewal occurs before certificate expiry
- [ ] Renewed certificates are used without service interruption

---

### Identity Disablement (Revocation‑by‑Design)
- [ ] Disabling a Conjur identity prevents certificate renewal
- [ ] Existing certificates remain valid only until expiry
- [ ] After expiry, mTLS connections fail
- [ ] No CRL or OCSP infrastructure is required for the demo

---

### Audit and Observability
- [ ] Certificate issuance events are logged
- [ ] Certificate denial events are logged
- [ ] Renewal attempts (success/failure) are logged
- [ ] Logs can be correlated to workload identity
- [ ] Basic metrics or indicators show certificate expiry status

---

## Non‑Functional Acceptance Criteria

### Security
- [ ] Private keys are generated and stored only by workloads
- [ ] Conjur holds only signing keys
- [ ] Certificate policies are defined as code
- [ ] No hard‑coded secrets are required for issuance

---

### Reliability
- [ ] Renewal failures do not crash workloads
- [ ] Workloads fail closed when certificates expire
- [ ] Demo can be restarted without manual certificate cleanup

---

### Clarity and Narrative
- [ ] Demo can be explained end‑to‑end in ~10 minutes
- [ ] The architectural role of Conjur is clearly stated
- [ ] Limitations of the approach are explicitly acknowledged

---

## Explicit Non‑Goals (Must Remain Out of Scope)

The demo **must not** include:
- Certificate inventory or discovery across environments
- User or device certificate management
- Public CA integration
- CRL or OCSP responder hosting
- Compliance dashboards or regulatory reporting

---

## Final Success Statement

The demo is successful when stakeholders can clearly see:

> **How Conjur enables secure, automated certificate issuance and renewal for workloads — and where it fits (and does not fit) in an enterprise certificate lifecycle strategy.**
``