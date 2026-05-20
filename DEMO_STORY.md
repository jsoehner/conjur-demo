# Demo Story: Conjur as a Certificate Lifecycle Issuance Component

## Purpose

This demonstration shows how **CyberArk Conjur** can be used as a **policy-driven certificate issuer** to support short-lived, automatically renewed X.509 certificates for workload identity and mutual TLS (mTLS).

The demo intentionally focuses on:
- Secure certificate issuance from CSRs
- Strong identity binding and policy enforcement
- Automated renewal as the primary lifecycle control

It explicitly does **not** attempt to demonstrate a full enterprise Certificate Lifecycle Management (CLM) platform.

---

## Problem Statement

Enterprise environments increasingly require:
- Machine‑to‑machine authentication (mTLS)
- Elimination of long‑lived secrets and certificates
- Automation to prevent certificate‑expiry incidents
- Clear ownership and policy‑based control over certificate issuance

Traditional PKI and CLM tooling struggles with:
- High operational overhead (CRLs, OCSP, inventories)
- Fragmented ownership across teams
- Manual or semi‑manual renewal processes

This demo explores whether Conjur can act as a **modern certificate issuance and renewal building block** aligned with Zero Trust and workload identity patterns.

---

## Architectural Positioning

In this demo, Conjur is positioned as:

> **A policy‑controlled, online intermediate CA for short‑lived workload certificates**

Conjur is **not** positioned as:
- A public CA
- A user or device certificate authority
- A full CLM inventory, discovery, or compliance reporting system

---

## Demo Architecture (Logical)

- Two workloads (A and B) run as separate services.
- Each workload has a unique Conjur identity.
- Conjur is configured with a certificate‑signing capability.
- Workloads generate private keys locally and submit CSRs to Conjur.
- Conjur signs CSRs according to policy and returns short‑lived certificates.
- Certificates are used for mutual TLS between workloads.
- A renewal loop automatically refreshes certificates before expiry.

---

## Demo Flow (10‑Minute Walkthrough)

### 1. Identity and Trust Setup
- Show Conjur identities mapped to workloads.
- Show certificate policy defining:
  - Who may request certificates
  - Allowed SAN patterns
  - Maximum certificate lifetime (TTL)

**Key message:** Certificate issuance is an *authorisation problem*, not just a cryptographic one.

---

### 2. Certificate Issuance (CSR → Certificate)
- Workload A:
  - Generates a private key locally
  - Builds a CSR with a constrained SAN (e.g. `spiffe://demo/workload-a`)
  - Authenticates to Conjur
  - Requests certificate signing
- Conjur:
  - Evaluates policy
  - Signs the CSR
  - Returns a short‑lived certificate and chain

**Key message:** Private keys never leave the workload; Conjur enforces policy before signing.

---

### 3. Mutual TLS in Action
- Workload A connects to Workload B using mTLS.
- Workload B validates:
  - Certificate chain
  - SAN identity
  - Certificate validity window

**Key message:** Certificates become workload identity, not just encryption material.

---

### 4. Automated Renewal
- Certificates are issued with a short TTL (hours, not months).
- A renewal process:
  - Monitors remaining lifetime
  - Requests a new certificate before expiry
  - Replaces the certificate without downtime

**Key message:** Renewal replaces manual rotation and reduces reliance on revocation.

---

### 5. Failure and Control Demonstrations
- Policy denial:
  - Attempt to request a certificate with an unauthorised SAN
  - Request is denied by Conjur
- Identity disablement:
  - Disable a Conjur identity
  - Renewal fails
  - Certificate naturally expires
  - mTLS connection fails

**Key message:** Control is exercised through identity and policy, not CRLs.

---

### 6. Audit and Evidence
- Show Conjur audit logs for:
  - Certificate issuance
  - Denied requests
  - Renewal attempts
- Show simple metrics:
  - Certificate expiry countdown
  - Renewal success/failure

**Key message:** Governance and visibility come from logs and telemetry, not certificate inventories.

---

## Security Model Summary

| Area | Demo Approach |
|-----|--------------|
| Key management | Client‑side key generation only |
| Certificate lifetime | Short‑lived |
| Renewal | Fully automated |
| Revocation | By identity disablement + expiry |
| Authorisation | Policy‑as‑code |
| Auditability | Centralised logs |

---

## What This Demo Proves

- Conjur can safely issue workload certificates from CSRs
- Policy‑driven certificate authorisation is practical
- Short‑lived certificates + automation reduce operational risk
- Certificate lifecycle can be simplified for internal workloads

---

## What This Demo Does NOT Prove

- End‑user certificate lifecycle management
- Device certificate management
- Enterprise‑wide certificate discovery
- Regulatory reporting or CRL/OCSP distribution

---

## Intended Takeaway

> **Conjur is not a full CLM platform — but it is a strong, modern building block for certificate issuance and renewal when workloads, automation, and short‑lived credentials are the primary design goals.**
