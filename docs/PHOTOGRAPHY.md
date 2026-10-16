# Fotografía JAC — carpeta compartida de Drive

16 de octubre de 2026. Función del ecosistema existente: web, iPhone y Mac; no se crea otro Site ni otro almacenamiento de producción.

## Uso

Fotografía muestra las carpetas y fotos/videos dentro de JAC. Conserva los meses y carpetas existentes de `Contenido 2026 Jhon Alex`, raíz `1yH4pNYQxArfynzho-IPBtx5w4AWbQ-C5`. Los cambios se consultan al entrar, volver a la ventana y cada 30 segundos mientras la vista está activa. Se puede actualizar manualmente. Las listas se paginan y la navegación incluye la ruta de carpetas.

Anderson (`andersonmejia0203@gmail.com`, usuario previsto `anderson`) tiene exclusivamente Fotografía y Mi cuenta. Puede crear una carpeta con fecha y nombre del show/jornada y subir varias fotos/videos desde archivos o, en iPhone, Fotos. La web admite además arrastrarlos. Las carpetas nuevas usan `AAAA-MM-DD · nombre`; se conservan los nombres de los archivos originales. No hay funciones de borrar, mover ni compartir archivos de Drive en esta entrega.

Camilo y la cuenta administradora `jac` consultan la galería. Solo el propietario Camilo conecta Google; Anderson no necesita acceso directo a Drive ni sus credenciales. Las cuentas generales de consulta de nómina/itinerarios no reciben acceso a Fotografía. El rol exclusivo se guarda en `media_only`; las respuestas lo acompañan de `itinerariesOnly:true` para impedir que clientes antiguos carguen nómina. Los editores antiguos de usuarios conservan el rol cuando lo omiten. Cambiar una cuenta mantiene revisión y cierre de sus sesiones anteriores.

## Activación real

1. Publicar exclusivamente el Site `appgprj_6aa0260b82a88191a47960614238350a` con su migración aditiva `0021_photography_gallery.sql`.
2. Camilo inicia sesión y abre `/fotografia` → Conectar Google Drive. Debe elegir `jacmusicestudios@gmail.com`. El callback existente verifica esa cuenta y que pueda añadir contenido a la raíz indicada antes de guardar la conexión.
3. Google pide un permiso nuevo de Drive. El scope OAuth `drive` es amplio porque deben consultarse también las carpetas y archivos preexistentes, ajenos a la creación inicial de JAC. **La restricción a esta carpeta se aplica en las API de JAC; no es una restricción por carpeta del permiso de Google.** No se cambia la compartición de Drive ni se revocan Gmail, Agenda o Sheets. El token de esta conexión se cifra y almacena por separado.
4. En Usuarios crear Anderson, correo indicado, rol **Solo fotos y videos**; generar su enlace de activación individual. No inventar una contraseña ni enviársela por correo como prueba. Verificar rol guardado antes de entregar el acceso. No crear con una versión antigua del servidor, que todavía no conoce este rol.
5. Actualizar el mismo proyecto iPhone con Run y la misma firma; la solicitud de permiso de Fotos aparece solo al elegir guardar en Fotos. Push permanece suspendido.

La lectura de la carpeta por el conector de Codex solo comprueba el acceso del conector: no sustituye la autorización persistente del sitio. La activación y creación reales deben registrarse expresamente al completarse; no inferirlas de los fixtures.

## iPhone: guardar y consultar sin conexión

**Guardar carpeta en Fotos** prepara un listado completo de la carpeta y sus subcarpetas, incluidas todas las páginas. Muestra cantidad/tamaño y permite revisar la transferencia antes de pedir permiso de adición a Fotos. No requiere permiso para leer toda la biblioteca. Cada archivo cuenta como guardado solo cuando PhotoKit confirma su creación; un formato incompatible o un fallo aparece por archivo. Los archivos exportados a Fotos quedan como copias del usuario.

**Disponible sin conexión** descarga explícitamente el contenido completo de esa carpeta, con subcarpetas, para consultarlo en JAC. No realiza una descarga masiva automática de Drive. Ofrece progreso, cancelación y eliminación de la copia local; comprueba el espacio necesario, incluido el archivo temporal mayor. Reabrir la app sin red conserva la sesión y permite navegar por la copia descargada y abrir fotos/videos. Las escrituras requieren conexión.

Metadatos e índices se cifran y los archivos grandes se procesan con FileHandle y AES-GCM en bloques de 1 MiB, con autenticación ligada a archivo/revisión/posición. La copia está separada por origen/sesión, excluida del respaldo y protegida en disco. Cerrar sesión, cambiar de cuenta o confirmar una revocación retira sus copias; una respuesta 403 nunca activa el fallback offline. Los fallos de conectividad sí permiten leer la última copia. Los temporales privados se limpian y la cubierta de privacidad existente se conserva.

## Archivos y servidor

JPEG, PNG, GIF, WebP, HEIC/HEIF, TIFF, MP4, MOV, WebM y M4V; máximo 20 GiB por archivo. Las posibilidades de reproducción/importación dependen también del códec del dispositivo. La web usa miniatura para HEIC/TIFF y permite descargar el original; un video no compatible muestra el error sin abrir Drive. Mac/iPhone usan vistas nativas y reproductores AVKit de plataforma sobre una descarga privada, sin WebView ni aplicaciones externas.

