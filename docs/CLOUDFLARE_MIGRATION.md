# Traslado de Sites a la cuenta de JAC

## Autorización vigente · 18 de octubre de 2026

Camilo pidió trasladar la web, servidor y servicios a su propia cuenta de Cloudflare y guardar la fuente en GitHub privado. La petición sustituye la restricción histórica de nuevos pushes para este traslado. No autoriza GitHub Actions ni cambiar las funciones, cálculos, permisos, diseño o proyectos nativos. Se prepara una rama separada `codex/cloudflare-migration` del repositorio privado existente `camiloidarraga98/nomina-jac`.

También autorizó personalmente la sesión oficial de Wrangler fuera del proyecto y GitHub, con lectura de cuenta/usuario/zonas y escritura de Workers, D1, rutas y certificados. Es una excepción explícita al almacenamiento local de esa sesión de herramienta; las claves de JAC y las bases de producción no se guardan en el repositorio. No publicar tokens, OAuth, sesiones, invitaciones, exportaciones ni firmas personales.

## Destino preparado

- Cuenta: `jacmusicestudios@gmail.com`, ID `9798d1043d57690ffa9aee16c74dfb93`.
- Worker de preparación: `https://jac-nomina.jacmusic.workers.dev`, sin rutas ni dominio de producción.
- D1 nueva: `jac-nomina`, ID `74f39547-ed41-4456-a4b3-e32b2dd13b03`, binding `DB`, con las 27 migraciones del proyecto y sin datos copiados todavía.
- R2 nuevo privado: `jac-documentos`, binding `BUCKET`, separado del original de Sites.
- Fotografía conserva el bucket privado existente `jac-fotografia`; no se traslada el histórico de Drive.

El perfil se activa al construir con `npm run build:cloudflare`. `npm run build` mantiene el perfil existente de Sites y su manifiesto sin cambiar. Se conservan versiones de dependencias y lockfile. La construcción de Cloudflare usa el mismo servidor y aplicaciones, con un envoltorio que responde 503 hasta habilitar `JAC_READY=1` como secreto de ejecución. `/_jac/health` permite comprobar únicamente servicio y preparación. La aplicación no puede inicializar datos ni enviar avisos durante esa espera. El despliegue independiente ignora los encabezados de identidad de Sites y utiliza las cuentas propias de JAC.

## Condiciones antes del cambio de dominio

1. Recuperar una copia íntegra y coherente de la D1 real y los objetos del BUCKET de Sites; preservar IDs, revisiones, nombres, metadatos y hashes. No usar el estado de localhost como origen.
2. Conservar `PAYROLL_AUTH_KEY` para verificar las contraseñas actuales y `PAYROLL_MAIL_KEY` para las conexiones cifradas. Sites confirma su existencia pero no devuelve sus valores. No activar el destino con claves nuevas y datos cifrados antiguos.
3. Verificar migraciones, esquema, recuentos y archivos, permisos por cuenta, protección de pases, contratos, nómina y clientes nativos con fixtures y pruebas aisladas. Sin correos, eventos, notificaciones, importaciones Slack o borrados reales como pruebas.
4. Coordinar el corte final de escrituras e ingesta para que no existan dos servidores procesando un mismo evento. Mantener Google/Slack/push y sus IDs/configuraciones; mismo dominio y rutas de callback. No activar servicios externos en el destino de prueba.
5. Cambiar `jhonalexcastano.com` únicamente tras verificar el destino y disponer de una reversión que no pierda las escrituras posteriores al corte. No borrar ni cancelar el Site original durante la preparación.

La autorización de Apple Developer es independiente de este traslado: conservar `co.jacmusic.nomina`, la sesión en Llavero y los mismos proyectos de iPhone/iPad/Mac. Las apps ya consultan `https://jhonalexcastano.com`; no necesitan otro proyecto para continuar con el mismo dominio.

## Traslado temporal cifrado

El exportador temporal exige la sesión propia del fundador Camilo, comprobada nuevamente tras leer, el mismo origen y una ventana máxima de dos horas. La clave pública del destinatario queda fijada en la configuración de ejecución. La base, las dos claves de ejecución y cada bloque de documentos salen cifrados con AES-256-GCM y RSA-OAEP; el navegador no los descifra. La clave privada y la capacidad del importador viven únicamente en la memoria del operador local. El archivo descargado contiene solamente sobres cifrados e inventario de cantidades; no se guarda una base o claves en texto claro.

