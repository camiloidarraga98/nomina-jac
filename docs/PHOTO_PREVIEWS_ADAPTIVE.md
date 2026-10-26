# Vistas previas y carpetas descargadas · iOS 0.36.0 (54)

Camilo reportó que una carpeta disponible sin conexión volvía a descargar fotos al abrirlas con Internet, y que sólo se preparaba la siguiente imagen. Pidió reutilizar las descargas, anticipar las vistas de la carpeta y adaptar su calidad a la conexión.

## Corrección

El visor llamaba a `mediaPhotoPreview`, que solicitaba siempre un JPEG remoto salvo cuando la app ya estaba en modo offline. Tampoco guardaba ese JPEG en la caché persistente. El modelo sólo mantenía la selección y una vecina en carga; cerrar o recorrer más de cinco fotos retiraba sus temporales.

Ahora se consulta primero la caché cifrada de vistas y el original descargado, tanto online como offline. Abrir la copia local no espera la comprobación remota de metadatos: el visor revalida en paralelo y retira el contenido ante una denegación. El descifrado y la decodificación siguen fuera de la interfaz; un original grande puede necesitar ese trabajo local aunque no haya transferencia de Internet.

Al abrir una carpeta comienza una precarga gradual de JPEG de pantalla completa, incluyendo las siguientes páginas, sin entrar en subcarpetas cerradas. Continúa dentro del visor y prioriza su selección. Una cola por cliente comparte solicitudes del mismo archivo/calidad, limita a dos transferencias y reserva capacidad para la imagen visible: como máximo una transferencia de precarga simultánea. Una vista que se cierra cancela sólo su suscripción. No se descargan originales para anticipar vistas ni se decodifica toda la carpeta en RAM.

En Wi-Fi sin restricciones y sin una medición lenta, se recorre la carpeta completa; sus vistas se conservan dentro de un presupuesto con retirada de las menos recientes. En datos móviles o una conexión lenta se anticipan hasta seis fotos por posición; en modo de datos reducidos no se hace precarga masiva. Abrir una foto explícitamente sigue funcionando. Cerrar/salir de la carpeta o pasar el visor a segundo plano detiene su precarga; no es una descarga persistente en segundo plano.

La primera imagen remota usa `preview=1&quality=balanced`: JPEG hasta1280px, calidad78 y máximo512KiB; si no cabe,1024px/calidad76. Se deriva de la vista privada ya guardada cuando existe, sin volver a leer el original ni sustituir la miniatura o la vista de detalle almacenadas. La selección puede mejorar a la vista existente2400px/calidad84 con Wi-Fi suficiente; se considera el rendimiento observado y se evita mejorar en datos móviles/reducidos. El bitmap anterior permanece hasta instalar el nuevo. Un fallo de esa mejora conserva la vista decente; una denegación sí retira el contenido. Los clientes antiguos conservan su perfil por defecto.

Las vistas se guardan cifradas en un almacén separado de96MiB/2048 archivos y48h de inactividad, ligado a sesión, origen, colección, archivo, revisión, MIME y calidad. Borrados y revocaciones retiran ambos perfiles y no permiten escrituras tardías. Ese presupuesto nunca recorta un original descargado manualmente. El sistema puede liberar bitmaps por memoria; eso no equivale a volver a descargar el JPEG.

## Verificación y distribución

Pruebas focales con archivos ficticios: originales fijados sin ninguna solicitud online/offline; reapertura entre clientes y mejora única; separación/cifrado/caducidad/borrado/colección; precarga de una tercera foto y páginas posteriores; cola compartida, prioridad, cancelación y revocación; conservación de la imagen durante una mejora y retirada de resultados tardíos. Se conservan las seis guardas de scroll en CI y el recorrido existente de swipe/zoom del visor. El alcance `adaptive-photos` comprueba iPhone y Release iPhone/Mac.

Entrega comprobada: 102 pruebas de servidor y 30 casos nativos distintos correctos entre los alcances descritos debajo, TypeScript/build correctos y endpoint publicado. No se ha instalado ni medido esta revisión en el iPhone físico. Team, AppGroup, push y WidgetKit permanecen; la extensión lleva la misma versión/build que la app. No se requieren migraciones ni modificaciones de originales en R2.

## Seguimiento de comprobaciones

