# Fluidez y trabajo de las secciones nativas

Entrega verificada: iOS **0.35.0 (53)**, 25 de octubre de 2026, Colombia. Camilo reportó desplazamiento entrecortado en varias vistas y pidió revisar la causa con profundidad. Implementación y comprobaciones de CI correctas. Posteriormente se completaron firma/instalación en el iPhone 17 Pro y una primera captura física de Animation Hitches + Time Profiler: [activación local, resultados y límites](IPHONE_WIDGETS_LOCAL_ACTIVATION.md). El propietario confirmó scroll fluido; la traza contiene pausas breves en transiciones y no se presenta como una garantía de FPS. Los apartados de evidencia CI siguientes conservan el estado previo a la comprobación local.

## Hallazgos de revisión de código

La inspección estática encontró trabajo costoso accesible desde propiedades consultadas al dibujar una vista: lecturas de sesión en Llavero, derivación del ámbito criptográfico, apertura de respuestas cifradas y decodificación JSON. En particular, la clave y el estado de cada tarjeta de pase recorrían de nuevo la consulta del aviso canónico. Con varias tarjetas, una evaluación de SwiftUI podía repetir ese recorrido para cada fila.

También se identificaron guardados individuales del índice de la copia offline y publicación de cambios ante respuestas de polling sin novedades. Las secciones de iPhone permanecen montadas para conservar rutas y scroll; comprobar sólo `scenePhase == .active` permitía que una sección tapada por otra, o por el menú lateral, siguiera consultando y precargando.

Estos son hallazgos de código, **no una captura de Instruments ni una medición de FPS**. No se atribuye todavía un porcentaje de mejora, una latencia concreta o un consumo de batería a un dispositivo real.

## Lecturas calientes y persistencia

`PayrollClient` conserva ámbitos ya derivados y respuestas tipadas en RAM, separados por sesión, generación y revisión. La caché tipada tiene un máximo de 256 entradas y un presupuesto de 32 MiB del contenido contabilizado; también limita las ausencias recordadas. Agenda conserva su registro autorizado en memoria. Las tarjetas usan `BoardingCardDetailsStore.presentationKey` y su estado listo para consultar los datos ya disponibles sin abrir el almacenamiento durante cada render.

La identidad de presentación no concede autorización para descargar o abrir archivos. Las operaciones reales conservan su revalidación estricta de sesión, permiso, aviso, archivo y revisión. Cerrar sesión, retirar acceso, borrar o sustituir una copia invalida las referencias calientes. Una denegación del feed completo también retira los avisos canónicos que se habían cargado. Una respuesta de workspace más antigua no reemplaza la revisión nueva de RAM o disco.

Las lecturas explícitas de `OfflineResponseCache` siguen autenticando el archivo cifrado actual; no se introduce una copia de respuestas en claro dentro de ese almacén. La primera carga y una operación de autorización pueden necesitar Llavero, disco y JSON: el presupuesto de cero se aplica al intervalo **caliente, ya autorizado**, no a todo el arranque de la app.

La persistencia de respuestas y Agenda se ordena fuera del hilo principal. `saveBatch` procesa el feed y sus avisos canónicos como un lote, con un solo guardado del índice. Compara contenido, cabeceras y revisión; cambiar únicamente la fecha de recepción no obliga a volver a cifrar/escribir una respuesta idéntica ni a incrementar `cacheRevision`. Épocas de invalidación evitan que un trabajo encolado restaure datos después de un borrado o una revocación. Un diario por recurso limita la invalidación de RAM a las claves modificadas: hasta128lotes,4096claves y4ámbitos, sin guardar bytes privados. Una actualización de otro módulo no enfría las tarjetas. Si se pierde el rango del diario, desborda o se limpia una sesión, se invalida todo de forma conservadora. La prueba de lote también comprueba129cambios y recuperación precisa de deltas recientes.

## Visibilidad sin perder estado

