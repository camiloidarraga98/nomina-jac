# Estabilidad de Fotografía en iPhone

## Corrección vigente · 19 de octubre de 2026

Camilo reportó que las miniaturas cargaban y desaparecían al desplazarse o esperar en una carpeta, que todo el contenido podía quedar vacío hasta volver arriba y que los archivos cambiaban de distribución. La intervención anterior con LazyVStack y caché de30segundos no resolvió esos casos. No se atribuye el problema al hardware ni se afirma haber medido fps físicos desde Cloud.

### Causas encontradas en el cliente

- Un404 del endpoint de miniaturas seguía la invalidación global de documentos: avanzaba la generación de sesión/caché y cancelaba las demás imágenes. Las carpetas reaccionaban al nuevo sello vaciando su contenido. Además, una petición aislada de miniatura sin conexión podía marcar toda la app como offline.
- La caché caducaba a los30segundos y su clave incluía una época nueva en cada refresco. Aunque el archivo no cambiara, volver a una celda repetía descarga y decodificación.
- Los contenedores LazyVStack anidados estimaban la altura de carpetas completas. Su onDisappear cancelaba la lectura y vaciaba metadatos mientras se desplazaban sus hijos; esa pérdida de altura causaba huecos y saltos.
- Las notificaciones generales de cacheRevision reemplazaban la lista visible por cachedMedia, que podía contener solo la primera página o una copia fijada anterior. Un error de refresco también podía reemplazar una lista completa por esa copia parcial.
- La ordenación reconstruía formateadores de fecha dentro de cada comparación, añadiendo trabajo innecesario al hilo de interfaz.
- Para archivos con la misma fecha, el cliente usaba comparación localizada/numérica y el servidor SQLite usaba nombre binario. Al cargar otra página, el cliente podía insertar el archivo2 delante del10 que ya estaba visible.

El servidor R2 ya conserva una miniatura indexada por archivo y lista por creación/nombre/ID. El diagnóstico no requiere migrar R2, modificar datos reales ni desplegar de nuevo el Worker.

### Comportamiento implementado

- Contenedores de carpetas VStack estables; únicamente las cuadrículas de archivos son lazy. Dos líneas reservadas para nombres mantienen alturas constantes al cargar imágenes. Se conserva la navegación desplegable y la selección múltiple.
- Los encabezados cerrados no consultan Llavero ni descifran el índice al recibir notificaciones de caché. Solo las carpetas abiertas mantienen lecturas activas.
- Salir de pantalla cancela la lectura de una carpeta, conservando sus metadatos y páginas. Solo el cierre explícito, cambio de colección/sesión o denegación limpia su estado. Al volver se revalida sin quitar el contenido permitido.
- MediaGalleryListing reúne todas las páginas antes de devolver el reemplazo: recuerda tanto las páginas solicitadas como la cantidad visible restaurada desde caché. Rechaza cursores repetidos y colecciones mezcladas; elimina duplicados y aplica borrados. Un fallo posterior no instala la primera página aislada.
- cacheRevision aplica únicamente identificadores de borrado confirmados a los elementos actuales, sin reordenar ni truncar páginas. La caché cifrada devuelve esos marcadores también para carpetas fijadas. Los refrescos autorizados sí actualizan cambios reales del contenido.
- Caché de píxeles NSCache por cliente, sesión/permisos, ID, revisión, tamaño y MIME; sin época ni caducidad arbitraria. Límites configurados256entradas/64MiB, con retirada por presión de memoria. Cada uso comprueba autorización. Logout y401/403 retiran la caché, y los resultados tardíos se rechazan.
- Cada celda reinicia explícitamente su solicitud al reaparecer. Al desaparecer libera su referencia y cancela el trabajo; la caché compartida permite recuperar los mismos píxeles sin red. El estado de una revisión anterior nunca sustituye la nueva.
- Hasta cuatro cargas/decodificaciones simultáneas, cola cancelable y decodificación ImageIO fuera de interfaz, máximo360píxeles/512KiB. Nunca se solicitan originales para poblar la cuadrícula.
- Una miniatura conocida como pendiente no genera peticiones fallidas. Un404/429/5xx aislado no invalida el resto; una celda visible hace hasta tres intentos ante indisponibilidad transitoria. Un fallo de esa petición no cambia la conectividad global. Un401/403 mantiene su retirada normal.
- Ante una pérdida temporal de conexión se pueden reutilizar únicamente píxeles ya presentes en memoria de esa sesión autorizada. No se crean nuevas descargas offline ni se ignoran denegaciones.
- Fechas de creación analizadas una vez por valor, con dos formateadores reutilizados, y orden por creación, nombre binario e ID, coincidiendo con el servidor entre páginas. La modificación de una miniatura no cambia la fecha usada para ordenar.

Esto corrige la pérdida y recarga de miniaturas existentes; no genera miniaturas históricas que nunca quedaron indexadas. Tampoco garantiza carga instantánea tras un arranque sin caché y con red lenta.

### Verificación al finalizar

Alcance gallery-stability en Actions: únicamente pruebas del cargador/ciclo de vida, miniatura pendiente, conectividad, permisos, borrados, orden y paginación, más recorridos UI de refresco real de30segundos con varias páginas/404 y recuperación tras validar sesión. Mac se compila una vez porque comparte DocumentsView/PayrollClient. No se repiten compresión, cola de subidas, web ni suites financieras.

El fixture UI nuevo conserva archivos en la segunda página mientras el encabezado está fuera de pantalla, verifica el siguiente refresco real, compara identidades/posiciones, vuelve arriba y selecciona/cancela. Incluye una portada que responde404 inicialmente, otra ausente y otra marcada pendiente. Solo servicios .invalid; ningún archivo real se sube, descarga o elimina.

Resultado online pendiente de la ejecución de cierre. La instalación y fluidez de carpetas reales se comprueban con pull/Run en el mismo Xcode. Team AYHVYN8BJF, firma personal sin Associated Domains, bundles y JAC_PUSH_ENABLED=NO conservados.

## Verificación histórica

La ejecución39202395410 sobre1735e026 aprobó23unitarias, tres UI y Release Mac de la intervención anterior. Su recorrido de80fotos no comprobaba permanencia durante el refresco de30segundos ni la pérdida de páginas; ese resultado no demuestra resuelto el nuevo fallo reportado. Las reglas vigentes de caché y contenedores son las de la sección anterior.
