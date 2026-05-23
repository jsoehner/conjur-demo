/**
 * main.js – Conjur mTLS Dashboard client-side logic
 *
 * Responsibilities:
 *  - Poll /api/status   every 5 s → update node status badges + global dot
 *  - Poll /api/certs    every 10 s → update cert cards + expiry bars
 *  - Stream /api/logs/stream (SSE) → live log panel
 *  - Animate mTLS packet on every successful request detected in log stream
 *  - Track stats counters (requests, failures, renewals)
 */

"use strict";

/* ── Constants ─────────────────────────────────────────── */
const POLL_STATUS_MS  = 5_000;
const POLL_CERTS_MS   = 10_000;
const LOG_MAX_LINES   = 300;
const START_TIME      = Date.now();

/* ── State ─────────────────────────────────────────────── */
let totalRequests = 0;
let successCount  = 0;
let failCount     = 0;
let renewalCount  = 0;
let logLines      = 0;

/* ── Element refs ──────────────────────────────────────── */
const $ = id => document.getElementById(id);

const els = {
  globalDot:     $("global-status-dot"),
  globalLabel:   $("global-status-label"),
  headerClock:   $("header-clock"),
  reqCounter:    $("request-counter"),

  // Nodes
  conjurBadge:   $("conjur-status-badge"),
  waBadge:       $("workload-a-status-badge"),
  wbBadge:       $("workload-b-status-badge"),

  // System status dots
  dotDatabase:   $("status-dot-database"),
  dotConjur:     $("status-dot-conjur"),
  dotCaSigner:   $("status-dot-ca-signer"),
  dotWorkloadA:  $("status-dot-workload-a"),
  dotWorkloadB:  $("status-dot-workload-b"),

  // Cert A
  certAStatus:   $("cert-a-status"),
  certABar:      $("cert-a-bar"),
  certATime:     $("cert-a-time"),
  certASubject:  $("cert-a-subject"),
  certAIssuer:   $("cert-a-issuer"),
  certASan:      $("cert-a-san"),
  certASerial:   $("cert-a-serial"),
  certAExpires:  $("cert-a-expires"),

  // Cert B
  certBStatus:   $("cert-b-status"),
  certBBar:      $("cert-b-bar"),
  certBTime:     $("cert-b-time"),
  certBSubject:  $("cert-b-subject"),
  certBIssuer:   $("cert-b-issuer"),
  certBSan:      $("cert-b-san"),
  certBSerial:   $("cert-b-serial"),
  certBExpires:  $("cert-b-expires"),

  // Log
  logStream:     $("log-stream"),
  logClearBtn:   $("log-clear-btn"),
  filterSidecar: $("filter-sidecar"),
  filterServer:  $("filter-server"),
  filterClient:  $("filter-client"),

  // mTLS
  mtlsPacket:    $("mtls-packet-ab"),

  // Stats
  statTotal:     $("stat-total-req"),
  statSuccess:   $("stat-success"),
  statFail:      $("stat-fail"),
  statRenewals:  $("stat-renewals"),
  statUptime:    $("stat-uptime"),
};

/* ── Clock ─────────────────────────────────────────────── */
function updateClock() {
  const now = new Date();
  els.headerClock.textContent = now.toLocaleTimeString("en-GB", { hour12: false });
}
setInterval(updateClock, 1000);
updateClock();

/* ── Uptime ────────────────────────────────────────────── */
function updateUptime() {
  const secs = Math.floor((Date.now() - START_TIME) / 1000);
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  const s = secs % 60;
  if (h > 0) els.statUptime.textContent = `${h}h ${m}m`;
  else if (m > 0) els.statUptime.textContent = `${m}m ${s}s`;
  else els.statUptime.textContent = `${s}s`;
}
setInterval(updateUptime, 1000);

/* ── Node status helpers ───────────────────────────────── */
function applyStatus(el, status) {
  el.textContent = status;
  el.className = "node-status-badge";
  if (status === "running") el.classList.add("running");
  else if (status === "exited" || status === "not found" || status === "error") el.classList.add("stopped");
  else el.classList.add("unknown");
}