`isWorkspaceActive` comunica si el destino del iPhone es el seleccionado y si el menú lateral está cerrado. Agenda, listas de avisos/pases, Fotografía y la biblioteca de Música combinan esa condición con la fase activa de la escena para controlar sus lecturas automáticas. Los identificadores de tarea incluyen ubicación y actividad; al ocultar la sección se cancela su ciclo, y las respuestas tardías comprueban otra vez la visibilidad antes de instalarse.

Fotografía detiene el productor de precarga y pausa las tareas de miniaturas al quedar oculta. Conserva las imágenes calientes y el estado de carpeta; al volver retoma la carga autorizada. Cancelar un productor no implica revocar una petición que el servidor ya recibió: el recorrido UI toma un punto estable antes de comprobar que no se inician más solicitudes ocultas.

El cambio conserva los destinos visitados y sus rutas, formularios, selección y scroll. No desmonta toda la aplicación para abrir el menú. La reproducción de audio, la cola persistente de subidas y las transferencias explícitas mantienen su ciclo independiente; pausar el polling de una biblioteca no equivale a detener su reproductor. El panel sigue desplazando físicamente el contenido y sus gestos verticales deben permitir recorrer las opciones sin cerrarlo.

## Instrumentación y presupuestos

`JACPerformanceDiagnostics` contabiliza operaciones reales de lectura/escritura de disco, guardado de índice, derivación de clave, codificación/decodificación JSON y lectura de sesión. Distingue totales y trabajo en el hilo principal. Los contadores y el informe agregado están habilitados en DEBUG, fuera de `ObservableObject`, para que medir no publique cambios de interfaz. El registro no contiene nombres, identificadores de archivos, URLs, tokens ni contenido de documentos. En Release sus puntos de diagnóstico no recolectan esos contadores.

Tres métodos de `PayrollClientTests` actúan como guardias rápidas en los alcances reales de pruebas presentes y futuros:

| Método | Presupuesto que debe verificar |
| --- | --- |
| `testWarmFortyBoardingCardsPerformNoMainThreadIOCryptoOrJSON` | Cuarenta tarjetas listas, 500 recorridos por sus claves y estados reales: 20.000 lecturas listas; cero lecturas/escrituras de disco, derivaciones, JSON o lecturas de sesión en el hilo principal durante el intervalo caliente. |
| `testWarmCalendarAndWorkspaceRenderDoNotReadSessionOrDecode` | Quinientos accesos calientes a workspace/Agenda del cliente y del store: cero operaciones costosas en el hilo principal; la copia deja de estar disponible tras cerrar sesión. |
| `testNoticeBatchPersistsOneIndexAndUnchangedPollDoesNotWriteOrPublish` | Feed de cuarenta avisos: un índice, 42 escrituras totales (feed + cuarenta avisos canónicos + índice), ninguna lectura/escritura de disco en el hilo principal. Repetir exactamente la respuesta produce cero escrituras de datos/índice y conserva `cacheRevision`. |
| `testUnrelatedCacheWritesKeepFortyWarmCardsOffMainThreadIO` | Tras actualizar workspace y Fotografía, cuarenta tarjetas conservan 20.000 accesos listos sin I/O, Llavero o JSON en el hilo principal. Cambiar una tarjeta retira sólo esa; denegar el feed retira todas. |
| `testGalleryPinPresentationChecksEightyItemsWithoutMainThreadIOAndRejectsRevocation` | Ochenta estados de descarga desde una reapertura: una foto guardada, otra retirada y el resto ausentes; cero lecturas de sesión y cero I/O/JSON/derivación en el hilo principal. Revocación y cierre impiden consultar el estado. |
| `testDecodedGalleryThumbnailsReuseEightyWarmImagesWithoutSessionReadsAndRejectRevocation` | Ochenta imágenes cargadas por el flujo real se reutilizan sin nuevos HTTP, Llavero ni trabajo costoso en MainActor; revocación y logout rechazan los píxeles todavía presentes en RAM. |

