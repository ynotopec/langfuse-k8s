#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
VALUES_FILE="$SCRIPT_DIR/values-langfuse.yaml"

# Générer les secrets
SALT="$(openssl rand -base64 32)"
ENCRYPTION_KEY="$(openssl rand -hex 32)"
NEXTAUTH_SECRET="$(openssl rand -base64 32)"
POSTGRES_PASSWORD="$(openssl rand -base64 24 | tr -d '=+/')"
REDIS_PASSWORD="$(openssl rand -base64 24 | tr -d '=+/')"
CLICKHOUSE_PASSWORD="$(openssl rand -base64 24 | tr -d '=+/')"
MINIO_PASSWORD="$(openssl rand -base64 24 | tr -d '=+/')"

# Écrire .env
cat > "$ENV_FILE" <<EOF
# Secrets pour Langfuse — générés automatiquement le $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Ce fichier est ignoré par git (.gitignore)

SALT="${SALT}"
ENCRYPTION_KEY="${ENCRYPTION_KEY}"
NEXTAUTH_SECRET="${NEXTAUTH_SECRET}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
REDIS_PASSWORD="${REDIS_PASSWORD}"
CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD}"
MINIO_PASSWORD="${MINIO_PASSWORD}"
EOF

chmod 600 "$ENV_FILE"

echo "Secrets écrits dans .env ($(wc -c < "$ENV_FILE") octets, permissions 600)"

# Produire values-langfuse.yaml
cat > "$VALUES_FILE" <<EOF
global:
  security:
    allowInsecureImages: true

langfuse:
  logging:
    level: info
    format: text

  features:
    telemetryEnabled: false
    signUpDisabled: false

  salt:
    value: "${SALT}"
  encryptionKey:
    value: "${ENCRYPTION_KEY}"
  nextauth:
    secret:
      value: "${NEXTAUTH_SECRET}"
    url: "https://langfuse.example.com"

  ingress:
    enabled: true
    className: public
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    hosts:
      - host: langfuse.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      enabled: true
      secretName: langfuse-tls

  deployment:
    replicas: 1

  web:
    replicas: 2
    resources:
      requests:
        cpu: "1"
        memory: "2Gi"
      limits:
        cpu: "2"
        memory: "4Gi"
    hpa:
      enabled: true
      minReplicas: 2
      maxReplicas: 4
      targetCPUUtilizationPercentage: 50

  worker:
    replicas: 4
    resources:
      requests:
        cpu: "1"
        memory: "2Gi"
      limits:
        cpu: "2"
        memory: "4Gi"
    hpa:
      enabled: true
      minReplicas: 4
      maxReplicas: 12
      targetCPUUtilizationPercentage: 50

postgresql:
  deploy: true
  auth:
    username: postgres
    password: "${POSTGRES_PASSWORD}"
    database: postgres_langfuse
  primary:
    persistence:
      enabled: true
      size: 20Gi
    resources:
      requests:
        cpu: "1"
        memory: "2Gi"
      limits:
        cpu: "2"
        memory: "4Gi"

redis:
  deploy: true
  auth:
    username: default
    password: "${REDIS_PASSWORD}"
  primary:
    extraFlags:
      - "--maxmemory-policy noeviction"
    persistence:
      enabled: true
      size: 8Gi
    resources:
      requests:
        cpu: "500m"
        memory: "1Gi"
      limits:
        cpu: "1"
        memory: "2Gi"

clickhouse:
  deploy: true
  shards: 1
  replicaCount: 1
  auth:
    username: default
    password: "${CLICKHOUSE_PASSWORD}"
  persistence:
    enabled: true
    size: 50Gi
  resourcesPreset: large

s3:
  deploy: true
  bucket: langfuse
  auth:
    rootUser: minio
    rootPassword: "${MINIO_PASSWORD}"
  defaultBuckets: langfuse
  persistence:
    enabled: true
    size: 50Gi
EOF

echo "values-langfuse.yaml regénéré"
