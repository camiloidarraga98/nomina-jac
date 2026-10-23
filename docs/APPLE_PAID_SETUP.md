# Cuenta Apple de pago: instalación, push y Wallet

Camilo confirmó el 22 de octubre de 2026 que su membresía de Apple Developer Program está lista y pidió instalación inalámbrica, reactivar las notificaciones y retomar Apple Wallet. Esto sustituye la suspensión de push y el aplazamiento de Wallet; no modifica permisos de cuentas JAC ni conexiones existentes.

## Estado de esta preparación

El mismo proyecto `ios/JACNomina.xcodeproj`, esquema `JACNomina`, bundle `co.jacmusic.nomina`, selecciona ahora `JACNominaPush.entitlements`, habilita Push Notifications y usa `JAC_PUSH_ENABLED=YES` en Debug y Release. Se conservan `APNS_ENVIRONMENT=development` para ejecución desde Xcode y `production` para Archive/TestFlight. Camilo confirmó que la membresía de pago conserva el Team ID `AYHVYN8BJF`, ya guardado en el proyecto. No se ha consultado su cuenta Apple desde este entorno.

El servidor ya permite guardar la clave APNs cifrada desde el formulario privado de JAC. Activar la capacidad de Xcode no crea esa clave, regenera un perfil firmado, instala una app ni confirma recepción real. No se requiere volver a publicar la web para esta reactivación.

Actualización del23 de octubre: Camilo confirmó instalación por TestFlight de0.27.0(40) y recepción real de APNs. Se incorpora Wallet en una entrega posterior al build40; ver [integración, conexión privada y estado de verificación](APPLE_WALLET.md). El código/documento original se conserva. No confundir la confirmación física de push con una prueba de Wallet.

## 1. Habilitar la firma y las notificaciones

