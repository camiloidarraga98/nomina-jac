# Vistas previas y carpetas descargadas · iOS 0.36.0 (54)

Camilo reportó que una carpeta disponible sin conexión volvía a descargar fotos al abrirlas con Internet, y que sólo se preparaba la siguiente imagen. Pidió reutilizar las descargas, anticipar las vistas de la carpeta y adaptar su calidad a la conexión.

## Corrección

El visor llamaba a `mediaPhotoPreview`, que solicitaba siempre un JPEG remoto salvo cuando la app ya estaba en modo offline. Tampoco guardaba ese JPEG en la caché persistente. El modelo sólo mantenía la selección y una vecina en carga; cerrar o recorrer más de cinco fotos retiraba sus temporales.

Ahora se consulta primero la caché cifrada de vistas y el original descargado, tanto online como offline. Abrir la copia local no espera la comprobación remota de metadatos: el visor revalida en paralelo y retira el contenido ante una denegación. El descifrado y la decodificación siguen fuera de la interfaz; un original grande puede necesitar ese trabajo local aunque no haya transferencia de Internet.

Al abrir una carpeta comienza una precarga gradual de JPEG de pantalla completa, incluyendo las siguientes páginas, sin entrar en subcarpetas cerradas. Continúa dentro del visor y prioriza su selección. Una cola por cliente comparte solicitudes del mismo archivo/calidad, limita a dos transferencias y reserva capacidad para la imagen visible: como máximo una transferencia de precarga simultánea. Una vista que se cierra cancela sólo su suscripción. No se descargan originales para anticipar vistas ni se decodifica toda la carpeta en RAM.

En Wi-Fi sin restricciones y sin una medición lenta, se recorre la carpeta completa hasta el presupuesto de almacenamiento. En datos móviles o una conexión lenta se anticipan hasta seis fotos por posición; en modo de datos reducidos no se hace precarga masiva. Abrir una foto explícitamente sigue funcionando. Cerrar/salir de la carpeta o pasar el visor a segundo plano detiene su precarga; no es una descarga persistente en segundo plano.

La primera imagen remota usa `preview=1&quality=balanced`: JPEG hasta1280px, calidad78 y máximo512KiB; si no cabe,1024px/calidad76. Se deriva de la vista privada ya guardada cuando existe, sin volver a leer el original ni sustituir la miniatura o la vista de detalle almacenadas. La selección puede mejorar a la vista existente2400px/calidad84 con Wi-Fi suficiente; se considera el rendimiento observado y se evita mejorar en datos móviles/reducidos. El bitmap anterior permanece hasta instalar el nuevo. Un fallo de esa mejora conserva la vista decente; una denegación sí retira el contenido. Los clientes antiguos conservan su perfil por defecto.

Las vistas se guardan cifradas en un almacén separado de96MiB/2048 archivos y48h de inactividad, ligado a sesión, origen, colección, archivo, revisión, MIME y calidad. Borrados y revocaciones retiran ambos perfiles y no permiten escrituras tardías. Ese presupuesto nunca recorta un original descargado manualmente. El sistema puede liberar bitmaps por memoria; eso no equivale a volver a descargar el JPEG.

## Verificación y distribución

Pruebas focales con archivos ficticios: originales fijados sin ninguna solicitud online/offline; reapertura entre clientes y mejora única; separación/cifrado/caducidad/borrado/colección; precarga de una tercera foto y páginas posteriores; cola compartida, prioridad, cancelación y revocación; conservación de la imagen durante una mejora y retirada de resultados tardíos. Se conservan las seis guardas de scroll en CI y el recorrido existente de swipe/zoom del visor. El alcance `adaptive-photos` comprueba iPhone y Release iPhone/Mac.

Estado al preparar la entrega: TypeScript correcto; pruebas Apple, build web, publicación del endpoint y verificación final pendientes. Registrar aquí sus resultados observados antes del cierre. No se ha instalado ni medido esta revisión en el iPhone físico. Team, AppGroup, push y WidgetKit permanecen; la extensión lleva la misma versión/build que la app. No se requieren migraciones ni modificaciones de originales en R2.
