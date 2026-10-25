# Widgets de JAC para iPhone

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

La app actualiza al abrirse, al recibir una agenda nueva y en oportunidades de actualización de segundo plano. Se agrupan las recargas, se evitan escrituras iguales y se muestra la antigüedad de la última actualización. **iOS decide la frecuencia real**, especialmente con ahorro de batería, actualización en segundo plano desactivada o app sin abrir. No es un monitor en tiempo real ni una descarga ilimitada. Una instantánea vencida muestra una invitación a abrir JAC; un fallo de red conserva únicamente la copia que aún no haya vencido.

`GET /api/media/recent` devuelve hasta ocho metadatos de imágenes listas, ordenados por fecha de carga y con carpeta de origen. Revalida sesión, permiso, colección, operación de carga y ancestros, excluye borrados y no hace listado de objetos ni descarga originales. La migración aditiva0038 añade el índice parcial de búsqueda reciente. Las miniaturas siguen obteniéndose y validándose a través de los endpoints privados existentes.

## Verificación

Fuentes: `ios/JACWidgets`, `ios/JACWidgetsShared`, `WidgetBridge.swift`, `WidgetLifecycle.swift` y `WidgetSharing.swift`. Pruebas focales `WidgetSnapshotTests`, `tests/media-recent.test.mjs`, `tests/media-recent-worker.test.mjs` y auditoría de migraciones. El alcance CI `[check-scroll-widgets]` también verifica Release iPhone y las fuentes compartidas de Mac. Los resultados definitivos de esta entrega se registran al terminar las comprobaciones; no confundir validación estática con ejecución en un iPhone.
