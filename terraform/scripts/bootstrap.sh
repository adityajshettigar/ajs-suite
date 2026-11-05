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

systemctl enable --now docker

echo "=== Installed versions ==="
docker --version
docker compose version
git --version

echo "=== AJS Suite bootstrap completed ==="
