# Nómina JAC Music

Aplicación privada de pagos de shows y nómina administrativa activa en https://jhonalexcastano.com. Lee `AGENTS.md` y `docs/PROJECT_CONTEXT.md` para el contexto actualizado, las condiciones acordadas y el flujo de publicación.

## Desarrollo

Node.js 24 LTS recomendado. Consulta la incidencia de instalación limpia del lockfile en `docs/PROJECT_CONTEXT.md`; la validación actual usa las dependencias preparadas del entorno.

```sh
npm ci
npx tsc --noEmit
node --test tests/payroll.test.mjs tests/payroll-auth.test.mjs tests/payroll-mail.test.mjs tests/payroll-mobile.test.mjs tests/payroll-mobile-oauth.test.mjs tests/calendar.test.mjs
npm run build
```

Las pruebas usan bases en memoria y correo simulado. Para vista local usa `npm run dev` con D1 local y claves independientes de desarrollo en archivos ignorados. No pruebes contra producción.

## Funciones

La app nativa de iPhone está en [`ios/`](ios/README.md), con proyecto SwiftUI/Xcode, acceso a las mismas cuentas y funciones de quincenas, pagos, personal, edición, cierres, archivo, usuarios, correo y documentos/impresión. Puede instalarse de forma privada en los tres iPhones registrados de Camilo sin publicarla en App Store. La guía detalla el alcance de esta entrega y la firma desde su Mac.

Personal, tarifas y conceptos editables; shows y ajustes de honorarios; kilometraje compartido y adicional; novedades y siete categorías de horas. Cierres con instantáneas, correcciones con historial y permiso delegable. Eliminación completa de quincenas por el propietario.

PDF de resumen/desprendibles, ZIP, Excel y buscador para imprimir por empleado. Envío automático de PDF individual por Gmail al cerrar, con estados y reintentos controlados.

Login propio en `/acceso`, administración de usuarios/permisos e invitaciones individuales temporales.

Agenda en la web y en iPhone: mes completo, eventos por día y próximos 90 días, con horarios de Colombia. Consulta Google Calendar de `jacmusicestudios@gmail.com`; Camilo autoriza la lectura y selecciona el calendario compartido. Los eventos se mantienen en Google Calendar. Consulta la [preparación](ios/README.md#agenda-con-google-calendar).

## Privacidad y publicación

Repositorio privado: los datos iniciales contienen personal, documentos y condiciones de pago. Nunca incluir bases reales, secretos, sesiones o exportaciones de nómina en Git.

Sites administra el dominio, D1/R2 y secretos. Mantén el proyecto identificado en `.openai/hosting.json`. Cloud/GitHub no transfieren automáticamente el acceso de publicación. Sin transferencias bancarias ni nómina electrónica DIAN.
