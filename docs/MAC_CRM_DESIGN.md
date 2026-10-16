# CRM con identidad JAC y fechas completas — Mac 1.2.0 (3)

16 de octubre de 2026. Camilo pidió retirar el aspecto genérico y comprimido del listado de CRM, y que los calendarios respondieran en toda la celda del día.

## Presentación

CRM abre con una cabecera azul JAC y fichas de show con fecha, empresario, estado y venta/abonos/saldo separados. Las fichas se abren con un clic en su superficie completa. La distribución horizontal aprovecha una ventana grande; en una pequeña, las cifras pasan a una segunda fila sin desbordarse. Se mantienen la identidad, el logo original, Semana, Empresarios, búsqueda, filtros y las acciones visibles de crear show y registrar abono. La tabla anterior permanece como opción, con selección, ordenación de columnas, doble clic y menú contextual. Las fichas disponen también de ordenación y menú contextual.

La cabecera cuenta registros próximos, registros con saldo y registros sin precio. No suma ni calcula una cartera alternativa. Los importes y estados financieros se presentan desde la misma respuesta del servidor. Se mantienen formularios, revisiones, idempotencia, archivos privados, permisos, privacidad, Llavero y caché cifrada.

## Fechas

Se identificó que la cuadrícula de Agenda dibujaba una celda amplia, pero su etiqueta no definía esa superficie como área de interacción. `contentShape(Rectangle())` dentro de la etiqueta, después del tamaño/fondo, hace seleccionable la celda completa. Se conserva el indicador de selección y se proporciona su valor a accesibilidad. La corrección pertenece a la vista compartida y queda también en el proyecto iPhone.

Los campos Mac usan `MacDatePicker`: botón completo, calendario desplegable con días de 36 puntos de alto y aproximadamente 42 de ancho, navegación de meses, Hoy y entrada escrita día/mes/año. Los selectores se reutilizan en CRM, Agenda, quincenas, movimientos, gastos y pases. Se respetan límites, zona horaria heredada y hora del valor original; las fechas inválidas o fuera del rango escrito muestran un error y no se aplican. Los campos de hora mantienen el control nativo de SwiftUI. `JACDatePicker` es un alias directo de `SwiftUI.DatePicker<Text>` en iOS, por lo que allí se conserva su selector del sistema.

## Fuente y entorno

Cambian `MacWorkspaceViews.swift`, `MacPlatform.swift`, la versión/proyecto Mac y un argumento DEBUG para preparar la ventana grande de prueba. Los archivos compartidos sustituyen llamadas de fecha por el alias de plataforma; Agenda amplía su área de clic. Se añaden casos de prueba y registros ficticios opcionales para revisar títulos largos, promocionales y ausencia de precio. Esos registros solo existen con un argumento de fixture DEBUG y no se publican ni se añaden a producción.

Los proyectos y esquemas personales del iPhone se comparan con `work/local/mac-crm12-baseline/` y se conservan. No cambian identificadores, push suspendido, API, cálculos, dependencias, lockfile, migraciones, web, Site, DB/BUCKET, secretos o conexiones. El trabajo es local en el mismo Mac y carpeta; no hay despliegue, GitHub ni Cloud.

## Verificación

Comprobado en este Mac, con Xcode 27/macOS 27:

