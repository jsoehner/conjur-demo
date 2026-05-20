#!/bin/bash
set -e

echo "=== Conjur Demo Initialization ==="

# Cleanup previous state
echo "[0/4] Cleaning up previous state..."
echo "       -> Tearing down existing containers, networks, and volumes to ensure a clean slate."
docker-compose down -v
docker volume rm conjur-demo_database_data 2>/dev/null || true
rm -rf certs/*

# 1. Generate a CA for the demo
echo "[1/4] Generating Demo Root CA..."
echo "       -> Creating a local Root Certificate Authority."
echo "       -> The Root CA simulates an enterprise CA that Conjur will use to sign workload certificates."
mkdir -p certs
chmod 777 certs
openssl genrsa -out certs/ca.key 2048 2>/dev/null
openssl req -x509 -new -nodes -key certs/ca.key -sha256 -days 3650 -out certs/ca.crt -subj "/CN=Demo-Root-CA" 2>/dev/null
chmod 644 certs/ca.key certs/ca.crt

# 2. Export variables for docker-compose
export CONJUR_DATA_KEY="$(docker run --rm cyberark/conjur:latest data-key generate)"
export CONJUR_DB_PASSWORD="demo_password123"

# Start the database and Conjur
echo "[2/4] Starting Conjur Infrastructure..."
echo "       -> Spinning up the PostgreSQL database and Conjur OSS container."
docker-compose up -d database conjur
sleep 15 # Wait for DB to be ready

# 3. Initialize Conjur
echo "[3/4] Initializing Conjur and loading policy..."
echo "       -> Creating the 'demo' account."
echo "       -> Loading policy/conjur.yml to define host identities, CA permissions, and restrictions."
docker-compose exec -T conjur conjurctl account create demo > admin_data.txt
API_KEY=$(grep "API key for admin" admin_data.txt | awk '{print $5}')

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

# 4. Start the workloads
echo "[4/4] Building and starting Workloads..."
echo "       -> This step launches the client (Workload A) and server (Workload B)."
echo "       -> Both workloads use a sidecar to independently generate a private key and CSR."
echo "       -> The sidecars authenticate with Conjur and receive signed X.509 certificates."
docker-compose up -d --build workload-a workload-b

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
echo "    docker-compose logs -f workload-a workload-b"
echo ""
echo "Press Ctrl+C to stop following the logs when you are done."
echo "=========================================================="
