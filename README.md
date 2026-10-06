# Nómina JAC Music

Aplicación privada de pagos de shows y nómina administrativa activa en https://jhonalexcastano.com. Lee `AGENTS.md` y `docs/PROJECT_CONTEXT.md` para el contexto actualizado, las condiciones acordadas y el flujo de publicación.

## Desarrollo

Node.js 24 LTS recomendado.

```sh
npm ci
npx tsc --noEmit
node --test tests/payroll.test.mjs tests/payroll-auth.test.mjs tests/payroll-mail.test.mjs
npm run build
```

Las pruebas usan bases en memoria y correo simulado. Para vista local usa `npm run dev` con D1 local y claves independientes de desarrollo en archivos ignorados. No pruebes contra producción.

## Funciones

Personal, tarifas y conceptos editables; shows y ajustes de honorarios; kilometraje compartido y adicional; novedades y siete categorías de horas. Cierres con instantáneas, correcciones con historial y permiso delegable. Eliminación completa de quincenas por el propietario.

PDF de resumen/desprendibles, ZIP, Excel y buscador para imprimir por empleado. Envío automático de PDF individual por Gmail al cerrar, con estados y reintentos controlados.

Login propio en `/acceso`, administración de usuarios/permisos e invitaciones individuales temporales.

## Privacidad y publicación

Repositorio privado: los datos iniciales contienen personal, documentos y condiciones de pago. Nunca incluir bases reales, secretos, sesiones o exportaciones de nómina en Git.

Sites administra el dominio, D1/R2 y secretos. Mantén el proyecto identificado en `.openai/hosting.json`. Cloud/GitHub no transfieren automáticamente el acceso de publicación. Sin transferencias bancarias ni nómina electrónica DIAN.
