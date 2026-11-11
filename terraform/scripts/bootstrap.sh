#!/bin/bash
set -Eeuo pipefail

exec > >(tee -a /var/log/ajs-suite-bootstrap.log) 2>&1

export DEBIAN_FRONTEND=noninteractive

echo "=== AJS Suite server bootstrap started ==="

apt-get update

apt-get install -y \
  docker.io \
  docker-compose-v2 \
  git \
  ca-certificates

# Enable docker to start without systemd on t3.micro
# (On some minimal AMIs, systemd may not be available)
mkdir -p /etc/docker

# Add ubuntu user to docker group so docker commands work without sudo
usermod -aG docker ubuntu

# Create the project network; || true if it already exists
docker network create ajs || true

systemctl start docker 2>/dev/null || true

echo "=== Installed versions ==="
docker --version
docker compose version
git --version

# Note: Ansible is NOT installed in Phase 1.
# Docker Compose is run manually after git clone, or via Ansible Phase 2+.
# Named volume admin_sessions is managed by docker compose, not by bootstrap.

echo "=== AJS Suite bootstrap completed ==="