Fuente inicial `b38dc12`, ejecución40251049590: ambas Release correctas y recorrido de swipe/zoom correcto39.650s; diez casos del modelo y quince del cliente correctos. Cuatro casos quedaron pendientes: dos fixtures de originales usaban IDs sin el prefijo R2 que exige la caché y otros devolvían PNG identificados como JPEG. Los reportes iniciales de archivos ausentes se aclararon con el diagnóstico posterior de MIME. Se corrigen los IDs ficticios, se serializan creación/retirada de temporales y se mueve la escritura del JPEG de presentación fuera del hilo principal, con revalidación y limpieza también si el control de sesión lanza un error. La prueba de reapertura cuenta una escritura real y exige cero escrituras en el hilo principal. La precarga prueba además la transición de seis fotos en datos móviles a toda la carpeta al recuperar Wi-Fi. El seguimiento repite sólo los casos afectados, privacidad, seis guardas y UI; conserva los diez casos del modelo sin cambios.

Servidor:102 pruebas correctas entre galería R2(69), móvil(8), OAuth móvil(4), permisos(5) y Workerd(16); TypeScript y build correctos. Perfil nuevo publicado al100% en Cloudflare `b31bdbdf-b765-46df-a2f7-a883f6040bfe`, catorce bindings conservados y sin migraciones. El dominio no se consulta desde Cloud porque la política de red no lo permite; la activación se verificó en la API de Cloudflare. Firma/instalación de54 siguen pendientes del Mac/TestFlight del propietario.


## Resultado final

Fuente funcional de app/proyectos `33d094a75b819e75a1a109695a3a8ff39403a05e`. Las fuentes de producto de la entrega final `2147e3c639ffc503ed5a3eb0c96724d056c61632` son idénticas; este último commit corrige únicamente los JPEG ficticios y retira trazas temporales de diagnóstico. No se debilitó la validación para aceptar un PNG etiquetado como JPEG.

| Comprobación | Evidencia |
| --- | --- |
| Release iPhone y Mac | [40252651922](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40252651922), jobs121347696194 y121347696532 correctos; Xcode26.3, sin advertencias Swift en ambas Release. |
| App y widget | El informe compilado confirma ambos bundles0.36.0(54), TeamAYHVYN8BJF, AppGroup`group.co.jacmusic.nomina.widgets`, tres tamaños y extensión incluida. Build sin firma: no equivale a Archive/instalación. Artefacto12621178889. |
| Modelos del visor | Diez casos correctos en [40251049590](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40251049590); sus entradas no cambiaron. |
| Copia local y guardas de scroll | La repetición40252651922 aprobó la apertura de tres originales fijados online/offline sin ninguna solicitud, las seis guardas y los casos de privacidad afectados. |
| Tres casos restantes y precarga de miniaturas | [40254995671](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40254995671), job121354826370: cuatro casos correctos, cero fallos. Incluye reapertura entre clientes con una escritura real y cero escrituras de presentación en el hilo principal, mejora única, retiro403, transición datos móviles→Wi-Fi, páginas y tercera foto sin petición adicional. |
| UI del visor | Recorrido existente de swipe, zoom, flechas y cierre correcto en40252651922:34.958s; no cambió después. |

Resultado conjunto: **30 casos nativos distintos correctos** (19 de cliente,10 de modelo y1 UI), utilizando resultados válidos de entradas sin cambios; no se presenta como una única ejecución de30 casos sobre el último SHA. La ejecución de diagnóstico40254314852 identificó explícitamente respuesta`image/png`,4758bytes, donde el contrato exigía JPEG: los fixtures ahora generan JPEG reales con ImageIO. Las dos Release y las seis guardas válidas se reutilizan en la última repetición de cuatro casos, sin volver a ejecutarlas.

La API está activada al100% y no requiere migraciones. El binario54 está preparado en GitHub; falta actualizarlo desde el Mac mediante Run o Archive/Upload y TestFlight interno. Se conservan las descargas existentes. Las pruebas físicas y firma anteriores del widget53 no se atribuyen a esta revisión.

## Comprobación después de instalar54

1. Actualizar `main` en el mismo proyecto del Mac y comprobar que app y extensión indiquen0.36.0(54). Conservar Team/AppGroup y actualizar sin desinstalar.
2. En una carpeta cuya descarga terminó, abrir varias fotos con Internet. La imagen debe salir del archivo local; puede haber una consulta pequeña de permisos/metadatos en paralelo, pero no otra transferencia de foto.
3. Repetir con modo avión y también después de cerrar/reabrir el visor. Los originales fijados no dependen de la caché temporal de JPEG.
4. En una carpeta todavía no descargada, dejar que se prepare en Wi-Fi y recorrer varias fotos, incluida la tercera; cerrar y abrir de nuevo debe reutilizar las vistas. No confundir la primera preparación de una foto sin caché con una descarga repetida.
5. Con red limitada, comprobar que la primera vista conserve una calidad suficiente y que no se vacíe cuando mejora. Las pruebas automáticas usan fixtures; esta revisión física corresponde al nuevo binario54 y no queda verificada por el resultado del CI.