- **72 pruebas de lógica Mac aprobadas**, incluidas las 66 compartidas y seis específicas de Mac. Se reutilizan en `mac-crm12-verified.xcresult` las comprobaciones compartidas no afectadas; `mac-crm12-final.xcresult` repite las seis específicas con el parser final. Los casos de fechas comprueban fecha inválida, formato de uno/dos dígitos, límites, lunes inicial, 42 celdas y conservación de hora/minutos en Colombia.
- **Ocho recorridos UI distintos aprobados entre las ejecuciones**, conservando los seis anteriores y añadiendo apertura directa de fichas/tabla y fechas por los bordes. Privacidad/regreso al editor, nómina/Agenda/documentos, reapertura sin red con pase privado y restricción del lector pasaron en `mac-crm12-verified.xcresult`; el recorrido de tabla/búsqueda/formularios y abono de 50 millones con saldo de 90 millones pasa en `mac-crm12-final.xcresult`. La distribución final grande/clara y pequeña/oscura pasa en `mac-crm12-design-final.xcresult`.
- `mac-crm12-dates.xcresult`, TEST SUCCEEDED, comprueba clics en cuatro esquinas fuera del número, apertura desde el borde del campo, entrada escrita de otra fecha y selección del día desde el borde en Agenda. Todos los cambios se hacen en un formulario ficticio que se cierra sin guardar.
- **iPhone: 65 unitarias y tres UI aprobadas**, más una comprobación física preexistente omitida explícitamente por CoreSimulator. `mac-crm12-iphone-regression.xcresult`: borde de día en Agenda, crear/editar evento y crear show de día único con primer abono/resumen semanal. Se libera únicamente el recopilador adicional `simctl diagnose` atascado después de finalizar correctamente los tests, sin cerrar el ejecutor ni retirar resultados.
- **78 pruebas de servidor simuladas aprobadas**, Agenda, avisos y Workerd local: `mac-crm12-server-verified.log`. La primera ejecución de Workerd no pudo abrir su puerto localhost bajo el sandbox; se repitió con permiso para el servidor local y salidas externas interceptadas. No se cambiaron los tests ni el código del servidor.
- Release Mac universal arm64/x86_64 y Release iPhone sin firma compilados: `mac-crm12-release-delivery.log` y `mac-crm12-iphone-release.log`, BUILD SUCCEEDED. Ejecución Mac verificada en Apple Silicon; no se afirma instalación en el teléfono físico ni ejecución en Intel. El proyecto iPhone conserva 0.15.0 (26), su equipo/esquema y el identificador original; Mac usa 1.2.0 (3). Push sigue en NO.

Los informes de intentos intermedios se conservan. La consulta del saldo se mantiene sobre la tabla explícitamente seleccionada después de regresar al CRM; no se retira su aserción. Se corrigió un identificador padre de accesibilidad que se propagaba a los controles del calendario e impedía identificar entrada/cierre en las pruebas. El recorrido espera a que el calendario se cierre antes de abrirlo otra vez; todas las comprobaciones de fecha, saldo y privacidad se mantienen. Las últimas repeticiones citadas arriba pasan. Se reutilizan pruebas no afectadas en lugar de repetirlas sin cambios.

Capturas finales con datos ficticios: `outputs/mac-crm12-fichas.png`, `mac-crm12-tabla.png`, `mac-crm12-selector-fechas.png`, `mac-crm12-agenda-dia.png` y `mac-ux-crm-compacto-oscuro.png`. Huellas de fuente en `work/local/mac-crm12-source-sha256.txt`. La entrega actualiza `outputs/JAC Music.app` y deja ZIP de app y fuente como respaldos opcionales; no requiere descargar otro proyecto.

Las pruebas usan `.invalid`, datos ficticios y salidas externas interceptadas. No se crean eventos, abonos, alertas, correos ni comprobantes reales para probar; no se alteran datos de producción.

## Apertura de la entrega en este Mac

App actualizada en su misma ubicación, firma local verificada, binario universal y ZIP de app/fuente comprobados. Al abrir la entrega, el control de ventana agotó su tiempo. Una muestra del proceso propio confirmó espera en `KeychainSessionStore.load → SecItemCopyMatching → SecurityServer::ClientSession::decrypt` durante la inicialización; no hay un cierre nuevo de JAC en DiagnosticReports. SecurityAgent estaba activo. El control de Mac rechaza acceder a `com.apple.SecurityAgent` por seguridad; se solicitó a Camilo resolver personalmente el aviso del Llavero y avisar para comprobar la ventana. No se lee la contraseña, no se retiran las protecciones del Llavero y no se borra ni se sustituye la sesión/caché. La apertura con su sesión queda pendiente de esa intervención; no se declara comprobada mientras el proceso espere allí.
