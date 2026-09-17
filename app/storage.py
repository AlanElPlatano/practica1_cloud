"""Operaciones sobre S3. El cliente boto3 toma las credenciales del instance profile."""
import boto3

from config import AWS_REGION, S3_BUCKET

_s3 = boto3.client("s3", region_name=AWS_REGION)


def upload_bytes(key: str, data: bytes, content_type: str = "image/jpeg") -> str:
    """Sube un objeto y devuelve su key."""
    _s3.put_object(Bucket=S3_BUCKET, Key=key, Body=data, ContentType=content_type)
    return key


def download_bytes(key: str) -> bytes:
    return _s3.get_object(Bucket=S3_BUCKET, Key=key)["Body"].read()


def delete_keys(keys: list[str]) -> int:
    """Borra objetos en lotes de 1000 (limite de la API). Devuelve cuantos borro."""
    keys = [k for k in keys if k]
    deleted = 0
    for i in range(0, len(keys), 1000):
        lote = [{"Key": k} for k in keys[i : i + 1000]]
        respuesta = _s3.delete_objects(Bucket=S3_BUCKET, Delete={"Objects": lote})
        deleted += len(respuesta.get("Deleted", []))
    return deleted


def presigned_url(key: str, expires: int = 3600) -> str:
    """URL temporal para ver un objeto sin hacer publico el bucket."""
    return _s3.generate_presigned_url(
        "get_object", Params={"Bucket": S3_BUCKET, "Key": key}, ExpiresIn=expires
    )
