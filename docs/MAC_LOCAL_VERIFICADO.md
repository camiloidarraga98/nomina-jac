# Comprobación local de JAC — 6 de octubre de 2026

**Actualización posterior:** se corrigió y verificó localmente el fallo de segundo plano descrito abajo. La versión final pasa 23 pruebas unitarias y 10 de interfaz en otro simulador nuevo. Se conserva la navegación y la privacidad protege también las hojas abiertas. El diagnóstico original se mantiene como evidencia histórica; ver [causa, corrección y comprobaciones](IOS_REGRESO_SEGUNDO_PLANO.md). La firma del iPhone sigue pendiente de la aprobación de Apple.

La carpeta de trabajo es `/Users/camiloidarraga/Documents/Proyectos/JAC`, sobre macOS 27.0 (26A428), con ejecución de comandos y compilaciones en este Mac. No se crearon trabajos Cloud ni se usó GitHub/Actions. La etiqueta visual Local/This computer no pudo inspeccionarse desde la herramienta de interfaz de Codex; la ruta y ejecución macOS sí se comprobaron directamente.

## Herramientas y arranque web

- Node/npm no estaban en el PATH general. Se instaló la distribución oficial ARM64 Node 24.21.0/npm 11.19.0 bajo `work/local/toolchain/`, sin modificar instalaciones ni configuración global.
- Archivo oficial: `node-v24.21.0-darwin-arm64.tar.gz`. SHA-256 verificado contra `SHASUMS256.txt` de nodejs.org: `bed7eea5325e1108f32ce5228ddd6a5f0f08a499ee42aa7442aea583702f6057`.
- `scripts/local-env.sh` permite ejecutar las herramientas desde esta carpeta y mantiene logs/registro Workerd locales. El runtime y sus descargas quedan ignorados por Git, bajo `work/`.
- `scripts/prepare-local.mjs` ejecutado con Node 24. Creó dos claves aleatorias independientes en `.dev.vars`, con permisos 0600. No se mostraron ni se copiaron claves reales.
- Migraciones 0000–0008 aplicadas con `--local`, ID de base de desarrollo y persistencia `.wrangler/state`. R2 también es emulado localmente. No se aplicaron migraciones remotas.
- Vite responde en `http://127.0.0.1:5173`. `/acceso?configurar=1` devolvió HTTP 200 y mostró «Tu acceso propio». El usuario puede crear allí su acceso de desarrollo; no se eligió una contraseña por él.

Desde la raíz del proyecto:

```sh
scripts/local-env.sh node -v
scripts/local-env.sh npm ci
scripts/local-env.sh node scripts/prepare-local.mjs
scripts/local-env.sh npx --no-install wrangler d1 migrations apply site-creator-d1 --local --persist-to .wrangler/state --config work/local/wrangler.json
scripts/local-env.sh npm run dev -- --host 127.0.0.1
```

Node/npm están en una carpeta ignorada, no son parte de una entrega de fuente. Si se restaura el proyecto en otro Mac, instala Node 24 oficial o prepara de nuevo el runtime local antes de esos comandos.

## Reparación mínima del lockfile

El primer `npm ci` falló por dependencias opcionales WASI incompletas. Se añadieron únicamente estas dos entradas a `package-lock.json`:

| Entrada | Versión | Motivo |
| --- | --- | --- |
| `node_modules/@emnapi/core` | 1.10.0 | Versión exacta ya requerida por `@rolldown/binding-wasm32-wasi@1.0.1` |
| `node_modules/@emnapi/runtime` | 1.10.0 | Mismo requisito exacto; satisface también los rangos existentes |

Los metadatos y sumas de integridad proceden del registro oficial npm para esas versiones. `core@1.10.0` requiere `@emnapi/wasi-threads@1.2.1`, que ya estaba fijado. No hizo falta cambiarlo. Una comparación JSON verificó que todas las entradas anteriores conservan exactamente su contenido: solo dos entradas nuevas, 22 líneas añadidas. `package.json` no cambió; no se borró el lockfile ni se ejecutó `npm update`.

`npm ci` posterior instaló 682 paquetes y salió con código 0. npm 11.19 avisó que no ejecutaba scripts de instalación no autorizados; los binarios empaquetados permitieron ejecutar D1/Workerd, pruebas y build correctamente. Un intento de `npm rebuild --allow-scripts=…` fue rechazado por npm sin modificar la configuración o los manifiestos; no fue necesario habilitar scripts para las comprobaciones que pasaron.

## Comprobaciones web que pasaron

- `npx --no-install tsc --noEmit`.
- `node --test tests/payroll.test.mjs tests/payroll-auth.test.mjs tests/payroll-mail.test.mjs`: 33/33.
- `node --test tests/payroll-mobile.test.mjs tests/payroll-mobile-oauth.test.mjs tests/calendar.test.mjs tests/calendar-worker.test.mjs tests/notifications.test.mjs tests/notifications-worker.test.mjs`: 41/41.
- `npm run build`.

Pruebas con bases en memoria, servicios simulados y salidas Workerd interceptadas. La web local no tiene conexiones Gmail, Calendar, Slack o APNs reales. Los logs y el estado local quedan bajo `work/`, `.wrangler/` y `.sites-runtime/`, ignorados por Git.

## Xcode e iPhone

Xcode 27.0 (27A266a), seleccionado en `/Applications/Xcode.app/Contents/Developer`. Proyecto `ios/JACNomina.xcodeproj`, esquema `JACNomina`, versión 0.5.0/build 6, identificador `co.jacmusic.nomina`, nombre e icono JAC conservados.

