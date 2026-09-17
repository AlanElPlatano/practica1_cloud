# Polaroid Booth — backend en AWS

Backend para la estación de fotos de un fotógrafo de bodas y eventos sociales.
Los invitados suben una foto con un mensaje para los festejados; el servicio
guarda la foto reducida, compone una **polaroid** (marco blanco + mensaje
escrito debajo) y, al cerrar el evento, entrega un `.zip` con el álbum listo
para imprimir.

Un mismo fotógrafo atiende varios eventos a la vez, así que cada foto queda
asociada a su `event_id` en la base de datos.

---

## Arquitectura

```
                    Internet
                        │
                        │  HTTP :8000
                        ▼
        ┌───────────────────────────────┐
        │  EC2 t3.micro (Amazon Linux)  │
        │  FastAPI + Uvicorn + Pillow   │
        │                               │
        │  Instance profile:            │
        │     LabInstanceProfile        │
        └───────────────────────────────┘
             │           │            │
   (1) GetSecretValue    │            │ (3) MySQL :3306
             │       (2) S3           │     (solo desde app-sg)
             ▼           ▼            ▼
   ┌──────────────┐ ┌──────────┐ ┌──────────────────┐
   │   Secrets    │ │    S3    │ │  RDS MySQL 8.0   │
   │   Manager    │ │  bucket  │ │  (no público)    │
   │              │ │          │ │                  │
   │ host, port,  │ │pictures/ │ │  events          │
   │ user, pass,  │ │polaroids/│ │  photos ─┐       │
   │ dbname       │ │          │ │     event_id FK  │
   └──────────────┘ └──────────┘ └──────────────────┘
```

**Cómo se conecta todo.** La EC2 no lleva ninguna credencial escrita. Al
arrancar, la app pide a Secrets Manager el secreto `polaroid-booth/rds` usando
las credenciales temporales que el **instance profile `LabInstanceProfile`**
entrega a través del metadata service, y con esas credenciales abre la conexión
a RDS. El mismo instance profile firma las llamadas a S3.

RDS vive en subredes privadas de la VPC por defecto y **no es accesible desde
internet**: su security group (`polaroid-booth-db-sg`) solo acepta el puerto
3306 con origen en el security group de la aplicación (`polaroid-booth-app-sg`).
El bucket de S3 tiene *Block Public Access* activado; las imágenes se comparten
mediante URLs prefirmadas que caducan en una hora.

En `POST /upload` la petición hace tres cosas en una sola llamada: reduce la
foto a 128×128 y la sube a `pictures/`, compone la polaroid (696×828 px) y la
sube a `polaroids/`, y escribe el renglón correspondiente en la tabla `photos`.
Las dos imágenes comparten el mismo UUID, de modo que original y polaroid son
trazables entre sí. En `POST /finish` se arma el `.zip` con las polaroids del
evento y **después** se borran de S3 las fotos originales, tal como pide el
flujo del servicio.

---

## Estructura del repositorio

```
app/                  Backend (Python 3.11 + FastAPI)
  main.py             Endpoints
  db.py               Conexión a MySQL y esquema (events, photos)
  config.py           Lectura del secreto desde Secrets Manager
  storage.py          Operaciones sobre S3
  polaroid.py         Miniatura 128x128 y composición Polaroid con Pillow
  requirements.txt

infra/                Aprovisionamiento (Bash + AWS CLI)
  00-config.sh        Nombres de recursos y archivo de estado
  01-s3.sh            Bucket + prefijos pictures/ y polaroids/
  02-security.sh      Key pair y los dos security groups
  03-rds.sh           Subnet group e instancia RDS MySQL
  04-secret.sh        Secreto en Secrets Manager
  05-ec2.sh           Empaqueta el código, lo sube a S3 y lanza la EC2
  user-data.sh        Bootstrap de la instancia (venv + systemd)
  package.sh          Empaqueta app/ y lo publica en S3
  deploy.sh           Redespliegue rápido sin recrear la instancia

teardown.sh           Elimina todos los recursos
samples/              Fotos de prueba para la demostración
```

---

## Requisitos previos

- AWS CLI v2 configurado con credenciales que puedan crear EC2, RDS, S3 y
  Secrets Manager (en AWS Academy Learner Lab basta con el bloque de
  credenciales que muestra la consola del laboratorio).
- Python 3 y Bash en la máquina local (Git Bash en Windows).
- El instance profile **`LabInstanceProfile`** debe existir en la cuenta.

---

## Despliegue

Los scripts se ejecutan en orden y comparten un archivo de estado
(`infra/.state`) donde guardan los IDs generados.

