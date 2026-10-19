# Fotografía: reproducción ligera y miniaturas

Camilo pidió separar visualización y descarga, mantener miniaturas al reabrir carpetas, corregir la selección de iPad, habilitar borrado individual de videos y simplificar las tarjetas. Eligió explícitamente Cloudflare Stream adaptativo, con facturación por uso. El secreto `JAC_STREAM_API_TOKEN` está configurado en el Worker según su confirmación y la lista de nombres de secretos; su valor no se consulta ni se versiona.

## Visualización y originales

- Fotos nuevas: el cliente genera miniatura360px/JPEG0.60 y vista1600px/JPEG0.76, limitada a2MiB. Ambas se indexan una vez, separadas del original. Si falla esa fase, el lote conserva el archivo local y reintenta sin duplicar el original. Fotos anteriores sin vista intermedia usan la miniatura existente, no el original. No se afirma haber regenerado variantes históricas.
- Videos online: AVPlayer en Apple, HLS nativo en Safari y hls.js1.6.15 en otros navegadores compatibles. Stream prepara variantes y el reproductor elige calidad según conexión y tamaño de pantalla. No se garantiza ausencia absoluta de pausas.
- Descargar/Guardar en Fotos/Disponible sin conexión mantienen los bytes completos del archivo almacenado en R2. La compresión obligatoria iOS previa a la subida conserva su política vigente; «original» aquí significa el archivo R2, no una recuperación de la grabación anterior a esa compresión.
- Sin conexión se pueden abrir únicamente originales ya descargados. Las vistas JPEG no se presentan como archivos originales descargados.

## Procesamiento y privacidad

Migración aditiva0028 y creación idempotente autorizada de `jac_media_presentations`: fuente, versión de colección, clave JPEG, UID/host/estado Stream y reserva recuperable. No reinicializa cuentas ni conexiones. Los objetos `previews/` se limpian con sus originales; borrado R2 conserva lotes de200claves.

El trabajo programado interno procesa un video pendiente por minuto y hasta cuatro registros de limpieza. Incluye videos R2 existentes y nuevos; no importa Drive. El primer acceso privado puede iniciar preparación, el enlace público solo consulta estado. Al publicar comienza el procesamiento gradual; una carpeta numerosa no queda lista inmediatamente.

COPY usa una URL R2 firmada temporal, enviada solo a Stream. Cada video exige URLs firmadas. La reserva SQL evita copias simultáneas y el creador estable permite reconciliar respuestas perdidas. Un COPY ambiguo queda en estado incierto y se busca en el catálogo antes de continuar; no se repite a ciegas un trabajo facturable. Los errores de configuración no provocan descarga del original como alternativa.

Los clientes reciben una autorización cifrada de una hora para un único archivo/revisión/colección y sesión o enlace compartido. El Worker valida permisos, ancestros, tombstones y revocación antes/después de manifiestos y tramos; reescribe variantes HLS a rutas JAC. No entrega el token de Cloudflare ni URL R2 a los reproductores. Los tramos en curso revalidan también cada1MiB/5s; cancelar cierra el upstream. Revocar un enlace no concede una sesión de usuario ni conserva una ruta pública permanente al video.

## Miniaturas y gestos

Tarjetas a imagen completa, sin pie blanco/nombre/texto «Video». Un icono de28px indica video; los nombres permanecen en accesibilidad y visor. Carpetas conservan sus nombres. Web privada, enlace público y apps comparten esta decisión con medidas adaptadas a cada dispositivo.

La app combina NSCache de píxeles con miniaturas AES-GCM temporales por sesión/revisión, protegidas y excluidas de backups. Disco:48h desde el acceso y poda periódica de128MiB/4096archivos, permitiendo sobrepaso breve entre32escrituras. No constituye descarga de originales. Logout/revocación retiran copias y bloquean escrituras tardías. Cada reapertura reutiliza caché válida; un archivo cambiado obtiene otra clave.

Pulsación prolongada450ms con tolerancia10pt inicia selección en iPad/iPhone, conserva desplazamiento y evita que soltar desmarque inmediatamente. Menús individuales y visor incluyen borrar video con permiso vigente, revisión y confirmación. Anderson conserva su permiso limitado a Fotografía.

## Comprobaciones

TypeScript y build web correctos. Suite R2/API:50casos aprobados, incluidos JPEG ligero, original intacto, COPY único, manifiestos con varias calidades, tramos, revocación, destinos rechazados, visitante sin procesamiento pagado y respuesta COPY ambigua. Regresiones obligatorias afectadas:72casos aprobados. Dos recorridos Chromium aprobados: reproducción HLS real con video sintético, fotos ligeras, tarjetas sin captions, selección, slideshow, ZIP, originales al descargar, offline y revocación. El Worker construido comprueba también las rutas y la entrada programada sin secreto ni llamadas externas.

La CI `media-light` compila las fuentes compartidas Mac y prueba únicamente caché/variantes/cargador/scroll en iPhone, reutilizando el mismo binario de simulador para un recorrido iPad de selección y menú de borrado. Resultados Apple y despliegue se registran al observarlos; no equivalen a instalación física. Mantener AYHVYN8BJF, bundle, firma automática, entitlements activos vacíos y pushNO. Camilo instala con pull/Run en el mismo Xcode.

Todas las comprobaciones usan datos locales ficticios, bases desechables y salidas interceptadas. El dominio de producción está bloqueado por la política de red del entorno; la credencial Cloud solo administra Workers y no puede consultar Stream/D1. La configuración del secreto y la activación del despliegue se verifican por metadatos, sin convertir esas limitaciones en una prueba de playback real de producción.
