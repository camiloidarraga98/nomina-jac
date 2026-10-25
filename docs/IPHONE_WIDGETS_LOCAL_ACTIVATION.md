# Activación real de widgets · 25 de octubre de 2026

Trabajo en la copia local del Mac, con Xcode **27.1 (27A9275)** y un **iPhone 17 Pro con iOS 27.0.1**. Fuente de producto `19b017084dc56dbe043b346f2ed9b4df8f6cdac9`, cierre previo `d2ad997`. `git fetch origin main` confirmó que no había commits pendientes en ninguna dirección. Se respaldaron los dos workspaces locales sin seguimiento; no se descartaron ni incorporaron a Git.

## Firma y provisión observadas

- Ambos targets mantienen firma automática y equipo **AYHVYN8BJF**. Apple Developer mostró el App Group registrado y los App IDs de app y extensión. La app conserva Push Notifications.
- Debug firmado y ambos perfiles de desarrollo autorizan exactamente **`group.co.jacmusic.nomina.widgets`**. `codesign --verify --strict` correcto en `co.jacmusic.nomina` y `co.jacmusic.nomina.widgets`; ambos **0.35.0 (53)**. APNs de Debug: `development`.
- La app se actualizó y abrió en el iPhone mediante CoreDevice, sin desinstalación. El inventario de iOS confirmó versión/build, pertenencia al App Group y acceso al contenedor. El primer intento, por Wi‑Fi con el teléfono bloqueado, terminó por timeout; conectado por cable y desbloqueado quedó preparado y compiló correctamente.
- Archive Release firmado correcto; `JACWidgets.appex` embebido. El IPA exportado usa **Cloud Managed Apple Distribution**, con perfiles Store para ambos IDs, el mismo grupo, `get-task-allow=false` y APNs `production` únicamente en la app. Se verificaron los binarios del IPA y sus perfiles, además de la configuración fuente.
- Exportación con `testFlightInternalTestingOnly=true` y `manageAppVersionAndBuildNumber=false`. App Store Connect mostraba 51 como última compilación previa; 53 estaba libre. No se cambió versión, build, bundle, Team, capacidades, producto ni backend.

## Comprobaciones realmente realizadas

| Comprobación | Resultado y límite |
| --- | --- |
| `WidgetSnapshotTests` y las seis guardas de rendimiento | Simulador aislado iOS 27.0: **18 aprobadas, 1 omitida, 0 fallos**. La omisión corresponde exclusivamente a Data Protection físico. Incluye caducidad, bloqueo del teléfono, separación/cambio de propietario, logout, enlaces y presupuestos de RAM/I/O. |
| `testSharedSnapshotDataProtectionOnPhysicaliPhone` | **1 aprobada, 0 fallos** en el iPhone conectado. Datos sintéticos en un directorio temporal, usando el almacén de producción; protección `completeUntilFirstUserAuthentication` en archivo y directorio. No es una prueba de suspensión/reinicio del teléfono ni una extracción de datos de su cuenta. |
| Widgets reales simultáneos | Observados directamente mediante Device Hub: Calendario pequeño y Fotografía mediano con imágenes; antes se observó Calendario mediano con próximos eventos. Capturas locales reales. |
| Selector, tamaños, destinos y sin conexión | Camilo confirmó Calendario/Fotografía, pequeño/mediano/grande, apertura de Agenda y de la carpeta de una foto, funcionamiento sin conexión y retirada del contenido al cerrar sesión. Son comprobaciones manuales informadas por el propietario, no recorridos XCTest. |
| Cambio entre dos cuentas reales | No realizado. La sustitución de propietario y rechazo de publicaciones tardías quedaron cubiertos por las pruebas sintéticas. No se crearon ni modificaron permisos o cuentas reales para probar. |
| Fluidez física | Camilo confirmó scroll fluido en Fotografía, menú y Pases. Captura de Instruments descrita abajo; no establece FPS ni ausencia absoluta de pausas. |

La extensión conserva instantáneas mínimas protegidas, sin credenciales ni peticiones de red. No se hicieron envíos, subidas de archivos, borrados ni cambios del backend como pruebas. iOS conserva el control de recarga y de las capturas de WidgetKit.

