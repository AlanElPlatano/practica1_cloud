# Descripción del proyecto

**Polaroid Booth** es el backend de una estación de fotos para bodas y eventos
sociales. Durante la fiesta, los invitados suben una fotografía acompañada de un
mensaje para los festejados; al terminar, el fotógrafo descarga un álbum de
polaroids listo para imprimir. Como un mismo fotógrafo atiende varios eventos a
la vez, cada imagen queda ligada a su evento dentro de la base de datos.

El servicio expone cuatro endpoints construidos con FastAPI. `POST /events`
registra un evento y devuelve su `event_id`. `POST /upload` resuelve tres tareas
en una sola llamada: reduce la foto a 128×128 px y la guarda en `pictures/`,
compone la polaroid con marco blanco y el mensaje escrito debajo usando Pillow,
la sube a `polaroids/` y escribe el registro correspondiente en la base.
`GET /events/{event_id}` devuelve la metadata del evento junto con el número de
fotos asociadas, y `POST /finish` empaqueta las polaroids del evento en un `.zip`
descargable y elimina de S3 las fotos originales, cerrando el ciclo del servicio.

La aplicación corre bajo systemd en una instancia EC2 `t3.micro` con Amazon Linux
2023. Las imágenes viven en un bucket de S3 con *Block Public Access* activado, y
se comparten mediante URLs prefirmadas; cada foto usa un UUID que comparten la
versión original y su polaroid. Los metadatos se guardan en RDS MySQL 8.0, en
subredes privadas y sin acceso desde internet: su security group solo admite el
puerto 3306 con origen en el security group de la aplicación.

La instancia no almacena ninguna credencial. Gracias al instance profile
`LabInstanceProfile`, la aplicación obtiene credenciales temporales del metadata
service y con ellas lee de Secrets Manager, en tiempo de ejecución, el usuario y
la contraseña de la base de datos. Un script `teardown.sh` elimina después todos
los recursos creados.
