"""Acceso a MySQL en RDS: conexion, esquema y consultas."""
import contextlib

import pymysql
from pymysql.cursors import DictCursor

from config import db_credentials

# Dos tablas relacionadas por event_id: al borrar un evento caen sus fotos.
SCHEMA = [
    """
    CREATE TABLE IF NOT EXISTS events (
        event_id    CHAR(36)     NOT NULL PRIMARY KEY,
        client_name VARCHAR(120) NOT NULL,
        event_type  VARCHAR(60)  NOT NULL,
        event_date  DATE         NOT NULL,
        created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    """,
    """
    CREATE TABLE IF NOT EXISTS photos (
        photo_id     CHAR(36)     NOT NULL PRIMARY KEY,
        event_id     CHAR(36)     NOT NULL,
        message      VARCHAR(255) NOT NULL,
        original_key VARCHAR(255) NULL,
        polaroid_key VARCHAR(255) NOT NULL,
        -- Precision de microsegundos: varias subidas caen en el mismo
        -- segundo y el album debe conservar el orden real de llegada.
        created_at   TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
        CONSTRAINT fk_photos_event FOREIGN KEY (event_id)
            REFERENCES events (event_id) ON DELETE CASCADE,
        INDEX idx_photos_event (event_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    """,
]


@contextlib.contextmanager
def connection():
    """Abre una conexion a RDS con las credenciales del secreto."""
    creds = db_credentials()
    conn = pymysql.connect(
        host=creds["host"],
        port=int(creds.get("port", 3306)),
        user=creds["username"],
        password=creds["password"],
        database=creds["dbname"],
        cursorclass=DictCursor,
        autocommit=False,
        charset="utf8mb4",
        connect_timeout=10,
    )
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def init_schema() -> None:
    """Crea las tablas si no existen. Se ejecuta al arrancar la app."""
    with connection() as conn, conn.cursor() as cur:
        for statement in SCHEMA:
            cur.execute(statement)
