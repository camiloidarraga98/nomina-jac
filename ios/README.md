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

La app autentica mediante `/api/auth` y conserva únicamente la sesión en el Llavero, accesible cuando el dispositivo está desbloqueado y sin sincronización a otros dispositivos. No guarda contraseñas ni una base de nómina en disco. Solo crea una copia JSON temporal si el usuario solicita respaldar un cambio pendiente. Usa una URLSession efímera, desactiva cookies/cachés globales y rechaza redirecciones para evitar reenviar credenciales.

`GET /api/mobile/payroll?workspace=1` devuelve una revisión consistente del estado, usuario y permisos; con `?period=ID`, devuelve el detalle y las mismas liquidaciones de `lib/payroll.ts`. Los snapshots y las versiones históricas permanecen en el servidor.

`POST /api/mobile/payroll` recibe comandos pequeños `edit`/`remove`, con tipo de formulario, registro, período y revisión. El servidor aplica los helpers compartidos, el esquema y las políticas y delega el guardado en la API original con su CAS/nonce. No recibe snapshots reconstruidos por Swift. `previewEdit` aplica la misma validación y calcula sin guardar ni preparar correos. `close`, `reopen`, `deletePeriod`, `deleteEmployee` y `restoreEmployee` delegan las acciones originales.

Usuarios, autenticación, correo y documentos reutilizan las API existentes. La autorización nativa de Gmail comienza en `POST /api/mobile/gmail`: un ticket de dos minutos y un solo uso abre la ventana de autenticación de Apple y entrega una cookie exclusiva de Gmail. Nunca entrega una sesión de nómina al navegador. El callback original verifica la sesión vigente, la cookie de protección, PKCE y la cuenta autorizada, y vuelve a `jacnomina://gmail` con resultado y nonce; la app valida el nonce. No agrega claves, tablas ni cambios de migraciones.

Las descargas usan `/api/payroll/export`. Los documentos se guardan temporalmente con protección de archivos de iOS y se eliminan al cerrar la vista, salir de la cuenta o arrancar de nuevo. El contenido se oculta al dejar de estar activa la app para proteger la vista del selector de aplicaciones. Los documentos que el usuario comparta/guarde expresamente quedan bajo su control, igual que las descargas web.

## Validación

El workflow `.github/workflows/ios.yml` compila y prueba en un runner macOS. Las pruebas de red nativas interceptan todas las peticiones con URLProtocol y usan dominios `.invalid`: nunca acceden a producción. Las suites `tests/payroll-mobile.test.mjs` y `tests/payroll-mobile-oauth.test.mjs` prueban D1 en memoria, ediciones, cierres, historial, CAS, permisos, eliminación y OAuth simulado. Las pruebas de interfaz optan por un backend `.invalid` con argumentos `--uitest-payroll` y `--uitest-reader`, compilado exclusivamente en DEBUG. La aplicación normal usa producción; Release excluye esas fixtures. Las pruebas unitarias ejecutan sus clientes sin montar la navegación de la app; las pruebas de interfaz verifican la navegación real por separado.

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
