# Contexto de Nómina JAC Music

## Objetivo y estado

Aplicación de pagos de shows y nómina administrativa activa en https://jhonalexcastano.com. Sustituyó una página de cumpleaños. Camilo quiere continuar desarrollándola desde Codex Cloud y el teléfono. Esta copia proviene del commit desplegado `0d26668b0b3361e18b5a471f955cbc4e2a682207`, versión 16 del Site `appgprj_6aa0260b82a88191a47960614238350a`. GitHub/Cloud no transfieren automáticamente la base D1, los secretos, el acceso de publicación ni las conexiones de producción. Este documento conserva el contexto; no es un traslado literal del hilo local.

## Condiciones acordadas

- Músicos: $750.000/show; Mauricio, director: $2.000.000/show, con ajuste manual por participante y evento. Las ventas no determinan los honorarios.
- Técnica: tarifas editables por persona, iniciales de las nóminas de septiembre. No inventar reglas nuevas para diferencias entre shows.
- Victor y Nicolás inactivos; Yonier y Fernando los reemplazan con las condiciones respectivas. Andrés Ricardo Rey sigue incluido.
- Jenny: pago mensual. Javier: sin AFP por devolución de saldos.
- Ensayo: $80.000 editable. Pasaje Manizales-Pereira: $18.000 por trayecto; $180.000 era un error.
- Conductores: misma ruta, un kilometraje por show y pagos automáticos a ambos. Mariano: $1.250/km más salario; Jhon Fredy Zambrano: $1.000/km. Permite kilometraje extra ajeno a shows.
- Administración: base habitual más novedades; siete categorías de horas. Divisor inicial 210 y factores editables 0,35 / 0,90 / 1,25 / 1,25 / 1,75 / 2,15 / 2,65. No actualizar automáticamente salarios ni reglas por cambio de año.
- Comisiones manuales; no porcentaje automático de ventas. Sin transferencias bancarias ni nómina electrónica DIAN.

## Funciones existentes

Personal y conceptos editables. Eliminar empleados conserva su historia. Shows/ventas/honorarios, rutas compartidas, extras, horas y descuentos. Cierres con instantáneas de cálculo y condiciones históricas.

Exporta resumen PDF, desprendibles individuales y conjuntos, ZIP y Excel de siete hojas con fórmulas. Después del cierre permite buscar y seleccionar un empleado para imprimir su desprendible individual. Desplegables con fondo blanco.

Reabrir/corregir conserva versiones anteriores. Camilo puede otorgar/revocar `modifyClosed` desde Usuarios para reabrir, corregir y volver a cerrar períodos restringidos. No otorgarlo automáticamente a Luisa o Paula; permisos normales para períodos nuevos son independientes. Los cambios de permisos invalidan sesiones e invitaciones.

Camilo puede eliminar completamente una quincena desde resumen o Archivo con confirmación explícita. API elimina el período y todos sus lotes/trabajos de correo, conserva otras quincenas/configuración y bloquea el borrado si hay envío reciente en curso. No retira correos enviados ni archivos descargados. El guardado normal no puede borrar períodos. Es válido tener cero quincenas y crear otra con las mismas fechas. Esta fue la última función añadida; el agente no borró cierres reales para probarla.

## Acceso y correo

Login propio en `/acceso`, independiente de ChatGPT después de inicializar al propietario. Camilo: `camilo@mac2you.co`; Luisa: `info@jacmusic.co`; Paula: `contabilidad@jacmusic.co`. Solo propietario administra usuarios, conexión Gmail y eliminación completa de quincenas. Los usuarios activos pueden consultar nómina.

Permisos: `payroll`, `staff`, `rules`, `close`, `send`, `export`, `modifyClosed`, obligatorios en servidor además de interfaz. Propietario protegido contra degradación. Invitación individual de un solo uso/24 horas mediante `/acceso#activacion=TOKEN`; no guardar enlaces reales en Git.

