#!/usr/bin/env bash
# Elimina TODOS los recursos de AWS creados por este proyecto.
#
#   ./teardown.sh          pide confirmacion
#   ./teardown.sh --yes    no pregunta
#
# El orden importa: primero lo que depende de otra cosa (EC2 antes que los
# security groups, RDS antes que su subnet group).
source "$(dirname "${BASH_SOURCE[0]}")/infra/00-config.sh"
# 00-config.sh activa 'set -e'; aqui lo desactivamos a proposito porque la
# limpieza debe continuar aunque un recurso ya no exista.
set +e

if [ "${1:-}" != "--yes" ]; then
  echo "Se eliminaran los recursos de '${PROJECT}' en ${AWS_DEFAULT_REGION}:"
  echo "  EC2 ${INSTANCE_ID:-(ninguna)} | RDS ${DB_IDENTIFIER} | S3 ${BUCKET}"
  echo "  Secret ${SECRET_NAME} | SGs ${APP_SG_NAME}, ${DB_SG_NAME} | Key ${KEY_NAME}"
  read -r -p "Escribe 'si' para continuar: " respuesta
  [ "$respuesta" = "si" ] || { echo "Cancelado."; exit 1; }
fi

echo
echo "=============== 1/6  EC2 ==============="
if [ -n "${INSTANCE_ID:-}" ]; then
  aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" \
    --query 'TerminatingInstances[0].CurrentState.Name' --output text || true
  echo "Esperando a que la instancia termine..."
  aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" || true
  echo "EC2 ${INSTANCE_ID} terminada."
else
  echo "No hay instancia registrada."
fi

echo
echo "=============== 2/6  RDS ==============="
if aws rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" >/dev/null 2>&1; then
  aws rds delete-db-instance --db-instance-identifier "$DB_IDENTIFIER" \
    --skip-final-snapshot --delete-automated-backups >/dev/null
  echo "Borrando ${DB_IDENTIFIER} (tarda unos minutos)..."
  aws rds wait db-instance-deleted --db-instance-identifier "$DB_IDENTIFIER" || true
  echo "RDS eliminada."
else
  echo "La instancia RDS no existe."
fi
aws rds delete-db-subnet-group --db-subnet-group-name "$DB_SUBNET_GROUP" 2>/dev/null \
  && echo "Subnet group eliminado." || echo "Subnet group ya no existe."

echo
echo "=============== 3/6  S3 ==============="
if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  aws s3 rm "s3://${BUCKET}" --recursive >/dev/null
  aws s3api delete-bucket --bucket "$BUCKET"
  echo "Bucket ${BUCKET} vaciado y eliminado."
else
  echo "El bucket no existe."
fi

echo
echo "=============== 4/6  Secrets Manager ==============="
# --force-delete-without-recovery evita la ventana de retencion de 7 dias.
aws secretsmanager delete-secret --secret-id "$SECRET_NAME" \
  --force-delete-without-recovery >/dev/null 2>&1 \
  && echo "Secreto ${SECRET_NAME} eliminado." || echo "El secreto no existe."

echo
echo "=============== 5/6  Security groups ==============="
# db-sg primero: app-sg no se puede borrar mientras db-sg lo referencie.
for sg in "${DB_SG_ID:-}" "${APP_SG_ID:-}"; do
  [ -n "$sg" ] || continue
  for intento in 1 2 3 4 5; do
    if aws ec2 delete-security-group --group-id "$sg" >/dev/null 2>&1; then
      echo "Security group ${sg} eliminado."
      break
    fi
    # Las ENI de la EC2 tardan un poco en liberarse tras el terminate.
    [ "$intento" = 5 ] && echo "No se pudo borrar ${sg} (revisa dependencias)." || sleep 15
  done
done

echo
echo "=============== 6/6  Key pair ==============="
aws ec2 delete-key-pair --key-name "$KEY_NAME" >/dev/null 2>&1 \
  && echo "Key pair ${KEY_NAME} eliminado." || echo "El key pair no existe."
rm -f "$(dirname "${BASH_SOURCE[0]}")/infra/${KEY_NAME}.pem"
rm -f "$STATE_FILE"

echo
echo "=============== VERIFICACION ==============="
echo "-- Instancias EC2 del proyecto (se espera vacio o 'terminated'):"
aws ec2 describe-instances --filters "Name=tag:Project,Values=${PROJECT}" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output text || true
echo "-- Instancias RDS (se espera vacio):"
aws rds describe-db-instances --query "DBInstances[?DBInstanceIdentifier=='${DB_IDENTIFIER}'].DBInstanceIdentifier" --output text || true
echo "-- Buckets S3 (se espera vacio):"
aws s3 ls | grep "$PROJECT" || echo "(ninguno)"
echo "-- Secretos (se espera vacio):"
aws secretsmanager list-secrets --query "SecretList[?Name=='${SECRET_NAME}'].Name" --output text || true
echo "-- Security groups (se espera vacio):"
aws ec2 describe-security-groups --filters "Name=group-name,Values=${PROJECT}-*" \
  --query 'SecurityGroups[].GroupName' --output text || true
echo
echo "Limpieza terminada."
