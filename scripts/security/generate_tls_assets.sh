#!/usr/bin/env bash
set -euo pipefail

umask 077

out_dir="${1:-.certs}"
primary_host="${2:-stem.local}"
alt_names_input="${3:-$primary_host}"
days="${DAYS:-365}"
client_cn="${CLIENT_CN:-stem-client}"

mkdir -p "$out_dir"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

alt_names=()
IFS=',' read -ra alt_names <<<"$alt_names_input"

# Generate CA key and certificate.
openssl genrsa -out "$out_dir/ca.key" 4096 >/dev/null 2>&1
openssl req \
  -x509 \
  -new \
  -key "$out_dir/ca.key" \
  -sha256 \
  -days "$days" \
  -out "$out_dir/ca.crt" \
  -subj "/CN=${primary_host}-ca" \
  >/dev/null 2>&1

# Render server CSR config with SANs.
cat >"$tmp_dir/server.cnf" <<EOF
[req]
default_bits = 4096
prompt = no
default_md = sha256
distinguished_name = req_dn
req_extensions = req_ext

[req_dn]
CN = ${primary_host}

[req_ext]
subjectAltName = @alt_names
extendedKeyUsage = serverAuth
basicConstraints = CA:FALSE

[alt_names]
EOF

index=1
for name in "${alt_names[@]}"; do
  echo "DNS.${index} = ${name}" >>"$tmp_dir/server.cnf"
  index=$((index + 1))
done

openssl req \
  -new \
  -nodes \
  -config "$tmp_dir/server.cnf" \
  -keyout "$out_dir/server.key" \
  -out "$tmp_dir/server.csr" \
  >/dev/null 2>&1

openssl x509 \
  -req \
  -in "$tmp_dir/server.csr" \
  -CA "$out_dir/ca.crt" \
  -CAkey "$out_dir/ca.key" \
  -CAcreateserial \
  -out "$out_dir/server.crt" \
  -days "$days" \
  -sha256 \
  -extensions req_ext \
  -extfile "$tmp_dir/server.cnf" \
  >/dev/null 2>&1

# Generate client certificate signed by the same CA (mutual TLS support).
cat >"$tmp_dir/client.cnf" <<EOF
[req]
default_bits = 4096
prompt = no
default_md = sha256
distinguished_name = req_dn
req_extensions = req_ext

[req_dn]
CN = ${client_cn}

[req_ext]
extendedKeyUsage = clientAuth
basicConstraints = CA:FALSE
EOF

openssl req \
  -new \
  -nodes \
  -config "$tmp_dir/client.cnf" \
  -keyout "$out_dir/client.key" \
  -out "$tmp_dir/client.csr" \
  >/dev/null 2>&1

openssl x509 \
  -req \
  -in "$tmp_dir/client.csr" \
  -CA "$out_dir/ca.crt" \
  -CAkey "$out_dir/ca.key" \
  -CAcreateserial \
  -out "$out_dir/client.crt" \
  -days "$days" \
  -sha256 \
  -extensions req_ext \
  -extfile "$tmp_dir/client.cnf" \
  >/dev/null 2>&1

rm -f "$out_dir/ca.srl"

cat <<EOF
Generated TLS assets in $out_dir
- CA:      ca.crt / ca.key
- Server:  server.crt / server.key (SANs: ${alt_names_input})
- Client:  client.crt / client.key (CN: ${client_cn})

Mount ${out_dir}/ca.crt into clients via STEM_TLS_CA_CERT, and keep private keys secure.
EOF