Xcode 27.1 no emitió advertencias Swift de las fuentes de aplicación en Debug/Archive. Conservó avisos de no retirar símbolos de una extensión ya firmada. Al compilar los targets de pruebas aparecieron avisos existentes de conformidad `Sendable` del fixture `MediaDownloadChunkProtocol`, dos usos obsoletos de `hasMediaCharacteristic` y extracción App Intents omitida en el runner. No impidieron las comprobaciones y no se declaran eliminados en esta entrega.

## Instruments

Se adjuntó **Animation Hitches + Time Profiler** al PID de JAC en el iPhone físico, con límite de 45 s, de 16:18:53 a 16:19:39 (Colombia); duración informada 46,140 s y unos 35,069 s identificados como primer plano activo. El intento inicial por nombre no encontró el proceso; el intento por PID sí produjo una traza completa.

El export contiene 15 señales de animation hitch (máxima 200,034 ms) y 25 posibles demoras de interacción. Tres se clasifican como microhang, de **336,983–460,919 ms**, alrededor de las transiciones de segundo/primer plano. Después de 12,2 s de la captura, la mayor demora de interacción registrada es **80,466 ms**; no se repiten las tres pausas mayores en ese tramo. Las muestras muestran trabajo de actualización/layout de SwiftUI y formateo de Agenda; no permiten atribuir toda pausa a una sola función. El perfil corresponde a Debug bajo instrumentación, mezcla navegación/refresco y scroll y no ofrece una comparación controlada con una versión anterior. No se declara una mejora porcentual, FPS estables ni cero tirones.

Los seis presupuestos automáticos permanecen intactos. No se añadieron I/O, Llavero, derivación ni JSON a los getters de dibujo.

## Distribución

La carga del Archive **0.35.0 (53)** terminó con `Upload succeeded` / `EXPORT SUCCEEDED` a las **16:24 del 25 de octubre de 2026**, hora de Colombia. Apple terminó el procesamiento y marcó la compilación **«Internos» / «Lista para las pruebas»**. La ficha mostró **un único grupo: Equipo JAC, Interno, 2 testers**; el grupo conserva su distribución automática de compilaciones de Xcode. La verificación final en la lista de ese grupo mostró **0.35.0 (53) Internos — «En pruebas»**. Se guardaron las instrucciones para los testers. [Ficha de la compilación 53](https://appstoreconnect.apple.com/teams/e329e296-db52-4c3b-beb8-0a965b11ed2c/apps/6826005572/testflight/ios/58f8e040-8088-44c1-9c43-d2c1ae1fefdd).

Se resolvió «Falta información de exportación» con la opción de no incorporar algoritmos propietarios ni cifrado adicional al del sistema operativo de Apple. Se contrastaron las llamadas a CryptoKit/Security/URLSession y la ausencia de bibliotecas criptográficas externas con la [referencia oficial de Apple](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/). No se quitó ni debilitó el cifrado de la app. No se cambió Info.plist ni se creó otra compilación para responder a este formulario.

La subida requirió una confirmación adicional porque la revisión automática interpretó las instrucciones históricas de Archive/Upload del propietario como un bloqueo. Camilo confirmó expresamente «Sí, autorizo la subida y TestFlight interno»; después se ejecutó la misma carga. No se publicó en App Store ni se envió a revisión externa.

La instalación verificada físicamente durante esta sesión es la de desarrollo firmada. La compilación de distribución ya está preparada en TestFlight para que los integrantes de Equipo JAC pulsen Actualizar; no se declara esa segunda instalación efectuada desde el resultado de carga.

## Evidencia privada local

En `work/local/widgets-activation-53/` (ignorado por Git): Archive, IPA interno, opciones/resultado de exportación, `focal.xcresult`, `data-protection-physical.xcresult`, `physical-scroll-pid.trace`, exportaciones XML/JSON y capturas `calendar-physical.png`, `widgets-physical.png` y `testflight-internal.jpg`. Los logs de construcción/carga están en `/private/tmp/jac-widgets-*.log` y se conservan también junto a la evidencia local al cerrar la entrega. Estos archivos no se suben al repositorio público; contienen firma, datos de diagnóstico o imágenes/eventos privados.
