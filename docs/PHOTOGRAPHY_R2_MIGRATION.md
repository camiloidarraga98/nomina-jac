# Fotografía: transición elegida a Cloudflare R2

16 de octubre de 2026. Camilo eligió **Cloudflare R2**, después de comparar almacenamiento/CDN para aproximadamente 1 TB. Anderson trabaja con **JPEG/HEIC y MP4/MOV**, sin RAW por ahora. Es continuidad de Fotografía en el mismo ecosistema web/iPhone/iPad/Mac; no es un cambio del hosting del Site.

## Estado comprobado

- Codex está trabajando localmente en el Mac, sin GitHub/Actions/Cloud.
- Sites reconoce a Camilo como propietario del Site existente `appgprj_6aa0260b82a88191a47960614238350a`, activo en v72. Se conserva su manifiesto, DB, BUCKET, secretos, dominio y conexiones de Agenda/correo/Slack/Sheets.
- Camilo inició sesión en Cloudflare con **jacmusicestudios@gmail.com** y completó personalmente la suscripción. El panel confirmó **Purchase complete / The subscription is active**; US$0 base y cobro posterior según uso.
- Se creó **jac-fotografia**, clase Standard, ubicación **Eastern North America (ENAM)**, cuenta `9798d1043d57690ffa9aee16c74dfb93`. El panel confirma **Public Access Disabled**, sin dominio personalizado, `r2.dev` deshabilitado y 0 B. Es independiente del BUCKET gestionado por Sites para nómina y adjuntos.
- CORS guardado y confirmado: origen exclusivo `https://jhonalexcastano.com`, método `PUT`, encabezados `content-type`/`x-amz-checksum-sha256`, expone `etag`, máximo 3.600 s. Esta política no concede acceso a objetos ni sustituye firmas/permisos. No incluye localhost ni orígenes comodín.
- Se conserva la regla predeterminada habilitada para abortar multipartes incompletas tras siete días. No se activaron dominios públicos, Local Uploads beta, logs ni productos auxiliares de pago.
- Formulario preparado **JAC Fotografía · servicio R2**, **Object Read & Write**, **Apply to specific buckets only → jac-fotografia**, duración Forever (hasta revocación). No se pulsó Create Account API Token ni se generó una credencial; pendiente autorización para ese nuevo acceso persistente y su almacenamiento como secreto en el Site existente.
- No se copió, movió ni eliminó contenido de Drive; JAC continúa usando su conexión actual. El código publicado todavía no es un cliente R2 para Fotografía. No se crearon secretos, Workers ni despliegues de aplicación en esta etapa.
- El catálogo de plugins no devolvió una conexión de Cloudflare disponible; el acceso se está preparando mediante su panel oficial. El acceso propietario de Sites está verificado por separado.

Evidencia local: `outputs/r2-jac-fotografia-privado.png`, `outputs/r2-jac-cors-privado.png` y `outputs/r2-permiso-jac-fotografia.png`. Fuente del Site v72 abierta con la herramienta oficial en `work/local/site-direct-source`, commit `3a5eb54b707e839bd98d05242221d625d80166bc`, sin cambios ni publicación. Los primeros intentos del ayudante local cambiaban al directorio raíz y detectaron divergencia sin sobrescribir nada; usar Node 24 directamente conserva el checkout correcto. El repositorio Git local de Xcode sigue sin remoto.

Actualizar este estado únicamente con resultados comprobados, sin confundir la activación de R2 o la creación de un bucket con una migración terminada.

## Costos revisados

R2 Standard cuesta **US$0,015 por GB/mes**: aproximadamente US$15 por 1.000 GB guardados continuamente. Su nivel gratuito incluye 10 GB, un millón de operaciones A y diez millones B al mes; si siguen disponibles, el ejemplo de 1.000 GB cuesta US$14,85 en almacenamiento. R2 no cobra transferencia de salida, pero sí puede cobrar operaciones y servicios auxiliares. Es pago por uso, no un paquete fijo ni un límite automático de gasto. Miniaturas/previsualizaciones también ocupan almacenamiento.

