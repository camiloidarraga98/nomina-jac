# JAC en la cuenta propia de Cloudflare

Estado comprobado el 18 de octubre de 2026. La web y su servidor de producción ya funcionan en **https://jhonalexcastano.com**, dentro de la cuenta `jacmusicestudios@gmail.com`. El dominio sigue registrado en GoDaddy; Cloudflare administra su DNS. Sites ya no atiende ese dominio.

## Recursos de producción

| Recurso | Identidad |
| --- | --- |
| Cuenta Cloudflare | `9798d1043d57690ffa9aee16c74dfb93` |
| Worker | `jac-nomina` |
| D1, binding DB | `jac-nomina` · `74f39547-ed41-4456-a4b3-e32b2dd13b03` |
| R2 de documentos, binding BUCKET | `jac-documentos`, privado |
| R2 de Fotografía | `jac-fotografia`, privado y conservado en su ubicación original |
| Zona DNS | `4ea77d648671345507d58c8b94e2fc90` |
| Servidores DNS | `gwen.ns.cloudflare.com`, `sterling.ns.cloudflare.com` |
| Fuente privada | https://github.com/camiloidarraga98/nomina-jac |

Workers Paid fue activado personalmente por Camilo: US$5/mes de base más consumo. El plan DNS es Free. Fotografía conserva su facturación R2 existente. No se contrataron otros planes, ni se importó, movió o borró contenido de Drive.

## Fuente y publicación desde el mismo Mac

Camilo autorizó expresamente este traslado y los pushes al repositorio privado existente. Esto sustituye para el flujo actual las instrucciones históricas de publicar en Sites y mantener GitHub solo como archivo. No autoriza Actions, PR ni trabajos Codex Cloud. La edición, pruebas y compilación continúan en esta misma carpeta del Mac. Los proyectos nativos y su firma personal no se sustituyen.

Con Node24 y el lockfile existente:

```sh
scripts/local-env.sh npx --no-install tsc --noEmit
scripts/local-env.sh node --test tests/payroll.test.mjs tests/payroll-auth.test.mjs tests/payroll-mail.test.mjs
scripts/local-env.sh npm run build
scripts/local-env.sh npm run deploy:cloudflare
```

`npm run build` construye ahora para Cloudflare propio. `build:cloudflare` es su alias explícito. La publicación usa `dist/server/wrangler.json` generado, el dominio declarado en `deploy/cloudflare/wrangler.json` y `--keep-vars`. No publica por un push a GitHub; no hay workflow de Actions. Los commits y la publicación son pasos separados desde el Mac.

`npm run dev` conserva el entorno local del proyecto; las migraciones y fixtures de desarrollo deben seguir siendo locales, con claves de desarrollo independientes. `db:migrate:cloudflare` apunta explícitamente a D1 real: usarlo solamente para migraciones de producción revisadas, nunca para preparar pruebas. Las migraciones0000–0026 ya están aplicadas; no volver a inicializar datos ni sustituirlos por localhost.

`build:sites`, `.openai/hosting.json` y el complemento heredado solo conservan la referencia histórica del proveedor anterior. No ejecutar su publicación para cambios futuros. El Worker propio no confía en encabezados de identidad de Sites: utiliza la sesión y los permisos existentes de JAC.

## Copia final y controles verificados

El origen se pausó antes de la copia final. Además del bloqueo HTTP, una barrera temporal de SQLite impidió INSERT/UPDATE/DELETE en las40 tablas de aplicación, incluso de solicitudes iniciadas antes del cambio de Worker. Esa barrera no cambió registros de aplicación y no forma parte del esquema de destino.

La copia final contiene **40 tablas,786 registros y114 documentos,27.773.665 bytes**. Se conservaron IDs, revisiones, metadatos, contadores de autoincremento y las27 migraciones existentes. Coincidieron las huellas canónicas de filas por tabla y el SHA-256 de cada documento. Se excluyeron los metadatos internos de Sites/D1 y `__jac_transfer_control`.

La base, los documentos y las dos claves de ejecución se transfirieron mediante sobres AES-256-GCM/RSA-OAEP. Solo el proceso local tuvo temporalmente la clave privada y los datos descifrados en RAM; las claves se instalaron por entrada estándar de Wrangler. Ninguna base real, clave, sesión o exportación se agregó al repositorio. Los archivos de descarga contienen sobres cifrados; no son una copia restaurable autónoma tras cerrar ese proceso.