Camilo pidió permitir cualquier contraseña no vacía, incluso uno/dos caracteres: no reintroducir restricciones sin cambio de requisito. Sigue almacenamiento seguro con scrypt, sal y secreto separado; sesión 12 horas, cookie HttpOnly/Secure/SameSite=Lax, tokens resumidos, límites de intentos y comprobación de origen.

Gmail conectado en producción: `jacmusicestudios@gmail.com`. El cierre prepara envío de PDF individual a cada empleado con correo. Lotes idempotentes por cierre; errores de resultado incierto no se reenvían automáticamente. Correcciones generan nuevo lote conservando anteriores. Desplegar no envía cierres antiguos. Credenciales OAuth cifradas en D1 con `PAYROLL_MAIL_KEY`; `PAYROLL_AUTH_KEY` independiente. No copiar claves ni conexión real a pruebas.

## Arquitectura y mantenimiento

React/Vinext, TypeScript, Vite, Cloudflare Workers/D1, Drizzle, pdf-lib y fflate. UI: `app/payroll-app.tsx`, `users-panel.tsx`, `auth-form.tsx`. API: `app/api/payroll/`, `app/api/users/route.ts`, `app/api/auth/route.ts`. Cálculo/políticas: `lib/payroll.ts`, `payroll-schema.ts`, `payroll-policy.ts`, `payroll-permissions.ts`. Persistencia: `payroll-store.ts`; autenticación: `payroll-auth-store.ts`, `payroll-auth-crypto.ts`, `payroll-access.ts`; correo/exportación: `payroll-mail.ts`, `payroll-mail-core.ts`, `payroll-export.ts`. Datos iniciales privados: `payroll-seed.ts`. Esquema: `db/schema.ts`, migraciones `drizzle/0000`–`0006`.

Estado global/revisión en `payroll_state`, períodos separados en `payroll_periods`, compare-and-swap/nonce para impedir escrituras parciales obsoletas. Correo: `payroll_mail_batches`/`payroll_mail_jobs`; usuarios/sesiones/invitaciones/límites propios. Conserva estas protecciones.

Última versión pasó TypeScript, compilación y 30 pruebas de cálculo, autenticación y correo. Borrado probado en bases simuladas: limpieza de lotes históricos, rechazo a no propietarios, versión obsoleta, envío en curso, cero períodos y creación posterior. UI comprobada con propietario/no propietario y sin quincenas. Algunas pruebas integradas heredadas aún describen el bootstrap anterior; no ejecutarlas contra producción.

## Aplicación para iPhone

El nombre visible en el iPhone es **JAC** y su icono es el símbolo azul sobre fondo blanco elegido por Camilo. La imagen opaca de 1024 × 1024 está en `ios/JACNomina/Assets.xcassets/AppIcon.appiconset` y se usa en Debug y Release. Las actualizaciones nativas se instalan desde Xcode sobre `co.jacmusic.nomina`.

Camilo pidió una app nativa para iPhone conectada a las mismas cuentas y D1 del webapp. Vive en `ios/`, SwiftUI para iOS 17+, proyecto `ios/JACNomina.xcodeproj`, esquema `JACNomina`, sin WebViews. La ampliación de paridad incorpora creación y edición de quincenas, shows, novedades, kilómetros y horas; archivo, pagos y documentos/impresión; personal, conceptos y reglas; cierre, reapertura y corrección con condiciones históricas; borrado exclusivo del propietario; correos/Gmail; usuarios, permisos, invitaciones y activación de cuentas. Consulta `ios/PARITY.md`.

Las API móviles conservan cálculos y políticas en el servidor. `GET /api/mobile/payroll?workspace=1` entrega la revisión consistente; `?period=ID` entrega detalle, condiciones históricas y templates de edición. `POST` recibe un comando por formulario y delega las acciones originales después de validar permisos, esquema e historial. `previewEdit` es de solo lectura. La app no reconstruye ni sobrescribe snapshots; CAS y nonces se conservan. Un conflicto deja una solicitud pendiente en memoria con respaldo JSON temporal solicitado por el usuario.

