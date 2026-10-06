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

## Preparar entorno Cloud

Node.js 24 LTS; `npm ci`; `npx tsc --noEmit`; `node --test tests/payroll.test.mjs tests/payroll-auth.test.mjs tests/payroll-mail.test.mjs`; `npm run build`. Para vista local `npm run dev`, D1 local y claves de desarrollo ignoradas, nunca credenciales reales. Para desplegar conecta Sites al mismo proyecto. Si falta ese acceso, deja cambios revisables e indica el bloqueo. Comprueba publicación del entorno Cloud y primera ejecución antes de afirmar que está listo.
