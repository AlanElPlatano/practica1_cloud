"""API del InstaBox.

Flujo: se crea un evento, los invitados suben fotos con un mensaje, y al
terminar se descarga un zip con las polaroids listas para imprimir.
"""
import io
import logging
import re
import uuid
import zipfile
from contextlib import asynccontextmanager
from datetime import date

from fastapi import FastAPI, File, Form, HTTPException, Response, UploadFile
from pydantic import BaseModel, Field

import db
import polaroid
import storage
from config import PICTURES_PREFIX, POLAROIDS_PREFIX, S3_BUCKET

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("polaroid-booth")

MAX_UPLOAD_BYTES = 15 * 1024 * 1024


@asynccontextmanager
async def lifespan(_: FastAPI):
    # Crear el esquema al arrancar hace la instancia reemplazable: si se
    # recrea la EC2, las tablas ya existen o se vuelven a crear solas.
    try:
        db.init_schema()
        log.info("Esquema de base de datos verificado.")
    except Exception:
        log.exception("No se pudo inicializar el esquema; se reintentara despues.")
    yield


app = FastAPI(title="InstaBox API", version="1.0.0", lifespan=lifespan)


class EventIn(BaseModel):
    client_name: str = Field(min_length=1, max_length=120)
    event_type: str = Field(min_length=1, max_length=60)
    event_date: date


class EventRef(BaseModel):
    event_id: str


def _get_event(cur, event_id: str) -> dict:
    cur.execute(
        "SELECT event_id, client_name, event_type, event_date, created_at "
        "FROM events WHERE event_id = %s",
        (event_id,),
    )
    evento = cur.fetchone()
    if not evento:
        raise HTTPException(status_code=404, detail=f"Evento {event_id} no encontrado")
    return evento


@app.get("/health")
def health():
    """Comprueba que la app puede leer el secreto y hablar con RDS."""
    with db.connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT 1 AS ok")
        cur.fetchone()
    return {"status": "ok", "bucket": S3_BUCKET}


@app.post("/events", status_code=201)
def create_event(payload: EventIn):
    """Registra un evento nuevo en RDS y devuelve su event_id."""
    event_id = str(uuid.uuid4())
    with db.connection() as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO events (event_id, client_name, event_type, event_date) "
            "VALUES (%s, %s, %s, %s)",
            (event_id, payload.client_name, payload.event_type, payload.event_date),
        )
    log.info("Evento creado: %s", event_id)
    return {
        "event_id": event_id,
        "client_name": payload.client_name,
        "event_type": payload.event_type,
        "event_date": payload.event_date.isoformat(),
    }


@app.post("/upload", status_code=201)
async def upload_photo(
    event_id: str = Form(...),
    message: str = Form(...),
    photo: UploadFile = File(...),
):
    """Sube la foto reducida, compone la polaroid y guarda todo en RDS.

    Las tres cosas ocurren en la misma llamada: S3 pictures/, S3 polaroids/
    y el registro en la tabla photos.
    """
    raw = await photo.read()
    if not raw:
        raise HTTPException(status_code=400, detail="El archivo llego vacio")
    if len(raw) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="La foto excede 15 MB")

    with db.connection() as conn, conn.cursor() as cur:
        _get_event(cur, event_id)  # valida el evento antes de tocar S3

    try:
        miniatura = polaroid.make_thumbnail(raw)
        compuesta = polaroid.make_polaroid(raw, message)
    except Exception as exc:
        log.exception("Fallo el procesamiento de la imagen")
        raise HTTPException(status_code=400, detail=f"Imagen invalida: {exc}") from exc

    # Nombre unico por foto; la original y la polaroid comparten el UUID
    # para que sea evidente que son la misma pieza.
    photo_id = str(uuid.uuid4())
    original_key = f"{PICTURES_PREFIX}{event_id}/{photo_id}.jpg"
    polaroid_key = f"{POLAROIDS_PREFIX}{event_id}/{photo_id}.jpg"

    storage.upload_bytes(original_key, miniatura)
    storage.upload_bytes(polaroid_key, compuesta)

    with db.connection() as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO photos (photo_id, event_id, message, original_key, polaroid_key) "
            "VALUES (%s, %s, %s, %s, %s)",
            (photo_id, event_id, message, original_key, polaroid_key),
        )

    log.info("Foto %s registrada en el evento %s", photo_id, event_id)
    return {
        "photo_id": photo_id,
        "event_id": event_id,
        "message": message,
        "original_key": original_key,
        "polaroid_key": polaroid_key,
        "polaroid_url": storage.presigned_url(polaroid_key),
    }


