# Traslado de Sites a la cuenta de JAC

## Autorización vigente · 18 de octubre de 2026

Camilo pidió trasladar la web, servidor y servicios a su propia cuenta de Cloudflare y guardar la fuente en GitHub privado. La petición sustituye la restricción histórica de nuevos pushes para este traslado. No autoriza GitHub Actions ni cambiar las funciones, cálculos, permisos, diseño o proyectos nativos. Se prepara una rama separada `codex/cloudflare-migration` del repositorio privado existente `camiloidarraga98/nomina-jac`.

También autorizó personalmente la sesión oficial de Wrangler fuera del proyecto y GitHub, con lectura de cuenta/usuario/zonas y escritura de Workers, D1, rutas y certificados. Es una excepción explícita al almacenamiento local de esa sesión de herramienta; las claves de JAC y las bases de producción no se guardan en el repositorio. No publicar tokens, OAuth, sesiones, invitaciones, exportaciones ni firmas personales.

## Destino preparado

- Cuenta: `jacmusicestudios@gmail.com`, ID `9798d1043d57690ffa9aee16c74dfb93`.
- Worker previsto: `jac-nomina`, sin rutas ni dominio de producción durante la preparación.
- D1 nueva vacía: `jac-nomina`, ID `74f39547-ed41-4456-a4b3-e32b2dd13b03`, binding `DB`.
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

## Estado

Sesión de Cloudflare verificada. D1 y R2 de destino creados vacíos. Acceso Git al repositorio privado existente verificado. Todavía no se ha cambiado el dominio, copiado la producción ni declarado terminado el traslado. El detalle de compilaciones, publicación de preparación, transferencia y corte se añadirá al verificarlos.
