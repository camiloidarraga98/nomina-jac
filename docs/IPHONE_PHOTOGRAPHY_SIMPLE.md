# Fotografía simplificada en iPhone — 0.25.0 (38)

Se actualiza el mismo proyecto `ios/JACNomina.xcodeproj`, esquema JACNomina. La firma personal, `co.jacmusic.nomina`, la sesión de Llavero y la suspensión de push se conservan. Esta petición se centra en el iPhone; la distribución de web, Mac e iPad permanece. El iPad comparte la mejora del visor de imágenes.

## Uso

La pantalla del iPhone muestra las carpetas y **Subir**, sin el título ni la introducción anterior. Tocar la fila completa despliega sus miniaturas dentro de la misma pantalla; pueden mantenerse varias carpetas abiertas. Los nombres no cambian y las nuevas continúan apareciendo primero. Los archivos generales anteriores siguen accesibles.

**Subir** abre una sola hoja: nombre de carpeta, selección de Fotos/videos o Archivos y confirmación. La carpeta se crea al confirmar con archivos, conservando el identificador durante reintentos. Cancelar retira los temporales y no crea una carpeta. **Subir aquí**, en los puntos de una carpeta existente, permite agregarle archivos con la misma hoja. Se mantienen las dos transferencias simultáneas, progreso general, velocidad y reintento de pendientes. La calidad continúa en Gestión → Calidad de las imágenes; los videos no se recomprimen.

Abrir una foto muestra un visor propio de iOS. Deslizar horizontalmente sobre ella cambia de imagen; pellizcar o dar doble toque amplía. Al ampliar, arrastrar mueve la imagen. Se conservan flechas y acciones de accesibilidad. El visor autoriza cada original y continúa únicamente por las imágenes de esa carpeta, incluyendo su paginación. La decodificación de visualización, orientada y acotada a 4096 píxeles, no modifica el original.

Disponible sin conexión, Guardar carpeta en Fotos y eliminación administrativa siguen en los puntos o al mantener presionada cada carpeta. Se conservan revisión de espacio, confirmación y cancelación de transferencias.

## Archivos y controles

- `DocumentsView.swift`: presentación compacta, contexto independiente del slideshow, entrega de subida después de cerrar la hoja y visor UIKit de imágenes. Mac conserva QuickLook.
- `MediaInlineFolder.swift`: listado por carpeta con sesión/colección/cursor propios, caché cifrada inmediata y revalidación; cierre cancela lecturas. Un 401/403 o borrado invalida el contenido y el visor. Ningún fallo de autorización admite fallback offline.
- `MediaSimpleUploadComposer.swift`: borrador único con selección, creación idempotente y propiedad explícita de temporales. Retirar acceso o cambiar sesión cancela el borrador.
- Proyecto iOS: dos referencias de fuente y versión. Se preserva la configuración personal del Mac; el respaldo y la fuente privada contienen la configuración portable sin equipo personal.
- `LaunchTests.swift`: comprobaciones existentes adaptadas a las acciones nuevas; añadido recorrido de despliegue simultáneo y cancelación. Se verifica el gesto sobre el centro de la imagen además de las flechas.

Sin cambios de API, esquema, dependencias, hosting, dominio, secretos ni datos reales. Las verificaciones utilizan exclusivamente `.invalid`, archivos ficticios y un escritor simulado de Fotos; no suben, borran ni exportan contenido de producción.

## Verificación y entrega

TypeScript, build web y las 37 pruebas obligatorias de nómina pasaron. El servidor web y sus entradas no cambiaron; la publicación web sigue en v77.

Pruebas nativas: 99 unitarias ejecutadas en iPhone, con 98 aprobadas y una comprobación de protección física omitida por CoreSimulator; 108 aprobadas en Mac. Diez recorridos UI distintos de Fotografía aprobados al sumar las comprobaciones finales: carpetas simultáneas/cancelación, swipe y zoom, creación/subida de foto y video, destino existente/nuevo, offline y Fotos simulado, carga administrativa, calidad persistente, prohibición de borrado al fotógrafo, confirmación administrativa y miniaturas al recuperar una sesión lenta. Dos regresiones UI de iPad aprobadas. Release iPhone y compilación Mac correctos.

Informes locales: `photo-simple-final.xcresult` (unitarias y regresiones), `photo-simple-destination.xcresult` (destino/swipe/zoom/cancelación), `photo-simple-regression.xcresult` (administrador/miniaturas/offline), `photo-simple-ipad.xcresult`, `photo-simple-mac-unit.xcresult`. Durante la implementación fallaron dos recorridos al perderse el destino en la primera apertura del formulario. Se corrigió pasando una solicitud identificable a la hoja; ambos se repitieron y aprobaron, sin retirar comprobaciones. La recopilación extensa de diagnósticos del primer intento quedó atascada después de terminar las pruebas y se interrumpió; sus logs se conservan. Los informes de las repeticiones son independientes.

La firma y el esquema personales se compararon con la copia local: no hay cambios de configuración ajenos a versiones, referencias de fuente y metadatos ya trasladados por Xcode. Se mantienen cámara/Fotos, orientaciones iPad y push suspendido.

El iPhone físico no estaba conectado al preparar la actualización; instalar con **Run en el mismo proyecto**. No hace falta sustituir ni descargar otro proyecto. No se afirma una instalación física de esta versión.
