#!/usr/bin/env bash
#
# Cloud Agent start: per-boot reconciliation. Brings up the Docker daemon that
# the Postgres schema/RLS suite (supabase/tests/run.sh) needs. Idempotent:
# returns immediately if dockerd is already serving.
set -euo pipefail

if sudo docker info >/dev/null 2>&1; then
  echo "==> start: dockerd already running"
  exit 0
fi

# Same nested-VM constraint as install.sh: overlay is unavailable, use vfs.
sudo mkdir -p /etc/docker
echo '{"features":{"containerd-snapshotter":false},"storage-driver":"vfs"}' \
  | sudo tee /etc/docker/daemon.json >/dev/null

echo "==> start: launching dockerd"
sudo nohup dockerd >/tmp/dockerd.log 2>&1 &

for _ in $(seq 1 30); do
  if sudo docker info >/dev/null 2>&1; then
    echo "==> start: dockerd ready"
    exit 0
  fi
  sleep 1
done

echo "==> start: dockerd failed to become ready" >&2
tail -30 /tmp/dockerd.log >&2 || true
exit 1