La selección completa de `JACNominaTests` ya incluye esas guardias; el workflow evita agregarlas dos veces. Los seguimientos explícitos UI-only y las acciones `build-for-testing` reutilizan los resultados previos del Core en lugar de ejecutarlas otra vez.

El alcance completo añade cinco casos nuevos de carreras, sustitución y revocación, además de las regresiones focales de caché de pases, copia cifrada, Agenda y autorización de Música:

- `testOfflineBatchRejectsLateWritesAfterRevocationAndRemainsReadableOnRelaunch`: reabre cuarenta registros persistidos; un lote con época anterior no puede restaurar una copia retirada.
- `testPendingNoticePersistenceCannotReturnAfterLogout`: suspende la petición real entre respuesta y commit mediante una barrera de fixture; el cierre de sesión obliga a cancelar, sin devolver el feed ni conservar RAM/disco.
- `testNoticeFeedDenialInvalidatesWarmCanonicalCards`: un 403 del feed retira los cuarenta avisos calientes y sus claves de presentación, sin fallback privado.
- `testOlderWorkspaceResponseCannotReplaceWarmNewerWorkspace`: una respuesta 13 tardía no sustituye la revisión 14 ya presente en RAM y disco.
- `testConcurrentAgendaPersistenceMergesMonthsAndRejectsOlderPendingUpdate`: conserva dos meses cuando se encola una segunda publicación durante el primer guardado y rechaza una actualización anterior del mismo mes; verifica RAM, disco y reapertura.

También se conserva `testRejectedWorkspaceSaveCannotRestoreRevokedRoleOrOldAgendaIdentity`, la regresión existente de permisos e identidad de Agenda ante un guardado rechazado.

## Recorridos UI y métrica de scroll

`ScrollPerformanceTests` usa exclusivamente el backend opt-in de DEBUG con URLs `.invalid`, ochenta fotos ficticias y cuarenta pases ficticios. La sonda se consulta mediante una acción explícita y sólo devuelve contadores agregados; no está disponible en una sesión normal. La carga de esos fixtures no sustituye una biblioteca real ni mide el coste de decodificar fotografías de producción.

`testWarmPhotoAndBoardingListsKeepResponsiveScrolling` recorre realmente ambas listas hasta sus extremos para calentarlas, comprueba que las cuarenta sillas llegaron a estado listo, vuelve al inicio y realiza cuatro iteraciones con `XCTOSSignpostMetric.scrollDecelerationMetric`. Comprueba que los elementos se desplazan, que la carpeta sigue abierta al volver y que no aparecen lecturas/escrituras de disco, derivaciones o JSON en el hilo principal. Distingue un intervalo atravesado por la revalidación global de sesión de uno sin nuevas solicitudes, y exige al menos un intervalo completamente inactivo de cada lista para aplicar el presupuesto conjunto de cero operaciones costosas. Los presupuestos deterministas de 500 recorridos no dependen de esa coincidencia temporal.

`testHiddenSectionsSuspendPollingAndPrefetchWhileSidebarScrolls` usa texto accesible grande para hacer desplazable el menú, cuatro lotes de gestos verticales desde el inicio verificado del panel y miniaturas deliberadamente lentas. Verifica que el menú permanece abierto, que la precarga empieza al abrir la carpeta y se interrumpe antes de solicitar las ochenta miniaturas. Después de asentarse, espera 31 segundos —más que el ciclo automático de 30— y comprueba que no aumentan las solicitudes de los feeds ocultos ni de sus miniaturas. Al cerrar el panel, la carpeta y sus elementos siguen presentes.

La métrica de XCTest registra las señales reales del sistema durante el scroll; **no establece un umbral de milisegundos o FPS dependiente del runner**. El éxito de una prueba no demuestra por sí solo una frecuencia estable de cuadros en un iPhone físico. El alcance completo conserva también `testPhoneSidebarKeepsMusicAndNestedAccountState` y `testAlexAgendaDatesRemainUsableAfterSwitchingMenusAndBackground` por los cambios directos de visibilidad y navegación.

