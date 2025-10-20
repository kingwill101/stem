#!/usr/bin/env bash
set -euo pipefail

out_dir="${1:-.certs}"
hostname="${2:-stem.local}"
days="${DAYS:-365}"

mkdir -p "$out_dir"

openssl req \
  -x509 \
  -nodes \
  -sha256 \
  -days "$days" \
  -newkey rsa:4096 \
  -keyout "$out_dir/server.key" \
  -out "$out_dir/server.crt" \
  -subj "/CN=$hostname" >/dev/null 2>&1

echo "Generated TLS key pair in $out_dir for host $hostname"
