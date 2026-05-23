# Abuse Case Plan: Issuance Controls Validation

This document outlines the abuse-case plan to validate certificate issuance controls within the infrastructure.

## 1. Attempt Forbidden SAN
**Objective**: Verify that certificates cannot be issued with an unauthorized Subject Alternative Name (SAN).

**Execution**:
1. Create a `Certificate` or `CertificateRequest` object specifying a SAN that does not match the allowed policy patterns (e.g., `evil.com`, `admin.default.svc.cluster.local`, or an IP address not in the allowed range).
2. Apply the request to the cluster targeting the restricted Issuer/ClusterIssuer.

**Expected Results**:
- The PKI backend (e.g., Vault, Conjur, or CA) must reject the signing request due to policy violations.
- The `Certificate` object in Kubernetes should remain in a `NotReady` or `False` state.

**Evidence Artifacts**:
- Output of `kubectl describe certificate <forbidden-san-cert>` displaying the explicit rejection reason from the CA.
- PKI/CA audit logs capturing the denied CSR and the corresponding policy violation.

---

## 2. Attempt Issuance from Non-Demo Namespace
**Objective**: Validate that namespaces other than the designated allowed namespaces (e.g., `demo`) cannot issue certificates using the restricted PKI infrastructure.

**Execution**:
1. Create a new, unauthorized namespace (e.g., `kubectl create ns unauthorized-test`).
2. Deploy a `Certificate` object in the `unauthorized-test` namespace referencing the protected Issuer/ClusterIssuer.

**Expected Results**:
- The issuance process must fail. 
- Depending on the integration, either cert-manager's RBAC/namespace selectors will block it, or the machine identity authentication from the non-demo namespace to the PKI backend will be denied.

**Evidence Artifacts**:
- Output of `kubectl describe certificate <test-cert> -n unauthorized-test` showing the failure (either RBAC denial or backend auth failure).
- Authentication provider (e.g., Conjur/Vault) audit logs showing an authentication or authorization failure for the unauthorized namespace identity.

---

## 3. Disable Identity and Verify Expiry & Renewal Failure
**Objective**: Ensure that disabling a workload's identity effectively halts automatic certificate renewal, and that mTLS communication fails once the existing certificate naturally expires.

**Execution**:
1. Issue a valid certificate with a very short TTL (e.g., 2 to 5 minutes) for a test workload.
2. Confirm that mTLS communication is successful between the test workload and a peer.
3. Disable, revoke, or delete the test workload's identity in the authentication provider (Conjur/Vault).
4. Monitor the workload as the certificate enters its renewal window.
5. Attempt mTLS communication after the certificate's absolute expiry time.

**Expected Results**:
- `cert-manager`'s automated attempts to renew the certificate must fail because the workload identity is no longer valid.
- Once the original certificate expires, mTLS handshakes must be rejected by peers due to an expired leaf certificate.

**Evidence Artifacts**:
- Output of `kubectl describe certificate <short-lived-cert>` showing continuous renewal failures and authentication errors.
- Application, ingress, or sidecar proxy logs showing mTLS handshake failures (e.g., `certificate expired`).
- Authentication backend logs recording denied login/auth attempts from the disabled machine identity.