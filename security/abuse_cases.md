# Security Abuse Cases – Certificate Issuance

## AC-01: SAN Escalation Attempt
- Attempt: Request SAN outside demo namespace
- Expected Result: Policy denial

## AC-02: Identity Disablement
- Action: Disable workload identity
- Expected Result:
  - Renewal fails
  - Existing cert expires
  - mTLS connection fails

## AC-03: Private Key Exfiltration Attempt
- Attempt: Access private key from another workload
- Expected Result: Access denied by filesystem / container isolation