## Ejecución y evidencia de CI

Workflow: [native-checks.yml](../.github/workflows/native-checks.yml). El commit con `[check-scroll-widgets]`, o el input manual `scope=scroll-widgets`, ejecuta los casos anteriores y `WidgetSnapshotTests`, compila Release de iPhone con `JACWidgets.appex` embebido y compila las fuentes compartidas de Mac. Los tres jobs seleccionan el Xcode más reciente ya instalado y registran Xcode/Swift; no instalan un SDK nuevo.

Comando manual equivalente para iniciar el alcance completo desde la fuente congelada de `main`:

```sh
gh workflow run native-checks.yml --ref main -f scope=scroll-widgets
gh run list --workflow native-checks.yml --limit 5
```

El job del simulador usa esta invocación, con `checks` formado por los selectores del alcance en el propio workflow y `JAC_CI_SIMULATOR_ID` generado para el simulador desechable:

```bash
xcodebuild -project ios/JACNomina.xcodeproj -scheme JACNomina \
  -destination "platform=iOS Simulator,id=$JAC_CI_SIMULATOR_ID" \
  -derivedDataPath native-ci/simulator -resultBundlePath native-ci/iphone.xcresult \
  -parallel-testing-enabled NO "${checks[@]}" \
  ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= JAC_PUSH_ENABLED=NO test
```

Tras una primera ejecución válida, un seguimiento con `[check-scroll-widgets] [scroll-widgets-ui-only] [iphone-only]` ejecuta **sólo las dos UI nuevas**. Omite las guardias rápidas, las unitarias restantes, las dos UI existentes y ambas Release únicamente cuando sus entradas no cambiaron; documentar el commit de fuentes reutilizado. No usar ese marcador para declarar comprobadas modificaciones del Core, del widget o del proyecto.

Los runners siguen siendo `macos-15` estándar con repositorio público, permisos de lectura, firma ad hoc de prueba, servicios interceptados y ningún envío, archivo, cuenta o secreto de producción. Release se compila sin certificado de distribución. Sus comprobaciones de bundle, App Group y entitlements efectivos/origen no equivalen a registrar el grupo en Apple ni a instalar la app. Los detalles del widget están en [IPHONE_WIDGETS.md](IPHONE_WIDGETS.md).

Artefactos previstos: `JAC-Apple-Diagnostics-<SHA>` (resumen, contadores en logs, capturas y exportación opcional de métricas), `JAC-Apple-<SHA>` (resultado `.xcresult` completo), `JAC-iPhone-Release-<SHA>` y `JAC-Mac-Release-<SHA>`. Consultar el `.xcresult` y los logs si la exportación opcional de métricas no produce datos; no presentar un archivo vacío como medición.

## Estado de comprobación de esta entrega

| Comprobación | Estado | Evidencia por registrar |
| --- | --- | --- |
| Revisión estática de rutas calientes y guardas de visibilidad | Implementada y contrastada con pruebas | No sustituye un perfil físico. |
| Presupuestos de Core y regresiones focales | Correctos | 24 casos distintos de PayrollClientTests entre las ejecuciones focales; detalle al final. |
| Dos UI nuevas, dos UI existentes y señales de scroll | Correctas | Sidebar en40228053257; scroll caliente en40230506716; dos recorridos existentes en40225259043. |
| WidgetSnapshotTests, Release iPhone/widget y Mac | Correctos, con una omisión física explícita | 12 casos del widget correctos/1 físico omitido; Release iPhone final40231517171 y Mac40230506716. |
| Instalación y perfil en iPhone/iPad físicos | **PENDIENTE** | Modelo, versión de iOS, Instruments (hilo principal, Animation Hitches/Time Profiler) y comparación con la misma carga. |

