# Nómina JAC Music — continuidad Cloud

Lee `docs/PROJECT_CONTEXT.md` antes de modificar el proyecto. Habla con Camilo en español.

- Node.js 24 LTS; instala con `npm ci` y el lockfile existente.
- Verifica con `npx tsc --noEmit`, `node --test tests/payroll.test.mjs tests/payroll-auth.test.mjs tests/payroll-mail.test.mjs` y `npm run build`. Estas pruebas usan bases en memoria y correo simulado.
- Las pruebas integradas con servidor solo pueden apuntar a una instancia local desechable. Nunca uses producción para pruebas de envío o eliminación.
- Mantén las migraciones aplicadas `drizzle/0000` a `0006`; agrega nuevas cuando cambie el esquema.
- La app nativa vive en `ios/`; consulta `ios/README.md`. Conserva cálculos y permisos en el servidor y la sesión móvil en Llavero. Para cambios de su API ejecuta también `node --test tests/payroll-mobile.test.mjs tests/payroll-mobile-oauth.test.mjs`; la compilación y pruebas SwiftUI se validan con el workflow macOS de GitHub. Camilo tiene Mac y Apple Developer; distribución privada a tres iPhones, sin necesidad de App Store.
- Respeta permisos en las API, instantáneas, controles de concurrencia y envíos idempotentes.
- Agenda web/iPhone consulta Google Calendar de `jacmusicestudios@gmail.com` en modo lectura; solo Camilo autoriza y selecciona el calendario, los usuarios activos consultan la agenda compartida. Ejecuta `node --test tests/calendar.test.mjs` al modificarla: D1 en memoria y Google simulado. La conexión cifrada está separada de Gmail en `payroll_calendar`, migración `0007`; no revocar el grant de Google al desconectar Agenda, porque puede invalidar Gmail. Mantén el callback de Google existente y el nonce/PKCE/guard/sesión activa.
- Al modificar las peticiones de Agenda a Google, ejecuta también `node --test tests/calendar-worker.test.mjs`: Workerd local con todas las salidas interceptadas. Cloudflare solo admite `redirect: 'manual'` o `'follow'`; usa `calendarGoogleFetch` con manual y rechazo de 3xx para no reenviar credenciales.
- El dominio es `https://jhonalexcastano.com`, Site existente `appgprj_6aa0260b82a88191a47960614238350a`. Mantén `.openai/hosting.json` y los enlaces D1/R2. No crees otro Site ni cambies DNS para corregir código.
- Cuando Camilo pida un cambio, incorpóralo al repositorio privado y publícalo en el Site existente sin solicitar otra confirmación, salvo que indique expresamente lo contrario.
- Publica mediante el flujo autenticado de Sites y sus habilidades. Si Cloud carece de ese acceso, conserva los cambios para revisión y explica el acceso faltante; no afirmes haber desplegado.
- Nunca guardes credenciales de publicación ni claves reales en archivos. `PAYROLL_MAIL_KEY` y `PAYROLL_AUTH_KEY` se administran en Sites. Usa claves independientes de prueba para desarrollo local.
- El código contiene datos iniciales de personal, documentos y tarifas: repositorio privado. No subas bases de producción, `.env`, `.dev.vars`, sesiones, invitaciones ni exportaciones de nómina.

Esta copia parte del commit de producción `0d26668b0b3361e18b5a471f955cbc4e2a682207`, exportado el 6 de octubre de 2026, con documentación adicional. No contiene historial Git ni datos actuales de la base real. Verifica la publicación y ejecución del entorno Cloud antes de declarar completa la migración.
