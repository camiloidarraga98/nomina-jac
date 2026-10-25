# Widgets de JAC para iPhone

**Activación local posterior al cierre de CI:** app y extensión 0.35.0 (53) firmadas y provisionadas en el Mac, instaladas en el iPhone 17 Pro y comprobadas con widgets reales. Archive/IPA de distribución verificados; Apple terminó de procesar la compilación interna, lista para las pruebas y asociada exclusivamente a **Equipo JAC**. Evidencia y límites físicos en [IPHONE_WIDGETS_LOCAL_ACTIVATION.md](IPHONE_WIDGETS_LOCAL_ACTIVATION.md). Los apartados de cierre de CI siguientes describen el estado previo a esta activación.

## Alcance autorizado

Camilo pidió un widget de pantalla de inicio que permita elegir Calendario y próximos eventos o las últimas fotografías. iOS 0.35.0 (53) añade la extensión `JACWidgets`, con tamaños pequeño, mediano y grande y selector **Mostrar → Calendario / Fotografía** al editar el widget. Se conserva el calendario como inicio de la app y no se cambian los permisos de módulos ni las conexiones existentes.

El calendario usa el mes actual de Colombia y los eventos del calendario conectado en JAC. El tamaño pequeño muestra el mes; los tamaños mediano y grande agregan próximos eventos. Fotografía presenta hasta cuatro miniaturas recientes según el tamaño, obtenidas del conjunto autorizado de la colección R2 actual, aunque el usuario no haya visitado antes la carpeta. Tocar el calendario abre Agenda; tocar una foto abre su carpeta tras la validación habitual de sesión y acceso.

## Activación en Apple y en el teléfono

La extensión es un segundo App ID: `co.jacmusic.nomina.widgets`. Comparte con la app `co.jacmusic.nomina` el App Group **`group.co.jacmusic.nomina.widgets`**, dentro del equipo pagado **AYHVYN8BJF**. El proyecto conserva firma automática, entitlements de push y entornos APNs anteriores. Esta solicitud sustituye, sólo para este widget, la antigua restricción histórica de no añadir App Groups del Personal Team.

Antes de distribuir con firma real:

1. En Apple Developer → Certificates, Identifiers & Profiles → Identifiers → App Groups, registrar `group.co.jacmusic.nomina.widgets` si Xcode no lo registra automáticamente.
2. Activar **App Groups** y seleccionar ese mismo grupo en los dos App IDs. Xcode → Signing & Capabilities debe mostrar el grupo y el equipo AYHVYN8BJF tanto en **JACNomina** como en **JACWidgets**; dejar **Automatically manage signing** activo.
3. Crear Archive de JACNomina y subirlo a App Store Connect. Instalar la compilación nueva desde TestFlight y abrir JAC con la cuenta habitual.
4. Mantener pulsada la pantalla de inicio → Editar → Añadir widget → JAC. Elegir tamaño. Mantener pulsado el widget → Editar widget → Mostrar → Calendario o Fotografía. Es posible añadir dos widgets con contenidos distintos.

El CI comprueba compilación e inclusión de la extensión, identificadores, versiones y configuración del grupo; no prueba el registro de App IDs, perfiles de Apple ni instalación física. No usar certificados o credenciales reales como fixtures.

## Datos y actualización

La extensión **no recibe token, cookies, claves ni URLs firmadas y no realiza peticiones de red**. La app principal consulta datos con la sesión existente, valida los recursos y escribe una instantánea mínima en el contenedor compartido. Sólo se copian títulos y fechas de eventos y miniaturas pequeñas; nunca PDF, pases, archivos originales ni directorios completos.

El actor de almacenamiento usa escritura atómica, protección de datos de iOS, exclusión de respaldo, separación por propietario, límites de tamaño y caducidad por sección de hasta 24 horas. Un cierre de sesión, cambio de cuenta o revocación invalida el trabajo pendiente y solicita la limpieza y recarga. Una respuesta tardía no puede volver a publicar la cuenta anterior. iOS controla cuándo actualiza sus capturas ya dibujadas; no prometer retirada instantánea de una captura del sistema.

La app actualiza al abrirse, al recibir una agenda nueva y en oportunidades de actualización de segundo plano. Si el iPhone está bloqueado, esa oportunidad no consulta las credenciales `WhenUnlocked` ni borra o renueva una instantánea todavía vigente; espera una oportunidad con los datos protegidos disponibles. La sesión mantiene su protección original en Llavero y no se copia al grupo compartido. Se agrupan las recargas, se evitan escrituras iguales y se muestra la antigüedad de la última actualización. **iOS decide la frecuencia real**, especialmente con ahorro de batería, actualización en segundo plano desactivada o app sin abrir. No es un monitor en tiempo real ni una descarga ilimitada. Una instantánea vencida muestra una invitación a abrir JAC; un fallo de red conserva únicamente la copia que aún no haya vencido.

`GET /api/media/recent` devuelve hasta ocho metadatos de imágenes listas, ordenados por fecha de carga y con carpeta de origen. Revalida sesión, permiso, colección, operación de carga y ancestros, excluye borrados y no hace listado de objetos ni descarga originales. La migración aditiva0038 añade el índice parcial de búsqueda reciente. Las miniaturas siguen obteniéndose y validándose a través de los endpoints privados existentes.

