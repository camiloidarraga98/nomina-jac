# Compresión obligatoria de videos en iOS

## Decisión vigente

Camilo pidió que los nuevos videos adjuntos en Fotografía se compriman siempre, incluyendo HDR y aunque baje la calidad. Esta petición sustituye el interruptor opcional, la conservación de HDR y el fallback al original de la primera prueba. La implementación cubre Fotos/Archivos del compositor de iPhone y la subida alternativa de iPad. Web y Mac mantienen su flujo previo.

Todos los videos nuevos pasan por AVFoundation antes de reservar su subida remota. Se usa MP4 H.264 con audio AAC cuando existe, calidad media, composición SDR Rec.709, orientación aplicada y un máximo de1280píxeles en el lado largo y30fps; el preset puede reducir más. HDR se convierte a SDR y la transparencia se aplana sobre negro. No se impone un tamaño objetivo fijo ni un nuevo límite de duración: el peso depende del contenido y la duración.

Se muestra tamaño anterior/nuevo y ahorro cuando existe, y se puede reproducir la copia antes de subir. Un archivo diminuto o ya muy eficiente puede terminar igual o mayor por la nueva codificación/contenedor; se indica «Recomprimido» y se envía la copia procesada, nunca se vuelve al original. Si el formato no se puede decodificar/exportar o falla la conversión, ese video se rechaza con un error. El resto del lote puede conservar sus archivos válidos.

Las fotos siguen usando su ajuste independiente. El archivo original de Fotos/Archivos queda intacto; JAC almacena la copia procesada. Mantener JAC abierta durante la preparación. Después de entregar el lote, la cola recuperable y las transferencias del sistema conservan su comportamiento en segundo plano.

## Controles

`MediaVideoPreparation.prepare` carece de modo original para videos. Se verifican video H.264, audio AAC, duración y límites de salida antes de aceptar el resultado. Cancelar elimina candidatos y temporales; un cambio de sesión/permiso descarta resultados tardíos. Los directorios/archivos privados conservan protección completa y exclusión de backup. No se envían videos a un servicio externo ni se añaden dependencias.

`MediaLocalFile.videoPrepared` identifica la preparación local terminada y `MediaUploadQueue.enqueue` rechaza videos nuevos sin esa marca. Reintentar usa los mismos bytes/UUID ya preparados. No se recodifican videos de la galería ni cargas remotas iniciadas: cambiar tamaño/MIME de una carga parcial rompería su confirmación y reanudación. La marca no cambia el contrato API ni el manifiesto existente.

## Verificación

La entrega agrupa la compresión y la mejora del scroll. La ronda final dirigida comprende preparación normal/HDR, rechazo de originales sin procesar, cancelación, audio/orientación/duración, cola, carga/caché de miniaturas y tres recorridos de interfaz (revisar/cancelar video, recorrer una carpeta grande y continuar una subida tras salir/Home). No se ejecutan suites financieras ni web. Se compila Mac porque DocumentsView contiene cambios compartidos; no se repite un segundo Release de iPhone. Fixtures locales .invalid, imagen/video ficticios y silencio PCM generado; sin subidas, borrados ni fototecas reales.

La primera versión opcional tuvo16 unitarias aprobadas en39191316820 y la UI corregida aprobó en39192378915. Esos resultados describen el comportamiento anterior y no verifican por sí mismos esta nueva política obligatoria. El resultado nuevo se registra al cerrar la entrega. La conversión de material real y la calidad visual requieren revisión en el iPhone físico.

Mismo proyecto Xcode y Team AYHVYN8BJF: actualizar main mediante pull y Run, sin reinstalar desde otro proyecto ni cambiar firma, bundles, entitlements o pushNO.

## Resultado final comprobado

[Ejecución39202395410](https://github.com/camiloidarraga98/nomina-jac/actions/runs/39202395410), fuente `1735e0268d3f772d08efba7897755cf4cb089b72`: iPhone y Release Mac correctos. Pasaron23 unitarias y tres UI, cero fallos y ninguna prueba omitida. Las seis de preparación incluyen un fixture HEVC Main10/HLG generado localmente: se confirmó que la fuente tiene HDR y que la copia final es H.264 SDR, sin volver al original. Se verificaron también audio/orientación/duración, fotos intactas, videos pequeños recomprimidos, cancelación y rechazo del video sin preparar en la cola.

Las tres UI aprobaron revisión/cancelación de video, scroll de80fotos con selección funcional y subida de foto/video MP4 que continúa después de salir/Home. El segundo Release iPhone quedó omitido; no hubo suites web/financieras ni repeticiones de la ronda. El cambio documental posterior mantiene las mismas entradas nativas/workflow comprobadas y no inicia otra ejecución. No se usaron videos/fototecas reales ni se instaló en un teléfono físico desde CI.