Los originales se guardan directamente en Drive. D1 conserva conexión cifrada y operaciones de subida/carpeta, sin duplicar las fotos en R2 ni cargar videos completos en memoria del Worker. Subidas por bloques de 1 MiB, progreso y recuperación mediante estado de Google; el último bloque puede ser menor. IDs de archivo reservados y UUID de petición estables evitan duplicados ante respuestas perdidas. Las sesiones de subida se cifran y no se entregan al navegador/teléfono; los clientes solo acceden a API privadas de JAC.

Cada petición comprueba sesión vigente, versión de cuenta y rol. Revalida conexión y ancestros actuales en Drive antes y después de leer/guardar; bloquea archivos movidos fuera de la raíz, accesos directos, ciclos y carpetas ajenas. Las descargas transmiten contenido y rangos HTTP privados desde JAC. Miniaturas se obtienen mediante proxy autorizado; no se entregan tokens ni enlaces privados de Google al cliente. Fetch manual rechaza redirecciones; solo el 308 propio de la sesión de subida se admite como progreso. No cambia la compartición de ningún archivo.

Fotógrafos quedan excluidos de los destinatarios automáticos de itinerarios, selección de Alertas/pases y entrega/registro push. Las API de nómina, CRM, Agenda, gastos y sus adjuntos rechazan su acceso. El workspace de sesión móvil entrega un sobre vacío sin datos financieros para permitir el inicio/restauración de la app.

## Verificación local

Node 24.21.0, TypeScript y build web locales correctos. `media-server-regression.log`: 196 pruebas de nómina/auth/correo/móvil/OAuth/Agenda/avisos/CRM y permisos/Drive aprobadas. Una prueba adicional de navegación protegida se ejecuta en `media-navigation-verified.log` (seis pruebas en total). `media-worker-verified.log`: dos casos de API nueva con Workerd/D1 reales locales y salidas interceptadas; `media-worker-regression.log`: siete regresiones de Agenda/avisos. No se repiten comprobaciones cuyas entradas no cambian.

Las pruebas nuevas cubren rol exclusivo y clientes antiguos, callbacks OAuth/cuenta/PKCE/guard/replay, carpetas ajenas y cambios en Drive, creación idempotente, subidas por bloques/reanudación/respuesta final perdida/concurrencia, rangos 206/416, miniaturas y rechazo de redirecciones/revocación. Todos los datos son ficticios y las salidas a Google se interceptan.

Vista web en localhost con servicios reales bloqueados: se creó una carpeta ficticia y se abrió automáticamente; selector múltiple guardó una foto y un video (2 de 2). Foto y clip H.264 local de dos segundos se abren dentro del diálogo de JAC. Capturas `outputs/fotografia-web-*.png`. La comprobación real de arrastrar se diferencia del selector, que sí se operó; los manejadores de arrastre se revisan en código.

La verificación definitiva de iPhone/Mac, compilaciones de entrega y estado de publicación/activación se agregan al finalizar. Los informes intermedios se conservan y ninguna prueba envía fotos, avisos, correos o datos ficticios a servicios reales.

## Publicación web verificada

Sites v64 publicada en el Site existente; fuente privada `d0d70362fb2fcfd0d90ca9e5e22b9f5eed2a6927`, versión `appgprj_6aa0260b82a88191a47960614238350a~appgver_871f3128a8d08191a11cad1957893e7e`, despliegue `appgdep_6ad23eeb50b48191b0a62a99861e4023`, estado succeeded y env_set_revision 2. Artefacto de 83 archivos, SHA256 `c41287bd8335b2db874faa2a6a98082a408edb1fb3502401863e86096dd0e596`. El flujo usó Node24 y el helper autenticado oficial de Sites; no se cambiaron dependencias ni lockfile. Se conservaron `.openai/hosting.json`, DB/BUCKET, secretos, conexiones, audiencia y dominio existentes.

La revisión automática bloqueó inicialmente la entrega de la credencial al terminal. Se conservó el trabajo local, se verificó el proceso oficial y Camilo autorizó explícitamente ese paso por entrada oculta; el flujo posterior fue aprobado y la credencial no se guardó en archivos ni se envió a GitHub. El primer empaquetado encontró npm fuera del PATH del helper; se corrigió únicamente la ruta al Node24 ya instalado y el empaquetado exacto finalizó correctamente.

Autorizar Google y crear/activar Anderson siguen siendo pasos separados de la publicación; su estado real se registra al completarlos.

Endurecimiento antes de activar la conexión: las denegaciones explícitas de Google (401/403 y OAuth invalid_grant) se entregan como 403 para retirar la caché de Fotografía; no se presentan como fallos temporales que puedan habilitar fallback. Los límites de cuota de Google conservan su carácter temporal (503) y no retiran la última copia. Una prueba adicional lo comprueba en `media-drive-permission-final.log` (13 pruebas Drive/OAuth aprobadas).