## Verificación

Fuentes: `ios/JACWidgets`, `ios/JACWidgetsShared`, `WidgetBridge.swift`, `WidgetLifecycle.swift` y `WidgetSharing.swift`. Pruebas focales `WidgetSnapshotTests`, `tests/media-recent.test.mjs`, `tests/media-recent-worker.test.mjs` y auditoría de migraciones. El alcance CI `[check-scroll-widgets]` también verifica Release iPhone y las fuentes compartidas de Mac. La evidencia de las regresiones de scroll y del Core se registra en `IOS_SCROLL_PERFORMANCE.md`.

Comprobaciones observadas el 25 de octubre de 2026:

| Alcance | Resultado |
| --- | --- |
| Release final iPhone y WidgetKit | [Ejecución40230506716](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40230506716), fuente `3f58e71e3ad813c774ffd79743808fe9d32834ef`, job121281112257: correcta con Xcode 26.3, build17C529. Incluye la protección del refresco con el iPhone bloqueado, compilación de la extensión y comprobaciones del bundle y del grupo compartido. |
| Release Mac | Job121281112375 de la misma ejecución y fuente: correcto con Xcode 26.3, build17C529, conservando las fuentes compartidas. |
| Snapshot y bridge del widget | [Ejecución40228053257](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40228053257), fuente `f1213c8`: doce casos correctos y una omisión explícita de protección física en CoreSimulator. Incluye el teléfono bloqueado y la guardia de cero lecturas de sesión durante actualizaciones omitidas. Las fuentes del widget no cambiaron después; la ejecución final40230506716 conserva esta evidencia y no vuelve a ejecutar esos trece casos. |
| API reciente de fotografías, local | Diez pruebas focales correctas entre Node y workerd, comprobación TypeScript y build correctos, con fixtures y servicios interceptados. |
| API publicada | Migración aditiva0038 aplicada y versión Cloudflare `e6cc4409-fe05-43b5-86b8-697c88098faf` activa al 100 %; se conservan los14 bindings existentes. |

El Release final contiene `JACNomina.app/PlugIns/JACWidgets.appex`, con bundle `co.jacmusic.nomina.widgets`. App y extensión coinciden en versión **0.35.0 (53)**, equipo **AYHVYN8BJF** y App Group **`group.co.jacmusic.nomina.widgets`**. Se verifican las tres familias declaradas y el punto de extensión `com.apple.widgetkit-extension`. Los ajustes efectivos de ambos targets y sus archivos de entitlements conservan el grupo. Este build sin firma no generó archivos `.xcent`: la comprobación no afirma que existan perfiles de distribución ni que Apple haya provisionado el grupo.

Los logs Release finales no contienen advertencias del compilador Swift, incluidas las de aislamiento del actor principal y actualización en segundo plano. El job de Mac conserva el aviso informativo de `appintentsmetadataprocessor` que omite la extracción de metadatos porque esa app no depende de `AppIntents.framework`; no es una advertencia Swift ni un fallo de compilación. El [artefacto iPhone12613335299](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40230506716/artifacts/12613335299) conserva los logs y los informes de configuración del bundle y del widget; el [artefacto Mac12612991157](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40230506716/artifacts/12612991157) conserva el build compartido. El seguimiento final de galería y scroll se registra por separado en `IOS_SCROLL_PERFORMANCE.md`; estos dos builds no se presentan como una nueva ejecución de los trece casos del widget.

`testProtectedSnapshotRoundTripsWithoutCredentialsAndDeduplicatesWrites` mantiene el round-trip, ausencia de credenciales, deduplicación y permisos Unix0600 del archivo/0700 del directorio, usando las mismas APIs de escritura protegida de producción. `testSharedSnapshotDataProtectionOnPhysicaliPhone` comprueba por separado el valor exacto de protección tanto del archivo como del directorio en un iPhone físico; se omite explícitamente con `XCTSkip` en CoreSimulator porque éste no expone ese atributo ni reproduce el cifrado del dispositivo. Un valor ausente en un iPhone físico continúa siendo un fallo. Este ajuste sólo cambia la prueba y no altera la protección del almacenamiento de la app.

La provisión del grupo y de ambos App IDs en la cuenta Apple, el Archive firmado y la comprobación del widget instalado en un iPhone siguen pendientes de realizarse desde el Mac de Camilo. Compilar y publicar la API no equivale a confirmar esa instalación física.

### Cierre de la entrega

La fuente final del producto es `19b0170`; Release iPhone/widget correcto en40231517171, ambas identidades 0.35.0(53), Team/AppGroup verificados sin firma real. La última modificación de producto afecta exclusivamente código iOS de miniaturas; el Mac correcto de3f58e71/40230506716 se reutiliza. La UI de80 fotos/40 pases pasó en40230506716 y la lateral en40228053257. El alcance final de memoria aprobó8 unitarias; los12casos del widget y una omisión física se conservan como evidencia previa de su fuente sin cambios.

No se instaló una app en el iPhone de Camilo ni se registró el AppGroup en Apple desde esta conexión. Completar la provisión de ambos AppIDs y Archive/Upload con su cuenta; después abrir JAC y añadir el widget. El refresco continúa sujeto a las oportunidades de iOS.
