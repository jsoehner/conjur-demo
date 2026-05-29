"""
dashboard/app.py – Backend API for the Conjur mTLS Demo Dashboard.

Endpoints:
  GET /api/status          – Health status of all containers
  GET /api/certs           – Certificate details for workload-a and workload-b
  GET /api/logs/stream     – Server-Sent Events stream of live Docker log lines
  GET /                    – Serve the frontend SPA
"""

import os
import re
import json
import subprocess
import threading
import queue
import time
from datetime import datetime, timezone
import docker
from flask import Flask, jsonify, render_template_string, Response, send_from_directory, request

app = Flask(__name__, static_folder="static")

try:
    docker_client = docker.from_env()
except Exception:
    docker_client = None

CERT_DIR = "/certs"
CA_CERT = os.path.join(CERT_DIR, "ca.crt")
WORKLOAD_A_CERT = "/workload_a_certs/tls.crt"
WORKLOAD_B_CERT = "/workload_b_certs/tls.crt"

CONTAINERS = [
    "conjur-demo-workload-a-1",
    "conjur-demo-workload-b-1",
    "conjur-demo-conjur-1",
    "conjur-demo-ca-signer-1",
    "conjur-demo-database-1"
]
CONTAINER_ALIASES = {
    "conjur-demo-workload-a-1": "workload-a",
    "conjur-demo-workload-b-1": "workload-b",
    "conjur-demo-conjur-1": "conjur",
    "conjur-demo-ca-signer-1": "ca-signer",
    "conjur-demo-database-1": "database",
}

# ---------------------------------------------------------------------------
# Metrics State
# ---------------------------------------------------------------------------
metrics_state = {
    "workload-a": {"last_serial": None, "successes": 0, "failures": 0},
    "workload-b": {"last_serial": None, "successes": 0, "failures": 0}
}
metrics_lock = threading.Lock()


# ---------------------------------------------------------------------------
# Helper: run openssl to parse a cert file
# ---------------------------------------------------------------------------
def parse_cert(cert_path):
    if not os.path.exists(cert_path):
        return None
    try:
        def run(args):
            r = subprocess.run(args, capture_output=True, text=True, timeout=5)
            return r.stdout.strip()

        subject = run(["openssl", "x509", "-in", cert_path, "-noout", "-subject"])
        issuer  = run(["openssl", "x509", "-in", cert_path, "-noout", "-issuer"])
        start   = run(["openssl", "x509", "-in", cert_path, "-noout", "-startdate"])
        end     = run(["openssl", "x509", "-in", cert_path, "-noout", "-enddate"])
        serial  = run(["openssl", "x509", "-in", cert_path, "-noout", "-serial"])
        san_raw = run(["openssl", "x509", "-in", cert_path, "-noout", "-ext", "subjectAltName"])

        # Parse expiry epoch using Python's native datetime
        end_val = end.split("=", 1)[1] if "=" in end else end
        try:
            clean_end = end_val.replace("GMT", "").replace("UTC", "").strip()
            clean_end = " ".join(clean_end.split())
            dt = datetime.strptime(clean_end, "%b %d %H:%M:%S %Y").replace(tzinfo=timezone.utc)
            exp_epoch = int(dt.timestamp())
        except Exception:
            exp_epoch = None

        now_epoch = int(time.time())
        seconds_left = (exp_epoch - now_epoch) if exp_epoch else None
        hours_left = round(seconds_left / 3600, 2) if seconds_left is not None else None
        
        # Calculate percentage based on 5-minute lifecycle (300 seconds)
        pct_remaining = None
        if seconds_left is not None:
            pct_remaining = max(0, min(100, round((seconds_left / 300) * 100, 1)))

        # Determine renewal status
        renewal_status = "ok"
        if seconds_left is not None:
            if seconds_left < 0:
                renewal_status = "expired"
            elif seconds_left < 60:
                renewal_status = "renewing"

        # Parse SANs
        sans = []
        for line in san_raw.splitlines():
            line = line.strip()
            if line and not line.startswith("X509v3"):
                for part in line.split(","):
                    part = part.strip()
                    if part:
                        sans.append(part)

        # Decode certificate details
        parsed_text = run(["openssl", "x509", "-in", cert_path, "-text", "-noout"])

        # Read raw PEM
        try:
            raw_pem = run(["openssl", "x509", "-in", cert_path])
        except Exception:
            raw_pem = "Unable to read certificate file"

        def clean(s, prefix):
            return s.split("=", 1)[1].strip() if "=" in s else s

        return {
            "subject": clean(subject, "subject="),
            "issuer":  clean(issuer,  "issuer="),
            "valid_from": clean(start, "notBefore="),
            "valid_to":   clean(end,   "notAfter="),
            "serial": serial.split("=", 1)[1] if "=" in serial else serial,
            "sans": sans,
            "seconds_remaining": seconds_left,
            "hours_remaining": hours_left,
            "pct_remaining": pct_remaining,
            "renewal_status": renewal_status,
            "raw_pem": raw_pem,
            "parsed_text": parsed_text,
        }
    except Exception as e:
        return {"error": str(e)}


