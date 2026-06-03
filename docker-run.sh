#!/bin/bash
set -e

echo "=== Conjur Demo Docker Run Script ==="

# Check if cleanup is requested
if [ "$1" = "down" ] || [ "$1" = "stop" ] || [ "$2" = "down" ] || [ "$2" = "stop" ]; then
    echo "=== Tearing down Conjur Demo Stack ==="
    docker stop dashboard workload-a workload-b ca-signer conjur database 2>/dev/null || true
    docker rm dashboard workload-a workload-b ca-signer conjur database 2>/dev/null || true
    docker volume rm database_data workload_a_certs workload_b_certs 2>/dev/null || true
    docker network rm conjur-demo_conjur 2>/dev/null || true
    rm -rf certs/*
    echo "Cleaned up all containers, volumes, networks, and certificates."
    exit 0
fi

# 0. Docker Hub Username Resolution (defaulting to jsoehner)
DOCKER_USERNAME="${1:-${DOCKER_USERNAME:-${REGISTRY_OWNER:-jsoehner}}}"

# If username is still not resolved and stdout is a tty, prompt for it
if [ -z "$DOCKER_USERNAME" ]; then
    if [ -t 0 ]; then
        read -p "Enter your Docker Hub Username: " DOCKER_USERNAME
    fi
fi

if [ -z "$DOCKER_USERNAME" ]; then
    echo "Error: Docker Hub username is required."
    echo "Usage: $0 <docker-hub-username> [down]"
    echo "Or set the DOCKER_USERNAME environment variable."
    exit 1
fi

# 1. Platform/Architecture Detection
# Detect if the host is running ARM64 (like Apple Silicon macOS) and enforce --platform linux/amd64 emulation.
PLATFORM_FLAG=""
if [ "$(uname -m)" = "arm64" ] || [ "$(uname -m)" = "aarch64" ]; then
    PLATFORM_FLAG="--platform linux/amd64"
    echo "       -> ARM64 architecture detected. Enabling '$PLATFORM_FLAG' emulation for registry images."
fi

# 2. Cleanup previous state
echo "[0/4] Cleaning up previous state..."
docker stop dashboard workload-a workload-b ca-signer conjur database 2>/dev/null || true
docker rm dashboard workload-a workload-b ca-signer conjur database 2>/dev/null || true
docker volume rm database_data workload_a_certs workload_b_certs 2>/dev/null || true
docker network rm conjur-demo_conjur 2>/dev/null || true
rm -rf certs/*

# Pre-flight: ensure required ports are free before starting anything.
REQUIRED_PORTS=(8080 8443 5001)
echo "[Pre-flight] Checking required ports: ${REQUIRED_PORTS[*]}..."
PORT_CONFLICT=0
for PORT in "${REQUIRED_PORTS[@]}"; do
    if nc -z localhost "$PORT" 2>/dev/null; then
        PORT_CONFLICT=1
        PIDS=$(lsof -nP -i tcp:"$PORT" -sTCP:LISTEN -t 2>/dev/null)
        echo "       -> Port $PORT is in use by PID(s): ${PIDS:-unknown}"
        lsof -nP -i tcp:"$PORT" -sTCP:LISTEN 2>/dev/null | tail -n +2 | \
            awk '{printf "          %s (PID %s)\n", $1, $2}'
        echo "       -> Releasing port $PORT..."
        if [ -n "$PIDS" ]; then
            echo "$PIDS" | xargs kill -9 2>/dev/null || true
        fi
        sleep 1
        if nc -z localhost "$PORT" 2>/dev/null; then
            PROC_NAME=$(lsof -nP -i tcp:"$PORT" -sTCP:LISTEN 2>/dev/null | awk 'NR==2{print $1}')
            echo ""
            echo "ERROR: Port $PORT is still in use and cannot be freed."
            echo "       Process: ${PROC_NAME:-unknown}"
            if [[ "$PROC_NAME" == "ControlCe" || "$PROC_NAME" == "AirPlayXP" ]]; then
                echo ""
                echo "       This is the macOS AirPlay Receiver, which claims port 5000/5001."
                echo "       To free it, go to:"
                echo "         System Settings → General → AirDrop & Handoff → AirPlay Receiver → OFF"
                echo "       Then re-run: bash docker-run.sh"
            else
                echo "       Please stop this process manually and re-run: bash docker-run.sh"
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

# 2. Recreate network and volumes
echo "Recreating network and volumes..."
docker network create conjur-demo_conjur
docker volume create database_data
docker volume create workload_a_certs
docker volume create workload_b_certs

# 3. Pull required images
echo "=== Pulling Images from Docker Hub ==="
for IMG in \
    "postgres:14" \
    "cyberark/conjur:latest" \
    "cyberark/conjur-cli:5" \
    "${DOCKER_USERNAME}/conjur-demo-ca-signer:latest" \
    "${DOCKER_USERNAME}/conjur-demo-workload-a:latest" \
    "${DOCKER_USERNAME}/conjur-demo-workload-b:latest" \
    "${DOCKER_USERNAME}/conjur-demo-dashboard:latest"; do
    echo "       -> Pulling $IMG..."
    docker pull $PLATFORM_FLAG "$IMG"
    done

# 4. Generate a CA for the demo
echo "[1/4] Generating Demo Root CA..."
mkdir -p certs
chmod 755 certs
openssl genrsa -out certs/ca.key 2048 2>/dev/null
openssl req -x509 -new -nodes -key certs/ca.key -sha256 -days 3650 -out certs/ca.crt -subj "/CN=Demo-Root-CA" 2>/dev/null
chmod 644 certs/ca.key certs/ca.crt

# 5. Export variables
export CONJUR_DATA_KEY="$(docker run --rm $PLATFORM_FLAG cyberark/conjur:latest data-key generate)"
export CONJUR_DB_PASSWORD="${CONJUR_DB_PASSWORD:-$(openssl rand -hex 16)}"

# 6. Start the database and Conjur
echo "[2/4] Starting Conjur Infrastructure (Database & Conjur)..."
docker run -d $PLATFORM_FLAG \
  --name database \
  --network conjur-demo_conjur \
  -e POSTGRES_DB=conjur \
  -e POSTGRES_USER=conjur \
  -e POSTGRES_PASSWORD="$CONJUR_DB_PASSWORD" \
  -v database_data:/var/lib/postgresql/data \
  postgres:14

docker run -d $PLATFORM_FLAG \
  --name conjur \
  --network conjur-demo_conjur \
  -p 8080:80 \
  -e DATABASE_URL="postgres://conjur:${CONJUR_DB_PASSWORD}@database/conjur" \
  -e CONJUR_DATA_KEY="$CONJUR_DATA_KEY" \
  -v "$(pwd)/policy:/policy" \
  cyberark/conjur:latest server

echo "       -> Waiting 15 seconds for Conjur database to initialize..."
sleep 15

# 7. Initialize Conjur
echo "[3/4] Initializing Conjur and loading policy..."
# Ensure sensitive files are removed on exit
trap "rm -f admin_data.txt policy/policy_data.json" EXIT

docker exec conjur conjurctl account create demo > admin_data.txt
API_KEY=$(grep "API key for admin" admin_data.txt | awk '{print $5}')
rm -f admin_data.txt

# Run the CLI container to load the policy
docker run --rm -i $PLATFORM_FLAG --network conjur-demo_conjur \
  -e CONJUR_APPLIANCE_URL=http://conjur:80 \
  -e CONJUR_ACCOUNT=demo \
  -v "$(pwd)/policy:/policy" \
  --entrypoint sh \
  cyberark/conjur-cli:5 -c "echo y | conjur init -u https://conjur -a demo && conjur authn login -u admin -p $API_KEY && conjur policy load root /policy/conjur.yml > /policy/policy_data.json"

export WORKLOAD_A_API_KEY=$(grep -A 1 '"id": "demo:host:demo/workload-a"' policy/policy_data.json | grep api_key | awk -F'"' '{print $4}')
export WORKLOAD_B_API_KEY=$(grep -A 1 '"id": "demo:host:demo/workload-b"' policy/policy_data.json | grep api_key | awk -F'"' '{print $4}')

if [ -z "$WORKLOAD_A_API_KEY" ] || [ -z "$WORKLOAD_B_API_KEY" ]; then
    echo "Error: Failed to retrieve API keys for workload-a and workload-b."
    exit 1
fi

# 8. Start the workloads and CA signer
echo "[4/4] Starting CA Signer, Workloads, and Dashboard..."

docker run -d $PLATFORM_FLAG \
  --name ca-signer \
  --network conjur-demo_conjur \
  -e CA_CERT_PATH=/ca/ca.crt \
  -e CA_KEY_PATH=/ca/ca.key \
  -e LISTEN_PORT=8000 \
  -v "$(pwd)/certs:/ca:ro" \
  "${DOCKER_USERNAME}/conjur-demo-ca-signer:latest"

docker run -d $PLATFORM_FLAG \
  --name dockerproxy \
  --network conjur-demo_conjur \
  -e CONTAINERS=1 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  tecnativa/docker-socket-proxy:latest

docker run -d $PLATFORM_FLAG \
  --name workload-b \
  --network conjur-demo_conjur \
  -p 8443:8443 \
  -e CONJUR_APPLIANCE_URL=http://conjur:80 \
  -e CONJUR_ACCOUNT=demo \
  -e CONJUR_AUTHN_LOGIN=host/demo/workload-b \
  -e CONJUR_AUTHN_API_KEY="$WORKLOAD_B_API_KEY" \
  -e CA_SIGNER_URL=https://ca-signer:8000 \
  -v "$(pwd)/certs/ca.crt:/ca/ca.crt:ro" \
  -v workload_b_certs:/certs \
  "${DOCKER_USERNAME}/conjur-demo-workload-b:latest"

docker run -d $PLATFORM_FLAG \
  --name workload-a \
  --network conjur-demo_conjur \
  -e CONJUR_APPLIANCE_URL=http://conjur:80 \
  -e CONJUR_ACCOUNT=demo \
  -e CONJUR_AUTHN_LOGIN=host/demo/workload-a \
  -e CONJUR_AUTHN_API_KEY="$WORKLOAD_A_API_KEY" \
  -e CA_SIGNER_URL=https://ca-signer:8000 \
  -v "$(pwd)/certs/ca.crt:/ca/ca.crt:ro" \
  -v workload_a_certs:/certs \
  "${DOCKER_USERNAME}/conjur-demo-workload-a:latest"

docker run -d $PLATFORM_FLAG \
  --name dashboard \
  --network conjur-demo_conjur \
  -p 5001:5000 \
  -e DOCKER_HOST=tcp://dockerproxy:2375 \
  -v workload_a_certs:/workload_a_certs \
  -v workload_b_certs:/workload_b_certs \
  -v "$(pwd)/certs/ca.crt:/certs/ca.crt:ro" \
  -v "$(pwd)/dashboard/app.py:/dashboard/app.py:ro" \
  "${DOCKER_USERNAME}/conjur-demo-dashboard:latest"

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
echo "    docker logs -f workload-a"
echo "    docker logs -f workload-b"
echo ""
echo "Or open the live visual dashboard in your browser:"
echo ""
echo "    http://localhost:5001"
echo ""
echo "To stop and clean up all containers, volumes, and networks, run:"
echo ""
echo "    bash docker-run.sh down"
echo "=========================================================="
