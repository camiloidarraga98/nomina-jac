# Cuenta Apple de pago: instalación, push y Wallet

Camilo confirmó el 22 de octubre de 2026 que su membresía de Apple Developer Program está lista y pidió instalación inalámbrica, reactivar las notificaciones y retomar Apple Wallet. Esto sustituye la suspensión de push y el aplazamiento de Wallet; no modifica permisos de cuentas JAC ni conexiones existentes.

## Estado de esta preparación

El mismo proyecto `ios/JACNomina.xcodeproj`, esquema `JACNomina`, bundle `co.jacmusic.nomina`, selecciona ahora `JACNominaPush.entitlements`, habilita Push Notifications y usa `JAC_PUSH_ENABLED=YES` en Debug y Release. Se conservan `APNS_ENVIRONMENT=development` para ejecución desde Xcode y `production` para Archive/TestFlight. Camilo confirmó que la membresía de pago conserva el Team ID `AYHVYN8BJF`, ya guardado en el proyecto. No se ha consultado su cuenta Apple desde este entorno.

El servidor ya permite guardar la clave APNs cifrada desde el formulario privado de JAC. Activar la capacidad de Xcode no crea esa clave, regenera un perfil firmado, instala una app ni confirma recepción real. No se requiere volver a publicar la web para esta reactivación.

Wallet todavía no está implementado: el visor existente extrae los píxeles originales del código del PDF/imagen y los muestra dentro de JAC. La preparación de identificador/certificado descrita abajo es un requisito para la nueva integración, no una declaración de que ya genera `.pkpass`.

## 1. Habilitar la firma y las notificaciones

