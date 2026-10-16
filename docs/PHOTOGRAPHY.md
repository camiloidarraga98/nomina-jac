# Fotografía JAC — carpeta compartida de Drive

16 de octubre de 2026. Función del ecosistema existente: web, iPhone y Mac; no se crea otro Site ni otro almacenamiento de producción.

## Uso

Fotografía muestra las carpetas y fotos/videos dentro de JAC. Conserva los meses y carpetas existentes de `Contenido 2026 Jhon Alex`, raíz `1yH4pNYQxArfynzho-IPBtx5w4AWbQ-C5`. Los cambios se consultan al entrar, volver a la ventana y cada 30 segundos mientras la vista está activa. Se puede actualizar manualmente. Las listas se paginan y la navegación incluye la ruta de carpetas.

Anderson (`andersonmejia0203@gmail.com`, usuario `anderson`) tiene exclusivamente Fotografía y Mi cuenta. Puede crear una carpeta con fecha y nombre del show/jornada y subir varias fotos/videos desde archivos o, en iPhone, Fotos. La web admite además arrastrarlos. Las carpetas nuevas usan `AAAA-MM-DD · nombre`; se conservan los nombres de los archivos originales. No hay funciones de borrar, mover ni compartir archivos de Drive en esta entrega.

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

iPhone: 72 unitarias aprobadas, una comprobación física omitida y cinco UI aprobadas en `work/local/ios-media-final.xcresult` (77 pasadas, una omitida, cero fallos). Tres recorridos de galería repetidos después del acabado visual en `ios-media-design-final.xcresult`, también correctos. Simulador nuevo `BC3888C5-9692-42BF-91F2-1AC2A8BAB9E8`, ahora apagado. Se conserva el aviso preexistente «Invalid frame dimension» en el resultado; no se declara corregido por esta entrega.

Mac: 80 unitarias aprobadas en `mac-media-unit-final.xcresult`; dos recorridos UI distintos aprobados entre ejecuciones y presentación/reproducción final aprobadas en `mac-media-design-accepted.xcresult` (`TEST EXECUTE SUCCEEDED`). Se mantienen los informes intermedios: un fallo anterior del reproductor SwiftUI en macOS 27 se diagnosticó y se sustituyó por AVKit de plataforma conservando las comprobaciones; se repitió y pasó. También se conservan el fallo intermedio de manejo 503 y las ejecuciones afectadas por foco/restauración de ventanas, con resultados finales correctos.

Release iPhone sin firma y Mac universal arm64/x86_64 compiladas (`ios-media-release-final.log`, `mac-media-release-final.log`). Versión iPhone 0.16.0(27), Mac 1.3.0(4), firma estricta Mac verificada. Misma app `outputs/JAC Music.app` actualizada sin cerrar la instancia anterior; requiere reabrirla para ejecutar el binario nuevo. Mismo proyecto iPhone y firma/esquema personales intactos, salvo cuatro valores de versión/build previstos. Para instalar en el teléfono: Run con el esquema JACNomina y el dispositivo conectado. Push continúa NO. No se declara probado un iPhone físico ni una fototeca real; PhotoKit se simula en las pruebas.

La vista local rechazó el acceso tras una revocación 403 sin conservar miniaturas. La comprobación del ancho móvil del navegador quedó limitada: el control de viewport seguía informando 1440 px después de pedir 390 px. No se declara verificada visualmente a 390 px; la revisión estática de sus reglas no encontró desbordamientos evidentes. Las pruebas nativas sí se ejecutaron en el simulador iPhone. Los informes intermedios se conservan y ninguna prueba envía fotos, avisos, correos o datos ficticios a servicios reales.

## Publicación web verificada

Sites v64 publicada en el Site existente; fuente privada `d0d70362fb2fcfd0d90ca9e5e22b9f5eed2a6927`, versión `appgprj_6aa0260b82a88191a47960614238350a~appgver_871f3128a8d08191a11cad1957893e7e`, despliegue `appgdep_6ad23eeb50b48191b0a62a99861e4023`, estado succeeded y env_set_revision 2. Artefacto de 83 archivos, SHA256 `c41287bd8335b2db874faa2a6a98082a408edb1fb3502401863e86096dd0e596`. El flujo usó Node24 y el helper autenticado oficial de Sites; no se cambiaron dependencias ni lockfile. Se conservaron `.openai/hosting.json`, DB/BUCKET, secretos, conexiones, audiencia y dominio existentes.

