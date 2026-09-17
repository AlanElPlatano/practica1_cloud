#!/usr/bin/env bash
# Redespliegue rapido: vuelve a empaquetar app/, lo sube a S3 y reinicia el
# servicio en la EC2. Util para iterar sin recrear la instancia.
source "$(dirname "${BASH_SOURCE[0]}")/00-config.sh"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "${PUBLIC_IP:-}" ]; then
  echo "ERROR: no hay instancia registrada. Ejecuta 05-ec2.sh primero." >&2
  exit 1
fi

bash "$HERE/package.sh"

SSH_OPTS=(-i "$HERE/${KEY_NAME}.pem" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
ssh "${SSH_OPTS[@]}" "ec2-user@${PUBLIC_IP}" bash -s <<REMOTE
set -euxo pipefail
sudo aws s3 cp "s3://${BUCKET}/deploy/app.zip" /tmp/app.zip --region ${AWS_DEFAULT_REGION}
sudo unzip -o /tmp/app.zip -d /opt/polaroid-booth
sudo chown -R ec2-user:ec2-user /opt/polaroid-booth
sudo /opt/polaroid-booth/venv/bin/pip install -q -r /opt/polaroid-booth/app/requirements.txt
sudo systemctl restart polaroid-booth
sleep 3
systemctl is-active polaroid-booth
REMOTE

echo ">> Redespliegue completo: http://${PUBLIC_IP}:8000/docs"
