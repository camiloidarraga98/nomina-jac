> Contratos y RUT: CRM → Contratos, con Subir RUT primero, campos editables y entrada manual. PDF con la plantilla JAC y compartir desde el teléfono. Lectura del RUT local; generación requiere internet. Mismo proyecto y firma, usa Run para instalar. Ver [uso y comprobaciones](../docs/CONTRACTS.md).

> Subidas · iPhone/iPad0.27.0(40): cola guardada independiente del menú, transferencias del sistema en segundo plano y miniaturas separadas para reducir la espera. Forzar el cierre requiere reabrir para retomar. Mismo proyecto/firma, actualizar con Run. Ver [cola y límites de iOS](../docs/IPHONE_BACKGROUND_UPLOADS.md).

> Fotos · iPhone0.26.0(39): visor a pantalla completa con swipe continuo, precarga y reutilización de fotos vistas; círculo con progreso real mientras carga. Mismo proyecto/firma, actualizar con Run. Ver [visor y caché](../docs/IPHONE_PHOTO_VIEWER.md).

> Fotografía · iPhone0.25.0(38): carpetas desplegables en la misma pantalla, una sola hoja para nombre/archivos y deslizar sobre las fotos. Mismo proyecto y firma; actualizar con Run. Ver [uso y comprobaciones](../docs/IPHONE_PHOTOGRAPHY_SIMPLE.md).

> Agenda · iPhone/iPad0.24.1(37): corregido el cierre de listas al abrir eventos en iOS26.6.1. Misma navegación, permisos y copia offline. Versión instalada y recorrido ficticio confirmado por Camilo en su iPhone; ver [diagnóstico y verificación](../docs/IOS_AGENDA_EVENT_DETAIL_LAYOUT.md).

> Fotografía: dos subidas simultáneas, círculo general y velocidad reciente; corregida la preparación de carpetas R2 para descarga privada y Fotos. Misma app/proyecto, sin activar push. Ver [comprobaciones y límites](../docs/PHOTOGRAPHY_UPLOAD_PERFORMANCE.md).

> Carpetas de Fotografía: los administradores pueden eliminarlas desde su menú, con confirmación y limpieza retomable de contenido/caché. Ver [guía de eliminación](../docs/PHOTOGRAPHY_FOLDER_DELETE.md). Mismo proyecto; usa Run para actualizar.

> Fotografía (16 octubre): visor anterior/siguiente y calidad de imágenes 2/4/6 MB u original desde Gestión/Configuración y el menú de Fotografía. Preferencia por dispositivo; videos intactos. Ver [guía de visor y calidad](../docs/PHOTOGRAPHY_VIEWER_QUALITY.md). Actualiza con Run sobre este mismo proyecto; no hace falta descargar otro.

## App universal iPhone/iPad — 0.20.0 (32)

## Fotografía R2 · iPhone/iPad 0.21.0 (33)

Mismo proyecto y esquema JACNomina. Fotografía está preparada para el archivo nuevo y privado de R2, sin importar contenido de Drive. Subidas directas reanudables, miniaturas JPEG nativas de fotos/videos y renovación de la copia cifrada por colección. Disponible sin conexión y Guardar en Fotos se conservan. Usa Run sobre tu iPhone o iPad conectado; tu equipo, firma, bundle co.jacmusic.nomina y push suspendido permanecen. No necesitas descargar otro proyecto. Ver docs/PHOTOGRAPHY_R2_MIGRATION.md para publicación, pruebas y límites.

El **mismo proyecto** ya incluye iPad, con barra lateral nativa, CRM para administradores y Agenda adaptada al ancho disponible. Fotografía, itinerarios/pases, alertas, nómina, Gestión y Mi cuenta conservan sus accesos y funciones. El iPhone mantiene sus pestañas. Ver [App para iPad](../docs/IPAD_APP.md) para pruebas y límites de verificación.

En pases privados, **Mostrar código** extrae localmente el QR/código original del PDF o imagen y lo muestra a pantalla completa. En iPhone/iPad sube temporalmente el brillo y lo restaura al cerrar o cambiar de app. Funciona con un PDF ya descargado sin internet; el pase completo sigue disponible. Ver [Código de embarque](../docs/BOARDING_CODE.md).

Para instalar, abre **este mismo `ios/JACNomina.xcodeproj`**, elige **JACNomina → tu iPad → Run**. Se conservan la firma personal y `co.jacmusic.nomina`; push sigue suspendido. No necesitas descargar ni sustituir otro proyecto.

## Fotografía: actualización inmediata — iPhone 0.18.1 (30)

La galería muestra la última copia guardada mientras consulta Drive al entrar; ya no espera el ciclo de 30 segundos para conectarse. La app precarga el listado principal tras validar la sesión. Sin internet conserva lo descargado y la sesión, y una revocación real retira el contenido. Actualiza con **Run desde el mismo proyecto**, conservando firma y push suspendido. Ver [Fotografía: UX](../docs/PHOTOGRAPHY_UX.md).

## Fotografía principal — iPhone 0.18.0 (29)

Fotografía tiene acceso en la barra principal para las cuentas autorizadas. **Mi cuenta** está dentro de **Gestión**, también en perfiles limitados a Fotografía u otra sección. Se conservan la sesión, el cierre manual y los permisos.

La galería muestra miniaturas ligeras y carpetas por fecha de creación, recientes primero. **Subir** permite elegir carpeta o crear la del evento con nombre/fecha en la ubicación actual y luego enviar el lote. No crea eventos de Calendar/CRM. Para **Disponible sin conexión** o **Guardar carpeta en Fotos**, mantén presionada la carpeta o abre sus puntos; las acciones se aplican a la carpeta elegida. La confirmación de transferencia, progreso y cancelación permanecen.

Se continúa con **Run en este mismo `ios/JACNomina.xcodeproj`**, esquema **JACNomina → tu iPhone**, conservando firma, bundle ID y push suspendido. Ver [Fotografía: UX](../docs/PHOTOGRAPHY_UX.md) para comprobaciones y entrega.

## App nativa de Mac en esta misma carpeta

El proyecto compañero está en **`macos/JACMac.xcodeproj`**, esquema **JACMac → My Mac → Run**. Comparte las funciones nativas y las mismas cuentas/servicios con el iPhone. Consulta [`macos/README.md`](../macos/README.md) para abrir la app, documentos, copia sin conexión y comprobaciones. El proyecto y la firma personal del iPhone se conservan; sigue usando **JACNomina → tu iPhone → Run** para el teléfono.

## Accesos por sección — iPhone 0.17.0 (28)

**Gestión → Usuarios → Editar** permite elegir cada módulo por separado. Consultar Fotografía y crear carpetas/subir archivos son permisos distintos; los administradores Camilo y `jac` pueden hacer ambas cosas. Los pases siguen siendo privados de su destinatario y CRM sigue siendo administrativo. La cuenta real de Anderson conserva Fotografía y subida hasta que Camilo guarde sus accesos elegidos.

