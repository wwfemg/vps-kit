#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Go + xcaddy install (arch-aware, fallback-safe)
# ==================================================

detect_arch() {
  case "$(uname -m)" in
    x86_64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *)
      echo "[ERROR] Unsupported architecture: $(uname -m)"
      exit 1
      ;;
  esac
}

get_latest_go_versions() {
  # first line = latest, second line = fallback
  curl -fsSL https://go.dev/dl/?mode=json \
    | grep -o '"version":"go[0-9.]*"' \
    | sed 's/"version":"//;s/"//' \
    | head -n 2
}

install_go() {
  if command -v go >/dev/null 2>&1; then
    echo "[INFO] Go already installed: $(go version)"
    return
  fi

  ARCH="$(detect_arch)"
  echo "[INFO] Architecture detected: ${ARCH}"

  mapfile -t GO_VERSIONS < <(get_latest_go_versions)

  if [[ "${#GO_VERSIONS[@]}" -eq 0 ]]; then
    echo "[ERROR] Unable to fetch Go version list"
    exit 1
  fi

  for GO_VERSION in "${GO_VERSIONS[@]}"; do
    GO_TARBALL="${GO_VERSION}.linux-${ARCH}.tar.gz"
    GO_URL="https://go.dev/dl/${GO_TARBALL}"

    echo "[INFO] Attempting to install ${GO_VERSION} (${ARCH})"

    if curl -fL "$GO_URL" -o "/tmp/${GO_TARBALL}"; then
      rm -rf /usr/local/go
      tar -C /usr/local -xzf "/tmp/${GO_TARBALL}"
      rm -f "/tmp/${GO_TARBALL}"
      export PATH="/usr/local/go/bin:$PATH"

      if command -v go >/dev/null 2>&1; then
        echo "[INFO] Go installed successfully: $(go version)"
        return
      fi
    fi

    echo "[WARN] Failed to install ${GO_VERSION}, trying fallback..."
  done

  echo "[ERROR] Go installation failed (all versions exhausted)"
  exit 1
}

install_xcaddy() {
  if command -v xcaddy >/dev/null 2>&1; then
    echo "[INFO] xcaddy already installed"
    return
  fi

  install_go

  echo "[INFO] Installing xcaddy..."
  GOBIN=/usr/local/bin /usr/local/go/bin/go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

  if ! command -v xcaddy >/dev/null 2>&1; then
    echo "[ERROR] xcaddy installation failed"
    exit 1
  fi

  echo "[INFO] xcaddy installed"
}

# Public entry
prepare_go_xcaddy() {
  install_go
  install_xcaddy
}