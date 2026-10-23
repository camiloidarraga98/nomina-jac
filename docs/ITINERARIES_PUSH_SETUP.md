## Destinatarios actuales ·22 de octubre de2026 (Colombia)

Camilo pidió que las cuentas recién creadas aparezcan al crear alertas y reportó que faltaba Andrés. El diagnóstico mínimo mostró su cuenta activa sin la sección Alertas. Se habilitó **solo Alertas para `andres`**, conservando las otras cinco secciones; se aplicaron CAS/version y cierre de sesiones/invitaciones anteriores, como en Gestión. No se cambiaron otros usuarios ni se enviaron avisos reales. Debe iniciar sesión nuevamente para recibir los permisos actualizados.

El selector consulta `/api/notices/recipients` al abrir, reanudar, cambiar usuarios y antes de publicar; también se refresca cada30s mientras está abierto. Solo usuarios activos con Alertas aparecen como destinatarios de alertas; Pases mantiene su lista independiente y acceso exclusivo. Las cuentas pendientes de activación elegibles siguen mostrándose con su estado. Una cuenta creada sin Alertas debe recibir ese permiso desde Gestión para aparecer: el refresco no concede secciones automáticamente.

Los formularios web/nativo conservan el borrador y las elecciones. Tras la primera carga, las cuentas nuevas aparecen sin seleccionar; no se amplían destinatarios silenciosamente. Una cuenta retirada o sin permiso se elimina de la selección y exige revisar la lista antes de publicar. Un error al refrescar bloquea el envío sin borrar el borrador, y un401/403 retira la lista privada. El endpoint solo lee nombres/IDs/estado, requiere administrador actual y revalida sesión; no importa Slack ni envía notificaciones.

Verificación local: cuatro casos Node focales y dos recorridos de navegador con24 comprobaciones aprobados; TypeScript y build correctos. Una regresión antigua necesitó inicializar su propia conexión Slack ficticia para ejecutarse aislada; se repitió solo ese caso. El primer intento del harness usó un nombre accesible equivocado; se corrigió únicamente el selector y los dos recorridos quedaron aprobados. Fuente, CI Apple y publicación finales pendientes de cerrar esta entrega. Las pruebas no usaron la cuenta real de Andrés ni servicios de envío reales.

# Itinerarios y alertas de JAC

> **Actualización22 de octubre:** Camilo confirmó membresía Apple pagada y pidió reactivar push. El proyecto activa la capacidad y los entitlements APNs. Configurar la clave en JAC y firmar/instalar con el equipo pagado sigue siendo necesario. La actualización se obtiene con pull del mismo proyecto, sin otro ZIP; TestFlight permite distribución inalámbrica. Ver [pasos vigentes](APPLE_PAID_SETUP.md).

La web incluye **Itinerarios** y **Alertas**. En la app JAC 0.8.0/build 9, Itinerarios tiene pestaña propia y Alertas está en **Gestión**. Las cuentas activas pueden consultar los PDF; solo Camilo crea alertas y elige destinatarios. Las alertas quedan visibles para sus destinatarios y para Camilo. Los permisos financieros se conservan.

La integración recibe exclusivamente PDF nuevos publicados en **JAC Music → #itinerarios-finales**, canal `C0C6V85SRL6`. Ignora mensajes de texto y otros archivos. El agente de ChatGPT puede seguir publicando en Slack como hasta ahora: no necesita enviar datos de nómina ni cambiar su generación del PDF. No se importan conversaciones ni archivos históricos automáticamente.

## Conectar Slack, desde la cuenta de Camilo