La navegación y la copia cifrada aplican las secciones concedidas; retirar un módulo elimina su información y documentos descargados. Falta de conexión conserva la última información permitida y la sesión. Se mantienen la cubierta de privacidad, el Llavero, los cálculos y la suspensión de push. Ver [Accesos por sección](../docs/SECTION_ACCESS.md) para servidor, compatibilidad y comprobaciones.

Para instalar, pulsa **Run en este mismo `ios/JACNomina.xcodeproj`**, esquema **JACNomina → tu iPhone**. Tu equipo/firma y `co.jacmusic.nomina` se conservan; no descargues ni reemplaces otro proyecto.

Verificado con simulador nuevo y fixtures `.invalid`: 75 unitarias más dos nuevas de revocación, cuatro recorridos UI de permisos/subida/privacidad y Release de dispositivo sin firma correctos; una comprobación requiere iPhone físico. Informes y límites en la guía de accesos. Run todavía corresponde al teléfono real.

## Fotografía — iPhone 0.16.0 (27)

En **Gestión → Fotografía**, Camilo y `jac` consultan las carpetas compartidas y abren fotos/videos dentro de JAC. Anderson ve únicamente **Fotografía** y **Mi cuenta**: puede crear carpetas por show o día y subir varios archivos desde Fotos o Archivos. La galería se actualiza al volver y cada 30 segundos mientras está visible; la conexión inicial de Drive se administra desde la web con Camilo.

**Disponible sin conexión** descarga la carpeta completa y sus subcarpetas tras mostrar archivos, tamaño y espacio necesario. La copia permanece cifrada y separada por sesión/origen; cerrar sesión o una revocación comprobada la elimina. **Guardar carpeta en Fotos** agrega los archivos a la fototeca del iPhone y pide solamente permiso para agregar; no lee la biblioteca. Ambas operaciones muestran progreso, permiten detenerlas y señalan los archivos que no pudieron completarse. Las copias que guardes expresamente en Fotos quedan bajo tu control.

Actualiza con **Run desde este mismo `ios/JACNomina.xcodeproj`**, esquema **JACNomina**, eligiendo tu iPhone. Conserva tu equipo/firma y `co.jacmusic.nomina`; push continúa suspendido. El respaldo ZIP es opcional y omite la configuración personal de firma; no sustituye tu proyecto de trabajo.

Verificado localmente: **72 pruebas unitarias aprobadas, una comprobación física omitida en CoreSimulator y cero fallos**; cinco recorridos UI distintos aprobados, incluidos permisos y privacidad, y tres recorridos de Fotografía repetidos tras el acabado visual. Informes `work/local/ios-media-final.xcresult` y `ios-media-design-final.xcresult`; Release de simulador sin firma compilado en `ios-media-release-final.log`. Simulador nuevo con datos `.invalid`, foto/video ficticios y guardado en Fotos simulado: no se usó la fototeca real ni se instaló en un iPhone físico. Ver [guía de Fotografía](../docs/PHOTOGRAPHY.md).

## Nueva distribución y personalidad — iPhone 0.15.0 (26)

Rediseño nativo con tarjetas de acceso en Gestión y Actividad, acciones principales visibles en Quincena/CRM/Alertas, pases tipo boleto y acceso/Mi cuenta renovados. Azul profundo y cian JAC, con acentos discretos por sección y soporte claro/oscuro. Agenda sigue mostrando primero el calendario, con Hoy/actualización/Nuevo evento bajo el mes. Las cinco pestañas, logo, funciones, permisos, datos, privacidad y copia offline se mantienen. Ver `docs/IPHONE_REDESIGN.md` para cambios y verificación.

Actualiza con **Run desde este mismo `ios/JACNomina.xcodeproj`**, esquema **JACNomina**, eligiendo tu iPhone. Conserva tu equipo, firma y `co.jacmusic.nomina`; push sigue suspendido. No descargues ni sustituyas otro proyecto. La web conserva v63; este cambio es de la app nativa. Verificado en simuladores grande/claro y pequeño/oscuro, con 65 unitarias y 20 recorridos UI distintos aprobados; una comprobación de cifrado requiere iPhone físico. Build Release sin firma correcto. El ZIP es solo respaldo opcional; estas pruebas no instalan la actualización en tu teléfono.

## Identidad azul JAC — iPhone 0.14.1 (25)

La identidad azul aprobada está aplicada a toda la app mediante el tema compartido: Quincena, Agenda, CRM, Itinerarios/Pases, Alertas, Gastos y Gestión. Conserva el logo, controles nativos, funciones, privacidad, copia sin conexión y colores de éxito/advertencia/eliminación. Consulta `docs/JAC_BLUE_PREVIEW.md`.

Actualiza con **Run desde este mismo `ios/JACNomina.xcodeproj`**, esquema **JACNomina**, eligiendo tu iPhone. Conserva tu equipo/firma, `co.jacmusic.nomina` y push suspendido. No descargues ni sustituyas el proyecto. Se comprobaron 65 pruebas unitarias y cinco de interfaz en simulador nuevo; una comprobación física requiere iPhone. Release sin firma compila correctamente; estas verificaciones no instalan la actualización en tu teléfono.

## CRM nativo — iPhone 0.14.0 (24)

En **Gestión → CRM · Shows y abonos**, Camilo y `jac` tienen el CRM nativo: shows de hoy en adelante, precios y abonos individuales con PDF/fotos, creación de un show de día único con primer abono opcional, ficha de empresario con documentos privados, presupuesto/rentabilidad, preparación y resumen semanal. Los demás usuarios conservan sus permisos anteriores.

**Empresario** es un único campo que sugiere contactos guardados por nombre o empresa, con o sin tildes. Toca una sugerencia para vincularla. Escribir otro nombre retira el vínculo anterior; el texto libre no crea una ficha automáticamente. Los valores COP usan separadores y permiten borrar todo el contenido, sin un cero inicial obligatorio.

**Rentabilidad** consulta los costos y la comisión del servidor. Distingue presupuesto estimado de honorarios/kilómetros/gastos registrados, conserva cierres históricos y las reglas de promocionales. La comisión mostrada es revisable y corresponde a toda la quincena, sin pago automático. Si un show antiguo no está vinculado, puedes elegir su registro de nómina sin modificarlo.

**Preparación** permite responsable, fecha límite, observación y estado de contrato/hotel/transporte/itinerario, además de tareas propias. El anticipo se calcula desde los abonos. **Semana** muestra los próximos shows, saldos, abonos, gastos según fecha de registro, costos de shows de la semana y tareas pendientes; usa las fechas de Colombia del servidor.

