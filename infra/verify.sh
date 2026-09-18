#!/usr/bin/env bash
# Reune en una sola salida la evidencia de que la arquitectura esta en pie:
# EC2 con su instance profile, RDS privada, bucket, secreto, y la comprobacion
# de que la aplicacion usa el rol de la instancia y no credenciales de usuario.
source "$(dirname "${BASH_SOURCE[0]}")/00-config.sh"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

titulo() { echo; echo "=============== $* ==============="; }

titulo "EC2 e instance profile"
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=${PROJECT}" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].{Instancia:InstanceId,Tipo:InstanceType,IP:PublicIpAddress,InstanceProfile:IamInstanceProfile.Arn}' \
  --output table

titulo "RDS"
aws rds describe-db-instances --db-instance-identifier "$DB_IDENTIFIER" \
  --query 'DBInstances[0].{Identificador:DBInstanceIdentifier,Motor:Engine,Version:EngineVersion,Estado:DBInstanceStatus,AccesiblePublicamente:PubliclyAccessible,Endpoint:Endpoint.Address}' \
  --output table

titulo "Secrets Manager"
aws secretsmanager list-secrets \
  --query "SecretList[?Name=='${SECRET_NAME}'].{Nombre:Name,ARN:ARN}" --output table
echo "Claves dentro del secreto (sin mostrar sus valores):"
aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --query SecretString --output text \
  | python -c 'import json,sys; print("  " + ", ".join(json.load(sys.stdin)))'

titulo "S3"
aws s3 ls "s3://${BUCKET}/" --recursive --human-readable --summarize \
  | grep -v '^ *deploy/' | tail -25

titulo "Security groups"
aws ec2 describe-security-groups --filters "Name=group-name,Values=${PROJECT}-*" \
  --query 'SecurityGroups[].{Nombre:GroupName,Id:GroupId}' --output table
echo "Regla de entrada de la base de datos (solo desde el SG de la app):"
aws ec2 describe-security-groups --group-ids "$DB_SG_ID" \
  --query 'SecurityGroups[0].IpPermissions[].{Puerto:FromPort,OrigenSG:UserIdGroupPairs[0].GroupId,OrigenCIDR:IpRanges[0].CidrIp}' \
  --output table

if [ -n "${PUBLIC_IP:-}" ]; then
  titulo "Dentro de la EC2: identidad efectiva y servicio"
  ssh -i "$HERE/${KEY_NAME}.pem" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR "ec2-user@${PUBLIC_IP}" bash -s <<'REMOTE'
echo "-- Rol entregado por el instance profile (metadata service IMDSv2):"
TOKEN="$(curl -s -X PUT http://169.254.169.254/latest/api/token \
         -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')"
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
     http://169.254.169.254/latest/meta-data/iam/security-credentials/; echo
echo "-- Identidad con la que la app firma sus llamadas a AWS:"
aws sts get-caller-identity --output table
echo "-- No hay credenciales en disco ni en el entorno del servicio:"
ls -la ~/.aws 2>/dev/null || echo "   (no existe ~/.aws)"
sudo systemctl show instabox -p Environment
echo "-- Estado del servicio:"
systemctl is-active instabox
REMOTE
fi

echo
echo "Verificacion terminada."
