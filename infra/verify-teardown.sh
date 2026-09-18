#!/usr/bin/env bash
# Comprueba, recurso por recurso, que ya no queda nada del proyecto en AWS.
#
# teardown.sh lo ejecuta al terminar, pero tambien sirve por separado para
# volver a mostrar la evidencia sin repetir el borrado:
#
#   bash infra/verify-teardown.sh
source "$(dirname "${BASH_SOURCE[0]}")/00-config.sh"
set +e

PENDIENTES=0

# Imprime una linea por recurso. Si la consulta no devolvio nada, ese recurso
# ya no existe; cualquier otra cosa es que sigue vivo.
comprobar() {
  local etiqueta="$1" encontrado="$2"
  if [ -z "$encontrado" ] || [ "$encontrado" = "None" ]; then
    printf '  %-18s %-28s ELIMINADO\n' "$etiqueta" "$3"
  else
    printf '  %-18s %-28s SIGUE EXISTIENDO\n' "$etiqueta" "$3"
    PENDIENTES=$((PENDIENTES + 1))
  fi
}

echo "=============================================================="
echo " VERIFICACION DE ELIMINACION - proyecto '${PROJECT}' (${AWS_DEFAULT_REGION})"
echo "=============================================================="
echo

# Una instancia terminada sigue apareciendo en describe-instances durante un
# rato, asi que se excluye ese estado: solo cuentan las que siguen vivas.
comprobar "EC2" "$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=${PROJECT}" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" \
  --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null)" "$EC2_NAME"

comprobar "RDS" "$(aws rds describe-db-instances \
  --query "DBInstances[?DBInstanceIdentifier=='${DB_IDENTIFIER}'].DBInstanceIdentifier" \
  --output text 2>/dev/null)" "$DB_IDENTIFIER"

comprobar "Subnet group" "$(aws rds describe-db-subnet-groups \
  --db-subnet-group-name "$DB_SUBNET_GROUP" \
  --query 'DBSubnetGroups[0].DBSubnetGroupName' --output text 2>/dev/null)" "$DB_SUBNET_GROUP"

comprobar "Bucket S3" "$(aws s3api list-buckets \
  --query "Buckets[?Name=='${BUCKET}'].Name" --output text 2>/dev/null)" "$BUCKET"

comprobar "Secreto" "$(aws secretsmanager list-secrets \
  --query "SecretList[?Name=='${SECRET_NAME}'].Name" --output text 2>/dev/null)" "$SECRET_NAME"

comprobar "Security groups" "$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${PROJECT}-*" \
  --query 'SecurityGroups[].GroupName' --output text 2>/dev/null)" "${PROJECT}-app-sg, -db-sg"

comprobar "Key pair" "$(aws ec2 describe-key-pairs --key-names "$KEY_NAME" \
  --query 'KeyPairs[0].KeyName' --output text 2>/dev/null)" "$KEY_NAME"

echo
echo "=============================================================="
if [ "$PENDIENTES" -eq 0 ]; then
  echo " RESULTADO: todos los recursos fueron eliminados."
else
  echo " RESULTADO: quedan ${PENDIENTES} recurso(s) sin eliminar."
  echo " Vuelve a ejecutar ./teardown.sh (es seguro repetirlo)."
fi
echo "=============================================================="
exit 0