La revisión automática bloqueó inicialmente la entrega de la credencial al terminal. Se conservó el trabajo local, se verificó el proceso oficial y Camilo autorizó explícitamente ese paso por entrada oculta; el flujo posterior fue aprobado y la credencial no se guardó en archivos ni se envió a GitHub. El primer empaquetado encontró npm fuera del PATH del helper; se corrigió únicamente la ruta al Node24 ya instalado y el empaquetado exacto finalizó correctamente.

Autorizar Google y crear/activar Anderson siguen siendo pasos separados de la publicación; su estado real se registra al completarlos.

Endurecimiento antes de activar la conexión: las denegaciones explícitas de Google (401/403 y OAuth invalid_grant) se entregan como 403 para retirar la caché de Fotografía; no se presentan como fallos temporales que puedan habilitar fallback. Los límites de cuota de Google conservan su carácter temporal (503) y no retiran la última copia. Una prueba adicional lo comprueba en `media-drive-permission-final.log` (13 pruebas Drive/OAuth aprobadas).


## Cierre real de publicación y activación — 16 de octubre

La continuación v65 publicó la revocación de permisos Google frente a fallos de cuota. v66 añade mensajes de diagnóstico OAuth con razones cerradas y sin registrar cookies, tokens, códigos ni respuestas externas; conserva los diez minutos, PKCE, nonce, cookie de navegador, sesión, revisión y consumo único. Las 14 pruebas Drive/OAuth y TypeScript pasaron (`media-oauth-reasons-verified.log`, `media-oauth-reasons-types.log`), y build local/archivo exacto aprobado. El primer retorno había fallado en etapa authorization sin razón específica disponible; no se atribuye una causa concreta sin evidencia. El nuevo intento terminó correctamente sin retirar comprobaciones.

v66 publicada **succeeded** en el mismo Site, fuente `4d4e670a6c6d07603d3bfc6fa20a29190032d3cc`, versión `appgprj_6aa0260b82a88191a47960614238350a~appgver_950538fbc5e88191bc1a6acd66fbbd11`, despliegue `appgdep_6ad2432fa1108191a5e923953658d2f2`, env_set_revision 2. Archivo 83 entradas, SHA256 `eef3aee6ab6c83c54ab22c535048433f1dc6e0b14e3a365936253b835c7fa102`. Permanecen dominio, audiencia, DB/BUCKET, hosting y secretos existentes. La conexión nueva es independiente y cifrada; no se modifican las otras conexiones.

Camilo completó personalmente la autorización de Google con `jacmusicestudios@gmail.com`. Se verificó en producción `/fotografia?drive=connected`, y el listado dentro de JAC mostró **60 carpetas preexistentes** de la raíz solicitada, con acceso de lectura para Camilo. Captura `outputs/fotografia-drive-conectado.png`. No se subieron ni borraron archivos reales como prueba ni se cambió su compartición.

Con confirmación explícita de Camilo al guardar el acceso, se creó la cuenta **Anderson**, usuario `anderson`, correo indicado, rol **Fotografía · subir y consultar**, activa y pendiente de establecer contraseña. Se verificó la fila guardada; captura `outputs/anderson-cuenta-creada.png`. Su enlace privado de activación quedó abierto en Usuarios para Camilo, válido 24 horas y una sola vez. No se copió a archivos, al repositorio o al chat ni se envió correo; Camilo debe compartirlo de forma privada y Anderson establecer su contraseña. Camilo y jac conservan consulta a la galería mediante su rol administrador.

Fuente nativa guardada localmente; respaldos opcionales `outputs/JAC-Mac-1.3.0.zip` y `outputs/JAC-iPhone-0.16.0-Mac-1.3.0-fuente-nativa.zip`, sin claves, datos locales ni ajustes personales de firma. Se continúa en los mismos proyectos abiertos en esta carpeta; no hay que descargar o sustituir el proyecto.


## Corrección de apertura de archivos compartidos — 16 de octubre

El aviso «Ese archivo o carpeta no pertenece a Fotografía JAC» apareció en cualquier foto desde Mac/iPhone. La lectura real de una foto existente dentro de OCTUBRE reprodujo 403, y el diagnóstico v67 confirmó reason=missing_parent, kind=image, depth=1, parentCount=0. La consulta individual files.get no devolvía padres, mientras el listado files.list de esa carpeta sí incluía la relación. Se verificó que ambos clientes nativos envían el ID seleccionado sin sustituirlo por nombre, carpeta o UUID de subida. No se atribuye a la cuenta de Camilo ni se cambia su rol.

