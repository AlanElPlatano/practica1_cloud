#!/usr/bin/env bash
# Empaqueta el backend, lo sube a S3 y lanza la EC2 que lo ejecuta.
# La instancia usa el instance profile LabInstanceProfile: no lleva claves de usuario.
source "$(dirname "${BASH_SOURCE[0]}")/00-config.sh"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"

# --- 1. Empaquetar el codigo y subirlo a S3 ---
bash "$HERE/package.sh"

# --- 2. Resolver la AMI mas reciente de Amazon Linux 2023 ---
# El parametro publico de SSM es la via corta, pero el Learner Lab no siempre
# permite ssm:GetParameter; en ese caso se busca la AMI en el catalogo de EC2.
AMI_ID="$(aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value --output text 2>/dev/null || true)"
if [ -z "$AMI_ID" ] || [ "$AMI_ID" = "None" ]; then
  AMI_ID="$(aws ec2 describe-images --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023.*-kernel-6.1-x86_64" \
              "Name=state,Values=available" \
    --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)"
fi
echo ">> AMI: ${AMI_ID}"

# --- 3. Renderizar el user-data con los valores reales ---
# Se escribe junto al proyecto y se referencia con ruta relativa: en Git Bash
# un file:// con ruta tipo /tmp lo mal traduce el AWS CLI nativo de Windows.
cd "$ROOT"
USER_DATA="infra/.user-data.rendered"
sed -e "s|__BUCKET__|${BUCKET}|g" \
    -e "s|__SECRET_NAME__|${SECRET_NAME}|g" \
    -e "s|__REGION__|${AWS_DEFAULT_REGION}|g" \
    "infra/user-data.sh" > "$USER_DATA"

# --- 4. Lanzar la instancia ---
SUBNET_ID="$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" \
             --query 'Subnets[0].SubnetId' --output text)"

INSTANCE_ID="$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type t3.micro \
  --key-name "$KEY_NAME" \
  --subnet-id "$SUBNET_ID" \
  --security-group-ids "$APP_SG_ID" \
  --iam-instance-profile "Name=${INSTANCE_PROFILE}" \
  --associate-public-ip-address \
  --user-data "file://${USER_DATA}" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${EC2_NAME}},{Key=Project,Value=${PROJECT}}]" \
  --query 'Instances[0].InstanceId' --output text)"

save_state INSTANCE_ID "$INSTANCE_ID"
echo ">> Instancia lanzada: ${INSTANCE_ID}"

aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
PUBLIC_IP="$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
             --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
save_state PUBLIC_IP "$PUBLIC_IP"

echo ">> IP publica: ${PUBLIC_IP}"
echo ">> API: http://${PUBLIC_IP}:8000/docs"
echo ">> El bootstrap (instalar dependencias) tarda 2-3 min mas."
