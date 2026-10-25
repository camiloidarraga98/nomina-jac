# Datos del vuelo en la tarjeta de pases

Camilo pidió mostrar la silla asignada, la hora de salida y la hora en sala junto a la ruta y el nombre que ya aparecen en la tarjeta nativa. La app iOS 0.32.0 (46) incorpora esta presentación compartida con iPad/Mac y conserva navegación, código original, PDF, menú y Apple Wallet.

La tarjeta muestra **Silla · Salida · En sala**, con horas locales en formato HH:mm. Por instrucción expresa, **En sala = Salida − 60 minutos**. Para una salida a las 00:30 muestra 23:30 y «Día anterior». Se hace aritmética civil, sin inventar zona horaria ni convertir a UTC. La tarjeta no modifica el pase original: la preparación editable de Wallet conserva su lectura original de embarque.

Los campos no identificados se muestran como «Sin indicar». Una llegada, puerta, fecha o hora de embarque no se convierte en salida. Tampoco se supone una silla. El menú permite «Actualizar datos del vuelo»; actualizar la lista reintenta lecturas fallidas. La lectura automática no marca el aviso como leído ni abre o firma Wallet.

## Lectura local y límites

Se analiza el adjunto privado existente, también para pases ya almacenados. No requiere nuevas claves, migraciones, servicios de aerolíneas, IA remota ni cambios web/API. Los originales mantienen su autorización y almacenamiento existentes.

El PDF de una página con etiquetas claras de silla y salida usa texto incrustado sin Vision. Para documentos incompletos e imágenes se usa código compatible de un solo tramo y OCR local acotado como alternativas. Una silla impresa tiene prioridad sobre el código; una indicación expresa sin asignación no se sustituye por una silla de fallback. Datos contradictorios o varios vuelos no se resuelven escogiendo el primero. Un PDF de varias páginas solo usa una página que contenga el único vuelo identificado; no mezcla hora y silla de páginas distintas.

El análisis automático admite PDF/JPG/PNG, hasta 10 MiB y 12 páginas; OCR sobre imágenes de hasta 1600 píxeles, máximo 4 millones de píxeles, 24 códigos y texto acotado. El texto completo de una página permite omitir la decodificación de códigos: es una presentación informativa del documento, sin verificación independiente de la aerolínea. Formatos o distribuciones que no permitan lectura inequívoca conservan el original para consulta.

## Caché y privacidad

Cada lista conserva hasta 64 resultados en memoria, incluidos los vacíos/fallidos, para evitar nuevas descargas y OCR al desplazar o volver a una tarjeta. Se usa la descarga privada existente y su caché cifrada para consulta offline; no se añade una copia persistente de los datos extraídos.

La clave incluye sesión/sello de acceso, aviso, adjunto, revisión y metadatos. Exigir el aviso canónico autorizado antes y después evita mostrar resultados de otra sesión, versión o archivo y evita reintentos en bucle tras un 403. Revocar o borrar retira los valores. Los temporales se eliminan tanto al terminar como ante fallo/cancelación.

Hay como máximo dos trabajadores por lista. Un trabajo cancelado sigue ocupando su puesto hasta terminar realmente, porque cancelar no interrumpe de inmediato una solicitud síncrona de Vision. El procesamiento de PDF/OCR ocurre fuera del hilo de interfaz; las consultas y resultados tardíos se revalidan antes de mostrarse.

## Verificación e instalación

Fuente funcional preparada en `455c22c`. Se comprueba únicamente el alcance modificado: cinco casos de cálculo/parser, tres de caché/concurrencia/revocación y un recorrido UI de tarjeta/PDF/medianoche, con originales sintéticos y red interceptada; compilación Mac por las fuentes compartidas. La sintaxis YAML y sus ocho bloques shell se comprobaron localmente. La ejecución [40162583700](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40162583700), sobre la misma fuente, aprobó ocho pruebas unitarias y un recorrido UI (25.008s), cero fallos y `TEST SUCCEEDED`. La compilación Release de Mac terminó con `BUILD SUCCEEDED`. Release de iPhone y suites de otros módulos se omitieron deliberadamente; no se repitió ningún caso. Esto no equivale a firma, subida a TestFlight o instalación física.

Las fuentes web/Worker no cambian y no se repiten sus compilaciones, pruebas o despliegues. Firma, bundle, Team ID y separación APNs se conservan. Para instalar, hacer pull en el mismo Xcode; crear/subir un Archive 0.32.0 (46) y actualizar desde TestFlight, o instalar mediante Run. La firma/distribución física permanece en el Mac de Camilo.