La resolución usa `jac_media_locations` (migración aditiva 0022) como localizador, sembrado solo por un listado de Google dentro de una carpeta cuya pertenencia se comprobó antes y después. Guarda únicamente ID de archivo, ID de carpeta y revisión de conexión; no nombres, datos originales ni credenciales. El guard de sesión y CAS de conexión protegen la escritura. Un localizador de otra revisión no se usa, y ningún localizador autoriza acceso por sí solo. Cuando files.get omite/entrega vacíos los padres, se consulta un listado fresco acotado al padre observado y al nombre escapado. Se busca el ID exacto, con el mismo nombre/MIME, sin borrado ni acceso directo, entre un máximo de diez páginas de 100 resultados; los homónimos no autorizan acceso. La cadena resultante debe llegar a la raíz fijada, sin ciclos ni padres múltiples, antes y después de descargar. Una relación no demostrable sigue siendo 403 y no habilita caché offline. No se añaden permisos, datos de prueba o conexiones; los localizadores guardados nunca sustituyen la comprobación actual y no se aceptan padres del cliente. Los nombres con apóstrofo/barra inversa se escapan y no pueden alterar la consulta.

Se mantiene un diagnóstico cerrado de rechazo (razón, profundidad, tipo y cantidad de padres), sin IDs, nombres privados, cookies, tokens o respuestas externas. v67 fue una publicación exclusivamente diagnóstica, succeeded, fuente `11fb586d06eee9874b5cc463f94748391e0871ec` y despliegue `appgdep_6ad247e65ab08191aa4af45c796dbbbd`. No se declara que ese paso por sí solo corrigiera la apertura.

La búsqueda general por nombre de v68 tampoco resolvió esta foto real; el registro confirmó el rechazo con la versión nueva del Worker. Por ello se reemplazó por la consulta dentro de su carpeta observada, sin atribuir al permiso de Google una causa no demostrada. No se declara que v68 corrigiera la apertura.

La modificación afecta al servidor compartido; los proyectos/binarios iPhone 0.16.0 y Mac 1.3.0 no cambian. Las comprobaciones nativas anteriores siguen siendo reutilizables porque sus fuentes y fixtures no cambian; la regresión de esta diferencia real de Google se ejecuta en el servidor y Workerd local con salidas interceptadas. Publicación y lectura final se registran al completarlas.


Cierre v69: TypeScript correcto; 24 pruebas Drive/OAuth en `work/local/media-parent-locations-verified.log`, ocho Workerd aprobadas con Google interceptado y 54 regresiones nómina/auth/correo/móvil/acceso en `media-location-final-regression.log` (86 pasadas, cero fallos). Build exacto del Site correcto. Se mantiene el rechazo antes/después para archivos movidos, localizadores ausentes/ajenos/obsoletos, cambios de conexión y revocación durante el guardado. Migración 0022 crea solo tres columnas de localización; no modifica ni reemplaza datos de aplicación existentes.

Publicación v69 succeeded, fuente `ee66303d6fe1888be94cf56ab59c432c09acbe46`, versión `appgprj_6aa0260b82a88191a47960614238350a~appgver_63eb35672a6c8191aa4034478fd1bd67`, despliegue `appgdep_6ad24a9c70f481918af8538f62007f8f`, env_set_revision 2. Archivo 85 entradas, SHA256 `4edad7be7e15658cd7cec285f5e016dcac667a2ce612781411b4f04c8935de24`. Mismo dominio, Site, DB/BUCKET, secretos, audiencia y conexiones.

Después de actualizar el listado real de OCTUBRE → 2 Oct - Cali, la foto que fallaba abrió como original dentro del diálogo de JAC: HTMLImageElement.complete=true, naturalWidth=4480, naturalHeight=2987, sin fallback a miniatura. Captura `outputs/fotografia-apertura-corregida-v69.png`. Diagnóstico de lectura exclusivamente, sin subir/borrar/mover archivos ni modificar la compartición de Drive. No se declara verificada esta corrección en un iPhone físico; el cliente nativo no cambia y usa el mismo endpoint. El control UI de Mac permitió leer su ventana, pero algunas acciones devolvieron noWindowsAvailable; no se afirma abierta esa foto en la app Mac por este control. Para recibir la corrección, reentrar/actualizar Fotografía con conexión; no hace falta cambiar proyecto o recompilar estos binarios.
