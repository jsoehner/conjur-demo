#!/usr/bin/env bash
# ==============================================================================
# run_docker.sh - Automated Container Runner for Conjur Certificate Lifecycle Demo
# ==============================================================================
# Orchestrates pre-built container images from GitHub Container Registry (ghcr.io)
# or Docker Hub to execute the policy-controlled certificate issuance and mTLS demo.
# ==============================================================================

set -euo pipefail

# Default Configuration
DEFAULT_OWNER="jsoehner"
REGISTRY_TYPE="${REGISTRY_TYPE:-ghcr}" # 'ghcr' or 'dockerhub'
REGISTRY_OWNER="${REGISTRY_OWNER:-$DEFAULT_OWNER}"
ACTION="up"
USE_COMPOSE=false
VERBOSE=false

# ------------------------------------------------------------------------------
# Helpers & UI
# ------------------------------------------------------------------------------
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_info() {
    echo -e "\033[1;34m[INFO]\033[0m $*"
}

log_success() {
    echo -e "\033[1;32m[SUCCESS]\033[0m $*"
}

log_warn() {
    echo -e "\033[1;33m[WARN]\033[0m $*"
}

log_err() {
    echo -e "\033[1;31m[ERROR]\033[0m $*" >&2
}

usage() {
    local exit_code="${1:-0}"
    cat <<EOF
Usage: $(basename "$0") [COMMAND] [OPTIONS]

Commands:
  up        (default) Start the complete Conjur mTLS demo stack
  down      Stop and clean up all containers, volumes, networks, and certificates
  verify    Test and verify active mTLS connection between workloads
  logs      Follow logs from workload-a (client) and workload-b (server)
  status    Display health and status of all demo containers

Options:
  -r, --registry TYPE   Container registry: 'ghcr' (default) or 'dockerhub'
  -u, --user OWNER      Registry owner / namespace (default: ${DEFAULT_OWNER})
  -c, --compose         Run using docker compose (docker-compose.hub.yml)
  -v, --verbose         Enable verbose log output
  -h, --help            Show this help message and exit

Examples:
  $(basename "$0") up --registry ghcr
  $(basename "$0") up --registry dockerhub --user myuser
  $(basename "$0") verify
  $(basename "$0") down
EOF
    exit "$exit_code"
}

# ------------------------------------------------------------------------------
# Argument Parsing
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        up|down|stop|verify|logs|status)
            ACTION="$1"
            if [[ "$ACTION" == "stop" ]]; then
                ACTION="down"
            fi
            shift
            ;;
        -r|--registry)
            REGISTRY_TYPE="$2"
            shift 2
            ;;
        -u|--user)
            REGISTRY_OWNER="$2"
            shift 2
            ;;
        -c|--compose)
            USE_COMPOSE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage 0
            ;;
        -*)
            log_err "Unknown option: $1"
            usage 1
            ;;
        *)
            # Allow positional username or command
            if [[ -z "${REGISTRY_OWNER_OVERRIDE:-}" && "$1" != "up" && "$1" != "down" ]]; then
                REGISTRY_OWNER="$1"
                REGISTRY_OWNER_OVERRIDE=true
                shift
            else
                log_err "Unexpected argument: $1"
                usage 1
            fi
            ;;
    esac
done

# Resolve Image Prefix based on registry
case "$REGISTRY_TYPE" in
    ghcr|ghcr.io)
        IMAGE_PREFIX="ghcr.io/${REGISTRY_OWNER}"
        ;;
    dockerhub|docker.io)
        IMAGE_PREFIX="${REGISTRY_OWNER}"
        ;;
    local)
        IMAGE_PREFIX=""
        ;;
    *)
        IMAGE_PREFIX="${REGISTRY_TYPE}/${REGISTRY_OWNER}"
        ;;
esac

format_img() {
    local name="$1"
    if [[ -z "$IMAGE_PREFIX" ]]; then
        echo "${name}:latest"
    else
        echo "${IMAGE_PREFIX}/${name}:latest"
    fi
}

