#!/bin/bash
# Bootstrap de la EC2. Se ejecuta una sola vez al primer arranque.
# Los marcadores __BUCKET__, __SECRET_NAME__ y __REGION__ los sustituye 05-ec2.sh.
set -xo pipefail
exec > >(tee /var/log/polaroid-bootstrap.log) 2>&1

APP_DIR=/opt/polaroid-booth

# mariadb105 trae el cliente mysql, util para inspeccionar las tablas por SSH.
# Las fuentes dejavu son las que usa Pillow para escribir el mensaje.
dnf -y install unzip mariadb105 dejavu-serif-fonts dejavu-sans-fonts
if dnf -y install python3.11 python3.11-pip; then
  PYBIN=python3.11
else
  dnf -y install python3 python3-pip
  PYBIN=python3
fi

# El codigo viaja por S3; la EC2 lo descarga con las credenciales de su
# instance profile, sin claves de usuario de por medio.
mkdir -p "$APP_DIR"
aws s3 cp "s3://__BUCKET__/deploy/app.zip" /tmp/app.zip --region __REGION__
unzip -o /tmp/app.zip -d "$APP_DIR"

$PYBIN -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install --upgrade pip
"$APP_DIR/venv/bin/pip" install -r "$APP_DIR/app/requirements.txt"
chown -R ec2-user:ec2-user "$APP_DIR"

# Solo configuracion no sensible: el nombre del secreto y el bucket.
# La contrasena de RDS jamas se escribe aqui.
cat > /etc/systemd/system/polaroid-booth.service <<UNIT
[Unit]
Description=InstaBox API
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=${APP_DIR}/app
Environment=AWS_REGION=__REGION__
Environment=SECRET_NAME=__SECRET_NAME__
Environment=S3_BUCKET=__BUCKET__
ExecStart=${APP_DIR}/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now polaroid-booth.service
echo "BOOTSTRAP COMPLETADO"