Gmail nativo usa Apple AuthenticationServices, un ticket de dos minutos/de un uso, guard de navegador y nonce de retorno `jacnomina://gmail`. El servidor revalida la sesión del propietario y conserva el OAuth/PKCE, cuenta Gmail y callback originales. No se entrega al navegador una sesión de nómina ni se agregan secretos o tablas. La sesión de iPhone permanece en Llavero y los documentos son temporales.

Camilo confirmó que tiene Mac y Apple Developer y que solo usarán la app tres personas. No necesita publicación en App Store: instalación con Xcode o distribución ad hoc a dispositivos registrados; TestFlight es alternativa de beta, con builds de 90 días. La firma se hace con su cuenta en su Mac, nunca copiando certificados o contraseñas al repositorio. Guía completa en `ios/README.md`.

CI en `.github/workflows/ios.yml` compila y ejecuta las pruebas nativas en macOS, con red simulada y sin consultar producción. Las pruebas de la API móvil y OAuth están en `tests/payroll-mobile.test.mjs` y `tests/payroll-mobile-oauth.test.mjs`, con D1 en memoria y sin tráfico real a Google. Las pruebas de edición/archivo/roles usan fixtures DEBUG `.invalid`; Release las excluye. No ejecutes pruebas de edición, borrado o correo contra producción.

El 6 de octubre de 2026, Camilo informó una pantalla en blanco en el simulador con Xcode 27.0. Tras limpiar la compilación, seguía abierta en blanco; confirmó que el formulario apareció al desmarcar **Debug executable** en **Product > Scheme > Edit Scheme > Run > Info**. Ese ajuste local permite continuar y se documenta en `ios/README.md`; no se desactiva el depurador globalmente en el esquema compartido. Las comprobaciones de arranque y regreso a la app pasaron en Xcode 16.4/iOS 18.5 y Xcode 26.3/iOS 26.2. CI conserva capturas y el `.xcresult`; Xcode 27.0 no está instalado en el runner actual.

## Agenda de Google Calendar en web e iPhone

Camilo pidió un calendario interno para conocer los conciertos y compromisos de Jhon Alex, sincronizado con `jacmusicestudios@gmail.com`, tanto en el webapp como en la app nativa. **Agenda** aparece en el sidebar web y como pestaña del iPhone; **Mi cuenta** se encuentra dentro de **Gestión** en iPhone. La versión nativa es 0.3.0/build 4.

Ambas interfaces consultan la misma selección de Google Calendar: mes de 42 días, eventos del día y próximos 90 días, detalles de fecha/hora/lugar/descripción y enlace seguro al evento. Se actualiza al abrir, volver tras 30 segundos o pulsar actualizar. Se usa `America/Bogota`, incluidos eventos de varios días, fin exclusivo de eventos de todo el día y recurrencias expandidas por Google. Los eventos se crean/editan en Google Calendar; JAC tiene permiso de lectura y no los convierte automáticamente en shows de nómina.

Preparación de Camilo: activar **Google Calendar API** en el mismo proyecto de Google ya utilizado para Gmail; abrir **Agenda → Conexión**, autorizar `jacmusicestudios@gmail.com` y seleccionar el calendario de Jhon Alex. Una autorización/selección sirve para web y los tres iPhones. No afirmar que la cuenta está conectada o que sus eventos reales fueron verificados antes de que Camilo complete ese consentimiento. No se solicitan claves ni tokens por el chat.

