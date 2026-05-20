# Conjur Policy Test Cases – Certificate Issuance

## Positive Test Cases

### TC-01: Authorised Workload Requests Certificate
- Identity: demo/workload-a
- Requested SAN: spiffe://demo/workload-a
- TTL: 4h
- Expected Result: Certificate issued

---

## Negative Test Cases

### TC-02: Forbidden SAN
- Identity: demo/workload-a
- Requested SAN: spiffe://prod/admin
- Expected Result: Request denied by policy

### TC-03: Unauthorised Identity
- Identity: dev/workload-x
- Requested SAN: spiffe://demo/workload-x
- Expected Result: Request denied (identity not in demo-workloads)

---

## Control Objective
Validate that certificate issuance is authorised by **identity + policy**, not by possession of network access.