Los precios y abonos se guardan en el CRM existente, y los comprobantes reciben el mismo consecutivo y enlace privado que en la web. Crear o eliminar un show actualiza el calendario compartido mediante las API existentes; se confirma antes de eliminar y se conserva el historial de pagos. Google Sheets sigue usando la conexión existente: puedes abrir la hoja y reintentar la sincronización; su conexión inicial se administra desde la web.

La copia cifrada por sesión incluye la información y documentos del CRM que termine de descargar. Desde **Mi cuenta → Copia sin conexión** puedes comprobar si quedan elementos pendientes. Sin internet puedes consultar lo descargado; guardar, sincronizar o eliminar requiere conexión. Los errores de red no cierran la sesión. Una denegación real no utiliza la copia como alternativa y retira el acceso local del CRM. Los reintentos de abonos, creación y documentos conservan el identificador mientras el formulario sigue abierto.

Actualiza con **Run en este mismo proyecto**, `ios/JACNomina.xcodeproj`, esquema **JACNomina**, conservando tu equipo y `co.jacmusic.nomina`. No borres la app ni descargues un proyecto nuevo. Push continúa suspendido. La compilación de simulador y Release sin firma no equivalen a instalar la actualización en tu iPhone; Run requiere el teléfono conectado y su firma vigente.

## Costos de show y comisión — iPhone 0.13.0 (23)

En **Quincena → Actividad → Shows** puedes marcar **Show promocional** al final del formulario. **Actividad → Gastos por show** permite registrar tiquetes, hoteles, alimentación y otros costos, siempre con un show seleccionado. **Pagos** y la vista previa muestran el cálculo de comisión del servidor y el desglose por show: 5% de las ventas menos honorarios brutos, kilómetros y gastos de shows no promocionales, con mínimo cero. Se excluyen salarios/fijos y movimientos ajenos; no se agrega como pago a Camilo ni cambia lo que recibe el equipo.

Actualiza este mismo proyecto con **Run**, conservando tu firma y `co.jacmusic.nomina`; push sigue suspendido. Consulta [reglas y controles](../docs/SHOW_COSTS_COMMISSION.md). Un cierre antiguo sin comisión guardada conserva su instantánea. La copia offline muestra lo que haya descargado el iPhone; registrar, editar o borrar sigue necesitando conexión.

## Escanear facturas — iPhone 0.12.2 (22)

En **Gestión → Gastos de viaje → Registrar gasto → Escanear factura** puedes tomar una foto o elegir una de Fotos. El OCR nativo de Apple se ejecuta en el iPhone, sin subir la imagen a un servicio de reconocimiento. Sugiere tipo de gasto, concepto, total en COP y fecha; muestra una vista previa y permite corregir todo antes de **Enviar a revisión**. El tipo elegido se conserva en la nota como `Tipo de gasto: …`, visible también desde la web. La foto queda como comprobante privado y se mantiene el proceso de revisión/incorporación existente.

La fecha sugerida es la primera fecha válida de arriba hacia abajo; si hay varias en una línea se toma la primera de izquierda a derecha. Se incluye su hora cuando aparece junto a ella o en la línea de Hora inmediatamente siguiente. Fecha y hora se pueden corregir; la hora queda en la nota como `Hora de factura: …`. Se admiten fechas numéricas, ISO y meses completos o abreviados en español. La categoría se sugiere según productos y servicios, además del comercio: comida, transporte, hospedaje o combustible; una clasificación sin coincidencia clara queda por elegir.

El concepto intenta usar el **nombre del comercio del encabezado**, leyendo también las letras del logo. Prioriza el nombre comercial explícito o el texto destacado sobre datos fiscales, cajero o productos. Hace una segunda lectura local del encabezado y ayuda al reconocimiento de «Frisby», incluidas letras separadas. Si solo hay un símbolo sin texto legible, completa el nombre manualmente. El resultado se puede corregir antes de enviar; no se garantiza la lectura de todos los logos.

Los totales ambiguos, fechas ilegibles o inválidas, otra moneda o centavos distintos de cero se dejan para revisión manual. No hay conversión de moneda, clasificación garantizada ni aprobación automática. Si una foto no contiene texto legible puedes repetirla o usar el formulario/adjuntos de siempre. El escaneo admite una foto a la vez; el gasto conserva hasta cinco comprobantes y 10 MB en conjunto.

El formulario guarda automáticamente un único borrador cifrado por sesión en este iPhone, incluyendo sus fotos. También ofrece **Guardar borrador y cerrar**, **Continuar borrador** y eliminación confirmada del borrador. Funciona sin red; enviar y aprobar siguen necesitando conexión. Cerrar sesión o una revocación comprobada elimina el borrador junto con la copia local. Un envío incierto conserva UUID y datos bloqueados para reintentar sin duplicados; no se encola ningún envío automático. Los borradores no se sincronizan con otros dispositivos.

Actualiza **este mismo proyecto con Run**, conservando tu firma personal y `co.jacmusic.nomina`. El push permanece suspendido. La cámara física y la calidad con tus facturas deben probarse en el iPhone; las pruebas locales usan imágenes de facturas ficticias y el motor Vision real, sin servicios externos.

## Contenido sin conexión — iPhone 0.11.0 (19)

Actualiza **este mismo proyecto con Run**, conservando tu firma personal y `co.jacmusic.nomina`. Push sigue suspendido. Abre la app una vez con internet y espera en **Mi cuenta → Copia sin conexión** a que termine la descarga. Después puedes cerrarla y reabrirla sin señal: muestra la última copia de Quincena, Agenda, Itinerarios, pases privados, Alertas y las consultas de Gestión que se hayan descargado. Los PDF e imágenes de avisos y comprobantes se descargan automáticamente en primer plano, sin marcar recibido ni enviar notificaciones. Un adjunto que aún no terminó de descargarse necesita internet; el estado indica si quedan archivos pendientes.

La copia aparece antes de esperar la red. Al recuperar conexión, regresar a primer plano y cada 30 segundos con la app activa se revalida la sesión y se actualiza el contenido. Sin red se permite consultar, abrir y compartir los archivos guardados; crear, editar, borrar, confirmar recepción, aprobar gastos y enviar correos requieren conexión. No se encolan escrituras. Si todavía no hay copia, la app conserva la sesión y pide conectarse para descargar; no vuelve al formulario de acceso por una falla de red.

La información y su índice se guardan con AES-GCM, clave derivada de la sesión del Llavero, separación por origen/cuenta, protección completa de archivos y exclusión de copias de seguridad. No se guardan contraseñas ni tokens en esos archivos. Límite de 512 MB de contenido, 16 MB por respuesta; los adjuntos mantienen su máximo de 10 MB. Se informa cuando no se puede completar la copia. Cerrar sesión elimina la copia y los temporales, incluso sin conexión. Una revocación real al reconectar (401/redirección o denegación del workspace) elimina el acceso; 403/404/410 de documentos no sirven una copia como alternativa. La falta de internet por sí sola nunca revoca la sesión. La autorización remota solo puede comprobarse cuando vuelve la conexión.