function setGlobalStatus(statuses) {
  const vals = Object.values(statuses);
  const allUp = vals.every(s => s === "running");
  const anyUp = vals.some(s => s === "running");

  els.globalDot.className = "status-dot";
  if (allUp) {
    els.globalDot.classList.add("online");
    els.globalLabel.textContent = "All services running";
  } else if (anyUp) {
    els.globalDot.classList.add("partial");
    els.globalLabel.textContent = "Partial — some services down";
  } else {
    els.globalDot.classList.add("offline");
    els.globalLabel.textContent = "Services offline";
  }
}

/* ── Node status dot helper ────────────────────────────── */
function applyStatusDot(el, status) {
  if (!el) return;
  el.className = "status-card-dot " + (status === "running" ? "running" : (status === "exited" || status === "not found" || status === "error" ? "stopped" : "unknown"));
}

/* ── Poll /api/status ──────────────────────────────────── */
async function pollStatus() {
  try {
    const res  = await fetch("/api/status");
    const data = await res.json();

    applyStatus(els.conjurBadge, data["conjur"]     ?? "unknown");
    applyStatus(els.waBadge,     data["workload-a"] ?? "unknown");
    applyStatus(els.wbBadge,     data["workload-b"] ?? "unknown");

    applyStatusDot(els.dotDatabase,  data["database"]   ?? "unknown");
    applyStatusDot(els.dotConjur,    data["conjur"]     ?? "unknown");
    applyStatusDot(els.dotCaSigner,  data["ca-signer"]  ?? "unknown");
    applyStatusDot(els.dotWorkloadA, data["workload-a"] ?? "unknown");
    applyStatusDot(els.dotWorkloadB, data["workload-b"] ?? "unknown");

    setGlobalStatus(data);
  } catch {
    els.globalDot.className = "status-dot offline";
    els.globalLabel.textContent = "Dashboard API unreachable";
  }
}

/* ── Cert helpers ──────────────────────────────────────── */
function formatTimeLeft(seconds) {
  if (seconds === null || seconds === undefined) return "–";
  if (seconds < 0) return "EXPIRED";
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0)  return `${h}h ${m}m remaining`;
  if (m > 0)  return `${m}m ${s}s remaining`;
  return `${s}s remaining`;
}

function formatSans(sans) {
  if (!sans || !sans.length) return "–";
  return sans.join(" · ");
}

function applyCertCard(prefix, certData) {
  const elStatus  = els[`cert${prefix}Status`];
  const elBar     = els[`cert${prefix}Bar`];
  const elTime    = els[`cert${prefix}Time`];
  const elSubject = els[`cert${prefix}Subject`];
  const elIssuer  = els[`cert${prefix}Issuer`];
  const elSan     = els[`cert${prefix}San`];
  const elSerial  = els[`cert${prefix}Serial`];
  const elExpires = els[`cert${prefix}Expires`];

  const elDecoded = $(`cert-${prefix.toLowerCase()}-decoded-val`);
  const elPem     = $(`cert-${prefix.toLowerCase()}-pem-val`);

  if (!certData) {
    elStatus.textContent = "loading";
    elStatus.className   = "cert-status-pill loading";
    elTime.textContent   = "Waiting for sidecar…";
    if (elDecoded) elDecoded.textContent = "Loading decoded certificate info...";
    if (elPem)     elPem.textContent = "Loading PEM certificate...";
    return;
  }
  if (certData.error) {
    elStatus.textContent = "error";
    elStatus.className   = "cert-status-pill expired";
    elTime.textContent   = certData.error;
    if (elDecoded) elDecoded.textContent = certData.error;
    if (elPem)     elPem.textContent = certData.error;
    return;
  }

  const status = certData.renewal_status ?? "ok";
  elStatus.textContent = status;
  elStatus.className   = `cert-status-pill ${status}`;

  const pct = certData.pct_remaining ?? 100;
  elBar.style.width = `${pct}%`;
  elBar.className = "cert-expiry-bar" +
    (pct < 20 ? " expired" : pct < 40 ? " warn" : "");

  elTime.textContent    = formatTimeLeft(certData.seconds_remaining);
  elSubject.textContent = certData.subject   ?? "–";
  elIssuer.textContent  = certData.issuer    ?? "–";
  elSan.textContent     = formatSans(certData.sans);
  elSerial.textContent  = certData.serial    ?? "–";
  elExpires.textContent = certData.valid_to  ?? "–";

  if (elDecoded) elDecoded.textContent = certData.parsed_text ?? "No decoded info available";
  if (elPem)     elPem.textContent = certData.raw_pem     ?? "No PEM available";
}

