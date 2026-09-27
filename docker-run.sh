#!/usr/bin/env bash
# ==============================================================================
# docker-run.sh - Compatibility wrapper for run_docker.sh
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/run_docker.sh" "$@"