La compilación de simulador pasó con firma ad hoc (`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`), sin certificados Apple Developer. Las 23 pruebas unitarias pasaron. La primera suite de interfaz tuvo 6/8 aprobadas: fallaron acceso y creación/edición de Agenda. Se repitieron los dos casos; siguieron fallando, incluso con un esquema temporal local sin depurador y un intento de ajustar el aislamiento/espera de la automatización. Esos experimentos se retiraron; el esquema compartido y las pruebas originales están intactos.

El simulador preexistente tenía una sesión guardada: el caso de acceso y un lanzamiento directo abrieron una nómina existente. Se detuvo la app; no se ejecutaron sobre esos datos acciones de cierre, borrado, correo, calendario, PDF o alertas. Las pruebas que optan por `--uitest-payroll` usaron sus fixtures `.invalid`. Para evitar esa sesión, se creó **JAC local - pruebas aisladas**, iPhone 18 Pro/iOS 27.0, y se repitieron todas las pruebas originales. No se borró ni reinicializó el simulador anterior.

**Resultado aislado definitivo:** 23/23 unitarias y 7/8 de interfaz. Agenda, edición de actividades, cierres/archivo, permisos, PDF y alertas pasaron con fixtures. La prueba de acceso mostró el formulario, permitió escribir y comprobó el regreso, pero Xcode detectó un cierre de la app. La repetición de ese único caso sin depurador también falló al regresar desde segundo plano. El diagnóstico contiene `NSInternalInconsistencyException` en `UINavigationBar.layoutSubviews`: el elemento superior pertenece a otra barra de navegación (`Nómina JAC`). No se atribuye el cierre a los avisos genéricos de Apple ni se declara resuelto por desactivar el depurador. No se modificó el código de aplicación ni se debilitaron las pruebas para hacerlo pasar.

Evidencia local, ignorada por Git: `work/local/ios-clean-simulator.log`, `work/local/ios-clean-simulator.xcresult`, `work/local/ios-clean-diagnostics/`, `work/local/ios-clean-screenshots/` y `work/local/ios-clean-login-no-debug.log`. Las capturas de inicio/regreso están en el manifiesto de las capturas. Queda pendiente corregir o resolver este fallo de ciclo de vida de SwiftUI/iOS 27 antes de afirmar que la interfaz nativa completa está verificada.

La cuenta de Xcode solo muestra Personal Team. Camilo confirmó que ya pagó la suscripción y espera aprobación de su documentación legal. La instalación firmada en el iPhone queda pendiente de Apple. El iPhone de Camilo aparece disponible y emparejado. No se seleccionó Personal Team ni se cambió el identificador para sortear la firma.

Cuando Apple active la membresía:

1. Abre Xcode → Settings → Apple Accounts y comprueba que aparezca el equipo de pago en la cuenta de la membresía.
2. Abre este proyecto, target JACNomina → Signing & Capabilities. Conserva firma automática, `co.jacmusic.nomina` y Push Notifications; selecciona ese equipo.
3. Selecciona tu iPhone como destino, acepta confianza/Modo de desarrollador en el teléfono si se solicita y pulsa Run. Actualiza sobre la app existente.
4. Completa tú cualquier inicio de sesión, permiso del Llavero o acuerdo legal que solicite Apple. No copies certificados, claves `.p8` o contraseñas al repositorio.

La app normal consulta producción. Las pruebas de cambios deben continuar con fixtures; instalarla no autoriza ensayos de cierre, eliminación o envío reales. La pantalla en blanco con depurador de Xcode 27 tiene la guía existente en `ios/README.md`.

Para repetir las pruebas nativas, crea siempre un simulador nuevo; no reutilices uno donde hayas iniciado sesión en producción. En este Xcode las identificaciones disponibles son `com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro` y `com.apple.CoreSimulator.SimRuntime.iOS-27-0`:

```sh
JAC_TEST_SIM=$(xcrun simctl create 'JAC pruebas locales' com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-0)
xcodebuild -project ios/JACNomina.xcodeproj -scheme JACNomina \
  -destination "platform=iOS Simulator,id=$JAC_TEST_SIM" \
  -derivedDataPath work/ios-build -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
```

Esas órdenes se ejecutan en el Mac. No necesitan GitHub, certificados de firma ni una conexión de servicios reales. No inicies sesión en producción en el simulador de pruebas.

## Sites y futuras publicaciones

Las herramientas Sites están disponibles y la lectura autenticada del proyecto existente funcionó. La cuenta de Camilo tiene rol **owner**; Site activo, URL `https://jhonalexcastano.com`, versión 25, commit `73b2cc223907d0c80b03beae92d16cf9bcc95a3c`. No hace falta conectar otro plugin para esa lectura. Esto no verifica aún una escritura o despliegue desde el Mac: no se solicitaron credenciales de publicación ni se ejecutaron esas acciones.

La preparación no publica. Antes de la primera publicación local, volver a leer el mismo Site y explicar los archivos cambiados. Actualizar exclusivamente `appgprj_6aa0260b82a88191a47960614238350a` mediante el flujo de Sites. Conservar `.openai/hosting.json`, DB, BUCKET, secretos y conexiones. Nunca subir `.dev.vars`, bases/estado de localhost, sesiones o exportaciones; nunca reemplazar datos reales con los locales ni crear otro Site o cambiar DNS.

Se inició Git exclusivamente local, rama `local`, con una versión inicial y sin remotos. La base conserva el paquete recibido; el commit local no pretende ser el commit original de Sites, cuyo historial no venía en el ZIP.

Los cambios finales de preparación se limitan al lockfile, `scripts/local-env.sh` y la documentación de continuidad. Los archivos de aplicación, cálculos, permisos, API, migraciones, diseño, logo, proyecto/esquema iOS y manifiesto de hosting permanecen iguales a la base local recibida.

El traslado no se declara terminado: la firma e instalación física requieren aprobación de Apple y la validación completa de interfaz debe quedar resuelta.
