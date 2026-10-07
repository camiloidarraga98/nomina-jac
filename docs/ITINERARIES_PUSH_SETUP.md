# Itinerarios y alertas de JAC

La web incluye **Itinerarios** y **Alertas**. En la app JAC 0.5.0/build 6 están en **Gestión**. Las cuentas activas pueden consultar los PDF; solo Camilo crea alertas y elige destinatarios. Las alertas quedan visibles para sus destinatarios y para Camilo. Los permisos financieros se conservan.

La integración recibe exclusivamente PDF nuevos publicados en **JAC Music → #itinerarios-finales**, canal `C0C6V85SRL6`. Ignora mensajes de texto y otros archivos. El agente de ChatGPT puede seguir publicando en Slack como hasta ahora: no necesita enviar datos de nómina ni cambiar su generación del PDF. No se importan conversaciones ni archivos históricos automáticamente.

## Conectar Slack, desde la cuenta de Camilo

1. Abre [Slack API → Your Apps](https://api.slack.com/apps) y crea una app **From scratch** para el espacio **JAC Music**. Necesitas permiso para instalar apps en ese espacio. Esta integración puede ser una app separada del agente que genera los itinerarios.
2. En **OAuth & Permissions → Bot Token Scopes**, agrega `files:read`, `channels:read` y `channels:history`. Instala la app en el espacio. Si cambias los permisos después, vuelve a instalarla.
3. Invita su bot a `#itinerarios-finales`: en el canal, añade la app desde sus integraciones o usa `/invite @nombre-del-bot`.
4. Conserva el **Bot User OAuth Token** (`xoxb-…`) y el **Signing Secret** de **Basic Information → App Credentials**. En JAC web, entra como Camilo y abre **Itinerarios → Conexión → Slack**. Ingresa ambos allí y pulsa **Guardar conexión**. JAC comprueba el espacio y que el bot sea miembro del canal.
5. En Slack activa **Event Subscriptions**. Usa esta **Request URL**:

   ```text
   https://jhonalexcastano.com/api/notices/slack
   ```

6. Agrega **Subscribe to bot events → `message.channels`** y guarda. Completa cualquier reinstalación que Slack solicite. Guarda primero las credenciales en JAC: la verificación de esa URL necesita el Signing Secret.

Cada PDF nuevo de ese canal se guarda en almacenamiento privado. La notificación se prepara después de guardar el archivo. El mismo archivo de Slack no genera un nuevo itinerario al reintentarse. Si una descarga falla, Camilo verá **PDF pendientes** en Conexión y podrá reintentar. Abrir Itinerarios también retoma trabajo pendiente. No se realiza una prueba sobre el canal ni se manda un mensaje real durante el despliegue.

La conexión de Slack disponible en este chat permite consultar información; el servidor necesita esta app de Slack para recibir eventos continuamente. No copies claves al chat, al repositorio o al agente que genera los PDF.

## Activar avisos en el navegador

1. Camilo abre **Itinerarios → Conexión → Notificaciones del navegador → Preparar navegador**. JAC genera y guarda cifradas las claves VAPID.
2. Cada usuario inicia sesión y pulsa **Activar en este navegador** en Itinerarios o Alertas, y concede el permiso. Hay que activarlo en cada navegador/dispositivo.
3. En Safari de iPhone/iPad, Web Push requiere iOS/iPadOS 16.4 o posterior y el webapp agregado a la pantalla de inicio. Para la app nativa se usa la conexión de Apple que sigue.

Puedes desactivar los avisos desde JAC o los ajustes del navegador. El service worker no almacena nómina ni PDF. Al tocar un aviso abre JAC y comprueba tu acceso al contenido.

## Activar push en la app de iPhone

Necesitas una **membresía vigente de Apple Developer Program**; una cuenta gratuita/Personal Team no habilita APNs. No necesitas publicar en App Store para usar push en una app instalada desde Xcode.

1. En [Apple Developer → Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list), verifica que el App ID `co.jacmusic.nomina` pertenece a tu equipo y tiene **Push Notifications**. Si ese identificador ya pertenece a otro equipo, debe ajustarse el proyecto y el topic del servidor juntos antes de activar push.
2. En **Keys**, crea una clave con **Apple Push Notifications service (APNs)**. Si eliges una clave limitada a un entorno o topic, debe cubrir `co.jacmusic.nomina` y el entorno instalado; una clave que admita sandbox y producción permite ambos flujos. Descarga el `.p8` y conserva su **Key ID** y el **Team ID** de tu membresía. Apple solo permite descargar esa clave una vez; guárdala de forma segura fuera del repositorio.
3. En JAC web, como Camilo: **Itinerarios → Conexión → Notificaciones del iPhone**. Ingresa Team ID, Key ID y selecciona el archivo `.p8`; pulsa **Guardar conexión**. Las claves se cifran en D1 y no se devuelven al consultar la configuración.
4. Descarga el ZIP actualizado entregado por Codex y abre `ios/JACNomina.xcodeproj` en Xcode. En **Signing & Capabilities**, selecciona tu equipo de pago y firma automática. El proyecto ya incorpora **Push Notifications** y los entitlements: Debug usa sandbox; Release usa producción. Xcode debe regenerar el perfil de firma correspondiente. No necesitas GitHub ni Actions para instalarlo.
5. Selecciona tu iPhone y pulsa **Run**. Inicia sesión y abre **Gestión → Itinerarios → Activar en este iPhone**. Concede el permiso. Repite en los tres iPhones. Compilar o publicar la web no actualiza los binarios instalados.

Si Apple rechaza una clave, un topic o un dispositivo, el aviso sigue en JAC pero no aparece el push. La compilación del simulador verifica el código y la navegación; la entrega APNs real requiere el equipo, la clave y un dispositivo registrado.

## Crear una alerta

Camilo abre **Alertas → Crear alerta** en la web o **Gestión → Alertas → +** en iPhone, escribe título/mensaje, elige usuarios y pulsa **Crear alerta y notificar**. La selección incluye inicialmente a los usuarios activos; puedes desmarcarlos. Una cuenta desactivada o con sesión revocada no recibe nuevas entregas. Salir de JAC desactiva el registro de ese dispositivo ligado a la sesión.

Un push muestra un texto genérico para proteger información en la pantalla bloqueada. Al abrirlo se consulta el aviso privado; el itinerario ofrece el PDF y una alerta manual muestra su mensaje. No se adjunta ni expone el PDF en una URL pública.

Las notificaciones requieren permiso y conexión del dispositivo y la aceptación de Apple/navegador. No se garantiza recepción ni lectura. Un resultado incierto del proveedor no se reenvía automáticamente, para evitar duplicados; el aviso permanece consultable en JAC. Los cambios de esta función no envían correos ni modifican quincenas.

## Continuidad técnica

`drizzle/0008_itineraries_notifications.sql` crea tablas independientes para configuración cifrada, avisos, destinatarios, dispositivos, entregas e importaciones. Conserva `DB`, `BUCKET` y las migraciones anteriores. `/api/notices` aplica sesión propia y autorización; `/api/notices/pdf` sirve PDF privados; `/api/notices/slack` verifica firma HMAC, timestamp, espacio/canal y metadatos del archivo. No solicita scopes de escritura en Slack.

Las pruebas usan D1/R2 en memoria, Slack/APNs/servicios push simulados y Workerd con todas las salidas interceptadas. Verifican destinatarios, revocación, reintentos, tamaño/formato del PDF, firmas ES256, descifrado independiente RFC 8291 y rechazo de redirecciones. Swift usa URLProtocol y dominios `.invalid` y prueba el PDF, las alertas y sus permisos. No usar producción para probar envíos, importaciones o cierres.
