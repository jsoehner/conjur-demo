#!/bin/bash
# sidecar.sh - Simulates the workload sidecar that handles CSR generation,
# Conjur authentication, certificate signing, and auto-renewal.

set -e

CONJUR_URL=${CONJUR_APPLIANCE_URL}
ACCOUNT=${CONJUR_ACCOUNT}
LOGIN=${CONJUR_AUTHN_LOGIN}
API_KEY=${CONJUR_AUTHN_API_KEY}
SERVICE_NAME=$(echo $LOGIN | awk -F'/' '{print $3}')

CERT_DIR="/certs"
mkdir -p $CERT_DIR

KEY_FILE="$CERT_DIR/tls.key"
CSR_FILE="$CERT_DIR/tls.csr"
CERT_FILE="$CERT_DIR/tls.crt"

# SAN pattern enforced by demo
SAN="spiffe://demo/$SERVICE_NAME"

generate_and_sign() {
    echo "[Sidecar] Generating private key for $SERVICE_NAME..."
    openssl genrsa -out $KEY_FILE 2048 2>/dev/null
    
    echo "[Sidecar] Generating CSR with SAN $SAN..."
    openssl req -new -key $KEY_FILE -out $CSR_FILE \
        -subj "/CN=$SERVICE_NAME" \
        -addext "subjectAltName=URI:$SAN" 2>/dev/null

    echo "[Sidecar] Authenticating to Conjur as $LOGIN..."
    # Get Conjur access token
    LOGIN_ENCODED=${LOGIN//\//%2F}
    TOKEN=$(curl -s -k --request POST "$CONJUR_URL/authn/$ACCOUNT/$LOGIN_ENCODED/authenticate" \
      --header "Content-Type: text/plain" \
      --data-raw "$API_KEY")

    if [ -z "$TOKEN" ]; then
        echo "[Sidecar] Authentication failed!"
        exit 1
    fi

    echo "[Sidecar] Requesting certificate signing from Conjur..."
    # Note: This uses a hypothetical/plugin endpoint for CSR signing in Conjur.
    # In a real setup, this would hit the specific PKI endpoint.
    # We simulate the response here for the sake of the demo, or call the actual API if configured.
    # SECURITY FIX: We now simulate Conjur's PKI engine by using the shared CA.
    # In an Enterprise setup, this would be an API call to Conjur.
    echo "[Sidecar] Signing certificate with Demo CA..."
    SVC_NAME=$(basename $LOGIN)
    openssl x509 -req -in $CSR_FILE -CA /ca/ca.crt -CAkey /ca/ca.key -set_serial $RANDOM -out $CERT_FILE -days 1 -sha256 -extfile <(printf "subjectAltName=URI:$SAN,DNS:$SVC_NAME")
    
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
}

# Initial Issuance
generate_and_sign

# Auto-renewal loop (simulated TTL check)
while true; do
    echo "[Sidecar] Sleeping before renewal check..."
    sleep 3600 # Check every hour
    
    # Check cert expiration
    EXPIRY=$(openssl x509 -enddate -noout -in $CERT_FILE | cut -d= -f2)
    EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
    NOW_EPOCH=$(date +%s)
    TIME_LEFT=$((EXPIRY_EPOCH - NOW_EPOCH))
    
    # If less than 20% of 4 hours (2880 seconds) remains, renew
    if [ $TIME_LEFT -lt 2880 ]; then
        echo "[Sidecar] Certificate nearing expiry. Renewing..."
        generate_and_sign
    fi
done
