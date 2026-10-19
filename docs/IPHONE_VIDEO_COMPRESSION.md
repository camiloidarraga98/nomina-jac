# Compresión opcional de videos en iPhone

Primera prueba solicitada por Camilo: reducir el peso según el contenido y duración, sin fijar un tamaño máximo nuevo por video ni prometer compresión sin pérdida. Alcance inicial: compositor de subida del iPhone; web/iPad/Mac conservan su flujo. El límite técnico previo del almacenamiento no se modifica.

Esta petición sustituye, solo para la opción del iPhone, la decisión anterior de subir siempre videos originales. La preferencia más reciente de trabajo exige agrupar cambios y probar únicamente al final lo modificado y sus dependencias afectadas, sin suites/builds redundantes. Una corrección que invalide un resultado sí requiere volver a comprobarlo. Las ramas de preparación ya no disparan Actions; la entrega final en main inicia la comprobación pertinente.

## Uso

1. Fotografía → Subir archivos, en una carpeta existente o indicando el nombre de una nueva.
2. Antes de agregar archivos, activar **Optimizar videos para web**. Está desactivado inicialmente y se fija mientras el lote contiene archivos.
3. Agregar fotos/videos desde Fotos o Archivos. Las fotos conservan su ajuste independiente. Mantener JAC abierta durante la preparación; Cancelar detiene la conversión y limpia sus temporales.
4. Cada video muestra el peso preparado. Si la conversión ahorra al menos un5%, muestra peso anterior/nuevo y porcentaje; en otro caso explica por qué conserva el original. **Ver video antes de subir** permite revisar la copia que realmente se enviará.
5. Subir entrega esos mismos bytes/UUID a la cola cifrada y recuperable existente. La subida puede continuar en segundo plano; la compresión previa no tiene esa garantía. Cerrar a la fuerza iOS conserva las limitaciones anteriores.

El archivo de Fotos/Archivos queda intacto. Si se sube una copia optimizada, esa copia es el archivo disponible en JAC y en las descargas posteriores; JAC no almacena además el original de cámara. Para conservarlo también en JAC, subir sin activar la opción.

## Implementación y límites

AVFoundation del iPhone, sin servicios externos, FFmpeg/WASM ni dependencias. `AVAssetExportPresetHighestQuality`, MP4 con optimización de inicio en red y varias pasadas permitidas; sin `fileLengthLimit`, reducción de resolución ni límite de duración nuevo. Se validan H.264, audio AAC cuando existe, número de pistas, tamaño visual/orientación, fotogramas por segundo y duración antes de aceptar la copia. No garantiza reproducibilidad en navegadores que no admitan ese perfil/resolución.

No se convierte silenciosamente HDR/transparencia ni videos de múltiples pistas. Un formato no admitido, falta de espacio, error, cambio de características o ahorro inferior al5% conserva el original con un mensaje. Un video HEVC ya eficiente puede quedar igual: convertirlo a H.264 no garantiza reducirlo. No se afirma un porcentaje real de ahorro para los videos de Camilo; debe comprobarse con material representativo en el teléfono.

La compresión usa pérdida; conservar dimensiones/fps no demuestra por sí solo igualdad visual. Se proporciona vista previa y opción original. Si los resultados de esta prueba no ahorran suficiente, un perfil con otra resolución/eficiencia requiere una decisión posterior sobre calidad y compatibilidad.

Temporales dentro de la raíz privada, protección completa de archivos/directorios y exclusión de copia de seguridad. La copia fallida/descartada se retira; la fuente temporal se libera después de aceptar la copia o cancelar. El candidato nunca reemplaza el archivo importado. Sesión/permiso se revalidan después de exportar y antes de incorporar el resultado. No se reserva una carga remota ni se crea una carpeta mientras se prepara/revisa. Reintentar usa exactamente el archivo ya preparado y la cola existente; no recodifica ni cambia tamaño/MIME de una carga iniciada.

## Verificación dirigida

Pruebas definidas para esta entrega: cinco unitarias de preparación (bytes originales/fotos intactos, ahorro, formato inválido, cancelación y MP4 real con audio generado/rotación/duración), regresiones de la cola afectada y un recorrido UI de activar, preparar, revisar y cancelar antes de subir. Fixtures locales `.invalid`, video ficticio y silencio PCM generado; sin fototecas, subidas, eliminaciones ni servicios reales.

El workflow usa un único job de simulador con `[check-video-upload]` al entregar en main, en runners públicos estándar. No repite suites financieras/web, UI de selección múltiple, Mac ni un segundo build Release de entradas sin cambio. Una comprobación fallida o invalidada por una corrección sí se repite. El resultado observado se registra al finalizar; la revisión de imagen y el ahorro real permanecen para la prueba física en el mismo proyecto Xcode.

Primera ejecución `39191316820`, fuente `2637d6d`: compilación correcta y16/16 unitarias aprobadas (cinco de preparación y once de cola). La conversión real con audio PCM ficticio verificó MP4 H.264/AAC, menor tamaño, orientación, duración e identidad del archivo; también pasaron original/fotos intactos, formato inválido, cancelación y umbral de ahorro. La única UI falló porque el identificador heredado de la fila reemplazaba el identificador del texto de resultado, aunque este y la vista previa estaban presentes. Se retira ese identificador del contenedor. Se conserva el código de compresión sin cambios y se repite únicamente esa UI, mediante `[check-video-upload] [ui-only]` o el alcance manual `video-upload-ui`. Las16 unitarias aprobadas se reutilizan.
