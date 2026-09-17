"""Configuracion de la aplicacion.

Las credenciales de RDS NO viven en variables de ambiente ni en el codigo:
se leen de AWS Secrets Manager en tiempo de ejecucion, usando las credenciales
temporales que la EC2 obtiene de su instance profile (LabInstanceProfile).
"""
import json
import os
from functools import lru_cache

import boto3

# Configuracion no sensible: solo el *nombre* del secreto y el bucket.
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
SECRET_NAME = os.environ.get("SECRET_NAME", "polaroid-booth/rds")
S3_BUCKET = os.environ.get("S3_BUCKET", "")

# Prefijos dentro del bucket.
PICTURES_PREFIX = "pictures/"
POLAROIDS_PREFIX = "polaroids/"


@lru_cache(maxsize=1)
def db_credentials() -> dict:
    """Devuelve las credenciales de RDS desde Secrets Manager.

    Se cachea porque el secreto no rota durante la vida del proceso; si rotara,
    bastaria con limpiar el cache (db_credentials.cache_clear()).
    """
    client = boto3.client("secretsmanager", region_name=AWS_REGION)
    response = client.get_secret_value(SecretId=SECRET_NAME)
    return json.loads(response["SecretString"])
