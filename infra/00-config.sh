#!/usr/bin/env bash
# Configuracion central del proyecto. Todos los scripts hacen "source" de este archivo.
set -euo pipefail

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

# Prefijo usado para nombrar todos los recursos creados por este proyecto.
export PROJECT="instabox"

# --- Identificadores de recursos ---
# Toda llamada a AWS necesita credenciales vigentes, y las del Learner Lab
# caducan al terminar la sesion. Se comprueba aqui, con un mensaje claro, en vez
# de dejar que 'set -e' aborte sin decir por que.
if ! ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"; then
  echo "ERROR: las credenciales de AWS no son validas o caducaron." >&2
  echo "       Copia el bloque nuevo del Learner Lab a ~/.aws/credentials" >&2
  echo "       y vuelve a intentarlo." >&2
  echo "       No se ha creado ni eliminado ningun recurso." >&2
  exit 1
fi
export ACCOUNT_ID
export BUCKET="${PROJECT}-${ACCOUNT_ID}"
export DB_IDENTIFIER="${PROJECT}-db"
export DB_NAME="instabox"
export DB_USER="instabox_admin"
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
