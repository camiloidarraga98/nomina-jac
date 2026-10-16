# Eliminar carpetas de Fotografía

16 de octubre de 2026. Mismo Site, bucket privado R2 y proyectos Xcode. iPhone/iPad 0.23.0(35); Mac 1.9.0(11).

## Uso

Administradores Camilo y `jac`: en la web hay una papelera discreta junto a cada carpeta y «Eliminar esta carpeta» en su menú interior. iPhone/iPad/Mac: menú de tres puntos o menú contextual de la carpeta → Eliminar carpeta. Confirmación breve antes de borrar la carpeta, sus fotos/videos y subcarpetas. Cancelar conserva el contenido. La carpeta principal no se elimina. El acceso de lectura/subida del fotógrafo no incluye eliminación.

Si la conexión se corta después de comenzar, el archivo queda oculto y aparece «Eliminación pendiente / Continuar eliminación» para administradores. La operación puede retomarse incluso desde la otra cuenta administradora, con la conexión vigente. Una eliminación final no se puede deshacer. Las copias ya exportadas a la biblioteca personal de Fotos no se eliminan.

## Servidor y concurrencia

Se reutiliza `jac_media_operations` con `kind=r2-delete-folder`, ID estable por carpeta y confirmación de estado; no cambia el esquema ni se necesita una migración. Un marcador duradero bloquea todo el subárbol antes de iniciar I/O. Se conserva solo metadato de carpetas para impedir que un reintento antiguo las recree; los archivos originales, sus miniaturas y entradas de archivo se eliminan.

Permiso de administración en API y SQL, sesión activa, origen, ámbito de carpeta y revisión de conexión revalidados antes/después de I/O. Se rechazan raíz, identificadores de Drive, IDs de archivos y claves que no correspondan al ID observado del archivo. No se hace inventario del bucket ni se toca Drive. Las escrituras de carpetas/subidas/publicaciones/miniaturas comprueban el marcador dentro de su SQL. Finalizaciones y miniaturas que ya tienen un claim terminan o se retiran antes de la limpieza; no pueden volver a publicar. Se cancelan multipartes pendientes y se limpian también objetos/miniaturas aún no adjuntos al catálogo. Las capacidades de partes ya emitidas no autorizan publicación; el ciclo de vida multipartes existente cubre restos de partes en vuelo.

Lotes de hasta cien archivos y doscientas claves, con checksum y confirmación explícita de cada resultado S3; una respuesta parcial, redirigida o perdida mantiene el trabajo retomable y no se declara éxito. Una rotación de conexión entre lotes bloquea la continuación hasta revisar la configuración. Referencias del protocolo: [Cloudflare R2](https://developers.cloudflare.com/r2/api/s3/api/) y [DeleteObjects](https://docs.aws.amazon.com/AmazonS3/latest/API/API_DeleteObjects.html).

## Copia sin conexión

El índice cifrado guarda los IDs eliminados. Al confirmar el borrado o recibir un listado actualizado, se retira solo ese subárbol de los listados descargados, metadatos, archivos cifrados y caché automática; las demás carpetas se conservan. Respuestas, copias y fijaciones tardías de ese contenido se rechazan. Un 410 al consultar una carpeta retira su copia y regresa al archivo principal sin cerrar la sesión. Otros dispositivos sin internet conocerán un borrado remoto al volver a conectarse. Si no puede persistirse el índice seguro, se retira la caché local de Fotografía para no restaurar datos eliminados; no se borran nómina, Agenda ni Llavero.

## Comprobado en este Mac

- Node 24.21.0: 128 pruebas de nómina/auth/correo/móvil/Fotografía/calidad, TypeScript y build correctos. Workerd 15 correctas, todo S3/Google interceptado. Nuevas pruebas: permisos de Camilo/jac frente al fotógrafo, raíz, homónimos y subcarpetas, pérdidas de respuesta/errores parciales, carrera antes del INSERT final, miniatura en vuelo sin adjuntar, carpeta de 101 archivos en dos lotes y cambio de conexión/claves ajenas. Informes work/local/folder-delete-node-tests.log, folder-delete-worker-tests.log y folder-delete-web-build.log.
- Web localhost, componente real y catálogo desechable: cancelar, confirmar una carpeta con cuatro fotos, conservar la otra, provocar un 503 ficticio, recargar y retomar el trabajo. Informe work/local/folder-delete-preview/report.json; captura outputs/fotografia-eliminar-carpeta-local.png. No se eliminaron ni subieron archivos reales de producción.
- iPhone: 95 unitarias correctas y una condición física omitida; cinco UI distintos correctos (cancelar/borrar como administrador, fotógrafo sin borrado, offline/Fotos simulado, visor y privacidad). El informe folder-delete-ios-tests.xcresult falló solo por el selector doble de accesibilidad del botón destructivo en iOS27; se corrigió el selector manteniendo comprobaciones y pasó folder-delete-ios-confirmation.xcresult. Los otros cuatro recorridos habían pasado.
- iPad: tres UI distintos correctos (administrador, fotógrafo y Agenda/galería tras reinicio sin red). Mismo selector de confirmación corregido; resultado folder-delete-ipad-confirmation.xcresult y los dos restantes en folder-delete-ipad-tests.xcresult. No se quitaron comprobaciones.
- Mac: 105 pruebas correctas en folder-delete-mac-tests.xcresult. Interfaz nativa verificada manualmente con fixtures: menú Eliminar carpeta, cancelar conserva la carpeta y confirmar muestra «Carpeta eliminada». Captura outputs/fotografia-eliminar-carpeta-mac.png. Se conserva el bloqueo previo del runner UI ad hoc por AMFI; no se debilitaron protecciones para sortearlo.
- Release iPhone/iPad sin firma y Mac universal correctos: folder-delete-ios-release.log y folder-delete-mac-release.log. Misma firma/esquema personales, co.jacmusic.nomina y push NO. Run necesario en los dispositivos físicos; no se declaran instalados por estas compilaciones.

La publicación y entrega final se registran después en PROJECT_CONTEXT.md. La carpeta real de prueba mencionada por Camilo no se usa para verificar el borrado: la elimina él con esta opción.
