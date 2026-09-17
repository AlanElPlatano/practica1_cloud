#!/usr/bin/env bash
# Configuracion central del proyecto. Todos los scripts hacen "source" de este archivo.
set -euo pipefail

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

# Prefijo usado para nombrar todos los recursos creados por este proyecto.
export PROJECT="polaroid-booth"

# --- Identificadores de recursos ---
export ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export BUCKET="${PROJECT}-${ACCOUNT_ID}"
export DB_IDENTIFIER="${PROJECT}-db"
export DB_NAME="polaroid"
export DB_USER="polaroid_admin"
export SECRET_NAME="${PROJECT}/rds"
export APP_SG_NAME="${PROJECT}-app-sg"
export DB_SG_NAME="${PROJECT}-db-sg"
export DB_SUBNET_GROUP="${PROJECT}-subnet-group"
export EC2_NAME="${PROJECT}-api"
export INSTANCE_PROFILE="LabInstanceProfile"
export KEY_NAME="${PROJECT}-key"

# Archivo donde se guardan los IDs generados (no se versiona).
export STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.state"
touch "$STATE_FILE"
# shellcheck disable=SC1090
source "$STATE_FILE"

# Guarda o actualiza una variable en el archivo de estado.
save_state() {
  local key="$1" value="$2"
  grep -v "^export ${key}=" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
  echo "export ${key}=\"${value}\"" >> "$STATE_FILE"
  export "${key}=${value}"
}
