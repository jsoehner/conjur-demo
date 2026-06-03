# Security Assessment Lessons Learned

## Overview
A security assessment was conducted on the Conjur mTLS demo repository to identify vulnerabilities, misconfigurations, and unsafe defaults. The assessment discovered critical issues related to excessive file permissions and containers running with root privileges.

## Identified Security Defects

### 1. Insecure Private Key Permissions (World-Readable CA Key)
**Finding:** The demo initialization script (`init.sh`) explicitly set the permissions of the newly generated Root Certificate Authority (CA) private key to `644` (`chmod 644 certs/ca.key`). This made the highly sensitive private key world-readable.
**Risk:** An attacker gaining access to the machine or container could read the private key and forge certificates, completely bypassing the mTLS authentication model.
**Remediation:** Updated `init.sh` to correctly restrict the CA private key to owner-read-only by applying `chmod 600 certs/ca.key`.

### 2. Workload Sidecar Private Key Permissions
**Finding:** The workload sidecar script (`sidecar.sh`) used `openssl genrsa` to generate the workload's private key. The script explicitly managed permissions for the signed certificate (`chmod 644`) but implicitly relied on the environment's `umask` for the private key, which could lead to overly permissive access depending on the environment.
**Risk:** Similar to the CA key, an overly permissive workload private key allows lateral movement or impersonation if an attacker compromises the container file system.
**Remediation:** Updated `sidecar.sh` to explicitly lock down the workload private key permissions using `chmod 600 "$KEY_FILE"`.

### 3. Containers Executing as Root User
**Finding:** Both the `ca-signer` and `dashboard` Dockerfiles omitted a `USER` directive, causing their respective Python applications to run as the `root` user by default inside the container.
**Risk:** Running applications as root inside a container violates the principle of least privilege. If an attacker exploits a vulnerability in the Python application (e.g., remote code execution), they gain root privileges inside the container, significantly increasing the likelihood of a container escape.
**Remediation:** 
- Modified both Dockerfiles to create a dedicated `appgroup` and `appuser`.
- Granted the non-root user explicit ownership only over the directories they need to write to (e.g., `/dashboard`, `/tmp/ca`).
- Switched execution to the non-root user by appending the `USER appuser` instruction.

## Conclusion
This assessment emphasizes the importance of explicit permission handling for cryptographic material and adhering to container security best practices. Future developments in this repository must ensure that:
1. Cryptographic keys are consistently generated and stored with `600` permissions.
2. All Docker containers define and execute as non-root users.
