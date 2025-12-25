#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Common utilities (logging / error handling / env)
# ==================================================

log() {
  echo "[INFO] $*"
}

die() {
  echo "[ERROR] $*" >&2
  exit 1
}
