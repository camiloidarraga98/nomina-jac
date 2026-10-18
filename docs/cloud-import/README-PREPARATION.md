> HISTÓRICO, sustituido el18/octubre2026. No extraer el ZIP antiguo ni publicar en Sites. Continuar desde main del repositorio y leer `continuidad-codex-cloud/README.md`.

# Nómina JAC Music — preparación Cloud

Esta importación contiene el código actual en `nomina-jac-cloud.zip` (159 archivos) y el contexto completo dentro de `docs/PROJECT_CONTEXT.md` en el paquete. Corresponde al commit de producción `0d26668b0b3361e18b5a471f955cbc4e2a682207`.

Para preparar el entorno, extrae el paquete en la raíz del repositorio. Este ZIP fue preparado por el propietario del proyecto y no contiene secretos ni la base real.

```sh
python3 -m zipfile -e nomina-jac-cloud.zip .
```

Después lee los archivos extraídos `AGENTS.md` y `docs/PROJECT_CONTEXT.md`. Configura Node.js 24 LTS, ejecuta `npm ci`, `npx tsc --noEmit`, `node --test tests/payroll.test.mjs tests/payroll-auth.test.mjs tests/payroll-mail.test.mjs` y `npm run build`. No pruebes contra producción ni envíes correos reales.

El primer trabajo de continuidad debe dejar los archivos extraídos versionados en GitHub, verificar las pruebas e identificar el acceso necesario al plugin de Sites. Hosting permanece en el Site existente `appgprj_6aa0260b82a88191a47960614238350a`, dominio https://jhonalexcastano.com. No crees otro Site ni cambies DNS.

Repositorio privado: el código contiene datos iniciales de personal, documentos y tarifas. La base actual y las credenciales reales permanecen en Sites.