@app.get("/events/{event_id}")
def get_event(event_id: str):
    """Metadata del evento y cuantas fotos tiene asociadas."""
    with db.connection() as conn, conn.cursor() as cur:
        evento = _get_event(cur, event_id)
        cur.execute("SELECT COUNT(*) AS total FROM photos WHERE event_id = %s", (event_id,))
        total = cur.fetchone()["total"]

    return {
        "event_id": evento["event_id"],
        "client_name": evento["client_name"],
        "event_type": evento["event_type"],
        "event_date": evento["event_date"].isoformat(),
        "created_at": evento["created_at"].isoformat(),
        "photo_count": total,
    }


@app.get("/events/{event_id}/photos")
def list_photos(event_id: str):
    """Listado de fotos con URLs prefirmadas (util para revisar el resultado)."""
    with db.connection() as conn, conn.cursor() as cur:
        _get_event(cur, event_id)
        cur.execute(
            "SELECT photo_id, message, original_key, polaroid_key, created_at "
            "FROM photos WHERE event_id = %s ORDER BY created_at, photo_id",
            (event_id,),
        )
        fotos = cur.fetchall()

    return [
        {
            "photo_id": f["photo_id"],
            "message": f["message"],
            "original_key": f["original_key"],
            "polaroid_key": f["polaroid_key"],
            "polaroid_url": storage.presigned_url(f["polaroid_key"]),
        }
        for f in fotos
    ]


def _slug(texto: str, limite: int = 40) -> str:
    limpio = re.sub(r"[^a-zA-Z0-9]+", "-", texto).strip("-").lower()
    return limpio[:limite] or "mensaje"


@app.post("/finish")
def finish_event(payload: EventRef):
    """Empaqueta las polaroids del evento en un zip descargable.

    Cierra el evento: una vez generado el album, las fotos originales
    reducidas se eliminan de S3, como indica el flujo del servicio.
    """
    event_id = payload.event_id
    with db.connection() as conn, conn.cursor() as cur:
        evento = _get_event(cur, event_id)
        cur.execute(
            "SELECT photo_id, message, original_key, polaroid_key "
            "FROM photos WHERE event_id = %s ORDER BY created_at, photo_id",
            (event_id,),
        )
        fotos = cur.fetchall()

    if not fotos:
        raise HTTPException(status_code=404, detail="El evento no tiene fotos")

    # El zip se arma primero: solo se borran originales si el album quedo bien.
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        indice = []
        for i, foto in enumerate(fotos, start=1):
            nombre = f"{i:02d}_{_slug(foto['message'])}.jpg"
            zf.writestr(nombre, storage.download_bytes(foto["polaroid_key"]))
            indice.append(f"{nombre}\t{foto['message']}")
        encabezado = (
            f"{evento['client_name']} - {evento['event_type']} - {evento['event_date']}\n"
            f"{len(fotos)} polaroids\n\n"
        )
        zf.writestr("album.txt", encabezado + "\n".join(indice) + "\n")

    originales = [f["original_key"] for f in fotos if f["original_key"]]
    borradas = storage.delete_keys(originales)
    with db.connection() as conn, conn.cursor() as cur:
        cur.execute("UPDATE photos SET original_key = NULL WHERE event_id = %s", (event_id,))
    log.info(
        "Evento %s cerrado: %s polaroids, %s originales borradas",
        event_id, len(fotos), borradas,
    )

    archivo = f"album-{_slug(evento['client_name'])}-{event_id[:8]}.zip"
    return Response(
        content=buffer.getvalue(),
        media_type="application/zip",
        headers={
            "Content-Disposition": f'attachment; filename="{archivo}"',
            "X-Polaroid-Count": str(len(fotos)),
            "X-Originals-Deleted": str(borradas),
        },
    )
