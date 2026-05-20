# mTLS Server Workload

## Purpose
Accept inbound mTLS connections from authorised workloads.

## Validation Steps
- Validate certificate chain
- Validate SAN format (spiffe://demo/*)
- Validate certificate validity window

## Failure Behaviour
- Reject expired certificates
- Reject certificates with invalid SANs