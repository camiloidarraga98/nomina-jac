> **Actualización · 25 de octubre de 2026:** los datos explícitos enviados con el pase en Slack tienen prioridad por campo. Hora en sala conserva el valor escrito; salida menos60minutos se usa si ese campo falta. Esta decisión sustituye el cálculo obligatorio descrito abajo cuando existe una hora explícita. Ver [Datos de Slack](BOARDING_SLACK_DETAILS.md).

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


## Alineación de las tres columnas · 25 de octubre de 2026

Camilo señaló que Silla, Salida y En sala no quedaban alineados con sus valores. El ajuste usa títulos de texto sin reserva para iconos: mismo borde izquierdo, fuente y separación vertical en cada columna. El aviso «Día anterior» permanece debajo de su hora y el tamaño de accesibilidad conserva la distribución vertical.

Fuente `580a203`, iOS 0.32.1 (47). Se reutilizan los ocho casos unitarios y la compilación Mac de la funcionalidad anterior, porque lectura, cálculo, caché y permisos no cambian. La ejecución [40163521420](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40163521420) aprobó la compilación iPhone y el único recorrido UI existente para obtener la captura actual. No se añaden pruebas para este ajuste visual ni se repiten web/API, Release o suites de otros módulos. La instalación física requiere actualizar desde Xcode/TestFlight a47.


## Tarjeta simplificada y apertura directa · 25 de octubre de 2026

Camilo pidió ocultar el nombre del archivo y retirar el botón dedicado «Abrir PDF». En iOS 0.32.2 (48), tocar la cabecera, fecha, datos del vuelo o espacios de la tarjeta abre el documento original mediante la misma lectura privada. «Mostrar código» y el menú mantienen sus acciones independientes; el indicador de apertura pasa a la cabecera. Si el nombre no permite reconocer la ruta, se muestra un título genérico en vez del nombre del archivo.

El botón de apertura ocupa el fondo de la tarjeta; su contenido informativo deja pasar el toque y el pie conserva controles hermanos activos, sin botones anidados ni gesto global que active también el PDF. Se conservan identificadores, etiquetas accesibles sin nombre de archivo, confirmación de borrado, permisos, originales, caché y reglas de horas.

Fuente `5329b37`. Se adapta únicamente el recorrido UI existente para verificar ausencia del nombre/botón anterior, apertura al tocar la zona de silla, vuelta al listado y acciones de código/menú sin abrir a la vez el PDF. Se reutilizan las ocho unitarias y demás compilaciones por no cambiar parser, lectura privada, cálculo o caché; no se repiten web/API ni se despliega el Worker. La ejecución [40164488391](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40164488391) aprobó la compilación iPhone y el recorrido focal. Mac/Release y las unitarias se omitieron; su evidencia anterior no se presenta como una prueba nueva de esta interacción. Instalar con pull y Archive/Upload 0.32.2 (48) o Run desde el Mac de Camilo; no se afirma instalación física.


## Código en cuarta columna y menú superior · 25 de octubre de 2026

Camilo pidió colocar Mostrar código junto a En sala y usar el espacio de la etiqueta PDF para el menú. En iOS 0.32.3 (49), el bloque contiene **Silla · Salida · En sala · Código**: el cuarto campo muestra un icono QR y conserva «Mostrar código» como etiqueta accesible y su objetivo táctil mínimo de44puntos. El menú ocupa la esquina superior derecha, sin etiqueta PDF/Imagen ni fila inferior de botones. Los títulos siguen alineados arriba, el icono escala con el texto y los tamaños de accesibilidad conservan la distribución vertical.

Los tres datos y el fondo decorativo dejan pasar el toque al documento; Código y el menú son controles independientes activos. Se conserva la apertura desde toda la zona pasiva, el indicador de carga en cabecera y el bloqueo durante apertura/borrado. No cambia ninguna lectura privada, dato, cálculo, caché, permiso o acción de Wallet.

Fuente `99b91bd`. Se reutiliza el recorrido UI existente, sin pruebas nuevas de estilo ni repetición de las unitarias/Mac/Release o web/API. La ejecución [40165430740](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40165430740) aprobó la compilación iPhone y el único recorrido UI (115.750s, cero fallos, `TEST SUCCEEDED`), con apertura del PDF desde los datos y acciones independientes de Código/menú. La actualización física requiere pull y Archive/Upload 0.32.3 (49) o Run desde el mismo Xcode; no se ha instalado desde CI.