[R2: precios oficiales](https://developers.cloudflare.com/r2/pricing/).

Cloudflare Images permite transformar JPEG/HEIC. El plan gratuito admite 5.000 transformaciones únicas por mes y rechaza las nuevas al agotarlo; en el plan de pago, las primeras 5.000 están incluidas y el exceso cuesta US$0,50 por cada mil transformaciones únicas mensuales. Workers y procesamiento de video tienen facturación/límites independientes. Las entradas del binding Images tienen un límite de 20 MB; no asumir que todas las fotos grandes pueden procesarse por ese camino. Para video, distinguir portada de transcodificación; MP4/MOV son contenedores y el códec determina si el dispositivo reproduce el original.

[Images: precios](https://developers.cloudflare.com/images/pricing/), [formatos y límites](https://developers.cloudflare.com/images/get-started/limits/).

R2 se administra por HTTPS/S3. Cyberduck ofrece un perfil R2 para gestionar archivos desde el Mac; FTP no es un requisito de las apps JAC. Bunny fue la alternativa: almacenamiento Standard de una región US$10 por 1.000 GB, CDN Standard de Sudamérica US$45 por 1.000 GB entregados y Optimizer US$9,50/mes; su FTP no admite cifrado. R2 se eligió por el control de carga y costo de descargas, no por una velocidad que aún no se haya medido.

[Cyberduck/R2](https://docs.cyberduck.io/protocols/s3/cloudflare/), [Bunny Storage](https://bunny.net/pricing/storage/), [CDN](https://bunny.net/docs/cdn/pricing), [Optimizer](https://bunny.net/pricing/optimizer/), [FTP](https://bunny.net/docs/storage/ftp).

## Preparación de infraestructura

1. Activar R2 en la cuenta propietaria de JAC, con facturación revisada por Camilo. No añadir ni transferir `jhonalexcastano.com` a esta cuenta por ese motivo.
2. Crear un bucket **privado y exclusivo de Fotografía**, separado del BUCKET existente de nómina/adjuntos. Desactivar cualquier acceso público `r2.dev`; no asociar un dominio público para saltarse permisos. Registrar nombre/región reales después de crearlo.
3. Preparar CORS limitado a los orígenes reales de JAC para subidas directas HTTPS. No permitir credenciales de cookies a R2 ni enviar tokens de sesión de JAC u OAuth de Google. Usar un bucket de prueba separado o un servicio simulado para las pruebas.
4. Preparar credenciales de lectura/escritura restringidas únicamente al bucket fotográfico. No usar permisos administrativos de todos los buckets. Mantenerlas como secretos de ejecución, sin archivos, argumentos, logs, repositorios o conversación. La creación de ese acceso persistente requiere revisar su alcance concreto antes de guardarlo.
5. Si se usa un procesador privado de miniaturas, su almacenamiento y acceso quedan limitados al mismo bucket; guardar su secreto de servicio fuera del proyecto. Verificar facturación adicional antes de activar un producto de pago.

## Contrato de la integración

- Mantener los endpoints y permisos de Fotografía existentes para los clientes anteriores. Un cambio de proveedor no debe conceder accesos financieros ni de Agenda; Anderson conserva sus secciones elegidas, y Camilo/jac lectura/subida.
- Conservar el catálogo de carpetas/archivos y las operaciones idempotentes en la DB existente mediante una migración **aditiva**. La fecha/show, padre y nombre visible deben ser independientes de la clave interna del objeto, para poder organizar sin copiar videos completos al renombrar una carpeta.
- Subir originales directamente mediante cargas multipartes autorizadas por JAC y URLs temporales limitadas a cada archivo/parte. Consultar partes confirmadas y finalizar en servidor; validar tamaño, tipo, firma, sesión, revisión y pertenencia antes de publicar. Un cliente no puede marcar un archivo como completo por sí mismo. Abortar/recolectar multipartes abandonadas con una política limitada al nuevo bucket.
- Las URLs S3 firmadas usan el endpoint S3, no el dominio personalizado de un CDN. Son capacidades utilizables hasta su caducidad; no prometer revocación instantánea de una URL ya emitida. Mantener caducidades breves y evitar cualquier lectura de originales pendientes.
- Generar miniatura de cuadrícula y previsualización mediana separadas del original; mostrar esas variantes en la galería. JPEG/HEIC mantienen el original y se visualizan con una variante compatible. Videos conservan el original y una portada; transcodificación adaptativa sería un servicio distinto y requiere presupuesto propio.
- La entrega privada/caché debe validar permisos actuales antes de responder y conservar el rechazo tras revocación. No convertir el bucket en público para acelerar la galería, ni reutilizar contenido local ante 403. Conservar rangos para video, caché cifrada por cuenta, descarga manual por carpeta y exportación a Fotos.
- Probar rendimiento real desde Colombia con un lote identificado por Camilo, midiendo miniaturas, apertura y subida reanudada. Las pruebas automatizadas siguen usando servicios interceptados y archivos ficticios; no subir contenido ni descargar 1 TB como prueba.

[R2: multipartes](https://developers.cloudflare.com/r2/objects/multipart-objects/), [URLs firmadas y restricciones de dominio](https://developers.cloudflare.com/r2/api/s3/presigned-urls/).

## Migración y corte

Inventariar únicamente la raíz Drive ya autorizada; revisar cantidad/tamaño y estimar el espacio total con variantes. Copiar conservando carpetas, nombres, fechas y correspondencia de IDs, sin modificar originales o compartición de Drive. Verificar cantidades, tamaños e integridad, registrar los fallos y reanudar sin duplicados. Impedir carreras con nuevas subidas durante el corte mediante una pausa breve o reconciliación explícita.

El cambio de proveedor solo ocurre después de verificar acceso privado, archivos completos, miniaturas, reproducción, cuentas restringidas, reanudación, caché y revocación en web y apps. Invalidar la generación de caché para no mezclar identificadores de dos almacenes. Mantener una ruta de vuelta y documentar archivos pendientes. **Desconectar únicamente Fotografía de Drive al completar la transición**; no revocar el grant amplio de Google ni afectar Gmail/Agenda/Sheets. No borrar los originales de Drive como parte automática del cambio.