/* ── Poll /api/certs ───────────────────────────────────── */
async function pollCerts() {
  try {
    const res  = await fetch("/api/certs");
    const data = await res.json();
    applyCertCard("A", data["workload-a"]);
    applyCertCard("B", data["workload-b"]);
  } catch {
    // Silently wait; status endpoint will show connectivity issue
  }
}

/* ── mTLS packet animation ─────────────────────────────── */
let packetAnimating = false;
function firePacket() {
  if (packetAnimating) return;
  packetAnimating = true;
  const pkt = els.mtlsPacket;
  pkt.classList.remove("flying");
  void pkt.offsetWidth; // force reflow
  pkt.classList.add("flying");

  // Flash nodes
  const nodeA = $("node-workload-a");
  const nodeB = $("node-workload-b");
  nodeA.classList.remove("node-flash"); void nodeA.offsetWidth;
  nodeA.classList.add("node-flash");
  setTimeout(() => {
    nodeB.classList.remove("node-flash"); void nodeB.offsetWidth;
    nodeB.classList.add("node-flash");
  }, 600);

  pkt.addEventListener("animationend", () => {
    pkt.classList.remove("flying");
    packetAnimating = false;
  }, { once: true });
}

/* ── Log panel ─────────────────────────────────────────── */
function getTag(line) {
  if (line.includes("[Sidecar]")) return { tag: "sidecar", label: "Sidecar" };
  if (line.includes("[Server]"))  return { tag: "server",  label: "Server"  };
  if (line.includes("[Client]"))  return { tag: "client",  label: "Client"  };
  return null;
}

function getTextClass(line) {
  const l = line.toLowerCase();
  if (l.includes("error") || l.includes("fail") || l.includes("reject")) return "error";
  if (l.includes("warn") || l.includes("renew") || l.includes("expir"))  return "warning";
  if (l.includes("200") || l.includes("success") || l.includes("certificate received")) return "success";
  if (l.includes("cert") || l.includes("csr") || l.includes("spiffe") || l.includes("cn=")) return "cert";
  return "";
}

function appendLogLine(source, text) {
  const tagInfo = getTag(text);
  if (!tagInfo) return; // Only show categorised lines

  // Respect filter checkboxes
  const filterMap = { sidecar: els.filterSidecar, server: els.filterServer, client: els.filterClient };
  if (filterMap[tagInfo.tag] && !filterMap[tagInfo.tag].checked) return;

  const now = new Date();
  const ts  = now.toLocaleTimeString("en-GB", { hour12: false });

  const row = document.createElement("div");
  row.className = "log-line";
  row.dataset.tag = tagInfo.tag;

  const timeEl   = document.createElement("span");
  timeEl.className = "log-time";
  timeEl.textContent = ts;

  const sourceEl = document.createElement("span");
  sourceEl.className = `log-source ${source}`;
  sourceEl.textContent = source;

  const tagEl    = document.createElement("span");
  tagEl.className = `log-tag ${tagInfo.tag}`;
  tagEl.textContent = tagInfo.label;

  // Strip the [Tag] prefix from display text
  const cleaned = text.replace(/\[Sidecar\]|\[Server\]|\[Client\]/g, "").trim();

  const textEl   = document.createElement("span");
  textEl.className = `log-text ${getTextClass(text)}`;
  textEl.textContent = cleaned;

  row.append(timeEl, sourceEl, tagEl, textEl);
  els.logStream.appendChild(row);

  logLines++;
  if (logLines > LOG_MAX_LINES) {
    els.logStream.firstChild?.remove();
    logLines--;
  }

  // Auto-scroll if already near bottom
  const { scrollTop, scrollHeight, clientHeight } = els.logStream;
  if (scrollHeight - scrollTop - clientHeight < 80) {
    els.logStream.scrollTop = els.logStream.scrollHeight;
  }

  // Stat tracking
  if (text.includes("[Client]")) {
    if (text.includes("Response:") && text.includes("200")) {
      totalRequests++;
      successCount++;
      els.statTotal.textContent   = totalRequests;
      els.statSuccess.textContent = successCount;
      els.reqCounter.textContent  = `${totalRequests} requests`;
      firePacket();
    } else if (text.includes("Connection failed") || text.includes("TLS") || text.includes("error")) {
      totalRequests++;
      failCount++;
      els.statTotal.textContent  = totalRequests;
      els.statFail.textContent   = failCount;
    }
  }
  if (text.includes("[Sidecar]") && (text.includes("Renew") || text.includes("renewal"))) {
    renewalCount++;
    els.statRenewals.textContent = renewalCount;
  }
}

