# Scroll de Fotografía en iPhone

Camilo reportó tirones al abrir y desplazar una carpeta. Se encontraron rutas concretas de trabajo: MediaTile decodificaba imágenes en su tarea de interfaz y descartaba la miniatura al salir del viewport; volver a ella repetía descarga/decodificación. Los contenedores verticales de la galería y carpetas también se construían de manera anticipada. No se atribuye todo el problema a la red o al teléfono ni se afirma haber medido fps físicos desde Cloud.

## Cambios

- Contenedores LazyVStack para galería, carpetas y contenido desplegado; se conserva la cuadrícula, navegación y selección múltiple.
- La comprobación de si una foto está guardada offline también lee el índice cifrado en una tarea de utilidad, con cancelación y sello de sesión, para no bloquear la aparición de cada menú durante el scroll.
- Decodificación ImageIO a360píxeles y caché inmediata de píxeles en una tarea detached de utilidad; se instala la imagen al regresar a la interfaz y revalidar sesión/cancelación.
- Hasta cuatro peticiones/decodificaciones simultáneas. Una celda retirada cancela su petición o espera pendiente y libera su turno; no se deja una cola de descargas de celdas ya retiradas.
- Caché de imágenes decodificadas solo en memoria: máximo96 entradas/12MiB, vencimiento de30segundos. La clave incluye cliente, sello de sesión/permisos, época de actualización e ID/revisión/tamaño del archivo. Una nueva revisión o actualización requiere volver a autorizar su miniatura. NSCache permite retirar memoria bajo presión.
- Se comprueba autorización antes de reutilizar y antes de instalar. 401/403 vacían la caché; no hay fallback ante una denegación ni inserción tardía después de invalidación. La tarea de celda conserva su borrado de imagen local al desaparecer.

El endpoint autenticado, límite de512KiB y tamaño máximo de visualización siguen vigentes. Nunca se usan los originales para poblar la cuadrícula. La caché no da acceso offline nuevo, no sustituye la copia cifrada y no cambia permisos, borrados ni revisiones.

## Verificación dirigida

Pruebas de reutilización/cambio de revisión, concurrencia limitada, cancelación de celdas pendientes y revocación de imágenes guardadas/tardías. Se conserva la prueba del endpoint exclusivo de miniaturas y sus límites. La UI usa una carpeta ficticia de80fotos para bajar/subir y seleccionar/cancelar después. Se comprueban junto a los cambios de compresión y su cola, una sola ronda al finalizar. Mac se compila por el archivo compartido; no hay suites web/financieras ni datos reales.

El recorrido de simulador comprueba comportamiento y las unitarias prueban que se evita trabajo repetido. No constituye una medición de fluidez en el iPhone físico: Camilo debe comprobar el scroll de sus carpetas tras pull/Run. El resultado online se registra al cierre.