La validación física debe incluir scroll prolongado de Fotografía y Pases, cuatro desplazamientos verticales del menú con texto grande, regreso a una carpeta abierta y reproducción/subida en curso. Registrar tirones observados y trabajo del hilo principal antes de atribuir una mejora cuantitativa. No repetir suites ya válidas si no cambian sus entradas; limitar los seguimientos a la corrección y a sus dependencias reales.

## Primera ejecución y seguimiento dirigido

CI40225259043 sobre010c3f6 confirmó18 unitarias de cliente/caché y dos UI existentes; Release iPhone/Mac también correctos. Diez pruebas del widget pasaron y una aserción de protección de datos falló porque el simulador devuelve un atributo de hardware nulo. Se separó esa aserción en un caso explícitamente físico, conservando las comprobaciones de contenido y permisos Unix; no se declara protección física probada en simulador.

Las dos UI nuevas detectaron una consulta estricta al Llavero desde el getter de aerolínea y un inicio del test lateral con su scroll ya al final. Se cambió el getter a la identidad de presentación en RAM y se exige el inicio correcto antes de desplazar. También se detectó en revisión el enfriamiento global de tarjetas por escrituras ajenas y se añadió el diario por recurso y el cuarto presupuesto. Las pruebas de primera carga y apertura privada mantienen validación estricta.

El seguimiento `[scroll-widgets-cache-followup]` junto a `[check-scroll-widgets]` ejecuta20casos de cliente/caché, la clase de widget corregida y las dos UI nuevas, y recompila Release iPhone/Mac. Reutiliza las dos UI existentes ya correctas. Resultados del seguimiento y cierre de la UI registrados abajo; no inferir una UI correcta únicamente del éxito de compilación.

El refresco del widget conserva la copia vigente al bloquearse el teléfono: comprueba la disponibilidad de datos protegidos antes de leer Keychain y distingue el estado exacto `errSecInteractionNotAllowed` de una sesión ausente o revocada. No cambia WhenUnlocked ni comparte credenciales. El caso de bloqueo usa disponibilidad inyectada y exige cero lecturas de sesión; la protección de archivos real sigue siendo una comprobación física explícita.

## Segundo resultado y cierre de Fotografía

CI40228053257 sobre f1213c8:20 unitarias de cliente correctas,12 unitarias del widget correctas y una comprobación física de protección omitida explícitamente en simulador. La UI lateral pasó156.454 s: cuatro desplazamientos efectivos y31 s sin nuevos requests de secciones ocultas; conserva la carpeta abierta. Release iPhone/widget y Mac correctos, sin advertencias Swift.

La UI caliente aún detectó24lecturas de sesión en Fotografía (tres por cada uno de ocho menús de foto recién visibles), con cero nuevas peticiones y sin disco/JSON/derivación en el hilo principal. La causa fue el indicador de descarga de `MediaPhotoMenu.updatePinned`, no el acceso a las imágenes. Se extrae `mediaPinnedForPresentation`: ámbitos y permisos de memoria, consulta de pin en utilidad y revalidación de memoria al terminar. La creación del cliente prepara el ámbito de Fotografía durante el arranque para conservar la reapertura sin conexión. Descargar, guardar o borrar mantienen sus validaciones estrictas.

`[scroll-widgets-gallery-followup]` con `[check-scroll-widgets]` ejecuta la UI caliente completa, el nuevo caso de ochenta estados, dos regresiones de descarga/revocación y los seis presupuestos obligatorios sin duplicarlos, más ambas Release. Reutiliza las pruebas del widget y la UI lateral ya correctas. Resultado final correcto en40230506716: siete unitarias y la UI caliente aprobadas.

## Precarga de imágenes ya disponibles

