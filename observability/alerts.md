# Certificate Lifecycle Alerts

## Alert: Certificate Near Expiry
- Condition: cert_expiry_seconds < 900
- Severity: Warning

## Alert: Renewal Failure
- Condition: cert_renewal_failure_total > 0
- Severity: High

## Rationale
Certificate lifecycle risk is addressed through **early detection**, not emergency renewal.