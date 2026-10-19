# Carpetas compartidas sin cuenta

Camilo pidió enlaces para compartir una carpeta con cualquier persona, sin usuario/contraseña, visibles en web y dentro de la app instalada. Generar no envía mensajes automáticamente: la persona elige dónde compartir/copiar el enlace.

## Flujo

En iPhone/iPad: menú de carpeta → Compartir carpeta. En web: icono de flecha para compartir de cada carpeta, con etiqueta accesible. Las acciones tienen ancho fijo y las tarjetas reservan espacio para el nombre. El panel usa un fondo blanco opaco, controles sólidos y centrado compatible con los portales de Radix y las traslaciones de Tailwind. Usuarios con Fotografía y subida vigentes pueden crear, consultar y revocar enlaces de esa carpeta. La raíz completa no se puede compartir. Vencimiento elegible de7,30 o90días; predeterminado30. La hoja informa que cualquier poseedor del enlace puede ver y descargar la carpeta y sus subcarpetas. No se crean cuentas de invitados ni se conceden permisos de JAC.

La ruta /compartir/<token> abre una galería web independiente de nómina/login, con navegación limitada, miniaturas, reproducción, descarga individual y paginación. HEIC/HEIF/TIFF usan el JPEG compatible disponible; otras imágenes pueden pasar a esa vista si el navegador no las decodifica. Se distingue la vista del archivo completo descargable y se informa cuando un formato de video no puede reproducirse. iOS recibe el enlace HTTPS mediante Associated Domains/AASA y lo presenta dentro de JAC con SFSafariViewController, también desde la pantalla sin sesión. La página ofrece además el enlace jacnomina://compartir/<token>. No se modifica la sesión nativa ni se habilita navegación privada. La instalación existente debe actualizarse desde el mismo Xcode para adquirir esa capacidad. El sistema Apple puede cachear AASA; la apertura física depende del perfil firmado y del dispositivo.

## Aislamiento

Tokens aleatorios de256bits (43caracteres base64url), búsqueda por SHA256 y copia cifrada para que el gestor autorizado pueda recuperar el enlace. UUID estable para reintentos sin duplicados. Se conserva actor/versión/conexión/fecha de vencimiento/revocación. La capacidad no es una cookie ni puede entrar en rutas de escritura. Cada operación revalida pertenencia actual al subárbol, estado del creador/permisos, conexión, caducidad, revocación y marcadores de eliminación antes/después de consultar R2. Los datos devueltos omiten raíz privada, ancestros externos, roles, estados de subidas, borrados de otras carpetas y claves de objetos/almacenamiento.

API pública GET exclusiva /api/media/shared; gestión autenticada /api/media/shares con origen obligatorio para mutaciones. Endpoints privados conservan sesión. No-store, no-referrer, noindex/nofollow/noarchive en respuestas públicas y página. La vista revalida al volver y cada30segundos para retirar una carpeta revocada; los bytes ya vistos/descargados no pueden recuperarse. R2 sigue privado, sin enlaces públicos S3 ni cambios de bucket/DNS.

## Almacenamiento y publicación

Migración aditiva0027_media_folder_shares.sql (tabla/índice con IF NOT EXISTS). La credencial del entorno permite publicar Workers pero la API administrativa D1 devolvió403/7403. El módulo inicializa exclusivamente su tabla/índice mediante el binding D1 existente del Worker, después de validar una gestión autenticada de la carpeta. Las peticiones anónimas nunca crean almacenamiento. No modifica otras tablas/datos ni crea enlaces reales como prueba. La migración normal posterior es idempotente y conserva los enlaces.

Prueba Workerd con las migraciones anteriores demuestra inicialización autorizada por binding, denegación de inicialización anónima, acceso al subárbol y rechazo tras revocación durante una lectura. Pruebas con SQLite en memoria comprueban origen/sesión, cifrado, vencimiento, idempotencia, navegación, archivos/miniaturas/rangos, revocación y retirada del creador. Simulador: manejo de URLs válidas/inválidas y crear/revocar con fixtures .invalid. Resultado final: PHOTOGRAPHY_MEDIA_DELIVERY.md.