La precarga que se reanuda al volver a una sección podía repetir autorización estricta por cada imagen aunque ya tuviera los píxeles decodificados. `MediaGridThumbnailLoader.image` reutiliza ahora exactamente la misma presentación de memoria que las celdas, con permiso conocido, ámbito actual, identidad del archivo y cancelación. Si falta el píxel decodificado, conserva todo el flujo previo de autorización, bytes y revalidación.

El caso de ochenta imágenes puebla el loader por peticiones reales a URLProtocol de fixture, no fabrica claves de caché; la segunda pasada no puede leer sesión ni iniciar otro HTTP. Retirar acceso o cerrar sesión rechaza las imágenes que sigan en la instancia local. `[scroll-widgets-memory-followup]` comprueba este cambio iOS, dos regresiones de privacidad y los seis presupuestos deduplicados, más Release iPhone. Mantiene el recorrido UI de la ejecución de galería en paralelo, sin cambiar sus entradas visuales ni repetirlo. Resultado correcto en40231517171: ocho unitarias aprobadas.

## Evidencia final · 25 de octubre de 2026

- **40231517171**, fuente `19b017084dc56dbe043b346f2ed9b4df8f6cdac9`: ocho unitarias de caché/privacidad correctas,90.680 s, incluida la carga real de80 imágenes y su reutilización sin HTTP ni lecturas de sesión. Release iPhone y extensión WidgetKit correctos, sin advertencias Swift. Ambos productos 0.35.0(53), Team AYHVYN8BJF y AppGroup verificados sin firma de distribución. Mac omitido porque este último cambio de producto está íntegramente bajo `#if os(iOS)`; su Release válido se reutiliza.
- **40230506716**, fuente `3f58e71e3ad813c774ffd79743808fe9d32834ef`: siete unitarias correctas y UI caliente correcta506.510 s. Tras probar listas de80 fotos/40 pases, los intervalos sin nuevo tráfico tienen delta0en todas las operaciones costosas del hilo principal. Los diez intervalos registrados (incluida la pasada de preparación de XCTest) no añadieron disco, JSON o derivaciones en MainActor; los intervalos con revalidación global se distinguen expresamente. Cuatro muestras de la señal Scroll_Deceleration:2.299437,2.309056,2.298261,2.299476 s; representan duración de deceleración acumulada del recorrido, **no latencia de la app, tiempo de bloqueo ni FPS**. Promedio 2.302 s, desviación relativa 0.189 %, sin comparación contra una versión física anterior. Release iPhone/widget y Mac correctos.
- **40228053257**, fuente `f1213c8`:20 unitarias de cliente correctas y12 de widget correctas,1física omitida; sidebar156.454 s correcto con cuatro lotes verticales y31 s de pausa de feeds ocultos. El fallo caliente de ese momento quedó resuelto y comprobado en el punto anterior.
- **40225259043**, fuente `010c3f6`: dos UI previas de navegación/Agenda correctas (205.989s y144.373s), reutilizadas por mantener sus entradas y comportamiento. Sus fallos iniciales del test físico/menú/etiqueta de aerolínea se registran arriba y no se presentan como aprobados.

Conjunto sin duplicar: **40 casos distintos correctos** (24 de cliente,12 de widget y4 UI), más una prueba física explícitamente omitida. Las suites se reutilizan por alcance; no se afirma que todos los casos se ejecutaran de nuevo sobre el último SHA. El flujo de memoria utiliza la misma instancia de imagen ya decodificada y conserva las guardas de lectura nueva, comprobadas por la carga real y revocación de ochenta entradas.

Diagnóstico compacto final de UI: `output/scroll-widgets-53-passed`, resumen8/8 y capturas reales de los fixtures. Artefactos GitHub: diagnóstico12613227732, iPhone final12613637234 y diagnóstico de memoria12613347890. El repo conserva los enlaces de las ejecuciones aunque caduquen los artefactos temporales. Todas las pruebas usan fixtures y protocolos locales, sin fotos, pases, cuentas ni notificaciones reales como pruebas.
