"""Procesamiento de imagenes con Pillow: miniatura y composicion Polaroid."""
import io
import os

from PIL import Image, ImageDraw, ImageFont, ImageOps

# Tamano al que se reduce la foto original antes de subirla a pictures/.
THUMBNAIL_SIZE = (128, 128)

# Tope de megapixeles aceptados. Una imagen se descomprime en memoria a
# ancho*alto*canales bytes: 7000x7000 px en RGBA son ~200 MB, suficiente para
# agotar la RAM de una t3.micro (1 GB) y tumbar el servicio. Con 30 MPx cabe
# de sobra cualquier foto de celular y el proceso queda acotado.
MAX_PIXELS = 30_000_000

# Geometria de la polaroid: marco delgado arriba y a los lados, ancho abajo
# para el mensaje, tal como una Polaroid real.
PHOTO_SIZE = 600
SIDE_MARGIN = 48
TOP_MARGIN = 48
BOTTOM_MARGIN = 180

CARD_WIDTH = PHOTO_SIZE + SIDE_MARGIN * 2
CARD_HEIGHT = TOP_MARGIN + PHOTO_SIZE + BOTTOM_MARGIN

WHITE = (255, 255, 255)
INK = (40, 40, 45)
EDGE = (208, 208, 210)

# Se prueba en orden; la ultima opcion es la fuente bitmap de Pillow.
FONT_CANDIDATES = [
    "/usr/share/fonts/google-noto/NotoSerif-Italic.ttf",
    "/usr/share/fonts/dejavu-sans-fonts/DejaVuSerif-Italic.ttf",
    "/usr/share/fonts/dejavu/DejaVuSerif-Italic.ttf",
    "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/liberation-sans/LiberationSans-Regular.ttf",
    "C:/Windows/Fonts/segoeui.ttf",
]


def _load_font(size: int):
    for ruta in FONT_CANDIDATES:
        if os.path.exists(ruta):
            try:
                return ImageFont.truetype(ruta, size)
            except OSError:
                continue
    return ImageFont.load_default(size)


def _open(raw: bytes) -> Image.Image:
    """Abre la imagen, corrige la rotacion segun EXIF y la pasa a RGB."""
    # Image.open solo lee la cabecera, asi que el tamano se conoce antes de
    # decodificar: se rechaza aqui, sin haber reservado la memoria.
    imagen = Image.open(io.BytesIO(raw))
    ancho, alto = imagen.size
    if ancho * alto > MAX_PIXELS:
        raise ValueError(
            f"La imagen es demasiado grande ({ancho}x{alto} px); "
            f"el maximo es {MAX_PIXELS // 10**6} megapixeles"
        )
    imagen = ImageOps.exif_transpose(imagen)
    return imagen.convert("RGB")


def _to_jpeg(imagen: Image.Image, quality: int = 90) -> bytes:
    buffer = io.BytesIO()
    imagen.save(buffer, format="JPEG", quality=quality, optimize=True)
    return buffer.getvalue()


def make_thumbnail(raw: bytes) -> bytes:
    """Version reducida a 128x128 exactos (recorte centrado) para pictures/."""
    return _to_jpeg(ImageOps.fit(_open(raw), THUMBNAIL_SIZE, Image.LANCZOS), quality=85)


def _wrap(texto: str, fuente, ancho_max: int, max_lineas: int = 3) -> list[str]:
    """Parte el mensaje en lineas que quepan en ancho_max."""
    def ancho(s: str) -> int:
        return int(fuente.getbbox(s)[2] - fuente.getbbox(s)[0])

    lineas: list[str] = []
    actual = ""
    for palabra in texto.split():
        tentativa = f"{actual} {palabra}".strip()
        if ancho(tentativa) <= ancho_max or not actual:
            actual = tentativa
        else:
            lineas.append(actual)
            actual = palabra
            if len(lineas) == max_lineas:
                break
    if actual and len(lineas) < max_lineas:
        lineas.append(actual)

    # Si el mensaje no cabe, se recorta la ultima linea con puntos suspensivos.
    if len(lineas) == max_lineas:
        consumido = len(" ".join(lineas))
        if consumido < len(texto.strip()):
            ultima = lineas[-1]
            while ultima and ancho(ultima + "...") > ancho_max:
                ultima = ultima[:-1]
            lineas[-1] = ultima.rstrip() + "..."
    return lineas


def make_polaroid(raw: bytes, mensaje: str) -> bytes:
    """Compone la polaroid: marco blanco alrededor de la foto y mensaje abajo."""
    foto = ImageOps.fit(_open(raw), (PHOTO_SIZE, PHOTO_SIZE), Image.LANCZOS)

    tarjeta = Image.new("RGB", (CARD_WIDTH, CARD_HEIGHT), WHITE)
    tarjeta.paste(foto, (SIDE_MARGIN, TOP_MARGIN))

    lienzo = ImageDraw.Draw(tarjeta)
    # Contorno de la tarjeta y de la foto, para que el marco se distinga
    # incluso sobre un fondo blanco.
    lienzo.rectangle([0, 0, CARD_WIDTH - 1, CARD_HEIGHT - 1], outline=EDGE, width=1)
    lienzo.rectangle(
        [SIDE_MARGIN - 1, TOP_MARGIN - 1,
         SIDE_MARGIN + PHOTO_SIZE, TOP_MARGIN + PHOTO_SIZE],
        outline=EDGE, width=1,
    )

    # El mensaje se centra en el marco inferior; la fuente se encoge si hace falta.
    texto = (mensaje or "").strip()
    if texto:
        zona_y = TOP_MARGIN + PHOTO_SIZE
        ancho_max = PHOTO_SIZE
        for tamano in (42, 36, 30, 26):
            fuente = _load_font(tamano)
            lineas = _wrap(texto, fuente, ancho_max)
            alto_linea = int(tamano * 1.35)
            if len(lineas) * alto_linea <= BOTTOM_MARGIN - 40:
                break
        alto_bloque = len(lineas) * alto_linea
        y = zona_y + (BOTTOM_MARGIN - alto_bloque) // 2
        for linea in lineas:
            lienzo.text((CARD_WIDTH // 2, y), linea, font=fuente, fill=INK, anchor="ma")
            y += alto_linea

    return _to_jpeg(tarjeta, quality=92)