1. Abre [Slack API → Your Apps](https://api.slack.com/apps) y crea una app **From scratch** para el espacio **JAC Music**. Necesitas permiso para instalar apps en ese espacio. Esta integración puede ser una app separada del agente que genera los itinerarios.
2. En **OAuth & Permissions → Bot Token Scopes**, agrega `files:read`, `channels:read` y `channels:history`. Instala la app en el espacio. Si cambias los permisos después, vuelve a instalarla.
3. Invita su bot a `#itinerarios-finales`: en el canal, añade la app desde sus integraciones o usa `/invite @nombre-del-bot`.
4. Conserva el **Bot User OAuth Token** (`xoxb-…`) y el **Signing Secret** de **Basic Information → App Credentials**. En JAC web, entra como Camilo y abre **Configuración general → Servicios conectados → Slack**. Ingresa ambos allí y pulsa **Guardar conexión**. JAC comprueba el espacio y que el bot sea miembro del canal.
5. En Slack activa **Event Subscriptions**. Usa esta **Request URL**:

   ```text
   https://jhonalexcastano.com/api/notices/slack
   ```

6. Agrega **Subscribe to bot events → `message.channels`** y guarda. Completa cualquier reinstalación que Slack solicite. Guarda primero las credenciales en JAC: la verificación de esa URL necesita el Signing Secret.

Cada PDF nuevo de ese canal se guarda en almacenamiento privado. La notificación se prepara después de guardar el archivo. El mismo archivo de Slack no genera un nuevo itinerario al reintentarse. Si una descarga falla, Camilo verá **PDF pendientes** en Servicios conectados y podrá reintentar. Abrir Itinerarios también retoma trabajo pendiente. No se realiza una prueba sobre el canal ni se manda un mensaje real durante el despliegue.

La conexión de Slack disponible en este chat permite consultar información; el servidor necesita esta app de Slack para recibir eventos continuamente. No copies claves al chat, al repositorio o al agente que genera los PDF.

## Activar avisos en el navegador

1. Camilo abre **Configuración general → Servicios conectados → Notificaciones del navegador → Preparar navegador**. JAC genera y guarda cifradas las claves VAPID.
2. Al entrar con su cuenta de JAC se muestra automáticamente la solicitud de notificaciones. Safari y otros navegadores requieren pulsar **Permitir notificaciones** en esa solicitud para poder mostrar su permiso del sistema; no se puede omitir ese gesto. Con permiso previamente concedido, JAC registra el navegador automáticamente. **Ahora no** cierra la solicitud durante la pestaña actual. **Configuración general → Notificaciones** permite desactivar o volver a permitir los avisos en ese navegador/cuenta. Desactivar se conserva al volver a entrar. El permiso y la preferencia son propios de cada navegador/dispositivo.
3. En Safari de iPhone/iPad, Web Push requiere iOS/iPadOS 16.4 o posterior y el webapp agregado a la pantalla de inicio. Para la app nativa se usa la conexión de Apple que sigue.

Puedes desactivar los avisos desde JAC o los ajustes del navegador. El service worker no almacena nómina ni PDF. Al tocar un aviso abre JAC y comprueba tu acceso al contenido.

## Activar push en la app de iPhone

Necesitas una **membresía vigente de Apple Developer Program**; una cuenta gratuita/Personal Team no habilita APNs. No necesitas publicar en App Store para usar push en una app instalada desde Xcode.

1. En [Apple Developer → Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list), verifica que el App ID `co.jacmusic.nomina` pertenece a tu equipo y tiene **Push Notifications**. Si ese identificador ya pertenece a otro equipo, debe ajustarse el proyecto y el topic del servidor juntos antes de activar push.
2. En **Keys**, crea una clave con **Apple Push Notifications service (APNs)**. Si eliges una clave limitada a un entorno o topic, debe cubrir `co.jacmusic.nomina` y el entorno instalado; una clave que admita sandbox y producción permite ambos flujos. Descarga el `.p8` y conserva su **Key ID** y el **Team ID** de tu membresía. Apple solo permite descargar esa clave una vez; guárdala de forma segura fuera del repositorio.
3. En JAC web, como Camilo: **Configuración general → Servicios conectados → Notificaciones del iPhone**. Ingresa Team ID, Key ID y selecciona el archivo `.p8`; pulsa **Guardar conexión**. Las claves se cifran en D1 y no se devuelven al consultar la configuración.
4. Haz pull en el proyecto existente y abre `ios/JACNomina.xcodeproj` en Xcode. En **Signing & Capabilities**, selecciona tu equipo de pago y firma automática. El proyecto ya incorpora **Push Notifications** y los entitlements: Debug usa sandbox; Release usa producción. Xcode debe regenerar el perfil de firma correspondiente. No necesitas GitHub ni Actions para instalarlo.
5. Selecciona tu iPhone y pulsa **Run**. Inicia sesión y permite las notificaciones; revisa también **Gestión → Notificaciones**. Concede el permiso. Repite en los tres iPhones. Compilar o publicar la web no actualiza los binarios instalados.

Si Apple rechaza una clave, un topic o un dispositivo, el aviso sigue en JAC pero no aparece el push. La compilación del simulador verifica el código y la navegación; la entrega APNs real requiere el equipo, la clave y un dispositivo registrado.

## Crear una alerta

Camilo abre **Alertas → Crear alerta** en la web o **Gestión → Alertas → +** en iPhone, escribe título/mensaje, elige usuarios y pulsa **Crear alerta y notificar**. La selección incluye inicialmente a los usuarios activos; puedes desmarcarlos. Una cuenta desactivada o con sesión revocada no recibe nuevas entregas. Salir de JAC desactiva el registro de ese dispositivo ligado a la sesión.

Un push muestra un texto genérico para proteger información en la pantalla bloqueada. Al abrirlo se consulta el aviso privado; el itinerario ofrece el PDF y una alerta manual muestra su mensaje. No se adjunta ni expone el PDF en una URL pública.

Las notificaciones requieren permiso y conexión del dispositivo y la aceptación de Apple/navegador. No se garantiza recepción ni lectura. Un resultado incierto del proveedor no se reenvía automáticamente, para evitar duplicados; el aviso permanece consultable en JAC. Los cambios de esta función no envían correos ni modifican quincenas.

## Eliminar una alerta

En la web, Camilo abre **Configuración general → Alertas** y pulsa la papelera de una alerta o **Eliminar alerta** dentro de su detalle. La confirmación indica que se eliminará para todos sus destinatarios y no se puede deshacer. Cancelar conserva la alerta. Solo Camilo puede ejecutar esta operación; los destinatarios mantienen su acceso de consulta.

El borrado elimina mensaje, destinatarios y entregas pendientes de esa alerta en una transacción. No borra itinerarios, PDF, dispositivos ni conexiones. Las notificaciones ya recibidas y las solicitudes que el proveedor ya está procesando no se pueden retirar. Un reintento de creación con el mismo identificador eliminado se rechaza, para no restaurar contenido ni generar nuevos avisos.

## Continuidad técnica

`drizzle/0008_itineraries_notifications.sql` crea tablas independientes para configuración cifrada, avisos, destinatarios, dispositivos, entregas e importaciones. Conserva `DB`, `BUCKET` y las migraciones anteriores. `/api/notices` aplica sesión propia y autorización; `/api/notices/pdf` sirve PDF privados; `/api/notices/slack` verifica firma HMAC, timestamp, espacio/canal y metadatos del archivo. No solicita scopes de escritura en Slack.

`drizzle/0009_deleted_alerts.sql` agrega únicamente `jac_deleted_alerts`: conserva el UUID y la fecha de borrado, sin título, mensaje ni destinatarios. Mantiene intactas las migraciones 0000–0008 y los datos existentes. Se aplica primero en D1 local; la publicación normal incorpora esta migración adicional al mismo DB.

Las pruebas usan D1/R2 en memoria, Slack/APNs/servicios push simulados y Workerd con todas las salidas interceptadas. Verifican destinatarios, revocación, reintentos, tamaño/formato del PDF, firmas ES256, descifrado independiente RFC 8291 y rechazo de redirecciones. Swift usa URLProtocol y dominios `.invalid` y prueba el PDF, las alertas y sus permisos. No usar producción para probar envíos, importaciones o cierres.

La eliminación se prueba con permisos, origen, confirmación, repetición idempotente, rollback atómico, rechazo de reintentos de creación y cancelación antes de entregar push. También se verifica en D1 de Workerd local sin salidas externas. No eliminar alertas reales como prueba.

## Texto de notificaciones y borrado de itinerarios

Los PDF nuevos de Slack envían el título **JAC** y el mensaje **Ya llegó tu itinerario para el día de hoy**. Es el texto solicitado, sin extraer fechas ni copiar conversaciones de Slack. Las alertas manuales envían su título y mensaje únicamente a los destinatarios seleccionados; ese contenido puede ser visible en las notificaciones y la pantalla bloqueada según las preferencias del dispositivo. Web Push sigue cifrado. Si una descripción supera el límite de bytes del proveedor, el aviso muestra una vista previa con puntos suspensivos; el contenido completo se conserva dentro de JAC. Se aplica tanto al navegador como al payload APNs del servidor, sin cambiar las claves ni el binario del iPhone.

El navegador actualiza su service worker al abrir Itinerarios/Alertas. Conserva registro, permisos e identificador del dispositivo; no se requiere conceder acceso de nuevo. El worker no guarda PDF, sesiones ni respuestas de la API y al pulsar el aviso sigue abriendo únicamente JAC con el UUID autorizado.

Solo Camilo puede **Eliminar itinerario**, desde la papelera de la lista o el detalle. La confirmación indica que se retira para todas las cuentas y elimina el PDF guardado en JAC; el original de Slack permanece. La API `deleteItinerary` exige sesión vigente, origen y confirmación del mismo UUID. La migración adicional `0010_deleted_itineraries.sql` añade una marca por UUID/origen, sin cambiar las migraciones anteriores ni datos de nómina. D1 retira aviso, destinatarios y entregas en un lote atómico; Slack no vuelve a importar ese archivo en un replay o reintento.

La eliminación del objeto R2 se reintenta si falla, manteniendo inaccesible el PDF desde JAC. Las importaciones con una concesión antigua comprueban la marca después de subir el archivo y retiran también una copia tardía; una revisión de limpieza impide que una operación vieja dé por terminada una limpieza nueva. Los avisos ya entregados al proveedor no pueden retirarse. Las pruebas usan D1/R2 en memoria, Workerd local y servicios simulados; no eliminan itinerarios ni envían avisos reales.

## Publicación manual y adjuntos (web/iPhone 0.6.0)

Camilo puede elegir Alerta o Itinerario desde Alertas → Crear/+ y adjuntar hasta cinco PDF, JPG o PNG (10 MB total). Alertas conservan destinatarios elegidos; los itinerarios se consultan por todo el equipo activo y preparan sus avisos sin Slack. Las imágenes de Fotos en iPhone se convierten a JPG. Los cuadros web tienen filas de archivos independientes y un pie separado para eliminar.

`POST /api/notices/publish` usa JSON acotado a 14 MiB con UUID estable, tipo, título, mensaje, destinatarios y archivos `{filename,data}` en base64. Comprueba cuenta propietaria, origen y sesión otra vez después de R2; valida firmas de contenido, cantidad y tamaño. El hash de contenido impide reutilizar el UUID para otro envío. Un token de subida separa intentos concurrentes y conserva un único juego de adjuntos y destinatarios. El comando anterior `alert` sigue admitido para versiones nativas anteriores.

Migraciones adicionales `0011_manual_notice_attachments` y `0012_manual_upload_token`; no alteran 0000–0010. D1 guarda metadatos y R2 los bytes con claves aleatorias privadas. La subida se registra antes de escribir; en fallo se conserva limpieza pendiente y los temporales abandonados caducan a la hora. Las revisiones de limpieza impiden perder una copia tardía. La eliminación de ambos tipos marca sus adjuntos dentro de la transacción D1; se revoca acceso aunque R2 falle y se reintenta limpieza al actualizar.

`GET /api/notices/file?id=UUID&file=UUID` exige sesión y acceso al aviso, revalida después de obtener R2 y sirve MIME verificado, `nosniff`, sandbox y `no-store`. No hay URL pública, caché de documentos ni importación de imágenes desde Slack. Los PDF existentes siguen disponibles por `/api/notices/pdf` y por el contrato de adjuntos nuevo.

Pruebas de servidor con D1/R2 en memoria y Workerd sin salidas reales: firmas, permisos/origen, destinatarios, reintento/concurrencia, revocación durante subida, rollback, limpieza pendiente, tombstones y descarga privada. Xcode usa fixtures `.invalid`; la prueba de cifrado físico se conserva separada y se omite explícitamente en simulador por falta de NSFileProtectionKey. No probar avisos, borrados o subidas en producción.
