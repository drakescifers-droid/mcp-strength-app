#!/usr/bin/env bash
#
# Cloud Agent install: durable, idempotent setup of the backend/services
# development experience for this repo.
#
# What runs on Linux (and what this prepares):
#   - Postgres schema + RLS suite  -> supabase/tests/run.sh   (needs Docker)
#   - MCP Edge Function unit tests -> deno test (supabase/functions/mcp)
#   - Library seed generator + row-mapping check -> python3 (stdlib only)
#   - Static consent/legal site    -> web/ (any static server)
#
# The native iOS app (MCPStrength/) is NOT buildable here: it requires macOS
# and Xcode. Only the shared backend and web surface run on a Linux VM.
#
# Per-boot work (starting dockerd) lives in start.sh, because with environment
# builds this script's result is baked into a snapshot and is not re-run when a
# new pod boots.
set -euo pipefail

echo "==> install: Deno"
if ! command -v deno >/dev/null 2>&1; then
  curl -fsSL https://deno.land/install.sh | sudo DENO_INSTALL=/usr/local sh -s -- -y
fi
deno --version

echo "==> install: Docker Engine"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sudo sh /tmp/get-docker.sh
fi
docker --version

# The Cloud Agent VM is a nested container; the kernel refuses to mount
# overlayfs, so Docker's default snapshotter fails. vfs needs no overlay.
echo "==> install: Docker daemon config (vfs storage driver)"
sudo mkdir -p /etc/docker
echo '{"features":{"containerd-snapshotter":false},"storage-driver":"vfs"}' \
  | sudo tee /etc/docker/daemon.json >/dev/null
sudo groupadd -f docker
sudo usermod -aG docker "$(id -un)" || true

echo "==> install: pre-cache Deno test dependencies"
deno cache supabase/functions/mcp/*_test.ts || true

echo "==> install: pre-pull postgres:17-alpine (used by the schema/RLS suite)"
if ! sudo docker image inspect postgres:17-alpine >/dev/null 2>&1; then
  sudo dockerd >/tmp/dockerd-install.log 2>&1 &
  dockerd_pid=$!
  for _ in $(seq 1 30); do sudo docker info >/dev/null 2>&1 && break; sleep 1; done
  sudo docker pull postgres:17-alpine || true
  sudo kill "$dockerd_pid" >/dev/null 2>&1 || true
  wait "$dockerd_pid" 2>/dev/null || true
fi

echo "==> install: done"
