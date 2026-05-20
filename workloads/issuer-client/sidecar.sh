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
    TOKEN=$(curl -s -k --request POST "$CONJUR_URL/authn/$ACCOUNT/$LOGIN_ENCODED/authenticate" \
      --header "Content-Type: text/plain" \
      --data-raw "$API_KEY")

    if [ -z "$TOKEN" ]; then
        echo "[Sidecar] ERROR: Authentication to Conjur failed — token was empty."
        return 1
    fi

    echo "[Sidecar] Requesting certificate signing from Conjur..."
    # Note: This uses a hypothetical/plugin endpoint for CSR signing in Conjur.
    # In a real setup, this would hit the specific PKI endpoint.
    # We simulate the response here for the sake of the demo, or call the actual API if configured.
    # SECURITY FIX: We now simulate Conjur's PKI engine by using the shared CA.
    # In an Enterprise setup, this would be an API call to Conjur.
    echo "[Sidecar] Signing certificate with Demo CA (5-minute TTL)..."
    SVC_NAME=$(basename $LOGIN)

    # Use openssl ca to allow specifying exact minute-level expiration
    mkdir -p /tmp/ca/newcerts
    touch /tmp/ca/index.txt
    echo "unique_subject = no" > /tmp/ca/index.txt.attr
    [ -f /tmp/ca/serial ] || echo 01 > /tmp/ca/serial
    cat > /tmp/ca/ca.cnf << 'EOF'
[ ca ]
default_ca = CA_default
[ CA_default ]
dir = /tmp/ca
database = $dir/index.txt
new_certs_dir = /certs
certificate = /ca/ca.crt
private_key = /ca/ca.key
serial = $dir/serial
default_md = sha256
policy = policy_any
[ policy_any ]
countryName = optional
stateOrProvinceName = optional
organizationName = optional
organizationalUnitName = optional
commonName = supplied
emailAddress = optional
EOF

    # Calculate exactly 5 minutes from now in YYMMDDHHMMSSZ format
    ENDDATE=$(date -u -d '+5 minutes' +%y%m%d%H%M%SZ)

    openssl ca -batch -config /tmp/ca/ca.cnf -in $CSR_FILE -out $CERT_FILE.tmp -enddate $ENDDATE \
        -extensions v3_req -extfile <(printf "[v3_req]\nsubjectAltName=URI:$SAN,DNS:$SVC_NAME\n") 2>/dev/null

    # Atomic swap to prevent KEY_VALUES_MISMATCH during hot-reload
    mv $KEY_FILE.tmp $KEY_FILE
    mv $CERT_FILE.tmp $CERT_FILE

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

# Initial Issuance — exit hard if this fails (no cert = nothing to do)
set -e
generate_and_sign
set +e

# Auto-renewal loop — errors are logged and retried next cycle, never fatal.
while true; do
    echo "[Sidecar] Sleeping before renewal check..."
    sleep 5 # Check every 5 seconds

    # BUG FIX: Use 'openssl x509 -checkend' to test expiry within the threshold.
    # This avoids brittle 'date -d' parsing and is portable across GNU/BusyBox.
    if ! openssl x509 -checkend $RENEWAL_THRESHOLD_SECONDS -noout -in "$CERT_FILE" 2>/dev/null; then
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
