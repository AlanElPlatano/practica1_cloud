#!/usr/bin/env bash
# Recorrido completo de la API, pensado para la demostración en video.
#
#   ./demo.sh                 usa la IP guardada en infra/.state
#   ./demo.sh http://1.2.3.4:8000
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [ $# -ge 1 ]; then
  API="$1"
else
  source infra/00-config.sh
  API="http://${PUBLIC_IP:?No hay IP registrada; pasa la URL como argumento}:8000"
fi

titulo() { echo; echo "=============== $* ==============="; }

titulo "0. Salud del servicio (lee el secreto y consulta RDS)"
curl -s "$API/health"; echo

titulo "1. POST /events"
EVENTO="$(curl -s -X POST "$API/events" \
  -H 'Content-Type: application/json' \
  -d '{"client_name":"Ana y Luis","event_type":"boda","event_date":"2026-09-20"}')"
echo "$EVENTO" | python -m json.tool
EVENT_ID="$(echo "$EVENTO" | python -c 'import json,sys; print(json.load(sys.stdin)["event_id"])')"
echo "EVENT_ID = $EVENT_ID"

# Cada foto va con el mensaje que el invitado dejo para los festejados.
FOTOS=(
  "samples/babymetal-metal_forth.jpg"
  "samples/tt.jpg"
  "samples/TheStageA7X.jpg"
)
MENSAJES=(
  "album chido"
  "teletubie"
  "segundo album chido"
)

titulo "2. POST /upload  (${#FOTOS[@]} fotos con mensaje)"
for i in "${!FOTOS[@]}"; do
  echo "--- ${FOTOS[$i]} ---"
  curl -s -X POST "$API/upload" \
    -F "event_id=${EVENT_ID}" \
    -F "message=${MENSAJES[$i]}" \
    -F "photo=@${FOTOS[$i]}" | python -m json.tool
done

titulo "3. GET /events/{event_id}"
curl -s "$API/events/$EVENT_ID" | python -m json.tool

titulo "4. POST /finish  (descarga del album)"
rm -rf album album.zip
curl -s -X POST "$API/finish" \
  -H 'Content-Type: application/json' \
  -d "{\"event_id\":\"$EVENT_ID\"}" \
  -o album.zip
python -c "
import zipfile
with zipfile.ZipFile('album.zip') as z:
    z.extractall('album')
    for n in z.namelist():
        print(' ', n)
"
echo
echo "Album descargado en ./album/  (EVENT_ID = $EVENT_ID)"
