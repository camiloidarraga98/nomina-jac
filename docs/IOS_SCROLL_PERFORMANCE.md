# Fluidez y trabajo de las secciones nativas

Entrega prevista: iOS **0.35.0 (53)**, 25 de octubre de 2026, Colombia. Camilo reportó desplazamiento entrecortado en varias vistas y pidió revisar la causa con profundidad. Este documento describe la implementación y las comprobaciones preparadas; los resultados de CI y la medición física permanecen **pendientes** hasta registrar su evidencia.

## Hallazgos de revisión de código

La inspección estática encontró trabajo costoso accesible desde propiedades consultadas al dibujar una vista: lecturas de sesión en Llavero, derivación del ámbito criptográfico, apertura de respuestas cifradas y decodificación JSON. En particular, la clave y el estado de cada tarjeta de pase recorrían de nuevo la consulta del aviso canónico. Con varias tarjetas, una evaluación de SwiftUI podía repetir ese recorrido para cada fila.

También se identificaron guardados individuales del índice de la copia offline y publicación de cambios ante respuestas de polling sin novedades. Las secciones de iPhone permanecen montadas para conservar rutas y scroll; comprobar sólo `scenePhase == .active` permitía que una sección tapada por otra, o por el menú lateral, siguiera consultando y precargando.

Estos son hallazgos de código, **no una captura de Instruments ni una medición de FPS**. No se atribuye todavía un porcentaje de mejora, una latencia concreta o un consumo de batería a un dispositivo real.

## Lecturas calientes y persistencia

`PayrollClient` conserva ámbitos ya derivados y respuestas tipadas en RAM, separados por sesión, generación y revisión. La caché tipada tiene un máximo de 256 entradas y un presupuesto de 32 MiB del contenido contabilizado; también limita las ausencias recordadas. Agenda conserva su registro autorizado en memoria. Las tarjetas usan `BoardingCardDetailsStore.presentationKey` y su estado listo para consultar los datos ya disponibles sin abrir el almacenamiento durante cada render.

La identidad de presentación no concede autorización para descargar o abrir archivos. Las operaciones reales conservan su revalidación estricta de sesión, permiso, aviso, archivo y revisión. Cerrar sesión, retirar acceso, borrar o sustituir una copia invalida las referencias calientes. Una denegación del feed completo también retira los avisos canónicos que se habían cargado. Una respuesta de workspace más antigua no reemplaza la revisión nueva de RAM o disco.

Las lecturas explícitas de `OfflineResponseCache` siguen autenticando el archivo cifrado actual; no se introduce una copia de respuestas en claro dentro de ese almacén. La primera carga y una operación de autorización pueden necesitar Llavero, disco y JSON: el presupuesto de cero se aplica al intervalo **caliente, ya autorizado**, no a todo el arranque de la app.

La persistencia de respuestas y Agenda se ordena fuera del hilo principal. `saveBatch` procesa el feed y sus avisos canónicos como un lote, con un solo guardado del índice. Compara contenido, cabeceras y revisión; cambiar únicamente la fecha de recepción no obliga a volver a cifrar/escribir una respuesta idéntica ni a incrementar `cacheRevision`. Épocas de invalidación y revisiones de memoria evitan que un trabajo encolado restaure datos después de un borrado o una revocación.

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

`testWarmPhotoAndBoardingListsKeepResponsiveScrolling` recorre realmente ambas listas hasta sus extremos para calentarlas, vuelve al inicio y realiza cuatro iteraciones con `XCTOSSignpostMetric.scrollDecelerationMetric`. Comprueba que los elementos se desplazan, que la carpeta sigue abierta al volver y que no aparecen lecturas/escrituras de disco, derivaciones o JSON en el hilo principal. Distingue un intervalo atravesado por la revalidación global de sesión de uno sin nuevas solicitudes, y exige al menos un intervalo completamente inactivo de cada lista para aplicar el presupuesto conjunto de cero operaciones costosas. Los presupuestos deterministas de 500 recorridos no dependen de esa coincidencia temporal.

`testHiddenSectionsSuspendPollingAndPrefetchWhileSidebarScrolls` usa texto accesible grande para hacer desplazable el menú, cuatro lotes de gestos verticales y miniaturas deliberadamente lentas. Verifica que el menú permanece abierto, que la precarga empieza al abrir la carpeta y se interrumpe antes de solicitar las ochenta miniaturas. Después de asentarse, espera 31 segundos —más que el ciclo automático de 30— y comprueba que no aumentan las solicitudes de los feeds ocultos ni de sus miniaturas. Al cerrar el panel, la carpeta y sus elementos siguen presentes.

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
| Revisión estática de rutas calientes y guardas de visibilidad | Preparada; hallazgos descritos arriba | No sustituye una ejecución ni un perfil físico. |
| Ocho casos nuevos de Core y regresiones focales | **PENDIENTE** | SHA, ejecución, conteos y fallos exactos. |
| Dos UI nuevas, dos UI existentes y señales de scroll | **PENDIENTE** | Ejecución, métricas, ventanas de contadores y capturas reales. |
| WidgetSnapshotTests, Release iPhone/widget y Mac | **PENDIENTE** | Resultado, identificadores, versiones y `widget-config.json`. |
| Instalación y perfil en iPhone/iPad físicos | **PENDIENTE** | Modelo, versión de iOS, Instruments (hilo principal, Animation Hitches/Time Profiler) y comparación con la misma carga. |

La validación física debe incluir scroll prolongado de Fotografía y Pases, cuatro desplazamientos verticales del menú con texto grande, regreso a una carpeta abierta y reproducción/subida en curso. Registrar tirones observados y trabajo del hilo principal antes de atribuir una mejora cuantitativa. No repetir suites ya válidas si no cambian sus entradas; limitar los seguimientos a la corrección y a sus dependencias reales.
