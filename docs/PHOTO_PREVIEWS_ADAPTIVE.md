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

## Seguimiento de comprobaciones

Fuente inicial `b38dc12`, ejecución40251049590: ambas Release correctas y recorrido de swipe/zoom correcto39.650s; diez casos del modelo y quince del cliente correctos. Cuatro casos quedaron pendientes: dos fixtures de originales usaban IDs sin el prefijo R2 que exige la caché, y dos recorridos notificaron archivos temporales ausentes. Se corrigen los IDs ficticios, se serializan creación/retirada de temporales y se mueve la escritura del JPEG de presentación fuera del hilo principal, con revalidación y limpieza también si el control de sesión lanza un error. La prueba de reapertura cuenta una escritura real y exige cero escrituras en el hilo principal. La precarga prueba además la transición de seis fotos en datos móviles a toda la carpeta al recuperar Wi-Fi. El seguimiento repite sólo los casos afectados, privacidad, seis guardas y UI; conserva los diez casos del modelo sin cambios.

Servidor:102 pruebas correctas entre galería R2(69), móvil(8), OAuth móvil(4), permisos(5) y Workerd(16); TypeScript y build correctos. Perfil nuevo publicado al100% en Cloudflare `b31bdbdf-b765-46df-a2f7-a883f6040bfe`, catorce bindings conservados y sin migraciones. El dominio no se consulta desde Cloud porque la política de red no lo permite; la activación se verificó en la API de Cloudflare. Firma/instalación de54 siguen pendientes del Mac/TestFlight del propietario.