1. En [Apple Developer → Membership details](https://developer.apple.com/account), verificar que la membresía figure activa; el **Team ID** del equipo de pago confirmado por Camilo es `AYHVYN8BJF`. Aceptar cualquier acuerdo pendiente que Apple muestre.
2. En **Certificates, Identifiers & Profiles → Identifiers**, seleccionar o registrar el App ID explícito `co.jacmusic.nomina` en ese equipo y habilitar **Push Notifications**. Si el identificador pertenece a otro equipo, resolver primero su disponibilidad; no cambiar el bundle unilateralmente porque también es el topic del servidor.
3. En **Keys → +**, crear una clave de **Apple Push Notifications service (APNs)** que cubra el topic `co.jacmusic.nomina` y **Production** para TestFlight. Si Apple ofrece **Sandbox & Production**, esa configuración permite usar también Run/Debug. Revisar las restricciones Team Scoped/Topic Specific antes de confirmar; una clave limitada a Production no habilita los avisos de un binario Debug/sandbox. Descargar el archivo `.p8`, anotar su **Key ID** y conservarlo fuera del repositorio. Apple solo permite descargarlo una vez.
4. En JAC web, iniciar sesión como Camilo y abrir **Configuración general → Servicios conectados → Notificaciones del iPhone**. Ingresar Team ID, Key ID y el archivo `.p8` en ese formulario HTTPS y guardar. No enviar el archivo por chat ni subirlo a GitHub. La clave de APNs no es una credencial de acceso a App Store Connect.
5. Hacer pull en el mismo Xcode. En el target JACNomina, **Signing & Capabilities**, seleccionar el equipo de pago, mantener **Automatically manage signing** y comprobar **Push Notifications**. Xcode debe crear/renovar los perfiles con `aps-environment`. Si el Team ID cambió, conservarlo también en la fuente para que el siguiente pull no lo retire.
6. JAC conserva una única clave APNs en esta conexión; guardar otra sustituye la anterior. Tras instalar el binario nuevo, entrar en JAC y permitir las notificaciones. Revisar también **Gestión → Notificaciones** y los ajustes de iOS. Repetir por dispositivo. Camilo confirmó recepción física de APNs después de esta configuración; las pruebas automáticas usan proveedores interceptados y nunca envían un aviso real.

## 2. Instalar y actualizar sin cable mediante TestFlight

TestFlight permite distribuir la beta sin publicar una ficha disponible en la tienda. Cada build dura hasta 90 días: subir uno nuevo antes de que venza. Los usuarios conservan sus permisos de JAC; ser tester no concede administración dentro de la app.

1. En [App Store Connect](https://appstoreconnect.apple.com/), abrir **Apps → + → New App**. Elegir iOS, un nombre disponible, idioma español y el bundle `co.jacmusic.nomina`. Un SKU interno posible es `JAC-IOS`; debe ser único en esa cuenta.
2. En el mismo Xcode, seleccionar **Any iOS Device (arm64)** o el destino genérico de iOS y usar **Product → Archive**. No elegir un simulador para el archivo de distribución. Si ya existe un build con el mismo número, incrementar el build antes de subir.
3. En **Organizer → Distribute App → App Store Connect → Upload**, usar la firma automática del equipo de pago y completar la validación de Xcode. No exportar ni compartir sus claves/certificados para este paso.
4. Esperar a que Apple procese el build. En **TestFlight**, completar los datos beta y las preguntas de cumplimiento que Apple solicite. Las respuestas deben corresponder al uso real de la app; no se predeclaran desde el código.
5. Para el propio administrador, usar el grupo de testers internos cuando su cuenta tenga el rol requerido en App Store Connect. Para integrantes del equipo que solo necesitan usar JAC, crear un grupo de **testers externos** e invitarlos por correo o enlace. La primera beta externa debe pasar la revisión de Apple; no dar roles de administración/desarrollo solo para instalar.
6. Cada persona instala **TestFlight** desde App Store y abre la invitación en el iPhone/iPad. Después puede instalar y actualizar JAC por internet. No necesita conectar su dispositivo al Mac para cada actualización.

Si en Bundle ID solo aparece `co.jacmusic.nomina.uitests`, ese identificador corresponde a las pruebas y no se debe seleccionar para distribuir JAC. Registrar primero **Identifiers → + → App IDs → App**, descripción JAC y Bundle ID **Explicit → `co.jacmusic.nomina`**, con Push Notifications. Después recargar App Store Connect y seleccionar el identificador principal. No cambiar el bundle del proyecto para hacerlo coincidir con el de las pruebas.

Alternativas: la distribución Ad Hoc conserva el uso privado con dispositivos registrados y exige UDID/perfiles y renovaciones. La instalación desde Xcode por Wi‑Fi requiere emparejar primero el dispositivo; no sustituye una distribución de actualizaciones al equipo. No hay una IPA firmada de distribución creada por estas comprobaciones de CI: los certificados y la firma permanecen en el Mac/cuenta de Camilo.

## 3. Conectar Apple Wallet

Usar el identificador original **Apple Wallet → `pass.co.jacmusic.nomina`**, que la captura de Camilo confirma registrado en su cuenta. El certificado y su clave privada deben aparecer vinculados en el mismo llavero del Mac para exportarlos como `.p12`. Si el certificado se instaló en Sistema y la clave CSR está en Inicio de sesión, importar el `.cer` también en Inicio de sesión. No sustituir el certificado por la clave APNs `.p8`.

El nuevo formulario privado de JAC recibe `.p12`, contraseña y el intermedio público WWDR G4. El flujo nativo conserva el documento y el código original, y solo ofrece añadir códigos compatibles de pases propios. [Pasos completos, límites y estado real](APPLE_WALLET.md). La copia firmada por JAC no equivale a la emitida por la aerolínea y no se retira automáticamente de Wallet al cerrar sesión.

Referencias de Apple: [TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/), [crear una clave privada](https://developer.apple.com/help/account/keys/create-a-private-key/), [Pass Type ID](https://developer.apple.com/help/account/capabilities/create-wallet-identifiers-and-certificates), [certificados de Wallet](https://developer.apple.com/help/account/capabilities/create-wallet-identifiers-and-certificates).


## Verificación de la preparación · 22 de octubre de 2026

Fuente funcional `f4f1990`: verificados configuración Debug/Release, herencia del Team ID, selección de entitlements y sintaxis del workflow. GitHub [39870756871](https://github.com/camiloidarraga98/nomina-jac/actions/runs/39870756871), Xcode16.4/iOS18.5: **Release iPhone sin firma aprobado**, con la configuración real de push y sin override a NO; **cuatro unitarias push aprobadas** y **una UI de solicitud/rechazo del permiso tras iniciar sesión aprobada**. No se ejecutó Mac ni pruebas web/servidor ajenas al cambio. Datos `.invalid`, hooks APNs interceptados y ninguna notificación real.

La otra UI, de indisponibilidad de push, pasó sus comprobaciones de estado, ausencia de permiso/activación y regreso desde segundo plano, pero falló después al tocar el PDF del itinerario. Se investigó el árbol de accesibilidad: vistas de navegación retenidas de Gestión e Itinerarios y una única fila existente pero no tocable. Se intentó volver explícitamente a Gestión y se repitió **solo ese caso** en [39872382232](https://github.com/camiloidarraga98/nomina-jac/actions/runs/39872382232), omitiendo Release y los cinco casos ya aprobados; el tramo de navegación volvió a fallar. El ajuste experimental del recorrido se retiró, conservando todas las aserciones originales. Esa UI queda pendiente: **no se declaran seis casos aprobados ni resuelto un problema de navegación físico**. No se rehizo la navegación como parte de la activación de Apple. Evidencia privada/local en `work/local/apple-paid-ci/`.

La fuente de producto no cambió durante ese diagnóstico; se conservan los resultados aprobados. Actualización posterior: Camilo completó firma/carga de0.27.0(40), instalación por TestFlight y confirmó recepción real APNs. Wallet se incorpora después de ese build y conserva su verificación física pendiente; ver APPLE_WALLET.md. No hubo cambios web/API, migraciones, datos, claves de producción o conexiones.

Camilo creó el registro «JAC App» en App Store Connect; la captura muestra Distribution y la pestaña TestFlight. Antes de subir debe confirmar en App Information el bundle principal `co.jacmusic.nomina`. La ficha de tienda creada por Apple en versión1.0 no implica una compilación ya subida ni obliga a enviar la app públicamente desde Distribution.