/* ── SSE connection ────────────────────────────────────── */
function connectSSE() {
  const sse = new EventSource("/api/logs/stream");

  sse.onopen = () => {
    console.log("[Dashboard] SSE stream connected");
  };

  sse.onmessage = event => {
    try {
      const { source, line } = JSON.parse(event.data);
      appendLogLine(source, line);
    } catch { /* ignore parse errors */ }
  };

  sse.onerror = () => {
    console.warn("[Dashboard] SSE stream error — reconnecting in 5s");
    sse.close();
    setTimeout(connectSSE, 5000);
  };
}

/* ── Clear log ─────────────────────────────────────────── */
els.logClearBtn.addEventListener("click", () => {
  els.logStream.innerHTML = "";
  logLines = 0;
});

/* ── Force Renew Buttons ───────────────────────────────── */
document.querySelectorAll(".renew-btn").forEach(btn => {
  btn.addEventListener("click", async () => {
    const workload = btn.dataset.workload;
    const originalText = btn.textContent;
    btn.textContent = "Renewing...";
    btn.disabled = true;
    
    try {
      await fetch(`/api/renew/${workload}`, { method: "POST" });
      // The cert API polling every 10s will naturally pick up the new cert
      // but let's do a quick poll immediately after 2 seconds to feel snappy
      setTimeout(pollCerts, 2000);
    } catch (err) {
      console.error(`Failed to trigger renewal for ${workload}:`, err);
    } finally {
      setTimeout(() => {
        btn.textContent = originalText;
        btn.disabled = false;
      }, 3000);
    }
  });
});

/* ── Filter toggles (re-render isn't needed; new lines respect filter) ── */
// Existing lines toggle visibility
[els.filterSidecar, els.filterServer, els.filterClient].forEach(checkbox => {
  checkbox.addEventListener("change", () => {
    const tag = checkbox.id.replace("filter-", "");
    els.logStream.querySelectorAll(`.log-line[data-tag="${tag}"]`).forEach(el => {
      el.style.display = checkbox.checked ? "" : "none";
    });
  });
});

/* ── Config Telemetry ──────────────────────────────────── */
const POLL_CONFIG_MS = 20_000;

function updateCaTelemetry(ca) {
  const container = document.getElementById("telemetry-ca-details");
  if (!container) return;
  if (!ca) {
    container.innerHTML = `<p class="loading-placeholder">No Root CA certificate found.</p>`;
    return;
  }
  if (ca.error) {
    container.innerHTML = `<p class="loading-placeholder" style="color: var(--accent-red)">Error: ${ca.error}</p>`;
    return;
  }
  
  container.innerHTML = `
    <div class="telemetry-ca-info">
      <div class="telemetry-row"><span class="t-key">Subject</span><span class="t-val">${ca.subject || '–'}</span></div>
      <div class="telemetry-row"><span class="t-key">Issuer</span><span class="t-val">${ca.issuer || '–'}</span></div>
      <div class="telemetry-row"><span class="t-key">Serial</span><span class="t-val t-mono">${ca.serial || '–'}</span></div>
      <div class="telemetry-row"><span class="t-key">Valid From</span><span class="t-val">${ca.valid_from || '–'}</span></div>
      <div class="telemetry-row"><span class="t-key">Valid To</span><span class="t-val">${ca.valid_to || '–'}</span></div>
      <div class="telemetry-row"><span class="t-key">SANs</span><span class="t-val t-mono">${(ca.sans && ca.sans.length) ? ca.sans.join(" · ") : 'None'}</span></div>
    </div>
    <div class="telemetry-pem-container">
      <span class="t-pem-title">Root CA PEM</span>
      <pre class="telemetry-pem">${ca.raw_pem || 'No PEM available'}</pre>
    </div>
  `;
}

