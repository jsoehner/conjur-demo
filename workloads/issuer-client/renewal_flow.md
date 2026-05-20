# Certificate Renewal Flow

1. Read current certificate expiry timestamp
2. Calculate remaining lifetime
3. If remaining lifetime > threshold:
   - Sleep
4. If remaining lifetime <= threshold:
   - Authenticate to Conjur
   - Submit CSR
   - Replace certificate + chain
5. Emit renewal success/failure log