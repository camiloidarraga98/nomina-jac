# Acciones individuales de Fotografía

18 de octubre de 2026. Cambio solicitado para web, iPhone, iPad y Mac, sobre los mismos proyectos y el archivo privado R2 existente.

## Uso

Cada foto tiene un menú de opciones. También está disponible en el visor de la foto seleccionada:

- **Descargar foto:** conserva los bytes del original. En iPhone/iPad abre el documento nativo con la opción de guardar en Archivos o compartir; en Mac conserva Guardar una copia/Compartir de la vista previa.
- **Guardar sin conexión:** guarda exclusivamente esa foto en la copia privada de ese dispositivo o navegador. Una foto vista y almacenada temporalmente se fija para que la limpieza de la caché automática no la retire.
- **Eliminar foto:** únicamente para administradores con los permisos existentes, con confirmación. Elimina la foto y su miniatura para el equipo; conserva la carpeta y los demás archivos. Subir fotos no concede permiso para borrarlas.

Las acciones de carpeta, su descarga recursiva y Guardar carpeta en Fotos permanecen disponibles. Las copias que el usuario exportó expresamente a sus archivos/fototeca no se eliminan de su dispositivo al borrar el original de JAC.

## Servidor y privacidad

`POST /api/media` acepta `deleteFile` con ID y revisión observada. Comprueba administración, sesión, origen, pertenencia, revisión y conexión tanto en la API como en SQL. Reutiliza `jac_media_operations` con un marcador duradero `r2-delete-file`, sin migraciones ni nuevas conexiones. Un error de S3 no equivale a borrado completado: la operación permanece oculta y retomable desde la cuenta administradora vigente.

Original y miniatura se eliminan solo mediante claves derivadas del ID observado, con confirmación de ambos resultados. El marcador bloquea publicación, reintentos de subida y miniaturas tardías. El feed comunica `deletedFiles` y, a los administradores, `pendingFileDeletions`. Las copias nativas filtran esos IDs en todas sus páginas/descargas, retiran bytes cifrados y rechazan lecturas/fijaciones tardías. Otros dispositivos desconectados conocerán el borrado al revalidar.

## Sin conexión en navegador

Fotografía enlaza **Fotos sin conexión en este navegador**, `/fotografia-offline.html`. La vista estática puede reabrirse sin red después de guardar una foto. No contiene identidad, datos privados ni HTML renderizado de nómina. Al volver la conexión comprueba la sesión y cada foto; una denegación no utiliza la copia como alternativa.

IndexedDB conserva los originales y metadatos cifrados AES-GCM, por cuenta/sesión/colección, con una capacidad de cifrado independiente de la autenticación. La clave se importa como `CryptoKey` no extraíble; no se persisten tokens de sesión, contraseñas, claves de aplicación ni credenciales de R2/Google. Cerrar sesión, entrar con otra cuenta, cambiar contraseña o conocer una revocación retira la copia. Una respuesta/cifrado pendiente después de esa retirada no puede restaurarla.

El service worker existente conserva el comportamiento de notificaciones y solo guarda los dos archivos **públicos** de esta vista. Nunca cachea respuestas de API, fotos, documentos privados o páginas autenticadas. No solicita permisos push por preparar esta vista. Se amplía la lista explícita de archivos públicos de `worker/cloudflare.ts`, conservando READY y las guardas privadas.

Límites del navegador: 64 MiB por foto y 512 MiB en conjunto, sujetos al espacio y cuotas del navegador. No hay descarga automática de toda la biblioteca. Las fotos sin conexión pueden requerir un visor compatible con su formato; el original descargado permanece intacto. Las apps continúan usando su caché nativa cifrada por bloques y la protección local existente.

## Verificación y entrega

- Node 24, TypeScript, build Cloudflare y regresiones de nómina/auth/correo/móvil/Fotografía comprobados en Linux, sin cambiar dependencias o lockfile.
- 36 pruebas de R2 en memoria, incluidas seis nuevas: autorización/revisión, borrado individual/idempotencia, recuperación por otro administrador, miniatura en vuelo, errores/redirecciones/revocación y capacidad de cifrado separada por sesión.
- 16 pruebas Workerd con S3/Google interceptados, incluida la eliminación individual conservando otra foto.
- Chromium con React real y almacenamiento local: selección individual, cancelar/borrar, descargas idénticas por SHA-256, copia cifrada, recarga y reapertura sin internet, retirada al reconectar con acceso revocado, fotógrafo sin borrado, rechazo de cifrado alterado, aislamiento de cuentas y logout durante cifrado. Script `tests/media-photo-browser.mjs`; Playwright lo proporciona el entorno de desarrollo, sin agregar dependencias al proyecto.
- Pruebas del service worker conservan los avisos y comprueban que la API/fotos/documentos no entren a su caché.
- Fuentes y dos regresiones nativas nuevas preparadas en el mismo proyecto compartido. **Compilación, pruebas SwiftUI e instalación pendientes en el Mac de Camilo: este entorno Linux no tiene Xcode.** Conservar bundles, firma/esquema personales, entitlements y `JAC_PUSH_ENABLED=NO`.

Informes y capturas locales en `work/local/photo-actions-*`, ignorados por Git. No hubo correos, notificaciones, eventos, subidas ni borrados reales de prueba. La publicación web queda pendiente de autorizar Cloudflare en este entorno; preparar el código o traer las fuentes con pull no instala ni publica la aplicación.