`PAYROLL_AUTH_KEY` y `PAYROLL_MAIL_KEY` se conservaron como secretos del Worker: mantienen contraseñas, sesiones y conexiones cifradas. La sesión oficial de Wrangler vive en la configuración personal del Mac, fuera del proyecto/GitHub, por autorización expresa. `JAC_READY=1` es una activación de ejecución, ausente de Git; sin ella la aplicación responde503 y no procesa servicios.

El dominio propio respondió con HTTPS y `/_jac/health` devolvió200/ready:true; `/acceso` devolvió200, `/api/users` sin sesión403 JSON y la API móvil sin sesión401 JSON. La sesión Camilo que ya existía pudo leer el listado de usuarios en la nueva D1. No se creó sesión de prueba, ni se modificaron cuentas, nóminas, correos, eventos, abonos, archivos o avisos reales para verificar el cambio.

Las rutas temporales `/migracion`, `/api/hosting-transfer`, `/api/hosting-transfer-inventory` y `/_jac/transfer` están retiradas del servidor definitivo y responden404. Se retiraron las capacidades temporales de ambos proveedores y se cerró el operador local. Su código auditado y pruebas se conservan fuera de las rutas de producción para registrar el procedimiento; los adaptadores antiguos están en `tests/fixtures/hosting-transfer`.

Comprobaciones locales:61 pruebas iniciales de nómina/auth/correo/móvil/traslado/corte y121 de servicios simulados aprobadas;14 comprobaciones finales de cifrado, barrera, bloqueo y retirada de accesos aprobadas. TypeScript y las construcciones Sites de origen y Cloudflare de destino correctas. No se cambiaron dependencias ni el lockfile. No se repitió Xcode: ninguna fuente nativa cambió por este traslado. Las apps conservan `co.jacmusic.nomina`, el mismo dominio, proyectos, sesión en Llavero y push suspendido.

## DNS y origen anterior

Se respaldó la zona GoDaddy en `work/local/dns-backup/` antes de copiarla a Cloudflare. Se conservaron los registros de correo/verificación y otros dominios. Los dos A anteriores de Sites se apartaron bajo `_jac-sites-backup.jhonalexcastano.com`, como DNS only, para conservar sus valores sin competir con el nuevo dominio administrado por Workers. No son una aplicación ni una ruta activa de respaldo. El dominio principal quedó vinculado directamente a `jac-nomina` con certificado Universal activo. El fallo TLS de www se observó antes del traslado; la comprobación de producción se refiere al dominio principal sin www.

El vínculo SaaS del dominio con Sites se retiró al último paso, después de verificar copia, Worker y certificado. El Site original `appgprj_6aa0260b82a88191a47960614238350a` se conserva pausado, versión89, fuente `af8fb271c16000c059f4df7eaf6186ef0d483f3f`, configuración de ejecución revisión6. Mantiene sus originales y las dos claves; solo conserva `JAC_ORIGIN_FROZEN=1` como control de mantenimiento, sin las capacidades de exportación.

**No descongelar ni volver a apuntar al origen antiguo tras recibir cambios en Cloudflare:** antes haría falta una copia inversa coherente de los registros/documentos posteriores. El respaldo anterior no se actualiza automáticamente. No borrar ni cancelar ese Site como parte de esta migración. El mantenimiento futuro se hace en Cloudflare y en el repositorio privado.

## Corrección de entrega estática · 18 octubre2026

Camilo detectó la página sin estilos después del corte. La comprobación inicial del HTML y la sesión no había comprobado sus dependencias visuales: con `run_worker_first=true`, CSS/JS y archivos públicos llegaban al router de la aplicación, que respondía404 aunque estaban cargados en Assets.

`worker/cloudflare.ts` entrega ahora GET/HEAD de `/assets/`, `/licenses/` y los archivos públicos explícitos de marca/manifest/service worker mediante `env.ASSETS.fetch`. El bloqueo READY se evalúa antes y las API, documentos privados y escrituras siguen pasando por las guardas de la aplicación. No cambió DNS, D1, R2, secretos, dependencias o fuentes nativas. Al agregar nuevos archivos raíz de `public/`, ampliar la lista explícita si corresponde.

43 pruebas incluidas las dos regresiones nuevas, TypeScript y build correctos. Despliegue propio `0ab4badb-288e-458a-89f3-5130448749c5`. Los21 archivos públicos responden200 con bytes idénticos al build; ambas CSS tienen `text/css`. Los dos metadatos internos de construcción permanecen404. Chrome cargó la hoja con361 reglas y el diseño grid del acceso; captura `outputs/jac-estilos-cloudflare-corregidos.jpg`. Sin sesiones nuevas ni acciones con servicios/datos reales de prueba.
