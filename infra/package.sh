#!/usr/bin/env bash
# Empaqueta app/ en un zip y lo deja en s3://$BUCKET/deploy/app.zip
# (se usa tanto en el arranque inicial de la EC2 como en cada redespliegue).
source "$(dirname "${BASH_SOURCE[0]}")/00-config.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ZIP="$(mktemp -d)/app.zip"
python - "$ROOT" "$ZIP" <<'PY'
import pathlib
import sys
import zipfile

raiz = pathlib.Path(sys.argv[1])
destino = sys.argv[2]
origen = raiz / "app"

with zipfile.ZipFile(destino, "w", zipfile.ZIP_DEFLATED) as zf:
    for archivo in sorted(origen.rglob("*")):
        if archivo.is_file() and "__pycache__" not in archivo.parts:
            zf.write(archivo, archivo.relative_to(raiz).as_posix())
print("Archivos empaquetados:", len(zipfile.ZipFile(destino).namelist()))
PY

aws s3 cp "$ZIP" "s3://${BUCKET}/deploy/app.zip"
rm -rf "$(dirname "$ZIP")"
echo ">> Codigo publicado en s3://${BUCKET}/deploy/app.zip"
