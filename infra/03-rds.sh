#!/usr/bin/env bash
# Crea el subnet group y la instancia RDS MySQL. La instancia NO es publica:
# solo se alcanza desde la EC2 del backend a traves de db-sg.
source "$(dirname "${BASH_SOURCE[0]}")/00-config.sh"

# --- Subnet group con las subredes por defecto de la VPC ---
SUBNET_IDS="$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" \
              --query 'Subnets[].SubnetId' --output text)"
if ! aws rds describe-db-subnet-groups --db-subnet-group-name "$DB_SUBNET_GROUP" >/dev/null 2>&1; then
  aws rds create-db-subnet-group \
    --db-subnet-group-name "$DB_SUBNET_GROUP" \
    --db-subnet-group-description "Subnets para ${PROJECT}" \
    --subnet-ids $SUBNET_IDS >/dev/null
  echo ">> Subnet group creado: ${DB_SUBNET_GROUP}"
else
  echo ">> Subnet group ya existe: ${DB_SUBNET_GROUP}"
fi

# --- Password aleatorio; solo vive en Secrets Manager y en el archivo de estado local ---
if [ -z "${DB_PASSWORD:-}" ]; then
  # openssl produce salida finita, asi que el pipe no dispara SIGPIPE con pipefail.
  DB_PASSWORD="$(openssl rand -hex 16)"
  save_state DB_PASSWORD "$DB_PASSWORD"
fi

if aws rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" >/dev/null 2>&1; then
  echo ">> La instancia RDS ${DB_IDENTIFIER} ya existe."
else
  echo ">> Creando instancia RDS ${DB_IDENTIFIER} (tarda ~8 min)..."
  aws rds create-db-instance \
    --db-instance-identifier "$DB_IDENTIFIER" \
    --db-instance-class db.t3.micro \
    --engine mysql \
    --engine-version 8.0 \
    --master-username "$DB_USER" \
    --master-user-password "$DB_PASSWORD" \
    --db-name "$DB_NAME" \
    --allocated-storage 20 \
    --storage-type gp2 \
    --vpc-security-group-ids "$DB_SG_ID" \
    --db-subnet-group-name "$DB_SUBNET_GROUP" \
    --no-publicly-accessible \
    --backup-retention-period 0 \
    --no-multi-az \
    --no-auto-minor-version-upgrade >/dev/null
fi

echo ">> Esperando a que la instancia quede disponible..."
aws rds wait db-instance-available --db-instance-identifier "$DB_IDENTIFIER"

DB_HOST="$(aws rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" \
           --query 'DBInstances[0].Endpoint.Address' --output text)"
save_state DB_HOST "$DB_HOST"
echo ">> RDS disponible en: ${DB_HOST}"
