1 Descripción de la actividad
Un fotógrafo ofrece un servicio para bodas y eventos sociales: coloca una estación donde los invitados suben fotos junto con un mensaje para los festejados. El fotógrafo atiende varios eventos a la vez, así que necesita llevar el registro de qué fotos y mensajes pertenecen a cada evento.

Al terminar el evento, se genera un álbum de fotos estilo Polaroid, cada una con su mensaje escrito debajo, listo para imprimir. Las fotos originales se eliminan al final.

Para esta actividad usa Python o TypeScript para desarrollar un backend con los siguientes endpoints:

POST /events

Crea un evento nuevo (por ejemplo nombre del cliente, tipo de evento y fecha) y guarda su registro en RDS. Regresa el event_id generado.

POST /upload

Recibe un event_id, una foto y un mensaje de texto. El backend debe:
- Subir la foto a S3 en un tamaño reducido (128x128 px) en pictures/.
- Componer la foto en formato Polaroid (marco blanco + mensaje escrito abajo).
- Subir la polaroid resultante a polaroids/.
- Guardar en RDS el registro de la foto (evento, mensaje, rutas en S3).

GET /events/{event_id}

Consulta RDS y regresa la metadata del evento junto con el número de fotos que tiene asociadas.

POST /finish

Recibe un event_id. El backend debe:
- Consultar en RDS las polaroids asociadas a ese evento.
- Empaquetarlas en un .zip y regresarlo como respuesta descargable.

2 Requerimientos técnicos
- EC2 corriendo el backend con todos los endpoints expuestos vía HTTP.
- S3 para las fotos originales reducidas y para las procesadas.
- RDS con una tabla events y una tabla photos relacionada por event_id.
- Las credenciales de RDS se guardan en AWS Secrets Manager y la app las lee en tiempo de ejecución, no en variables de ambiente ni hardcodeadas.
- La instancia EC2 debe tener asignado el instance profile LabInstanceProfile para poder leer el secret. No debe usar las credenciales de su usuario.
- Las fotos deben guardarse con un nombre único, por ejemplo UUID, para la versión original y la polaroid.
- No se espera una aplicación compleja, pero sí funcional, clara y coherente con la arquitectura.

3 Entregables
1. Capturas del procedimiento en un documento PDF con descripción del proyecto y diagrama de arquitectura (200-300 palabras)
2. Código en repositorio de GitHub con README. El readme debe incluir los pasos para eliminar los recursos o debe incluir un script 'teardown.sh'.
3. Video demostrativo (5-10 min):
    - Es requisito que corra en la nube.
    - Crea un evento con /events.
    - Sube 3 fotos con mensaje vía /upload para ese evento.
    - Llama GET /events/{event_id} y muestra la metadata regresada.
    - Llama /finish, muestra las 3 polaroids resultantes descargadas.
    - Debes mostrar en AWS Console dónde está el bucket, los archivos generados, la instancia RDS con las tablas events y photos, el secret en Secrets Manager, así como la instancia de EC2 con su instance profile.
    - Al terminar, ejecuta teardown.sh y muestra en consola que los recursos fueron eliminados.

4 Checklist de revisión
Cada uno de estos aspectos tiene un valor de 10 puntos y se asignan los puntos de acuerdo a qué tan completo esté.

- EC2 corriendo el backend en la nube, no en local, con el instance profile LabInstanceProfile asignado (no usa credenciales de usuario) y las credenciales de RDS obtenidas desde AWS Secrets Manager en tiempo de ejecución.
- RDS con las tablas events y photos relacionadas correctamente por event_id.
- POST /events crea el evento en RDS y regresa un event_id válido.
- POST /upload sube la foto original a pictures/, genera y sube la polaroid a polaroids/, y guarda su metadata en RDS, todo en la misma llamada.
- Composición Polaroid correcta: marco y mensaje visibles.
- GET /events/{event_id} regresa la metadata del evento y el número de fotos asociadas, consultando RDS.
- /finish consulta RDS para obtener las polaroids del evento solicitado y regresa un .zip descargable con ellas.
- Código legible y organizado.
- README claro explicando qué hace el proyecto y cómo correrlo.
- Vídeo demostrativo completo con evidencia en la consola de AWS; incluye la ejecución de teardown.sh (o los pasos de limpieza del README) y confirmación de que los recursos fueron eliminados.