Las pruebas nuevas usan exclusivamente URLProtocol y archivos ficticios `.invalid`, incluidos relanzamiento sin red y red lenta. La protección física de archivos conserva su comprobación en iPhone: CoreSimulator no reproduce el cifrado del dispositivo.

## Agenda más directa — iPhone 0.10.2 (18)

Agenda comienza con el selector Mes/Próximos y el calendario. Se retiraron el bloque «Actualizando agenda… / Última descarga», las fechas de sincronización y el encabezado con el nombre del calendario. La copia sin conexión, la actualización automática/al regresar a la app, el gesto de actualizar, el botón de recarga y todos los permisos de consulta/edición se conservan. Los avisos de falta de conexión o de guardado aparecen debajo del contenido. Conexión continúa accesible desde su icono autorizado y cuando aún no se ha preparado.

Actualiza este mismo proyecto con Run, conservando la firma personal, `co.jacmusic.nomina` y push suspendido. No se cambian API ni la web.

## Sesión opcional sin caducidad — iPhone 0.10.1 (17)

En el acceso puedes marcar **Mantener la sesión iniciada**. Solo esa nueva sesión permanece sin vencimiento por tiempo, incluso después de cerrar/reabrir la app o reiniciar el iPhone; se conserva en el Llavero, sin guardar la contraseña. Sin marcarla, sigue el vencimiento habitual de 12 horas. Las sesiones ya abiertas conservan su modalidad: cierra sesión y entra una vez marcando la opción para activarla.

**Mi cuenta → Cerrar sesión** elimina el acceso local y revoca la sesión en el servidor cuando hay conexión. Desactivar la cuenta, cambiar permisos o restablecer su contraseña continúa revocando el acceso por seguridad. Si cambias tu propia contraseña desde la app, el nuevo acceso conserva la modalidad elegida y las otras sesiones se revocan. La cubierta de privacidad y la protección de Agenda sin conexión siguen activas.

Actualiza **este mismo proyecto** con Run; conserva tu equipo de firma y `co.jacmusic.nomina`. Push continúa suspendido. El servidor requiere la migración aditiva `0016_persistent_mobile_sessions.sql`; no modifica cuentas ni convierte sesiones antiguas.

## Viajes — iPhone 0.10.0 (16)

Actualiza este mismo proyecto con **Run**. Alertas e Itinerarios incluyen **Confirmar recibido**, independiente de abrir el aviso; administradores ven las confirmaciones por versión. Un administrador puede actualizar un itinerario con la versión completa y un resumen de cambios: aparece **Actualizado** y se solicita confirmar otra vez.

**Gestión → Gastos de viaje** permite enviar concepto, valor COP, fecha y comprobantes desde Archivos, Fotos o Cámara. Solo el autor y administradores consultan sus archivos. Los administradores aprueban e incorporan a una persona/quincena abierta o rechazan con motivo. La incorporación y revisión son atómicas, sin reintegros duplicados ni envíos de correo. Alex conserva su bloqueo de nómina y puede registrar sus propios gastos. Ver `docs/TRAVEL_WORKFLOWS.md`.

El push continúa suspendido mientras Apple revisa la membresía. Mantén tu firma personal local y `co.jacmusic.nomina`. No necesitas descargar otro proyecto ni borrar la app instalada.

## Push suspendido temporalmente — iPhone 0.9.5 (15)

Mientras Apple revisa la membresía, este mismo proyecto compila sin la capacidad Push Notifications ni `aps-environment`. `JAC_PUSH_ENABLED=NO` en Debug y Release impide pedir autorización, registrar APNs o enviar comandos de registro; Gestión → Notificaciones explica la suspensión. Se conserva la preferencia del usuario para una futura reactivación. Agenda, itinerarios, pases privados, alertas dentro de la app, adjuntos y privacidad siguen funcionando. Las notificaciones de la web no cambian.

Abre **este mismo** `ios/JACNomina.xcodeproj`, esquema **JACNomina**. En **Signing & Capabilities** elige tu **Personal Team** y firma automática, selecciona tu iPhone y pulsa **Run**. Mantén `co.jacmusic.nomina`; no hace falta descargar ni sustituir el proyecto. Si Xcode conserva el diagnóstico anterior, detén Run, usa **Product → Clean Build Folder** y vuelve a compilar. La firma puede requerir que completes acceso/confianza/Modo de desarrollador en Xcode o el teléfono.

Cuando Apple apruebe la membresía, reactivar de forma coordinada: seleccionar el equipo de pago, agregar **Push Notifications**, cambiar `CODE_SIGN_ENTITLEMENTS` a `JACNomina/JACNominaPush.entitlements` y `JAC_PUSH_ENABLED` a `YES` en Debug y Release, conservar `APNS_ENVIRONMENT=development`/`production` respectivamente y regenerar perfiles mediante firma automática. El archivo push solo contiene la declaración de entitlement; no es una clave. Verificar firma/APNs antes de declarar push operativo. No cambiar secretos del sitio ni copiar certificados o claves al proyecto.

Las pruebas anteriores de permisos, rechazo, desactivación y tokens tardíos se conservan mediante inyección explícita; los fixtures DEBUG de interfaz no registran APNs. La nueva prueba cubre el build suspendido sin permisos, registros ni cambios de preferencias.

Actualización 0.9.4 (14): Alex dispone de Agenda de consulta y Alertas, sin nómina. Crear alerta incluye cuentas activas pendientes de activación, con su estado visible. Trabajar sobre este mismo proyecto y actualizar con Run.

## Borrado con gestos — iPhone 0.9.3 (13)

En las listas ya no aparece un botón grande de eliminación. Camilo puede deslizar un pase o itinerario hacia la izquierda y pulsar Eliminar, o mantenerlo pulsado y elegir Eliminar. Siempre se pide confirmación; Cancelar conserva el documento. Para un pase solo se pregunta «¿Estás seguro de que quieres eliminar este pase de abordar?». Se conservan los permisos y la apertura directa del PDF. Instala con Run desde este mismo proyecto.

## Borrado manual — iPhone 0.9.2 (12)

Camilo dispone de Eliminar pase de abordar en cada publicación de sus pases, también en el historial, y Eliminar itinerario en la lista compartida. Antes de borrar se confirma el alcance. Los pases privados de otras personas no son accesibles para Camilo. Se eliminan todos los adjuntos de la publicación en JAC y las entregas pendientes; el original de Slack se conserva. Cancelar mantiene el contenido. La apertura directa del PDF sigue disponible.