# ------------------------------------------------------------------------------
# Teardown Action
# ------------------------------------------------------------------------------
teardown() {
    log_info "Tearing down Conjur Demo Stack..."
    if command -v docker &>/dev/null; then
        docker stop dashboard workload-a workload-b ca-signer conjur database dockerproxy 2>/dev/null || true
        docker rm dashboard workload-a workload-b ca-signer conjur database dockerproxy 2>/dev/null || true
        docker volume rm database_data workload_a_certs workload_b_certs conjur-demo_database_data conjur-demo_workload_a_certs conjur-demo_workload_b_certs 2>/dev/null || true
        docker network rm conjur-demo_conjur 2>/dev/null || true
    fi
    rm -rf certs/* .env
    log_success "Cleaned up all containers, volumes, networks, and certificates."
}

if [[ "$ACTION" == "down" ]]; then
    teardown
    exit 0
fi

# ------------------------------------------------------------------------------
# Status Action
# ------------------------------------------------------------------------------
if [[ "$ACTION" == "status" ]]; then
    log_info "Conjur Demo Container Status:"
    docker ps -a --filter "name=conjur|database|workload|ca-signer|dashboard|dockerproxy" \
        --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    exit 0
fi

# ------------------------------------------------------------------------------
# Logs Action
# ------------------------------------------------------------------------------
if [[ "$ACTION" == "logs" ]]; then
    log_info "Streaming logs from workload-a and workload-b (Ctrl+C to stop)..."
    exec docker logs -f workload-a
fi

# ------------------------------------------------------------------------------
# Verify Action
# ------------------------------------------------------------------------------
verify_mtls() {
    log_info "Verifying mutual TLS (mTLS) connectivity between workloads..."
    local attempts=15
    local interval=2
    local success=false

    for ((i=1; i<=attempts; i++)); do
        local client_logs
        client_logs=$(docker logs workload-a 2>&1 || true)
        if echo "$client_logs" | grep -q "mTLS connection successful"; then
            success=true
            break
        fi
        log "Waiting for sidecars to provision certificates and establish mTLS (attempt ${i}/${attempts})..."
        sleep "$interval"
    done

    if [[ "$success" == "true" ]]; then
        log_success "Verification Succeeded! Workload A established mTLS with Workload B."
        echo ""
        docker logs --tail 10 workload-a
        return 0
    else
        log_err "Verification Failed: mTLS connection was not observed in client logs."
        docker logs --tail 25 workload-a
        return 1
    fi
}

if [[ "$ACTION" == "verify" ]]; then
    verify_mtls
    exit $?
fi

# ------------------------------------------------------------------------------
# Start Stack (Action: 'up')
# ------------------------------------------------------------------------------
log_info "=================================================================="
log_info " 🚀 Starting Conjur Certificate Lifecycle & mTLS Demo"
log_info "    Registry: ${IMAGE_PREFIX:-local}"
log_info "    Mode:     ${ACTION}"
log_info "=================================================================="

# Check docker daemon
if ! docker info &>/dev/null; then
    log_err "Docker daemon is not running or accessible. Please start Docker and retry."
    exit 1
fi

# Platform / Architecture Detection (Apple Silicon ARM64 compatibility)
PLATFORM_FLAG=()
if [[ "$(uname -m)" == "arm64" || "$(uname -m)" == "aarch64" ]]; then
    PLATFORM_FLAG=(--platform "linux/amd64")
    log_info "ARM64 host detected. Enabling '--platform linux/amd64' for compatible images."
fi

# Cleanup previous state
teardown

# Pre-flight: Check required ports (8080, 8443, 5001)
REQUIRED_PORTS=(8080 8443 5001)
for PORT in "${REQUIRED_PORTS[@]}"; do
    if command -v nc &>/dev/null && nc -z localhost "$PORT" 2>/dev/null; then
        log_warn "Port ${PORT} is currently in use. Attempting to free..."
        PIDS=$(lsof -nP -i tcp:"$PORT" -sTCP:LISTEN -t 2>/dev/null || true)
        if [[ -n "$PIDS" ]]; then
            echo "$PIDS" | xargs kill -9 2>/dev/null || true
            sleep 1
        fi
        if nc -z localhost "$PORT" 2>/dev/null; then
            log_err "Port ${PORT} is still occupied. Please terminate the conflicting process."
            exit 1
        fi
    fi
done
log_success "All required ports (8080, 8443, 5001) are free."

# If user requested Compose mode, delegate to docker compose
if [[ "$USE_COMPOSE" == "true" ]]; then
    log_info "Launching stack via docker compose..."
    if [[ "$REGISTRY_TYPE" == "ghcr" || "$REGISTRY_TYPE" == "ghcr.io" ]]; then
        export REGISTRY_OWNER="ghcr.io/${REGISTRY_OWNER}"
    else
        export REGISTRY_OWNER="${REGISTRY_OWNER}"
    fi
    docker compose -f docker-compose.hub.yml up -d
    verify_mtls
    exit 0
fi

# Native Docker Orchestration
echo ""
log_info "[1/5] Recreating network and storage volumes..."
docker network create conjur-demo_conjur
docker volume create database_data
docker volume create workload_a_certs
docker volume create workload_b_certs

# 2. Pull images
log_info "[2/5] Pulling pre-built images..."
CORE_IMAGES=(
    "postgres:14"
    "cyberark/conjur:latest"
    "cyberark/conjur-cli:5"
    "tecnativa/docker-socket-proxy:latest"
)
DEMO_IMAGES=(
    "$(format_img conjur-demo-ca-signer)"
    "$(format_img conjur-demo-workload-a)"
    "$(format_img conjur-demo-workload-b)"
    "$(format_img conjur-demo-dashboard)"
)

for IMG in "${CORE_IMAGES[@]}" "${DEMO_IMAGES[@]}"; do
    log "  -> Pulling ${IMG}..."
    docker pull "${PLATFORM_FLAG[@]}" "$IMG" || {
        log_warn "Could not pull $IMG from remote registry. Attempting local build fallback if available..."
    }
done

# 3. Generate CA for the demo
log_info "[3/5] Generating Demo Root CA with strict security permissions..."
mkdir -p certs
chmod 755 certs
openssl genrsa -out certs/ca.key 2048 2>/dev/null
openssl req -x509 -new -nodes -key certs/ca.key -sha256 -days 3650 -out certs/ca.crt -subj "/CN=Demo-Root-CA" -addext "subjectAltName=DNS:ca-signer,DNS:localhost,IP:127.0.0.1" 2>/dev/null
chmod 600 certs/ca.key
chmod 644 certs/ca.crt
log_success "Demo Root CA generated (ca.key secured with chmod 600)."

# Export variables
export CONJUR_DATA_KEY="$(docker run --rm "${PLATFORM_FLAG[@]}" cyberark/conjur:latest data-key generate)"
export CONJUR_DB_PASSWORD="${CONJUR_DB_PASSWORD:-$(openssl rand -hex 16)}"

# 4. Start Infrastructure
log_info "[4/5] Starting Database and Conjur Server..."
docker run -d "${PLATFORM_FLAG[@]}" \
  --name database \
  --network conjur-demo_conjur \
  -e POSTGRES_DB=conjur \
  -e POSTGRES_USER=conjur \
  -e POSTGRES_PASSWORD="$CONJUR_DB_PASSWORD" \
  -v database_data:/var/lib/postgresql/data \
  postgres:14

docker run -d "${PLATFORM_FLAG[@]}" \
  --name conjur \
  --network conjur-demo_conjur \
  -p 8080:80 \
  -e OPENSSL_FIPS="0" \
  -e DATABASE_URL="postgres://conjur:${CONJUR_DB_PASSWORD}@database/conjur" \
  -e CONJUR_DATA_KEY="$CONJUR_DATA_KEY" \
  -v "$(pwd)/policy:/policy:ro" \
  cyberark/conjur:latest \
  server

log "Waiting for Conjur server to reach healthy state..."
CONJUR_READY=0
for i in {1..30}; do
  if curl -s -f -o /dev/null http://localhost:8080/health 2>/dev/null; then
    CONJUR_READY=1
    break
  fi
  sleep 2
done

if [[ "$CONJUR_READY" -ne 1 ]]; then
  log_err "Conjur server failed to start within 60 seconds."
  docker logs conjur
  exit 1
fi
log_success "Conjur server is healthy."

# Initialize Conjur Account
log "Initializing Conjur 'demo' account..."
docker exec conjur conjurctl account create demo > /dev/null 2>&1 || true

# Authenticate Conjur CLI & Load Policy
CONJUR_ADMIN_KEY=$(docker exec conjur conjurctl role retrieve-key demo:user:admin)
docker run --rm -i "${PLATFORM_FLAG[@]}" --network conjur-demo_conjur \
  -e CONJUR_AUTHN_LOGIN=admin \
  -e CONJUR_AUTHN_API_KEY="$CONJUR_ADMIN_KEY" \
  cyberark/conjur-cli:5 \
  init -u http://conjur -a demo > /dev/null 2>&1

docker run --rm -i "${PLATFORM_FLAG[@]}" --network conjur-demo_conjur \
  -v "$(pwd)/policy:/policy:ro" \
  -e CONJUR_AUTHN_LOGIN=admin \
  -e CONJUR_AUTHN_API_KEY="$CONJUR_ADMIN_KEY" \
  cyberark/conjur-cli:5 \
  policy load root /policy/policy.yml > policy/policy_data.json

export WORKLOAD_A_API_KEY=$(grep -A 1 '"id": "demo:host:demo/workload-a"' policy/policy_data.json | grep api_key | awk -F'"' '{print $4}')
export WORKLOAD_B_API_KEY=$(grep -A 1 '"id": "demo:host:demo/workload-b"' policy/policy_data.json | grep api_key | awk -F'"' '{print $4}')
rm -f policy/policy_data.json

# Write .env for session persistence
cat <<EOF > .env
CONJUR_DATA_KEY=${CONJUR_DATA_KEY}
CONJUR_DB_PASSWORD=${CONJUR_DB_PASSWORD}
WORKLOAD_A_API_KEY=${WORKLOAD_A_API_KEY}
WORKLOAD_B_API_KEY=${WORKLOAD_B_API_KEY}
REGISTRY_OWNER=${REGISTRY_OWNER}
EOF

# 5. Start Workloads
log_info "[5/5] Launching CA Signer, Workloads, and Dashboard..."
docker run -d "${PLATFORM_FLAG[@]}" \
  --name ca-signer \
  --network conjur-demo_conjur \
  -e CA_CERT_PATH=/ca/ca.crt \
  -e CA_KEY_PATH=/ca/ca.key \
  -e LISTEN_PORT=8000 \
  -v "$(pwd)/certs:/ca:ro" \
  "$(format_img conjur-demo-ca-signer)"

docker run -d "${PLATFORM_FLAG[@]}" \
  --name workload-b \
  --network conjur-demo_conjur \
  -p 8443:8443 \
  -e CONJUR_APPLIANCE_URL=http://conjur:80 \
  -e CONJUR_ACCOUNT=demo \
  -e CONJUR_AUTHN_LOGIN=host/demo/workload-b \
  -e CONJUR_AUTHN_API_KEY="$WORKLOAD_B_API_KEY" \
  -e CA_SIGNER_URL=https://ca-signer:8000 \
  -v "$(pwd)/certs:/ca:ro" \
  -v workload_b_certs:/certs \
  "$(format_img conjur-demo-workload-b)"

docker run -d "${PLATFORM_FLAG[@]}" \
  --name workload-a \
  --network conjur-demo_conjur \
  -e CONJUR_APPLIANCE_URL=http://conjur:80 \
  -e CONJUR_ACCOUNT=demo \
  -e CONJUR_AUTHN_LOGIN=host/demo/workload-a \
  -e CONJUR_AUTHN_API_KEY="$WORKLOAD_A_API_KEY" \
  -e CA_SIGNER_URL=http://ca-signer:8000 \
  -v "$(pwd)/certs:/ca:ro" \
  -v workload_a_certs:/certs \
  "$(format_img conjur-demo-workload-a)"

docker run -d \
  --name dockerproxy \
  --network conjur-demo_conjur \
  -e CONTAINERS=1 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  tecnativa/docker-socket-proxy:latest

docker run -d "${PLATFORM_FLAG[@]}" \
  --name dashboard \
  --network conjur-demo_conjur \
  -p 5001:5000 \
  -e DOCKER_HOST=tcp://dockerproxy:2375 \
  -v workload_a_certs:/workload_a_certs:ro \
  -v workload_b_certs:/workload_b_certs:ro \
  -v "$(pwd)/certs:/certs:ro" \
  "$(format_img conjur-demo-dashboard)"

echo ""
log_success "All services are up and running!"
echo "  • Conjur UI / Health:  http://localhost:8080/health"
echo "  • Workload B (mTLS):   https://localhost:8443"
echo "  • Demo Web Dashboard:  http://localhost:5001"
echo ""

verify_mtls
