# mTLS Client Workload

## Purpose
Demonstrate outbound mTLS using Conjur-issued certificates.

## Behaviour
- Load certificate and private key from shared volume
- Establish TLS connection with client authentication
- Fail closed if certificate is missing or expired