Verificado en simulador nuevo con fixtures .invalid y Release sin firma. Actualiza con Run desde este mismo proyecto, sin descargar ni sustituir otra carpeta. La publicación web no instala el binario en tu iPhone.

# Nómina JAC para iPhone

El nombre visible en el iPhone es **JAC**. El proyecto y el esquema de Xcode siguen siendo `JACNomina`.

Aplicación nativa en SwiftUI para iOS 17 o posterior. Usa las mismas cuentas y la misma base D1 que https://jhonalexcastano.com a través de HTTPS. No contiene WebViews ni otra base de nómina.

## Notificaciones al entrar — iPhone 0.8.0, build 9

Itinerarios contiene únicamente sus publicaciones, consulta y borrado autorizado. Alertas conserva creación y destinatarios. Los controles de avisos están en **Gestión → Notificaciones** para todas las cuentas activas.

Tras iniciar sesión o restaurar una sesión validada, JAC solicita automáticamente el permiso nativo de iOS si todavía no se decidió. Un rechazo no se vuelve a preguntar al regresar a primer plano; se ofrece abrir Ajustes del iPhone. Desactivar desde Gestión se conserva en ese dispositivo y no se revierte al iniciar sesión de nuevo. Un token tardío no puede reactivar la opción, y desactivar espera cualquier registro en curso antes de revocarlo. La preferencia de la app no sustituye el permiso del sistema.

Verificado en simulador nuevo: diálogo real de iOS al entrar con sesión ficticia, rechazo y regreso sin repetirlo, controles fuera de Itinerarios/Alertas, permisos de lector, publicación manual/adjuntos/borrado y privacidad. Solo fixtures `.invalid`; el diálogo de prueba no registra APNs. El push remoto físico sigue necesitando la membresía aprobada, firma y APNs. Continúa con **Run en este mismo proyecto**; el ZIP es un respaldo opcional.

## Distribución y Agenda sin conexión — iPhone 0.7.0, build 8

La barra inferior tiene **Quincena, Agenda, Itinerarios, Mi cuenta y Gestión**, en ese orden. **Gestión** reúne Alertas, Archivo de quincenas, Equipo, Conceptos y reglas, Correos y Gmail, y Usuarios y permisos (solo propietario). Las funciones anteriores siguen disponibles con sus mismos permisos. Archivo y Equipo utilizan la navegación de Gestión, sin anidar otra barra de navegación.

**Agenda** muestra inmediatamente la última copia descargada del mes mientras consulta internet. También puede abrir esa copia después de cerrar y volver a abrir la app sin señal. Se conservan hasta seis meses consultados, dentro de un límite de 4 MB, con sus eventos, detalles y próximos 90 días descargados. Un mes que nunca se descargó necesita conexión. Se indica la fecha y hora de la descarga y si se está actualizando o sin conexión. La actualización se intenta al entrar, volver a primer plano, recuperar conexión y cada 30 segundos mientras Agenda está abierta y activa; también puedes deslizar o pulsar Actualizar. Es actualización automática por consulta, no una conexión en directo a Google.

La copia es de consulta: crear/editar y cambiar la conexión necesitan acceso validado al servidor. En un arranque sin conexión, Agenda y la identidad de Mi cuenta están disponibles; el resto de secciones espera la validación de internet. No se guardan quincenas ni se encolan ediciones sin conexión. Antes de poder usar este modo hay que haber iniciado sesión y descargado la agenda al menos una vez.

Los archivos locales se cifran con AES-GCM y una clave derivada de la sesión que permanece en el Llavero; no se escribe la sesión ni la clave al archivo. Están vinculados al sitio/sesión, solicitan protección completa de iOS y se excluyen de copias de respaldo. Salir, una sesión vencida, denegación de Agenda o desconectar/cambiar el calendario retira la copia anterior. Sin internet no se puede conocer una revocación remota hasta la próxima comprobación; mientras tanto solo se consulta lo previamente descargado en ese iPhone. Se conserva la cubierta de privacidad.

Continúa abriendo **el mismo proyecto de esta carpeta** y usa Run. No necesitas descargar otro proyecto; la aprobación de Apple y la firma siguen siendo necesarias para instalar la configuración con push en un iPhone físico. La verificación local utiliza únicamente fixtures `.invalid`.

## Itinerarios y Alertas — iPhone 0.6.0, build 7

En **Itinerarios** y **Gestión → Alertas** consultas el mismo contenido de la web. Camilo puede eliminar cualquiera desde su detalle, con confirmación; se revocan acceso y entregas pendientes y se borran sus adjuntos privados de JAC. El archivo original de Slack se conserva. Los avisos que ya llegaron al dispositivo no se pueden retirar.

Desde **Alertas → +**, elige **Alerta** o **Itinerario**. Una alerta exige mensaje y destinatarios seleccionados; un itinerario se publica directamente en Itinerarios para todo el equipo activo, sin Slack. Admite hasta cinco PDF, JPG o PNG que sumen 10 MB. En iPhone se eligen desde Archivos o Fotos (las fotos se convierten a JPG); se pueden quitar antes de guardar. Puedes abrir y compartir cada adjunto con la vista previa nativa. Los borradores y archivos elegidos permanecen en memoria; las descargas usan temporales protegidos y se limpian al cerrar o salir de la cuenta.

Los avisos de itinerarios dicen **Ya llegó tu itinerario para el día de hoy**. Las alertas muestran su título y descripción (los textos muy largos se abrevian solo en push). Se conserva `co.jacmusic.nomina`, la sesión en Llavero, la cubierta de privacidad y el procesamiento en el servidor. El push del iPhone requiere membresía/equipo de Apple habilitado, firma con Push Notifications y configuración APNs en Configuración general → Servicios conectados de la web; no basta con instalar el binario. No se han generado ni copiado certificados o claves.

Para actualizar el iPhone abre `ios/JACNomina.xcodeproj`, esquema JACNomina, selecciona tu equipo y tu iPhone y pulsa **Run** sobre la app existente, sin borrarla. La web y las API se actualizan con Sites; instalar el binario requiere Xcode o distribución ad hoc.

La verificación usa Xcode 27/iOS 27 en un simulador nuevo y fixtures `.invalid`, sin servicios ni sesiones reales. La comprobación de cifrado `NSFileProtectionKey` se conserva en una prueba específica para iPhone físico: CoreSimulator no expone esa propiedad. La aplicación solicita protección completa para carpeta y archivos; el cifrado efectivo y el push real quedan pendientes de un iPhone firmado. Las pruebas de acceso, adjuntos, borrado, privacidad de vistas y regreso desde segundo plano sí se ejecutan en simulador.

## Funciones de la app

La app cubre las funciones del webapp con formularios y navegación de iOS. Consulte [`PARITY.md`](PARITY.md) para la correspondencia completa.