# ---------------------------------------------------------------------------
# Helper: check if a Docker container is running
# ---------------------------------------------------------------------------
def container_status(name):
    if not docker_client:
        return "error"
    try:
        container = docker_client.containers.get(name)
        # docker-py container.status returns string like 'running', 'exited'
        return container.status
    except docker.errors.NotFound:
        alias = CONTAINER_ALIASES.get(name, name)
        try:
            container = docker_client.containers.get(alias)
            return container.status
        except docker.errors.NotFound:
            return "not found"
        except Exception:
            return "error"
    except Exception:
        return "error"


# ---------------------------------------------------------------------------
# API Routes
# ---------------------------------------------------------------------------

@app.route("/api/status")
def api_status():
    statuses = {}
    for cname in CONTAINERS:
        alias = CONTAINER_ALIASES.get(cname, cname)
        statuses[alias] = container_status(cname)
    return jsonify(statuses)


@app.route("/api/certs")
def api_certs():
    cert_a = parse_cert(WORKLOAD_A_CERT)
    cert_b = parse_cert(WORKLOAD_B_CERT)

    with metrics_lock:
        for wl, cert_data in [("workload-a", cert_a), ("workload-b", cert_b)]:
            if cert_data and "error" not in cert_data and cert_data.get("serial"):
                current_serial = cert_data["serial"]
                last_serial = metrics_state[wl]["last_serial"]
                if last_serial is not None and current_serial != last_serial:
                    metrics_state[wl]["successes"] += 1
                metrics_state[wl]["last_serial"] = current_serial

    return jsonify({
        "workload-a": cert_a,
        "workload-b": cert_b,
    })

@app.route("/api/metrics")
def api_metrics():
    with metrics_lock:
        return jsonify(metrics_state)


@app.route("/api/config")
def api_config():
    ca_cert_info = parse_cert(CA_CERT)
    container_telemetry = {}
    
    if docker_client:
        for cname in CONTAINERS:
            alias = CONTAINER_ALIASES.get(cname, cname)
            try:
                try:
                    container = docker_client.containers.get(cname)
                except docker.errors.NotFound:
                    container = docker_client.containers.get(alias)
                
                attrs = container.attrs
                
                # Extract IP Address
                ip_address = None
                networks = attrs.get("NetworkSettings", {}).get("Networks", {})
                for net_name, net_info in networks.items():
                    ip_address = net_info.get("IPAddress")
                    if ip_address:
                        break
                
                # Extract safe environment variables
                env_list = attrs.get("Config", {}).get("Env", [])
                env_vars = {}
                for env in env_list:
                    if "=" in env:
                        k, v = env.split("=", 1)
                        if any(secret in k.lower() for secret in ["key", "password", "secret", "token"]) or (k.startswith("CONJUR_") and k not in ["CONJUR_APPLIANCE_URL", "CONJUR_ACCOUNT"]):
                            env_vars[k] = "********"
                        else:
                            env_vars[k] = v
                
                container_telemetry[alias] = {
                    "image": attrs.get("Config", {}).get("Image"),
                    "ip_address": ip_address or "N/A",
                    "env": env_vars,
                    "created": attrs.get("Created", "")[:19].replace("T", " "),
                }
            except Exception as e:
                container_telemetry[alias] = {
                    "error": str(e)
                }
                
    return jsonify({
        "root_ca": ca_cert_info,
        "containers": container_telemetry
    })


