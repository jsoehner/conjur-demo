#!/bin/bash
# sidecar.sh - Simulates the workload sidecar that handles CSR generation,
# Conjur authentication, certificate signing, and auto-renewal.

# NOTE: Do NOT use 'set -e' at the top level. A renewal failure must not
# terminate the sidecar process — the workload should keep running with its
# current cert and retry on the next cycle.

CONJUR_URL=${CONJUR_APPLIANCE_URL}
ACCOUNT=${CONJUR_ACCOUNT}
LOGIN=${CONJUR_AUTHN_LOGIN}
API_KEY=${CONJUR_AUTHN_API_KEY}
CA_SIGNER_URL=${CA_SIGNER_URL:-http://ca-signer:8000}
SERVICE_NAME=$(echo $LOGIN | awk -F'/' '{print $3}')

CERT_DIR="/certs"
mkdir -p $CERT_DIR

KEY_FILE="$CERT_DIR/tls.key"
CSR_FILE="$CERT_DIR/tls.csr"
CERT_FILE="$CERT_DIR/tls.crt"

# SAN pattern enforced by demo
SAN="spiffe://demo/$SERVICE_NAME"

# Renewal threshold: renew if less than 60 seconds of the 5-minute lifetime remains
RENEWAL_THRESHOLD_SECONDS=60

generate_and_sign() {
    echo "[Sidecar] Generating private key for $SERVICE_NAME..."
    openssl genrsa -out $KEY_FILE.tmp 2048 2>/dev/null

    echo "[Sidecar] Generating CSR with SAN $SAN..."
    openssl req -new -key $KEY_FILE.tmp -out $CSR_FILE \
        -subj "/CN=$SERVICE_NAME" \
        -addext "subjectAltName=URI:$SAN" 2>/dev/null

    echo "[Sidecar] Authenticating to Conjur as $LOGIN..."
    # Get Conjur access token
    LOGIN_ENCODED=${LOGIN//\//%2F}
    TOKEN=$(curl -s --request POST "$CONJUR_URL/authn/$ACCOUNT/$LOGIN_ENCODED/authenticate" \
      --header "Content-Type: text/plain" \
      --data-raw "$API_KEY")

    if [ -z "$TOKEN" ]; then
        echo "[Sidecar] ERROR: Authentication to Conjur failed — token was empty."
        return 1
    fi

    echo "[Sidecar] Requesting certificate signing from CA signer service..."
    TEMP_CERT=$(mktemp)
    HTTP_CODE=$(curl -sS -o "$TEMP_CERT" -w "%{http_code}" \
      --request POST "$CA_SIGNER_URL/sign" \
      --header "Content-Type: application/pem-certificate-request" \
      --header "X-SAN: URI:$SAN" \
      --header "X-Auth-Token: $TOKEN" \
      --data-binary @"$CSR_FILE")

    if [ "$HTTP_CODE" != "200" ]; then
        echo "[Sidecar] Certificate request failed with status $HTTP_CODE"
        cat "$TEMP_CERT"
        rm -f "$TEMP_CERT"
        return 1
    fi

    mv "$TEMP_CERT" "$CERT_FILE"
    mv "$KEY_FILE.tmp" "$KEY_FILE"
    chmod 644 "$CERT_FILE"

    echo "[Sidecar] Certificate received and saved to $CERT_FILE"

    echo "[Sidecar] --- Certificate Attributes ---"
    SUBJECT=$(openssl x509 -in "$CERT_FILE" -noout -subject | sed 's/^subject=//')
    ISSUER=$(openssl x509 -in "$CERT_FILE" -noout -issuer | sed 's/^issuer=//')
    VALID_FROM=$(openssl x509 -in "$CERT_FILE" -noout -startdate | cut -d= -f2)
    VALID_TO=$(openssl x509 -in "$CERT_FILE" -noout -enddate | cut -d= -f2)
    SANS=$(openssl x509 -in "$CERT_FILE" -noout -ext subjectAltName | grep -v "Subject Alternative Name" | tr -d ' \n')
    echo "[Sidecar] Subject : $SUBJECT"
    echo "[Sidecar] Issuer  : $ISSUER"
    echo "[Sidecar] Valid   : $VALID_FROM to $VALID_TO"
    echo "[Sidecar] SANs    : $SANS"
    echo "[Sidecar] ------------------------------"
    return 0
}

# Initial Issuance — retry on startup issues before giving up
MAX_RETRIES=10
RETRY_COUNT=0
until generate_and_sign; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "[Sidecar] ERROR: Initial certificate issuance failed after $MAX_RETRIES attempts. Exiting."
        exit 1
    fi
    echo "[Sidecar] CA signer or Conjur not ready. Retrying initial issuance in 3 seconds ($RETRY_COUNT/$MAX_RETRIES)..."
    sleep 3
done

# Auto-renewal loop — errors are logged and retried next cycle, never fatal.
while true; do
    echo "[Sidecar] Sleeping before renewal check..."
    sleep 5 # Check every 5 seconds

    # BUG FIX: Use 'openssl x509 -checkend' to test expiry within the threshold.
    # This avoids brittle 'date -d' parsing and is portable across GNU/BusyBox.
    if ! openssl x509 -checkend $RENEWAL_THRESHOLD_SECONDS -noout -in "$CERT_FILE" >/dev/null 2>/dev/null; then
        echo "[Sidecar] Certificate will expire within ${RENEWAL_THRESHOLD_SECONDS}s. Renewing..."
        if generate_and_sign; then
            echo "[Sidecar] Renewal SUCCESS."
        else
            echo "[Sidecar] Renewal FAILED. Will retry next cycle. Current cert remains in use."
        fi
    else
        echo "[Sidecar] Certificate is valid. No renewal needed."
    fi
done
