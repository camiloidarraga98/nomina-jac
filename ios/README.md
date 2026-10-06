# Nómina JAC para iPhone

Primera versión nativa en SwiftUI para iOS 17 o posterior. Usa las mismas cuentas y la misma base D1 que https://jhonalexcastano.com a través de HTTPS. No contiene WebViews ni otra base de nómina.

## Funciones de esta entrega

- Acceso con el usuario/correo y contraseña actuales, restauración de sesión de 12 horas y cierre de sesión.
- Consulta y búsqueda de quincenas abiertas y cerradas, resumen y desglose por persona.
- Consulta de shows, honorarios, recorridos compartidos/anteriores, novedades y siete categorías de horas.
- Personal activo e inactivo y sus condiciones actuales; los pagos históricos muestran la instantánea del cierre.
- Resumen PDF, desprendibles conjuntos e individuales, Excel y ZIP, con vista previa y compartir de iOS. Respeta el permiso `export` y exige cierre.
- Consulta de permisos y cambio de contraseña, conservando la regla de cualquier contraseña no vacía.

La edición de nómina, cierres/correcciones, administración de usuarios y Gmail permanecen en la web en esta primera entrega. No hay botones de edición sin implementar. Se incorporarán a la app en entregas posteriores, reutilizando las API y reglas actuales.

## Abrir y ejecutar en el Mac

1. Clona/actualiza el repositorio privado `camiloidarraga98/nomina-jac` y abre `ios/JACNomina.xcodeproj` con Xcode 16 o posterior.
2. Selecciona el esquema **JACNomina** y un simulador de iPhone para compilar sin certificados.
3. Para un iPhone real, selecciona el target **JACNomina**, abre **Signing & Capabilities**, activa la firma automática y elige tu equipo de Apple Developer.
4. El identificador inicial es `co.jacmusic.nomina`. Si Apple indica que no está disponible para tu equipo, usa otro identificador de tu cuenta antes de la primera instalación y conserva ese identificador para las actualizaciones.
5. Conecta el iPhone al Mac, acepta la confianza del dispositivo, activa **Modo de desarrollador** si Xcode lo solicita y selecciónalo como destino. Pulsa **Run**.
6. Inicia sesión con la misma cuenta del webapp. Las cuentas del equipo se activan con los enlaces que Camilo genera desde Usuarios en la web; no hay registro abierto en la app.

No necesitamos publicar en la App Store. Camilo confirmó que dispone de Mac y Apple Developer.

## Si el simulador queda en blanco o se cierra

Los mensajes `Failed to send CA Event`, `com.apple.PointerUI` y `cannot add handler to 0` proceden de componentes de Apple y, por sí solos, no identifican un cierre de la app. Conserva el mensaje que diga `Thread 1`, `Fatal error`, `Precondition failed` o la excepción, si aparece.

1. Comprueba que abres `ios/JACNomina.xcodeproj` y que el esquema seleccionado es **JACNomina**.
2. Detén la ejecución y usa **Product > Clean Build Folder** (Mayús + Comando + K). Ejecuta otra vez con **Run**.
3. Si continúa, crea un simulador nuevo en **Window > Devices and Simulators > Simulators**. Esto permite comprobar el inicio sin borrar tus otros simuladores.
4. En ese simulador nuevo, sin iniciar sesión, usa **Product > Test** (Comando + U). La prueba de interfaz comprueba que aparecen y se pueden usar los campos de acceso, y que siguen visibles al volver a la app. No envía un inicio de sesión al servidor.
5. Abre **Report Navigator** (Comando + 9), selecciona la última ejecución o prueba y conserva el primer fallo y la pila de llamadas. Indica también la versión de Xcode y del iOS simulado; los avisos de la consola no sustituyen ese diagnóstico.

El workflow de GitHub conserva el resultado `.xcresult` y capturas del arranque en el artefacto **JACNomina-diagnostico-arranque** durante siete días. Las comprobaciones se hacen en un simulador nuevo sin una sesión de producción guardada. La versión de Xcode usada por CI aparece en el primer paso del workflow; una comprobación en otra versión no garantiza compatibilidad con la versión local.

## Instalarla solo en los tres iPhones

Para uso privado, recomendamos distribución **ad hoc** a los tres dispositivos registrados en tu cuenta. Registra sus identificadores en Apple Developer y crea/exporta el archivo firmado desde **Product > Archive** con la opción de distribución a dispositivos registrados. Apple explica el [registro de dispositivos](https://developer.apple.com/help/account/devices/devices-overview) y la [distribución a dispositivos registrados](https://help.apple.com/xcode/mac/current/en.lproj/dev7ccaf4d3c.html). Se necesita renovar la firma/perfil cuando expire y distribuir nuevas versiones firmadas para actualizar la app.

Como alternativa, **TestFlight** facilita instalar y actualizar sin publicar la app en la tienda. Cada build vence a los 90 días; la primera beta para testers externos requiere revisión. Ver [TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/) e [invitación a testers externos](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers).

La firma y los perfiles se gestionan desde tu Mac/cuenta Apple. No se han solicitado ni incluido certificados, claves de Apple, UDID o contraseñas en este repositorio. La entrega de simulador de CI no es un IPA instalable en un iPhone físico.

## Integración y privacidad local

La app autentica mediante `/api/auth` y conserva únicamente la sesión en el Llavero, accesible cuando el dispositivo está desbloqueado y sin sincronización a otros dispositivos. No guarda contraseñas ni archivos JSON de nómina en disco. Usa una URLSession efímera, desactiva cookies/cachés globales y rechaza redirecciones para evitar reenviar credenciales.

`GET /api/mobile/payroll` devuelve el índice de quincenas, personal, usuario y permisos. `GET /api/mobile/payroll?period=ID` añade el detalle con cálculos ejecutados por `lib/payroll.ts`; los cierres conservan sus instantáneas. Solo admite sesiones reales: no acepta el acceso de bootstrap/desarrollo. La ruta es de consulta y no cambia períodos ni dispara correo. La versión compartida de estado acompaña cada respuesta.

Las descargas usan `/api/payroll/export`. Los documentos se guardan temporalmente con protección de archivos de iOS y se eliminan al cerrar la vista, salir de la cuenta o arrancar de nuevo. El contenido se oculta al dejar de estar activa la app para proteger la vista del selector de aplicaciones. Los documentos que el usuario comparta/guarde expresamente quedan bajo su control, igual que las descargas web.

## Validación

El workflow `.github/workflows/ios.yml` compila y prueba en un runner macOS. Las pruebas de red nativas interceptan todas las peticiones con URLProtocol y usan dominios `.invalid`: nunca acceden a producción. La suite `tests/payroll-mobile.test.mjs` usa D1 simulado en memoria, credenciales de prueba y la biblioteca de cálculo existente.

```sh
xcodebuild -project ios/JACNomina.xcodeproj -scheme JACNomina \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

node --test tests/payroll-mobile.test.mjs
```

Este entorno Cloud es Linux. La instalación y firma final en los dispositivos se completan desde Xcode en el Mac. El icono de distribución puede configurarse en Assets antes de exportar una versión para TestFlight; el logo oficial se conserva íntegro en la interfaz nativa.
