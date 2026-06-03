#!/bin/bash
set -e

echo "=== Conjur Demo Initialization ==="

# 0. Cleanup previous state
echo "[0/4] Cleaning up previous state..."
echo "       -> Tearing down existing containers, networks, and volumes to ensure a clean slate."
docker compose down -v 2>/dev/null || true
docker volume rm conjur-demo_database_data conjur-demo_workload_a_certs conjur-demo_workload_b_certs 2>/dev/null || true
rm -rf certs/*

# Pre-flight: ensure required ports are free before starting anything.
# -n  = skip hostname resolution (prevents lsof hanging on DNS lookups)
# -P  = skip port-name resolution (prevents lsof hanging on /etc/services lookups)
# NOTE: Port 5001 is used for the dashboard (avoids macOS AirPlay Receiver on port 5000).
REQUIRED_PORTS=(8080 8443 5001)
echo "[Pre-flight] Checking required ports: ${REQUIRED_PORTS[*]}..."
PORT_CONFLICT=0
for PORT in "${REQUIRED_PORTS[@]}"; do
    # Use nc for a fast non-blocking check first; only call lsof if the port is actually busy.
    if nc -z localhost "$PORT" 2>/dev/null; then
        PORT_CONFLICT=1
        # -nP suppresses slow DNS + port-name lookups so lsof returns immediately.
        PIDS=$(lsof -nP -i tcp:"$PORT" -sTCP:LISTEN -t 2>/dev/null)
        echo "       -> Port $PORT is in use by PID(s): ${PIDS:-unknown}"
        lsof -nP -i tcp:"$PORT" -sTCP:LISTEN 2>/dev/null | tail -n +2 | \
            awk '{printf "          %s (PID %s)\n", $1, $2}'
        echo "       -> Releasing port $PORT..."
        if [ -n "$PIDS" ]; then
            echo "$PIDS" | xargs kill -9 2>/dev/null || true
        fi
        # Brief wait to allow OS to release the socket
        sleep 1
        # Verify it's actually free now
        if nc -z localhost "$PORT" 2>/dev/null; then
            # Identify whether this is a system process we cannot kill
            PROC_NAME=$(lsof -nP -i tcp:"$PORT" -sTCP:LISTEN 2>/dev/null | awk 'NR==2{print $1}')
            echo ""
            echo "ERROR: Port $PORT is still in use and cannot be freed."
            echo "       Process: ${PROC_NAME:-unknown}"
            if [[ "$PROC_NAME" == "ControlCe" || "$PROC_NAME" == "AirPlayXP" ]]; then
                echo ""
                echo "       This is the macOS AirPlay Receiver, which claims port 5000/5001."
                echo "       To free it, go to:"
                echo "         System Settings → General → AirDrop & Handoff → AirPlay Receiver → OFF"
                echo "       Then re-run: bash init.sh"
            else
                echo "       Please stop this process manually and re-run: bash init.sh"
            fi
            echo ""
            exit 1
        fi
        echo "       -> Port $PORT is now free."
    else
        echo "       -> Port $PORT is free. ✓"
    fi
done
if [ "$PORT_CONFLICT" -eq 1 ]; then
    echo "[Pre-flight] Port conflicts resolved."
else
    echo "[Pre-flight] All ports are available."
fi

# 1. Generate a CA for the demo
echo "[1/4] Generating Demo Root CA..."
echo "       -> Creating a local Root Certificate Authority."
echo "       -> The Root CA simulates an enterprise CA that Conjur will use to sign workload certificates."
mkdir -p certs
chmod 755 certs
openssl genrsa -out certs/ca.key 2048 2>/dev/null
openssl req -x509 -new -nodes -key certs/ca.key -sha256 -days 3650 -out certs/ca.crt -subj "/CN=Demo-Root-CA" 2>/dev/null
chmod 600 certs/ca.key
chmod 644 certs/ca.crt

# 2. Export variables for docker compose
export CONJUR_DATA_KEY="$(docker run --rm cyberark/conjur:latest data-key generate)"
export CONJUR_DB_PASSWORD="${CONJUR_DB_PASSWORD:-$(openssl rand -hex 16)}"

# Start the database and Conjur
echo "[2/4] Starting Conjur Infrastructure..."
echo "       -> Spinning up the PostgreSQL database and Conjur OSS container."
docker compose up -d database conjur
sleep 15 # Wait for DB to be ready

# 3. Initialize Conjur
echo "[3/4] Initializing Conjur and loading policy..."
echo "       -> Creating the 'demo' account."
echo "       -> Loading policy/conjur.yml to define host identities, CA permissions, and restrictions."
docker compose exec -T conjur conjurctl account create demo > admin_data.txt
API_KEY=$(grep "API key for admin" admin_data.txt | awk '{print $5}')

# BUG FIX: Remove admin_data.txt immediately after extracting the API key so it
# is never accidentally committed or left on disk.
rm -f admin_data.txt

# Use the CLI container to load the policy
docker run --rm -i --network conjur-demo_conjur \
  -e CONJUR_APPLIANCE_URL=http://conjur:80 \
  -e CONJUR_ACCOUNT=demo \
  -v $(pwd)/policy:/policy \
  --entrypoint sh \
  cyberark/conjur-cli:5 -c "echo y | conjur init -u http://conjur:80 -a demo && conjur authn login -u admin -p $API_KEY && conjur policy load root /policy/conjur.yml > /policy/policy_data.json"

# Extract Workload API Keys
export WORKLOAD_A_API_KEY=$(grep -A 1 '"id": "demo:host:demo/workload-a"' policy/policy_data.json | grep api_key | awk -F'"' '{print $4}')
export WORKLOAD_B_API_KEY=$(grep -A 1 '"id": "demo:host:demo/workload-b"' policy/policy_data.json | grep api_key | awk -F'"' '{print $4}')

# BUG FIX: Remove policy_data.json immediately after extracting the API keys so they
# are never accidentally committed or left on disk.
rm -f policy/policy_data.json

# 4. Start the workloads and CA signer
echo "[4/4] Building and starting Workloads..."
echo "       -> This step launches the client (Workload A) and server (Workload B)."
echo "       -> Both workloads use a sidecar to independently generate a private key and CSR."
echo "       -> The sidecars authenticate with Conjur and receive signed X.509 certificates."
docker compose up -d --build workload-a workload-b dashboard

echo ""
echo "=========================================================="
echo "          🚀 Demo Initialized Successfully! 🚀          "
echo "=========================================================="
echo ""
echo "The CyberArk Conjur environment is now running and policy is enforced."
echo "Both workloads have securely obtained their certificates and are now communicating."
echo "Workload A (Client) is actively making mTLS requests to Workload B (Server)."
echo ""
echo "To observe the mTLS traffic in action and view the sidecar certificate logic, run:"
echo ""
echo "    docker compose logs -f workload-a workload-b"
echo ""
echo "Or open the live visual dashboard in your browser:"
echo ""
echo "    http://localhost:5001"
echo ""
echo "Press Ctrl+C to stop following the logs when you are done."
echo "=========================================================="