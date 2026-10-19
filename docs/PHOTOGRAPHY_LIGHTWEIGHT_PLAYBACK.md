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

TypeScript y build web correctos. Suite R2/API:51casos distintos aprobados, incluidos JPEG ligero, original intacto, COPY único, manifiestos con varias calidades, tramos, revocación, destinos rechazados, visitante sin procesamiento pagado y respuesta COPY ambigua. Regresiones obligatorias afectadas:72casos aprobados. Dos recorridos Chromium aprobados: reproducción HLS real con video sintético, fotos ligeras, tarjetas sin captions, selección, slideshow, ZIP, originales al descargar, offline y revocación. El Worker construido comprueba también las rutas y la entrada programada sin secreto ni llamadas externas.

La CI `media-light` compila las fuentes compartidas Mac y prueba únicamente caché/variantes/cargador/scroll en iPhone, reutilizando el mismo binario de simulador para un recorrido iPad de selección y menú de borrado. Resultados Apple y despliegue se registran al observarlos; no equivalen a instalación física. Mantener AYHVYN8BJF, bundle, firma automática, entitlements activos vacíos y pushNO. Camilo instala con pull/Run en el mismo Xcode.

Todas las comprobaciones usan datos locales ficticios, bases desechables y salidas interceptadas. El dominio de producción está bloqueado por la política de red del entorno; la credencial Cloud solo administra Workers y no puede consultar Stream/D1. La configuración del secreto y la activación del despliegue se verifican por metadatos, sin convertir esas limitaciones en una prueba de playback real de producción.

## Publicación confirmada

Fuente `4b46058` en `main`. TypeScript, build,51casos R2,72regresiones, dos recorridos Chromium y el Worker construido aprobados. La prueba del artefacto aplica migraciones locales y dispara la entrada scheduled de Workerd sin secreto ni salidas externas.

Worker versión `bbdedaca-22a2-44ba-900e-51b74b153dea`, despliegue `87502da4-1c16-4a26-8f36-49b60f1e4bff`, activo al100% desde17:22 UTC del19 de octubre. DB, BUCKET, ASSETS, JAC_HOSTING y los cuatro secretos conservados; cron `* * * * *` registrado. La edición del secreto desde el panel había dejado la última publicación con origen dash; Wrangler deploy intentó consultar rutas/dominios sin permiso y falló antes de subir. Se usó `wrangler versions upload --keep-vars` y activación por API, preservando rutas/dominio, y se añadió únicamente el cron requerido por API. No se repitió el build ni se modificó DNS.

CI vigente de esta entrega: [39294831756](https://github.com/camiloidarraga98/nomina-jac/actions/runs/39294831756), fuente `e8741ef`; resultado Apple pendiente de observar. Las ejecuciones39293288079/39294465309 fueron sustituidas estando en cola por las correcciones finales; no se repitieron resultados Apple aprobados de esta entrega. Release iPhone duplicado omitido; iPhone/iPad comparten el binario de pruebas y Mac compila sus fuentes compartidas.

El ajuste final de menú sitúa también las opciones privadas web/Mac sobre la imagen, sin otra franja inferior. iPad conservaba una cuadrícula distinta que no tenía el control de selección; ahora sus archivos usan MediaSelectableTile y su barra inferior también aparece en iPad, manteniendo navegación y distribución de tablet. El visor iPad mantiene su hoja habitual. Fuente final nativa `e8741ef`; se conserva la verificación web de `65f1402`.

La entrada programada respeta además JAC_READY: pausar el Worker detiene también procesamiento pagado, aunque exista el secreto. Comprobación Workerd del artefacto final aprobada con entorno pausado/sin tablas; la prueba configurada del procesamiento usa D1 en memoria y Stream falso, prepara una sola copia, pasa a listo y limpia la variante después del borrado. Esa prueba adicional pasó aisladamente, reutilizando los50casos R2 ya aprobados. La revisión del menú repitió únicamente Chromium privado y el build afectado; el recorrido público y las72regresiones no cambiaron y se reutilizan.

Publicación final web/API: versión `82a2f37c-b15e-47b4-879e-f5d84103a4f0`, despliegue `14e2073e-a812-46d6-964e-9d12f6231d3f`, activo al100% desde17:29 UTC. La versión anterior7f20a197 solo añadió el aviso de licencia de hls.js; la final incluye ese archivo público y el build completo del ajuste de menú/readiness. Ocho nombres de bindings/variables/secretos y cron existente conservados, confirmados por API sin valores secretos. La corrección nativa posterior no requiere otra publicación web.

## Incidencia de pantalla negra · 19 de octubre

Camilo reportó que el reproductor queda negro en todos los dispositivos. Las comprobaciones anteriores con fixtures no demostraron la entrega real de Stream. La credencial del entorno administra Workers, pero Stream y telemetría responden403 y el dominio de producción está fuera de su política de red; no se eluden esos límites ni se extrae el secreto del Worker.

Se añade `GET /api/media/playback?diagnostics=1`, exclusivamente con la sesión del propietario y su guarda real de conexión. Consulta conteos/estados y la entrega del manifiesto y una variante, sin iniciar COPY ni leer segmentos/originales. Solo devuelve resultados de etapa y errores sanitizados: nunca nombres, manifiestos, URLs firmadas, tokens o claves. Revalida la sesión al terminar. Usuarios de Fotografía sin ese permiso y visitantes no pueden consultarlo. Los fallos Stream distinguen HTTP/credencial sin confundirlos con revocación de una sesión JAC. Diagnóstico pendiente de evidencia real; no se afirma resuelto el playback por publicar esta herramienta.

TypeScript, build y el caso específico de permisos/entrega/errores sanitizados de diagnóstico aprobados. El artefacto construido comprueba además que sin sesión no devuelve diagnóstico. Fuentes Apple sin cambios: se reutilizan sus comprobaciones existentes, sin lanzar más jobs.
