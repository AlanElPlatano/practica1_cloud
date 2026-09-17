#!/usr/bin/env bash
# Crea el key pair y los dos security groups:
#   app-sg : permite HTTP al backend (8000) y SSH administrativo.
#   db-sg  : permite MySQL (3306) UNICAMENTE desde app-sg, nunca desde internet.
source "$(dirname "${BASH_SOURCE[0]}")/00-config.sh"

VPC_ID="$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)"
save_state VPC_ID "$VPC_ID"
echo ">> VPC por defecto: ${VPC_ID}"

# --- Key pair ---
KEY_FILE="$(dirname "${BASH_SOURCE[0]}")/${KEY_NAME}.pem"
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
  echo ">> Key pair ${KEY_NAME} ya existe."
else
  aws ec2 create-key-pair --key-name "$KEY_NAME" --query KeyMaterial --output text > "$KEY_FILE"
  chmod 400 "$KEY_FILE"
  echo ">> Key pair creado: ${KEY_FILE}"
fi
save_state KEY_FILE "$KEY_FILE"

create_sg() {  # nombre, descripcion -> imprime el group id
  local name="$1" desc="$2" id
  id="$(aws ec2 describe-security-groups --filters Name=group-name,Values="$name" Name=vpc-id,Values="$VPC_ID" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)"
  if [ "$id" = "None" ] || [ -z "$id" ]; then
    id="$(aws ec2 create-security-group --group-name "$name" --description "$desc" --vpc-id "$VPC_ID" \
          --query GroupId --output text)"
  fi
  echo "$id"
}

APP_SG_ID="$(create_sg "$APP_SG_NAME" "Backend InstaBox (HTTP + SSH)")"
DB_SG_ID="$(create_sg "$DB_SG_NAME" "RDS MySQL InstaBox")"
save_state APP_SG_ID "$APP_SG_ID"
save_state DB_SG_ID "$DB_SG_ID"
echo ">> app-sg: ${APP_SG_ID}   db-sg: ${DB_SG_ID}"

# authorize-security-group-ingress falla si la regla ya existe: lo ignoramos.
allow() { aws ec2 authorize-security-group-ingress "$@" >/dev/null 2>&1 || true; }

MY_IP="$(curl -s https://checkip.amazonaws.com || echo "0.0.0.0")"
save_state MY_IP "$MY_IP"
echo ">> IP publica detectada para SSH: ${MY_IP}"

allow --group-id "$APP_SG_ID" --protocol tcp --port 22   --cidr "${MY_IP}/32"
allow --group-id "$APP_SG_ID" --protocol tcp --port 8000 --cidr 0.0.0.0/0
allow --group-id "$DB_SG_ID"  --protocol tcp --port 3306 --source-group "$APP_SG_ID"

echo ">> Security groups configurados."