`GET /api/calendar?month=YYYY-MM` exige una cuenta propia activa; el calendario elegido es consultable por todos los usuarios activos. Listar calendarios, autorizar, elegir y desconectar requiere propietario y origen válido en operaciones POST; elegir/desconectar usa revisión CAS. Se reutilizan el client ID/secret cifrados de Google ya configurados en Correos y el callback registrado `/api/payroll/gmail/callback`. La autorización independiente solicita `openid email calendar.readonly`, verifica cuenta y scope y guarda su propio refresh token cifrado con `PAYROLL_MAIL_KEY` en `payroll_calendar` (nueva migración `0007`). No modifica la conexión ni tokens de Gmail, los cálculos o la nómina. Desconectar Agenda elimina solo esa conexión local y no llama a revoke de Google.

OAuth web usa guard HttpOnly/Secure/Lax y la sesión propia del propietario. iPhone usa AuthenticationServices, ticket de dos minutos/de un uso, guard independiente y retorno `jacnomina://calendar` con nonce; no comparte la sesión de nómina con el navegador. Ambos revalidan sesión activa y revisión/configuración antes de guardar. Los datos no incluyen tokens, se sirven sin caché y las peticiones de Google se limitan a endpoints fijos, paginación y campos de eventos necesarios.

Pruebas adicionales: `tests/calendar.test.mjs` comprueba acceso, origen, OAuth web/nativo, PKCE, cuenta/scope, cifrado, expiración/revocación/replay, selección CAS, paginación/recurrencias, errores de Google, cambios concurrentes, fechas y desconexión sin modificar Gmail. Usan SQLite en memoria y Google simulado. CI nativa comprueba modelo/horarios/nonce y navegación de Agenda, detalles, próximos, cuenta y consulta sin acciones del propietario con fixtures DEBUG `.invalid`.

Camilo informó un fallo al autorizar Agenda desde `jhonalexcastano.com` después de seleccionar la cuenta y aceptar en Google. La conexión no se guardó; el mensaje anterior agrupaba todas las causas. El callback ahora devuelve un motivo fijo (`reason`) y registra únicamente ese motivo y el modo web/nativo, sin códigos, tokens, URLs OAuth ni respuestas de Google. La web muestra instrucciones específicas mediante `lib/calendar-oauth-errors.ts`; ignora texto arbitrario recibido en la URL. Se distinguen permiso Calendar no concedido, falta de refresh token, rechazo del cliente/código por Google, verificación de cuenta, sesión, concurrencia y guardado. Se mantienen guard, PKCE, consumo de un uso, revalidaciones y conexión de Gmail independiente. Las pruebas simulan estos fallos y comprueban que ni los logs ni el retorno filtran secretos. La causa real requiere un nuevo intento de consentimiento de Camilo; no declarar Agenda conectada basándose únicamente en estas pruebas.

## Preparar entorno Cloud

Node.js 24 LTS; `npm ci`; `npx tsc --noEmit`; `node --test tests/payroll.test.mjs tests/payroll-auth.test.mjs tests/payroll-mail.test.mjs`; `npm run build`. Para vista local `npm run dev`, D1 local y claves de desarrollo ignoradas, nunca credenciales reales. Para desplegar conecta Sites al mismo proyecto. Si falta ese acceso, deja cambios revisables e indica el bloqueo. Comprueba publicación del entorno Cloud y primera ejecución antes de afirmar que está listo.

## Incidencia de instalación limpia detectada durante la paridad

Las dependencias ya preparadas permiten TypeScript, build y las 37 pruebas requeridas del servidor. Un `npm ci` nuevo en GitHub y en una copia temporal de los manifiestos falla por entradas heredadas incompletas de dependencias opcionales WASI (`@emnapi/core`, `@emnapi/runtime`, `@emnapi/wasi-threads`); también se comprobó con npm 10 y 11. No se cambió el lockfile, package.json ni la instalación preparada para esta entrega. La CI nativa de Xcode no necesita Node. Antes de preparar otro entorno Node desde cero, deberá repararse y verificarse por separado el lockfile heredado. No declarar que una instalación limpia pasó mientras continúe esta incidencia.