- **Quincenas:** crear por mes y mitad; shows, ventas, participantes y honorarios; novedades y descuentos; recorridos compartidos, anteriores y extras; siete tipos de horas, días, vacaciones y notas.
- **Pagos y Archivo:** búsqueda, filtros, desglose completo por persona, condiciones utilizadas y documentos de cierres. PDF de resumen/desprendibles, Excel y ZIP, vista previa, compartir e imprimir PDF mediante AirPrint.
- **Cierres:** cerrar con instantánea y envío automático cuando Gmail esté conectado; reabrir, corregir condiciones y parámetros históricos y volver a cerrar con `modifyClosed`. El propietario puede eliminar completamente una quincena con confirmación.
- **Equipo y Gestión:** crear/editar personas y todas sus condiciones, inactivar, eliminar y restaurar; conceptos y parámetros; estados de correo, contactos, envío conjunto/individual y conexión/configuración de Gmail; usuarios, permisos e invitaciones del propietario.
- **Mi cuenta y acceso:** mismo usuario y contraseña, activación/restablecimiento con enlace privado, cambio de contraseña y cierre de sesión. Cualquier contraseña no vacía sigue permitida.
- **Agenda:** calendario mensual y eventos por día, próximos 90 días y detalles; consulta y creación/edición de eventos en Google Calendar para Camilo, Luisa y Paula. **Mi cuenta** tiene su propia pestaña.

Cada operación usa los permisos y la validación del servidor. Una pérdida de conexión o conflicto conserva la solicitud en memoria; puedes reintentar, compartir una copia JSON protegida de los cambios o descartarlos y actualizar. No se reinterpreta ni se vuelve a guardar silenciosamente un formulario sobre una revisión diferente. Cerrar la sesión o terminar la app descarta los cambios que no guardaste.

## Agenda con Google Calendar

La pestaña **Agenda** y el sidebar **Agenda** de la web muestran el mismo calendario de Jhon Alex. Los horarios se presentan en hora de Colombia. Puedes cambiar de mes, elegir un día, consultar los próximos conciertos y abrir sus detalles. Muestra primero la copia descargada y se actualiza al entrar, volver a la app, recuperar conexión, cada 30 segundos en primer plano o actualizar manualmente; en iPhone también puedes deslizar la lista hacia abajo.

Camilo prepara la conexión una vez:

1. Abre [Google Calendar API](https://console.cloud.google.com/apis/library/calendar-json.googleapis.com) en el proyecto de Google que ya utilizas para la conexión de Gmail de JAC y actívala.
2. En JAC, abre **Agenda → Conexión** (engranaje en iPhone) y **Conectar Google**. Si no existen credenciales de Google, prepara primero las de Correos/Gmail mediante el formulario privado de JAC.
3. Autoriza con **jacmusicestudios@gmail.com** y concede consultar calendarios y editar eventos. Si Google muestra `access_denied`, comprueba que esa cuenta esté incluida como usuario de prueba en el consentimiento OAuth del proyecto.
4. Selecciona el calendario donde mantienes la agenda de Jhon Alex y pulsa **Usar este calendario**. La misma elección sirve para web y los tres iPhones, sin conectar Google individualmente en cada dispositivo.

Todos los usuarios activos pueden consultar esa agenda; solo Camilo puede conectar, elegir o desconectar. Los eventos se crean y modifican en Google Calendar y aparecen en JAC al actualizar. JAC no modifica Google ni genera automáticamente shows de nómina. Desconectar Agenda conserva los eventos y la conexión de Gmail. No se solicitan ni incorporan nuevas claves al repositorio: el servidor reutiliza las credenciales OAuth existentes y almacena el permiso de Agenda cifrado por separado. El callback registrado de Google permanece igual.

## Actualizar desde Xcode

Seguimos editando esta misma carpeta del Mac, sin depender de GitHub ni Actions. Abre su `ios/JACNomina.xcodeproj`; no necesitas descargar otro proyecto ni reemplazar la carpeta. Mientras la membresía está pendiente, selecciona tu Personal Team en **Signing & Capabilities**, conserva `co.jacmusic.nomina` como identificador y pulsa **Run** con tu iPhone seleccionado. Instala sobre la app existente; no hace falta borrarla. Los ZIP entregados son copias de respaldo opcionales. El repositorio de GitHub queda como copia histórica.

La publicación del servidor actualiza las API; el binario instalado en cada iPhone se actualiza al compilar/instalar de nuevo con Xcode o distribuir una nueva versión ad hoc.

## Mensaje «Operación cancelada» al navegar

Las consultas ligadas a una pantalla pueden cancelarse al salir de ella. SwiftUI/URLSession pueden devolver `CancellationError` o `NSURLErrorCancelled` (-999). Antes se mostraban algunas de estas cancelaciones como un error local y compartido, que reaparecía en Archivo y otros menús. Las lecturas de quincenas, Agenda/calendarios, Correos, Usuarios e Itinerarios/Alertas ahora reconocen ambas cancelaciones sin publicar ese error ni borrar los datos consultados. Los demás errores siguen visibles y la sesión vencida sigue revocando el acceso.

El manejo de guardados no cambia: una cancelación de transporte puede tener resultado incierto en el servidor, por lo que conserva el borrador y sus controles de reintento. Se mantienen las comprobaciones de sesión, versión y privacidad. Las pruebas usan únicamente URLProtocol `.invalid` y un simulador local.

## Abrir y ejecutar en el Mac

1. Abre `ios/JACNomina.xcodeproj` desde esta carpeta estable del Mac con Xcode 16 o posterior. El flujo actual es local, sin GitHub ni Actions.
2. Selecciona el esquema **JACNomina** y un simulador de iPhone para compilar sin certificados.
3. Para un iPhone real, selecciona el target **JACNomina**, abre **Signing & Capabilities**, activa la firma automática y elige tu equipo de Apple Developer.
4. Conserva `co.jacmusic.nomina`. Si Apple indica que no pertenece al equipo, revisa la cuenta/equipo y su registro antes de continuar; no cambies el identificador de una app ya instalada.
5. Conecta el iPhone al Mac, acepta la confianza del dispositivo, activa **Modo de desarrollador** si Xcode lo solicita y selecciónalo como destino. Pulsa **Run**.
6. Inicia sesión con la misma cuenta del webapp. Las cuentas del equipo se activan con los enlaces que Camilo genera desde Usuarios en la app o la web. En el acceso nativo, abre «Activar cuenta o restablecer contraseña» y pega el enlace. No hay registro abierto.

No necesitamos publicar en la App Store. Camilo confirmó que dispone de Mac y Apple Developer.

## Si el simulador queda en blanco o se cierra

El cierre local de Xcode 27/iOS 27 al pasar a segundo plano con un campo enfocado se diagnosticó por separado: `.privacySensitive()` envolvía la navegación raíz y UIKit intentaba distribuir un elemento perteneciente a otra barra. El marcado ahora se aplica al contenido de formularios, listas y documentos; la cubierta opaca con logo protege también las hojas presentadas. Al desactivarse se oculta el teclado sin vaciar los campos ni descartar borradores; puedes volver a tocar el campo al regresar. No se alteran las rutas ni se elimina ninguna comprobación. Diagnóstico, comparaciones y resultados locales: [regreso desde segundo plano](../docs/IOS_REGRESO_SEGUNDO_PLANO.md). Desactivar el depurador no corregía esta excepción.

Los mensajes `Failed to send CA Event`, `com.apple.PointerUI` y `cannot add handler to 0` proceden de componentes de Apple y, por sí solos, no identifican un cierre de la app. Conserva el mensaje que diga `Thread 1`, `Fatal error`, `Precondition failed` o la excepción, si aparece.

1. Comprueba que abres `ios/JACNomina.xcodeproj` y que el esquema seleccionado es **JACNomina**.
2. Detén la ejecución y usa **Product > Clean Build Folder** (Mayús + Comando + K). Ejecuta otra vez con **Run**.
3. Para comprobar si el bloqueo depende del depurador, abre **Product > Scheme > Edit Scheme > Run > Info**, desmarca **Debug executable** y vuelve a ejecutar. Camilo confirmó que este paso permitió abrir el acceso en su simulador con Xcode 27.0. Puede conservarlo desmarcado para usar la app; al depurar con puntos de interrupción debe volver a activarlo. No es necesario desactivar el depurador para todos los desarrolladores.
4. Si continúa, crea un simulador nuevo en **Window > Devices and Simulators > Simulators**. Esto permite comprobar el inicio sin borrar tus otros simuladores.
5. En ese simulador nuevo, sin iniciar sesión, usa **Product > Test** (Comando + U). La prueba de interfaz comprueba que aparecen y se pueden usar los campos de acceso, y que siguen visibles al volver a la app. No envía un inicio de sesión al servidor.
6. Abre **Report Navigator** (Comando + 9), selecciona la última ejecución o prueba y conserva el primer fallo y la pila de llamadas. Indica también la versión de Xcode y del iOS simulado; los avisos de la consola no sustituyen ese diagnóstico.

El workflow de GitHub conserva el resultado `.xcresult` y capturas del arranque en el artefacto **JACNomina-diagnostico-arranque** durante siete días. Las comprobaciones se hacen en un simulador nuevo sin una sesión de producción guardada. La versión de Xcode usada por CI aparece en el primer paso del workflow; una comprobación en otra versión no garantiza compatibilidad con la versión local.

## Instalarla solo en los tres iPhones

Para uso privado, recomendamos distribución **ad hoc** a los tres dispositivos registrados en tu cuenta. Registra sus identificadores en Apple Developer y crea/exporta el archivo firmado desde **Product > Archive** con la opción de distribución a dispositivos registrados. Apple explica el [registro de dispositivos](https://developer.apple.com/help/account/devices/devices-overview) y la [distribución a dispositivos registrados](https://help.apple.com/xcode/mac/current/en.lproj/dev7ccaf4d3c.html). Se necesita renovar la firma/perfil cuando expire y distribuir nuevas versiones firmadas para actualizar la app.

Como alternativa, **TestFlight** facilita instalar y actualizar sin publicar la app en la tienda. Cada build vence a los 90 días; la primera beta para testers externos requiere revisión. Ver [TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/) e [invitación a testers externos](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers).

La firma y los perfiles se gestionan desde tu Mac/cuenta Apple. No se han solicitado ni incluido certificados, claves de Apple, UDID o contraseñas en este repositorio. La entrega de simulador de CI no es un IPA instalable en un iPhone físico.

## Integración y privacidad local

La app autentica mediante `/api/auth` y conserva únicamente la sesión en el Llavero, accesible cuando el dispositivo está desbloqueado y sin sincronización a otros dispositivos. No guarda contraseñas. Desde 0.11.0 conserva respuestas autorizadas cifradas para consulta sin conexión; los cálculos y escrituras siguen en el servidor. También puede crear una copia JSON temporal si el usuario solicita respaldar un cambio pendiente. Usa una URLSession efímera, desactiva cookies/cachés globales y rechaza redirecciones para evitar reenviar credenciales.

`GET /api/mobile/payroll?workspace=1` devuelve una revisión consistente del estado, usuario y permisos; con `?period=ID`, devuelve el detalle y las mismas liquidaciones de `lib/payroll.ts`. Los snapshots y las versiones históricas permanecen en el servidor.

`POST /api/mobile/payroll` recibe comandos pequeños `edit`/`remove`, con tipo de formulario, registro, período y revisión. El servidor aplica los helpers compartidos, el esquema y las políticas y delega el guardado en la API original con su CAS/nonce. No recibe snapshots reconstruidos por Swift. `previewEdit` aplica la misma validación y calcula sin guardar ni preparar correos. `close`, `reopen`, `deletePeriod`, `deleteEmployee` y `restoreEmployee` delegan las acciones originales.

Usuarios, autenticación, correo y documentos reutilizan las API existentes. La autorización nativa de Gmail comienza en `POST /api/mobile/gmail`: un ticket de dos minutos y un solo uso abre la ventana de autenticación de Apple y entrega una cookie exclusiva de Gmail. Nunca entrega una sesión de nómina al navegador. El callback original verifica la sesión vigente, la cookie de protección, PKCE y la cuenta autorizada, y vuelve a `jacnomina://gmail` con resultado y nonce; la app valida el nonce. No agrega claves, tablas ni cambios de migraciones.

Las descargas usan `/api/payroll/export`. Los documentos se guardan temporalmente con protección de archivos de iOS y se eliminan al cerrar la vista, salir de la cuenta o arrancar de nuevo. El contenido se oculta al dejar de estar activa la app para proteger la vista del selector de aplicaciones. Los documentos que el usuario comparta/guarde expresamente quedan bajo su control, igual que las descargas web.

## Validación

Las compilaciones y pruebas actuales se ejecutan localmente en el Mac; el workflow histórico de GitHub no se utiliza. Las pruebas de red nativas interceptan todas las peticiones con URLProtocol y usan dominios `.invalid`: nunca acceden a producción. Las suites `tests/payroll-mobile.test.mjs` y `tests/payroll-mobile-oauth.test.mjs` prueban D1 en memoria, ediciones, cierres, historial, CAS, permisos, eliminación y OAuth simulado. Las pruebas de interfaz optan por un backend `.invalid` con argumentos `--uitest-payroll` y `--uitest-reader`, compilado exclusivamente en DEBUG. La aplicación normal usa producción; Release excluye esas fixtures. Las pruebas unitarias ejecutan sus clientes sin montar la navegación de la app; las pruebas de interfaz verifican la navegación real por separado.

```sh
xcodebuild -project ios/JACNomina.xcodeproj -scheme JACNomina \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build

node --test tests/payroll-mobile.test.mjs tests/payroll-mobile-oauth.test.mjs tests/calendar.test.mjs
```

Las pruebas del simulador usan firma local ad hoc (`CODE_SIGN_IDENTITY=-`), sin certificados de Apple Developer. El Llavero necesita que el ejecutable del simulador esté firmado; desactivar completamente la firma puede impedir guardar o leer la sesión. La suite comprueba el Llavero real del simulador con una cuenta temporal de prueba, además de las respuestas de red simuladas.

Las comprobaciones actuales se ejecutan en el Mac de Camilo. Consulta `../docs/MAC_LOCAL_VERIFICADO.md` para el resultado real de Xcode y los pasos de firma pendientes.

El icono de **JAC** usa el símbolo azul sobre fondo blanco elegido por Camilo. Está en `JACNomina/Assets.xcassets/AppIcon.appiconset`, como PNG RGB opaco de 1024 × 1024. Xcode genera los tamaños necesarios a partir de esa imagen; el catálogo `AppIcon` está seleccionado tanto en Debug como en Release. Para verlo en el iPhone, abre el proyecto actualizado del ZIP y vuelve a instalar con **Run** sobre la misma app. El proyecto y el esquema son `JACNomina` y el identificador es `co.jacmusic.nomina`.

## Agenda editable y colores de JAC (0.4.0/build 5)

Camilo, Luisa y Paula pueden pulsar **+** en Agenda para crear un evento, o abrir uno y pulsar **Editar evento**. Incluye título, fecha/hora de inicio y fin, todo el día, lugar y descripción. Se guarda en el mismo Google Calendar de la web; una recurrencia modifica solo la ocurrencia elegida. La conexión y selección permanecen exclusivas de Camilo.

La conexión existente sigue consultando. Para habilitar edición, Camilo abre **Agenda → Conexión → Volver a autorizar Google**, elige `jacmusicestudios@gmail.com` y acepta consultar calendarios/editar eventos. El calendario seleccionado se conserva. Los calendarios de solo lectura no permiten guardar. Si alguien modificó el evento, cancela, actualiza Agenda y vuelve a abrirlo; el formulario conserva tus datos ante un error.

La interfaz usa los verdes oscuro y lima y los fondos claros del webapp, conservando controles nativos, modo oscuro, logo y nombre **JAC**. Para instalar estos cambios, abre `ios/JACNomina.xcodeproj` del ZIP actualizado, elige tu iPhone y pulsa **Run**. Conserva tu Team y firma local.

## Itinerarios y alertas (0.5.0/build 6)

**Gestión → Itinerarios** muestra los PDF recibidos de `#itinerarios-finales`, con vista previa y hoja para compartir. **Gestión → Alertas** permite consultar avisos; únicamente Camilo ve **+**, escribe el mensaje y elige destinatarios. Una notificación abre el aviso privado y permite abrir su PDF. La API aplica los mismos controles que la web.

Para recibir esta versión abre el proyecto del ZIP y usa Run. Para **push real**, selecciona un equipo con membresía vigente de Apple Developer Program: Personal Team gratuito no admite APNs. Esta capacidad está suspendida desde 0.9.5; consulta la sección inicial para reactivarla tras la aprobación. Camilo debe preparar Slack y la clave APNs desde **Itinerarios → Conexión** en la web; cada usuario activa después sus notificaciones en el iPhone. Sigue [la guía de configuración](../docs/ITINERARIES_PUSH_SETUP.md). No necesita publicación en App Store.

Las pruebas nativas usan un PDF ficticio y URLProtocol `.invalid`; no registran el simulador en los servicios reales ni envían avisos. El registro de dispositivos se desactiva al salir de la cuenta y respeta la desactivación elegida por el usuario.

## Actualización 0.9.0 (10): pases de abordar

Usa este mismo proyecto de Xcode. Itinerarios → Pases de abordar muestra los pases privados de hoy, próximos días e historial plegado según Colombia. Desde Gestión → Alertas, Camilo puede elegir Pase, adjuntar PDF/imágenes, elegir una persona y revisar la fecha. Las cuentas de Solo itinerarios no muestran Nómina, Agenda ni Administración. Ver docs/BOARDING_PASSES.md para reglas de fechas, privacidad y pruebas. La instalación física sigue usando Run y tu firma Apple; la preparación de APNs requiere la membresía aprobada y sus claves, gestionadas fuera del proyecto.

### 0.9.1 (11) — mañana y PDF directo

Actualización del mismo proyecto: Pases de abordar muestra hoy y mañana; prioriza mañana si hoy está vacío. Cada adjunto abre directamente el PDF/imagen y muestra pasajero y ruta del nombre `Camilo 16 de octubre Pereira-Bogota.pdf`. Conserva sesión, privacidad y documentos temporales protegidos. Instala con Run en tu proyecto actual; el ZIP es respaldo opcional.

Verificación 0.9.3 (13): simulador local ios-gestures37-native-style.xcresult TEST SUCCEEDED (gestos, confirmación breve, PDF/historial y lector); itinerario manual con adjunto también pasó. Release sin firma correcto. Web v37 publicada en el Site existente. Instalar con Run desde este mismo proyecto.

0.9.4 (14) verificada en simulador: 37 unitarias y cinco pruebas de interfaz distintas pasadas; una comprobación física omitida explícitamente. Release sin firma correcto. Web v38 publicada; ver docs/PROJECT_CONTEXT.md.

## Fotografía 0.19.0 (31)

Mismo proyecto: subidas directas a Drive con control final JAC, reproducción nativa por rangos y caché cifrada limitada para fotos abiertas. Se conservan descargas offline por carpeta y Guardar en Fotos. Ver [transferencias](../docs/PHOTOGRAPHY_TRANSFER.md). Para actualizar tu teléfono, Run en JACNomina sobre tu iPhone; no necesitas descargar otro proyecto. Firma personal y co.jacmusic.nomina conservados; push continúa suspendido. Build Release sin firma y pruebas locales con fixtures verificados; instalación física pendiente de Run.

## Archivo de contratos · 17 de octubre de2026

CRM → Contratos permite crear con RUT/manual, guardar automáticamente, abrir el archivo compartido y asignar a un show. PDF abierto disponible en la caché privada sin conexión; edición requiere red.137unitarias(136aprobadas,1condición física omitida) y recorrido UI completo aprobados, Release compilado. Se mantiene este proyecto/firma/bundle/push; instalar con Run. Ver docs/CONTRACTS.md.