@app.route("/api/renew/<workload>", methods=["POST"])
def api_renew(workload):
    auth_header = request.headers.get("Authorization")
    if auth_header != "Bearer demo-token":
        return jsonify({"error": "unauthorized"}), 401

    cert_path = WORKLOAD_A_CERT if workload == "workload-a" else WORKLOAD_B_CERT if workload == "workload-b" else None
    if not cert_path:
        return jsonify({"error": "invalid workload"}), 400
    try:
        if os.path.exists(cert_path):
            os.remove(cert_path)
            return jsonify({"status": "renewal triggered"})
        return jsonify({"status": "already renewing"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ---------------------------------------------------------------------------
# SSE log streaming
# ---------------------------------------------------------------------------

log_queue = queue.Queue(maxsize=500)
_stream_started = False
_stream_lock = threading.Lock()


def _tail_container_logs(cname):
    alias = CONTAINER_ALIASES.get(cname, cname)
    if not docker_client:
        return
    while True:
        try:
            try:
                container = docker_client.containers.get(cname)
            except docker.errors.NotFound:
                container = docker_client.containers.get(alias)
            for line in container.logs(stream=True, tail=50):
                if line:
                    decoded_line = line.decode('utf-8', errors='replace').rstrip()
                    
                    # Intercept sidecar errors for metrics
                    l_lower = decoded_line.lower()
                    if "[sidecar]" in l_lower and ("error" in l_lower or "fail" in l_lower):
                        with metrics_lock:
                            if "workload-a" in cname:
                                metrics_state["workload-a"]["failures"] += 1
                            elif "workload-b" in cname:
                                metrics_state["workload-b"]["failures"] += 1

                    entry = json.dumps({
                        "source": alias, 
                        "line": decoded_line
                    })
                    try:
                        log_queue.put_nowait(entry)
                    except queue.Full:
                        pass
        except Exception:
            time.sleep(2) # retry on error/restart

def _docker_log_reader():
    """Background thread: spawn individual threads to tail container logs."""
    containers = ["conjur-demo-workload-a-1", "conjur-demo-workload-b-1"]
    for c in containers:
        threading.Thread(target=_tail_container_logs, args=(c,), daemon=True).start()


def ensure_log_stream():
    global _stream_started
    with _stream_lock:
        if not _stream_started:
            t = threading.Thread(target=_docker_log_reader, daemon=True)
            t.start()
            _stream_started = True


@app.route("/api/logs/stream")
def api_logs_stream():
    ensure_log_stream()

    def generate():
        # Each client gets its own view of the queue via a local deque
        local_q = queue.Queue(maxsize=200)

        def relay():
            while True:
                item = log_queue.get()
                try:
                    local_q.put_nowait(item)
                except queue.Full:
                    pass

        relay_thread = threading.Thread(target=relay, daemon=True)
        relay_thread.start()

        yield "retry: 3000\n\n"
        while True:
            try:
                item = local_q.get(timeout=20)
                yield f"data: {item}\n\n"
            except queue.Empty:
                # Keepalive
                yield ": keepalive\n\n"

    return Response(generate(), mimetype="text/event-stream",
                    headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


# ---------------------------------------------------------------------------
# Serve frontend
# ---------------------------------------------------------------------------

@app.route("/")
def index():
    return send_from_directory("static", "index.html")


@app.route("/<path:path>")
def static_files(path):
    return send_from_directory("static", path)


if __name__ == "__main__":
    host = os.getenv("FLASK_HOST", "127.0.0.1")
    port = int(os.getenv("FLASK_PORT", "5000"))
    app.run(host=host, port=port, debug=False, threaded=True)
