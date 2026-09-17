#!/usr/bin/env bash
# Guarda las credenciales de RDS en AWS Secrets Manager.
# La app las lee en tiempo de ejecucion; nunca viajan en variables de ambiente.
source "$(dirname "${BASH_SOURCE[0]}")/00-config.sh"

if [ -z "${DB_HOST:-}" ] || [ -z "${DB_PASSWORD:-}" ]; then
  echo "ERROR: falta DB_HOST o DB_PASSWORD. Ejecuta primero 03-rds.sh." >&2
  exit 1
fi

SECRET_JSON="$(python -c '
import json, sys
print(json.dumps({
    "engine": "mysql",
    "host": sys.argv[1],
    "port": 3306,
    "username": sys.argv[2],
    "password": sys.argv[3],
    "dbname": sys.argv[4],
}))' "$DB_HOST" "$DB_USER" "$DB_PASSWORD" "$DB_NAME")"

if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" >/dev/null 2>&1; then
  echo ">> El secreto ya existe, se actualiza su valor."
  aws secretsmanager put-secret-value \
    --secret-id "$SECRET_NAME" --secret-string "$SECRET_JSON" >/dev/null
else
  aws secretsmanager create-secret \
    --name "$SECRET_NAME" \
    --description "Credenciales de RDS MySQL para ${PROJECT}" \
    --secret-string "$SECRET_JSON" >/dev/null
  echo ">> Secreto creado."
fi

SECRET_ARN="$(aws secretsmanager describe-secret --secret-id "$SECRET_NAME" \
              --query ARN --output text)"
save_state SECRET_ARN "$SECRET_ARN"

echo ">> Secreto listo: ${SECRET_NAME}"
echo "   ARN: ${SECRET_ARN}"
echo "   Claves guardadas: $(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" \
     --query SecretString --output text | python -c 'import json,sys; print(", ".join(json.load(sys.stdin)))')"
