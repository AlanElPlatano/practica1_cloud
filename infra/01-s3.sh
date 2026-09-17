#!/usr/bin/env bash
# Crea el bucket de S3 que almacena las fotos reducidas (pictures/) y las polaroids (polaroids/).
source "$(dirname "${BASH_SOURCE[0]}")/00-config.sh"

echo ">> Creando bucket s3://${BUCKET}"
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "   El bucket ya existe, se reutiliza."
else
  # us-east-1 es la unica region que NO acepta LocationConstraint.
  aws s3api create-bucket --bucket "$BUCKET" --region "$AWS_DEFAULT_REGION" >/dev/null
fi

# El bucket es privado: la app entrega las imagenes con URLs prefirmadas.
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Prefijos logicos (S3 no tiene carpetas reales, se crean con objetos marcador).
aws s3api put-object --bucket "$BUCKET" --key "pictures/" >/dev/null
aws s3api put-object --bucket "$BUCKET" --key "polaroids/" >/dev/null

save_state BUCKET "$BUCKET"
echo ">> Bucket listo: ${BUCKET}"
