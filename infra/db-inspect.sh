#!/usr/bin/env bash
# Muestra las tablas de RDS desde la EC2.
# RDS no es accesible desde internet, asi que la consulta se hace por SSH y las
# credenciales se leen del secreto, igual que hace la aplicacion.
source "$(dirname "${BASH_SOURCE[0]}")/00-config.sh"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${PUBLIC_IP:?No hay instancia registrada; ejecuta 05-ec2.sh primero}"

ssh -i "$HERE/${KEY_NAME}.pem" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "ec2-user@${PUBLIC_IP}" bash -s <<REMOTE
set -euo pipefail
CREDS="\$(aws secretsmanager get-secret-value --secret-id ${SECRET_NAME} \
         --query SecretString --output text --region ${AWS_DEFAULT_REGION})"
campo() { echo "\$CREDS" | python3 -c "import json,sys; print(json.load(sys.stdin)['\$1'])"; }
H="\$(campo host)"; U="\$(campo username)"; P="\$(campo password)"; D="\$(campo dbname)"

q() { mysql -h "\$H" -u "\$U" -p"\$P" "\$D" --table -e "\$1"; }

echo "=============== Tablas ==============="
q "SHOW TABLES;"

echo "=============== Estructura de events ==============="
q "DESCRIBE events;"

echo "=============== Estructura de photos ==============="
q "DESCRIBE photos;"

echo "=============== Llave foranea photos -> events ==============="
q "SELECT CONSTRAINT_NAME, COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
   FROM information_schema.KEY_COLUMN_USAGE
   WHERE TABLE_SCHEMA='\$D' AND TABLE_NAME='photos' AND REFERENCED_TABLE_NAME IS NOT NULL;"

echo "=============== Eventos y su numero de fotos ==============="
q "SELECT e.event_id, e.client_name, e.event_type, e.event_date,
          COUNT(p.photo_id) AS fotos
   FROM events e LEFT JOIN photos p ON p.event_id = e.event_id
   GROUP BY e.event_id ORDER BY e.created_at;"

echo "=============== Fotos registradas ==============="
q "SELECT photo_id, event_id, message, polaroid_key FROM photos ORDER BY created_at;"
REMOTE