```bash
bash infra/01-s3.sh        # bucket
bash infra/02-security.sh  # key pair + security groups
bash infra/03-rds.sh       # RDS MySQL (tarda ~8 min)
bash infra/04-secret.sh    # secreto con las credenciales de RDS
bash infra/05-ec2.sh       # empaqueta el código y lanza la EC2
```

Al terminar, `05-ec2.sh` imprime la IP pública. El bootstrap de la instancia
tarda 2–3 minutos adicionales en instalar dependencias; cuando termina, la
documentación interactiva queda en `http://<IP>:8000/docs`.

Para comprobar que la app puede leer el secreto y hablar con RDS:

```bash
curl http://<IP>:8000/health
```

Si se modifica el código, `bash infra/deploy.sh` lo vuelve a publicar y
reinicia el servicio sin recrear la instancia.

---

## Endpoints

Todos los ejemplos usan `API=http://<IP>:8000`.

### `POST /events` — crea un evento

```bash
curl -s -X POST $API/events \
  -H 'Content-Type: application/json' \
  -d '{"client_name":"Ana y Luis","event_type":"boda","event_date":"2026-09-20"}'
```

```json
{
  "event_id": "1f0c2a54-...",
  "client_name": "Ana y Luis",
  "event_type": "boda",
  "event_date": "2026-09-20"
}
```

### `POST /upload` — sube una foto con mensaje

Recibe `multipart/form-data`. Sube la foto reducida a `pictures/`, genera y
sube la polaroid a `polaroids/`, y guarda la metadata en RDS.

```bash
curl -s -X POST $API/upload \
  -F "event_id=$EVENT_ID" \
  -F "message=Felicidades Ana y Luis!" \
  -F "photo=@samples/foto1.jpg"
```

Devuelve el `photo_id`, las dos rutas en S3 y una URL prefirmada para ver la
polaroid en el navegador.

### `GET /events/{event_id}` — metadata y número de fotos

```bash
curl -s $API/events/$EVENT_ID
```

```json
{
  "event_id": "1f0c2a54-...",
  "client_name": "Ana y Luis",
  "event_type": "boda",
  "event_date": "2026-09-20",
  "created_at": "2026-09-17T22:41:09",
  "photo_count": 3
}
```

### `POST /finish` — descarga el álbum

Consulta en RDS las polaroids del evento, las empaqueta en un `.zip` y borra
de S3 las fotos originales.

```bash
curl -s -X POST $API/finish \
  -H 'Content-Type: application/json' \
  -d "{\"event_id\":\"$EVENT_ID\"}" \
  -o album.zip
```

El zip incluye las polaroids numeradas y un `album.txt` con los mensajes.

### Extras

- `GET /health` — verifica el acceso al secreto y a RDS.
- `GET /events/{event_id}/photos` — listado con URLs prefirmadas.

---

## Verificación en la consola de AWS

| Recurso | Dónde mirar |
|---|---|
| Bucket y objetos | S3 → `polaroid-booth-<ACCOUNT_ID>` → `pictures/`, `polaroids/` |
| Base de datos | RDS → Databases → `polaroid-booth-db` |
| Secreto | Secrets Manager → `polaroid-booth/rds` → *Retrieve secret value* |
| Instancia y su rol | EC2 → Instances → `polaroid-booth-api` → pestaña *Security* → **IAM Role: LabInstanceProfile** |

Para ver las tablas directamente, desde la EC2 (RDS no es accesible desde fuera
de la VPC):

```bash
ssh -i infra/polaroid-booth-key.pem ec2-user@<IP>
# el host de RDS se obtiene del propio secreto
mysql -h <endpoint-rds> -u polaroid_admin -p polaroid -e "
  SELECT e.client_name, e.event_type, COUNT(p.photo_id) AS fotos
  FROM events e LEFT JOIN photos p ON p.event_id = e.event_id
  GROUP BY e.event_id;"
```

---

## Eliminar los recursos

```bash
./teardown.sh          # pide confirmación
./teardown.sh --yes    # sin preguntar
```

El script borra, en este orden: la instancia EC2, la instancia RDS y su subnet
group, el bucket de S3 (lo vacía primero), el secreto de Secrets Manager —con
`--force-delete-without-recovery`, para que no quede en la ventana de
retención de 7 días—, los dos security groups y el key pair. Al final imprime
una verificación consultando cada servicio, que debe salir vacía.

Si se prefiere hacerlo a mano, es exactamente esa misma secuencia; el orden
importa porque los security groups no se pueden borrar mientras la EC2 siga
usando sus interfaces de red.