El importador solo funciona en el Worker de preparación bloqueado, con capacidad y caducidad, sin aceptar peticiones de navegador. No admite SQL arbitrario ni otros buckets. Verifica columnas, filas, contadores, huellas de cada tabla y SHA-256 de cada documento. Las claves se instalan mediante la entrada estándar del Wrangler oficial, sin registros ni archivos de credenciales. La activación deshabilita el importador, y al terminar se deben retirar las rutas y valores temporales de ambos destinos. La primera copia es de preparación; todavía requiere corte final coherente y control de escrituras antes del DNS.

Archivos nuevos: `lib/hosting-transfer.ts`, las dos API `hosting-transfer*`, `/migracion`, `scripts/cloudflare-transfer-local.mjs` y sus pruebas. El envoltorio de Cloudflare incorpora la importación antes de su bloqueo; el servidor habitual conserva todas sus rutas y servicios. No cambia ninguna dependencia, migración ni proyecto nativo.

## Estado verificado

Sesión de Cloudflare y acceso Git privado verificados. Fuente actual guardada en la rama privada, sin workflow de Actions. Worker publicado con `ready:false`, D1 con 27 migraciones y R2 privado nuevo. TypeScript, build independiente y 52 pruebas iniciales pasaron; las 11 comprobaciones finales de importación, cifrado y bloqueo también pasan con SQLite y R2 ficticios. No se ha cambiado el dominio ni copiado producción. GoDaddy necesita revisión/respaldos DNS y faltan datos, secretos, comprobación del plan de Workers y corte final. No declarar terminado el traslado hasta verificarlos.

### Actualización de preparación · 18 octubre, 22:10 UTC

La copia inicial ya está en el destino: 40 tablas de aplicación, 786 filas y 114 documentos (27.773.665 bytes), huellas por tabla y SHA-256 por objeto comprobados. La tabla interna `__appgarden_migrations` queda excluida junto con los metadatos de D1/Drizzle; las 27 migraciones del destino ya están registradas por Wrangler. Las dos claves se instalaron por stdin sin archivos en claro. Los sobres cifrados descargados están fuera de Git. El R2 de Fotografía sigue en el mismo bucket y su catálogo sí forma parte de la copia.

Camilo activó personalmente Workers Paid (US$5/mes más consumo) y autorizó expresamente activar el Worker tras un rechazo de revisión automática. `/_jac/health` responde 200/ready:true, `/acceso` muestra el formulario con 200 y `/api/users` rechaza una petición sin sesión con 403. No se probaron envíos, Google/Slack/push reales ni mutaciones de usuarios reales. Son verificaciones de disponibilidad/autenticación, todavía no una prueba completa del servicio en el dominio.

61 pruebas de nómina/auth/correo/móvil/traslado/corte y 121 de servicios simulados aprobadas. Ambos perfiles compilan con Node24 y TypeScript pasa. No cambios de dependencias o proyectos nativos.

DNS de GoDaddy respaldado en `work/local/dns-backup/` (ignorado). Cloudflare zona `4ea77d648671345507d58c8b94e2fc90`, plan DNS Free independiente de Workers Paid, siete registros de usuario conservados como DNS only. SOA y NS del proveedor no se importan como registros de usuario. Camilo confirmó guardar `gwen.ns.cloudflare.com` y `sterling.ns.cloudflare.com`; GoDaddy aceptó y procesa el cambio. El registro del dominio sigue en GoDaddy, `.co` y otros dominios no se modificaron. Aún sirve el Site original y falta propagación/SSL y corte final.

`JAC_ORIGIN_FROZEN` está preparado pero NO activado. Al corte se debe bloquear primero el origen, esperar solicitudes en curso y tomar copia final; desactivar `JAC_READY` en el destino antes de reimportar. Después activar destino, conectar dominio y retirar el custom hostname de Sites al último paso (su prioridad SaaS puede prevalecer). No descongelar el origen después de recibir escrituras en Cloudflare sin una copia inversa coherente. Retirar rutas y valores temporales al concluir.
