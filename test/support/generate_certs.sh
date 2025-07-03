#!/bin/bash

# Script to generate SSL certificates for PostgreSQL
# This creates self-signed certificates for testing/CI purposes

set -e

CERT_DIR="$(dirname "$0")"
cd "$CERT_DIR"

echo "Generating SSL certificates for PostgreSQL..."

# Check if certificates already exist (skip regeneration for efficiency)
if [[ -f ca-cert.pem && -f server-cert.pem && -f client-cert.pem ]]; then
    echo "SSL certificates already exist, skipping generation..."
    exit 0
fi

# Clean up any partial certificate files
rm -f *.pem *.srl *.req

# Generate private key for CA
openssl genrsa -out ca-key.pem 2048

# Generate CA certificate (longer validity for CI stability)
openssl req -new -x509 -key ca-key.pem -out ca-cert.pem -days 1 -subj "/C=US/ST=CA/L=San Francisco/O=Glific/OU=CI/CN=Glific CA"

# Generate server private key
openssl genrsa -out server-key.pem 2048

# Generate server certificate signing request with multiple hostnames
cat > server.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = postgres
DNS.3 = *.localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

openssl req -new -key server-key.pem -out server-req.pem -config server.conf -subj "/C=US/ST=CA/L=San Francisco/O=Glific/OU=CI/CN=localhost"

# Generate server certificate signed by CA
openssl x509 -req -in server-req.pem -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial -out server-cert.pem -days 1 -extensions v3_req -extfile server.conf

# Generate client private key
openssl genrsa -out client-key.pem 2048

# Generate client certificate signing request
openssl req -new -key client-key.pem -out client-req.pem -subj "/C=US/ST=CA/L=San Francisco/O=Glific/OU=CI/CN=postgres"

# Generate client certificate signed by CA
openssl x509 -req -in client-req.pem -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial -out client-cert.pem -days 1

# Set appropriate permissions
chmod 600 *-key.pem
chmod 644 *-cert.pem ca-cert.pem

# Clean up temporary files
rm -f server-req.pem client-req.pem ca-cert.srl server.conf

# Verify certificates
echo "Verifying certificates..."
openssl verify -CAfile ca-cert.pem server-cert.pem
openssl verify -CAfile ca-cert.pem client-cert.pem

echo "SSL certificates generated successfully!"
echo "Files created:"
echo "  - ca-cert.pem (Certificate Authority)"
echo "  - server-cert.pem (Server certificate)"
echo "  - server-key.pem (Server private key)"
echo "  - client-cert.pem (Client certificate)"
echo "  - client-key.pem (Client private key)"
echo "  - ca-key.pem (CA private key)"

# Display certificate information for debugging
if [[ "${CI:-}" == "true" ]] || [[ "${DEBUG_CERTS:-}" == "true" ]]; then
    echo ""
    echo "Certificate details:"
    echo "CA Certificate:"
    openssl x509 -in ca-cert.pem -text -noout | grep -E "(Subject|Issuer|Not Before|Not After)"
    echo ""
    echo "Server Certificate:"
    openssl x509 -in server-cert.pem -text -noout | grep -E "(Subject|Issuer|Not Before|Not After|DNS:|IP Address:)"
fi
