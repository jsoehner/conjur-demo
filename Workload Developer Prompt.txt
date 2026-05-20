
Provide pseudocode (or language-agnostic steps) for a sidecar that:
1) generates an RSA/ECDSA key,
2) builds a CSR with SAN spiffe://demo/<service>,
3) requests signing from Conjur,
4) stores key+cert+chain on disk,
5) renews when remaining lifetime < 20%.
Also provide minimal mTLS client/server config steps to prove connectivity.
Return: workloads/issuer-client/README.md + renewal_flow.md