function updateContainerTelemetry(containers) {
  const grid = document.getElementById("telemetry-container-grid");
  if (!grid) return;
  if (!containers || Object.keys(containers).length === 0) {
    grid.innerHTML = `<p class="loading-placeholder">No container telemetry available.</p>`;
    return;
  }
  
  let html = "";
  const order = ["database", "conjur", "ca-signer", "workload-b", "workload-a"];
  const sortedKeys = Object.keys(containers).sort((a, b) => {
    const idxA = order.indexOf(a);
    const idxB = order.indexOf(b);
    if (idxA !== -1 && idxB !== -1) return idxA - idxB;
    return a.localeCompare(b);
  });

  for (const name of sortedKeys) {
    const info = containers[name];
    if (info.error) {
      html += `
        <div class="tel-container-card error">
          <div class="tel-card-header">
            <span class="tel-card-name">${name}</span>
            <span class="tel-card-badge stopped">Error</span>
          </div>
          <p class="tel-card-err-msg">${info.error}</p>
        </div>
      `;
      continue;
    }
    
    const envEntries = Object.entries(info.env || {}).sort((a, b) => a[0].localeCompare(b[0]));
    let envHtml = "";
    if (envEntries.length > 0) {
      envHtml = envEntries.map(([k, v]) => `<div><span class="tel-env-k">${k}</span>=<span class="tel-env-v">${v}</span></div>`).join("");
    } else {
      envHtml = `<div class="tel-env-empty">No environment variables loaded</div>`;
    }
    
    html += `
      <div class="tel-container-card">
        <div class="tel-card-header">
          <span class="tel-card-name">${name}</span>
          <span class="tel-card-ip">${info.ip_address}</span>
        </div>
        <div class="tel-card-body">
          <div class="tel-line"><span class="tel-key">Image</span><span class="tel-val">${info.image || 'N/A'}</span></div>
          <div class="tel-line"><span class="tel-key">Created</span><span class="tel-val">${info.created || 'N/A'}</span></div>
          <div class="tel-env-wrapper">
            <div class="tel-env-title">Configuration Env</div>
            <div class="tel-env-list">${envHtml}</div>
          </div>
        </div>
      </div>
    `;
  }
  
  grid.innerHTML = html;
}

async function pollConfig() {
  try {
    const res = await fetch("/api/config");
    const data = await res.json();
    updateCaTelemetry(data.root_ca);
    updateContainerTelemetry(data.containers);
  } catch (err) {
    console.error("Failed to poll configuration telemetry:", err);
  }
}

/* ── Kick everything off ───────────────────────────────── */
function init() {
  // Tab switching logic
  document.querySelectorAll(".cert-tab-btn").forEach(btn => {
    btn.addEventListener("click", () => {
      const tab = btn.dataset.tab;
      const workload = btn.dataset.workload; // 'a' or 'b'
      const card = btn.closest(".cert-card");

      // Deactivate other tabs in this card
      card.querySelectorAll(".cert-tab-btn").forEach(b => b.classList.remove("active"));
      card.querySelectorAll(".cert-tab-content").forEach(c => c.classList.remove("active"));

      // Activate selected tab
      btn.classList.add("active");
      const contentId = `cert-${workload}-tab-${tab}`;
      const contentEl = document.getElementById(contentId);
      if (contentEl) contentEl.classList.add("active");
    });
  });

  // Config tab switching logic
  document.querySelectorAll(".config-tab-btn").forEach(btn => {
    btn.addEventListener("click", () => {
      const tab = btn.dataset.tab;
      const panel = btn.closest(".config-panel");

      // Deactivate other tabs
      panel.querySelectorAll(".config-tab-btn").forEach(b => b.classList.remove("active"));
      panel.querySelectorAll(".config-tab-content").forEach(c => c.classList.remove("active"));

      // Activate selected tab
      btn.classList.add("active");
      const contentId = `config-tab-${tab}`;
      const contentEl = document.getElementById(contentId);
      if (contentEl) contentEl.classList.add("active");
    });
  });

  pollStatus();
  pollCerts();
  pollConfig();
  connectSSE();

  setInterval(pollStatus, POLL_STATUS_MS);
  setInterval(pollCerts,  POLL_CERTS_MS);
  setInterval(pollConfig, POLL_CONFIG_MS);
}

init();