1. En [Apple Developer → Membership details](https://developer.apple.com/account), verificar que la membresía figure activa; el **Team ID** del equipo de pago confirmado por Camilo es `AYHVYN8BJF`. Aceptar cualquier acuerdo pendiente que Apple muestre.
2. En **Certificates, Identifiers & Profiles → Identifiers**, seleccionar o registrar el App ID explícito `co.jacmusic.nomina` en ese equipo y habilitar **Push Notifications**. Si el identificador pertenece a otro equipo, resolver primero su disponibilidad; no cambiar el bundle unilateralmente porque también es el topic del servidor.
3. En **Keys → +**, crear una clave de **Apple Push Notifications service (APNs)** que cubra el topic `co.jacmusic.nomina` y **Production** para TestFlight. Si Apple ofrece **Sandbox & Production**, esa configuración permite usar también Run/Debug. Revisar las restricciones Team Scoped/Topic Specific antes de confirmar; una clave limitada a Production no habilita los avisos de un binario Debug/sandbox. Descargar el archivo `.p8`, anotar su **Key ID** y conservarlo fuera del repositorio. Apple solo permite descargarlo una vez.
4. En JAC web, iniciar sesión como Camilo y abrir **Configuración general → Servicios conectados → Notificaciones del iPhone**. Ingresar Team ID, Key ID y el archivo `.p8` en ese formulario HTTPS y guardar. No enviar el archivo por chat ni subirlo a GitHub. La clave de APNs no es una credencial de acceso a App Store Connect.
5. Hacer pull en el mismo Xcode. En el target JACNomina, **Signing & Capabilities**, seleccionar el equipo de pago, mantener **Automatically manage signing** y comprobar **Push Notifications**. Xcode debe crear/renovar los perfiles con `aps-environment`. Si el Team ID cambió, conservarlo también en la fuente para que el siguiente pull no lo retire.
6. JAC conserva una única clave APNs en esta conexión; guardar otra sustituye la anterior. Tras instalar el binario nuevo, entrar en JAC y permitir las notificaciones. Revisar también **Gestión → Notificaciones** y los ajustes de iOS. Repetir por dispositivo. La validación física de APNs queda pendiente de esa configuración; las pruebas automáticas usan proveedores interceptados y nunca envían un aviso real.

## 2. Instalar y actualizar sin cable mediante TestFlight

TestFlight permite distribuir la beta sin publicar una ficha disponible en la tienda. Cada build dura hasta 90 días: subir uno nuevo antes de que venza. Los usuarios conservan sus permisos de JAC; ser tester no concede administración dentro de la app.

1. En [App Store Connect](https://appstoreconnect.apple.com/), abrir **Apps → + → New App**. Elegir iOS, un nombre disponible, idioma español y el bundle `co.jacmusic.nomina`. Un SKU interno posible es `JAC-IOS`; debe ser único en esa cuenta.
2. En el mismo Xcode, seleccionar **Any iOS Device (arm64)** o el destino genérico de iOS y usar **Product → Archive**. No elegir un simulador para el archivo de distribución. Si ya existe un build con el mismo número, incrementar el build antes de subir.
3. En **Organizer → Distribute App → App Store Connect → Upload**, usar la firma automática del equipo de pago y completar la validación de Xcode. No exportar ni compartir sus claves/certificados para este paso.
4. Esperar a que Apple procese el build. En **TestFlight**, completar los datos beta y las preguntas de cumplimiento que Apple solicite. Las respuestas deben corresponder al uso real de la app; no se predeclaran desde el código.
5. Para el propio administrador, usar el grupo de testers internos cuando su cuenta tenga el rol requerido en App Store Connect. Para integrantes del equipo que solo necesitan usar JAC, crear un grupo de **testers externos** e invitarlos por correo o enlace. La primera beta externa debe pasar la revisión de Apple; no dar roles de administración/desarrollo solo para instalar.
6. Cada persona instala **TestFlight** desde App Store y abre la invitación en el iPhone/iPad. Después puede instalar y actualizar JAC por internet. No necesita conectar su dispositivo al Mac para cada actualización.

Alternativas: la distribución Ad Hoc conserva el uso privado con dispositivos registrados y exige UDID/perfiles y renovaciones. La instalación desde Xcode por Wi‑Fi requiere emparejar primero el dispositivo; no sustituye una distribución de actualizaciones al equipo. No hay una IPA firmada de distribución creada por estas comprobaciones de CI: los certificados y la firma permanecen en el Mac/cuenta de Camilo.

## 3. Preparar Apple Wallet

Para convertir un PDF en un pase propio de JAC se necesita una integración adicional de lectura del código, construcción/firma del paquete y el botón nativo de PassKit. Si la aerolínea entrega su `.pkpass` original, importar ese archivo firmado conserva su emisor y evita reconstruir el código. El servidor actual todavía no acepta ese tipo de adjunto.

1. En **Apple Developer → Identifiers → + → Pass Type IDs**, registrar un identificador propio, por ejemplo `pass.co.jacmusic.nomina`, si está disponible. No cambia el bundle de la app.
2. En el Mac, abrir **Acceso a Llaveros → Asistente de Certificados → Solicitar un certificado de una autoridad de certificación**. Guardar el CSR en disco, conservar la clave privada en el Llavero y usar el CSR para crear el **Pass Type ID Certificate** del identificador anterior.
3. Descargar e instalar el certificado. Para la firma futura del servidor se necesitarán certificado, clave privada correspondiente y cadena intermedia WWDR válida. Conservar el material privado fuera de Git; aún no hay en JAC un formulario de conexión Wallet donde cargarlo. No copiarlo al chat ni sustituir por la clave `.p8` de APNs: son materiales distintos.

La integración debe mantener acceso exclusivo al destinatario, archivo/revisión y validación de sesión; conservar PDF y Mostrar código, tratar varios códigos con selección explícita y no inventar datos de vuelo o códigos desde nombre/ruta/fecha. Un pase firmado por JAC no se convierte en un pase emitido por la aerolínea ni garantiza aceptación en lectores de aeropuerto. El archivo original debe seguir accesible. Wallet administra sus copias fuera de la caché de JAC; retirar acceso o cerrar sesión no retira automáticamente un pase ya añadido.

Presentar `PKAddPassesViewController` para agregar un pase válido no requiere por sí solo habilitar el entitlement Wallet de gestión de pases. No añadir capacidades de consulta de `PKPassLibrary` ni Associated Domains solo para resolver la instalación o las notificaciones.

Referencias de Apple: [TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/), [crear una clave privada](https://developer.apple.com/help/account/keys/create-a-private-key/), [Pass Type ID](https://developer.apple.com/help/account/capabilities/create-wallet-identifiers-and-certificates), [certificados de Wallet](https://developer.apple.com/help/account/capabilities/create-wallet-identifiers-and-certificates).
