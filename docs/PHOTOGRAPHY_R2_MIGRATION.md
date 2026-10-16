# Fotografía: archivo nuevo en Cloudflare R2

## Decisión vigente: empezar desde cero, sin transferir Drive

Camilo indicó expresamente el 16 de octubre de 2026: **no transferir fotos ni videos de Drive a R2**. R2 comienza como una colección independiente y vacía para las fotos/videos nuevos de hoy en adelante. No inventariar, descargar, copiar, mover ni borrar el archivo histórico de Drive para este trabajo. Sus originales, carpetas y permisos se conservan intactos. Esta decisión sustituye cualquier propuesta anterior de migración histórica en este documento.

Después precisó que no debe quedar ninguna conexión con Drive en Fotografía. Al activar R2 se vacía exclusivamente `jac_media_connection.credentials/email` y se invalidan autorizaciones pendientes `jac-media:` en una transacción con el cambio de proveedor. No se llama a la revocación de Google, ni se tocan Gmail, Agenda, Sheets, compartición o archivos de Drive. Mientras R2 esté activo, cualquier error de R2 se informa como tal; nunca se recurre a Drive como alternativa. La galería web y nativa ya no ofrecen conectar Drive.

Las nuevas carpetas y metadatos de Fotografía se guardarán en tablas independientes y aditivas de la D1 existente; los originales y miniaturas nuevos irán al bucket privado `jac-fotografia`. No crear otra base para nómina, reinicializar producción ni reemplazar DB/BUCKET. El corte debe distinguir las colecciones en la caché de las apps para evitar mezclar archivos anteriores con el nuevo archivo.

Estado real: la preparación está publicada en el Site existente **v73**, fuente `9864b1993ae22bc1f2858e98d08934ce172d66db`, despliegue `appgdep_6ad278a4e2c0819198113236c7495e0a` succeeded, secretos de Sites revisión 2 conservados. Camilo autorizó la credencial restringida al bucket y se verificó el HEAD firmado real desde JAC. La conexión se guardó cifrada en `jac_media_r2_connection`; las claves no se devolvieron al navegador ni se guardaron en archivos. **`enabled=0`: la galería todavía usa Drive.** La activación del archivo nuevo requiere completar y verificar el proveedor R2 de la galería; guardar la credencial no equivale a activar la nueva galería.

16 de octubre de 2026. Camilo eligió **Cloudflare R2**, después de comparar almacenamiento/CDN para aproximadamente 1 TB. Anderson trabaja con **JPEG/HEIC y MP4/MOV**, sin RAW por ahora. Es continuidad de Fotografía en el mismo ecosistema web/iPhone/iPad/Mac; no es un cambio del hosting del Site.

## Estado comprobado

- Codex está trabajando localmente en el Mac, sin GitHub/Actions/Cloud.
- Sites reconoce a Camilo como propietario del Site existente `appgprj_6aa0260b82a88191a47960614238350a`, activo en v72. Se conserva su manifiesto, DB, BUCKET, secretos, dominio y conexiones de Agenda/correo/Slack/Sheets.
- Camilo inició sesión en Cloudflare con **jacmusicestudios@gmail.com** y completó personalmente la suscripción. El panel confirmó **Purchase complete / The subscription is active**; US$0 base y cobro posterior según uso.
- Se creó **jac-fotografia**, clase Standard, ubicación **Eastern North America (ENAM)**, cuenta `9798d1043d57690ffa9aee16c74dfb93`. El panel confirma **Public Access Disabled**, sin dominio personalizado, `r2.dev` deshabilitado y 0 B. Es independiente del BUCKET gestionado por Sites para nómina y adjuntos.
- CORS guardado y confirmado: origen exclusivo `https://jhonalexcastano.com`, método `PUT`, encabezados `content-type`/`x-amz-checksum-sha256`, expone `etag`, máximo 3.600 s. Esta política no concede acceso a objetos ni sustituye firmas/permisos. No incluye localhost ni orígenes comodín.
- Se conserva la regla predeterminada habilitada para abortar multipartes incompletas tras siete días. No se activaron dominios públicos, Local Uploads beta, logs ni productos auxiliares de pago.
- Camilo autorizó y se creó **JAC Fotografía · servicio R2**, **Object Read & Write**, **Apply to specific buckets only → jac-fotografia**, duración Forever (hasta revocación). Confirmación de Cloudflare observada; claves conservadas únicamente en memoria para guardarlas por el formulario privado de JAC. No guardar valores en documentación, scripts, argumentos, archivos o salida.
- No se copió, movió ni eliminó contenido de Drive; JAC continúa usando su conexión actual. No se creó un Worker de almacenamiento ni se activó un producto adicional de pago.
- El catálogo de plugins no devolvió una conexión de Cloudflare disponible; el acceso se está preparando mediante su panel oficial. El acceso propietario de Sites está verificado por separado.

Evidencia local: `outputs/r2-jac-fotografia-privado.png`, `outputs/r2-jac-cors-privado.png` y `outputs/r2-permiso-jac-fotografia.png`. Fuente del Site v72 abierta con la herramienta oficial en `work/local/site-direct-source`, commit `3a5eb54b707e839bd98d05242221d625d80166bc`, sin cambios ni publicación. Los primeros intentos del ayudante local cambiaban al directorio raíz y detectaron divergencia sin sobrescribir nada; usar Node 24 directamente conserva el checkout correcto. El repositorio Git local de Xcode sigue sin remoto.

Actualizar este estado únicamente con resultados comprobados, sin confundir la activación de R2 o la creación de un bucket con una migración terminada.

## Configuración privada preparada en JAC

`Configuración general → Servicios conectados` incluye para Camilo **Almacenamiento de Fotografía**. La API `/api/media/storage` valida la cuenta/credenciales S3, hace un HEAD firmado al bucket exacto de R2 sin seguir redirecciones y conserva la conexión cifrada con la clave de correo existente. GET devuelve únicamente cuenta/bucket/versión/estado; nunca devuelve Access Key ID, Secret Access Key ni el cifrado. El formulario borra sus campos secretos después de guardar.

La migración aditiva **0024_photography_r2_connection** crea solo `jac_media_r2_connection`, separada de Drive y sin datos iniciales. Guarda `enabled=0`: **preparar la conexión no cambia el proveedor de la galería**. Una conexión activa no puede reemplazarse a ciegas desde este formulario. Solo Camilo configura; la API exige sesión vigente, origen, permisos y CAS antes/después de consultar R2 y en el guardado SQL. No basta con ocultar la interfaz.

Verificado localmente con Node 24.21.0: TypeScript/build correctos, **89 pruebas de servidor/cliente** y **13 de Workerd** aprobadas, con D1 en memoria/Workerd local y S3/Google interceptados. Se comprueba cifrado, ausencia de claves en respuestas, denegación por rol/origen, URL fija, rechazo de redirecciones, revocación durante la consulta y antes del commit, versiones concurrentes y conservación de Drive. El formulario real se probó en localhost con datos ficticios y retiró los campos secretos tras guardar; `outputs/r2-formulario-local-guardado.png`. Estos fixtures no acreditan todavía el acceso real de la credencial.

La revisión automática rechazó un receptor local porque habría escrito la clave en stdout; ese receptor no llegó a ejecutarse. La alternativa usa el formulario HTTPS de JAC y cifrado del lado del servidor, sin salida local ni archivo intermedio de credenciales. No repetir el receptor ni una variante indirecta.

El instalador antiguo del checkout publicado usaba `npm install` y volvió a resolver el árbol WASI opcional. Se descartó ese resultado del lockfile y se restauró el lockfile local ya verificado: las únicas adiciones respecto a la fuente publicada son `@emnapi/core@1.10.0` y `@emnapi/runtime@1.10.0`; ninguna entrada/versión existente cambia. `install:ci` pasa a `npm ci --no-audit --no-fund`. La instalación limpia y compilación exacta del checkout del Site completaron correctamente; no se borró el lockfile ni se ejecutó npm update.

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

## Activación del archivo nuevo

No hay migración histórica. El nuevo catálogo empieza vacío y recibe exclusivamente las nuevas cargas realizadas en JAC después de activar R2. El cambio de proveedor solo ocurre después de verificar acceso privado, archivos completos, miniaturas, reproducción, cuentas restringidas, reanudación, caché y revocación en web y apps. Invalidar la generación de caché para no mezclar identificadores de dos almacenes. Mantener una ruta de vuelta y documentar las cargas pendientes. Desactivar únicamente el uso de Drive por Fotografía al completar la transición; no revocar el grant amplio de Google ni afectar Gmail/Agenda/Sheets. No borrar, modificar ni transferir originales de Drive.

## Proveedor nuevo implementado localmente

Migración aditiva **0025_photography_r2_new_collection**: `jac_media_r2_entries` contiene el catálogo nuevo, con índice de padre/creación. No contiene semillas ni referencias copiadas de Drive. Raíz `jac_r2_root`, colección `jac-r2-new-20261016`, IDs nuevos `r2_UUID`. Carpetas ordenadas primero, creación descendente, páginas de 100. Los nombres/fechas de carpetas se guardan en D1; las claves UUID de originales y miniaturas son independientes.

Los endpoints existentes `/api/media`, `/api/media/file` y `/api/media/upload` usan el proveedor R2 cuando está activo. Controles conservados: sesión/cuenta/revisión/permiso actuales, origen de escritura, cadena de padres y catálogo antes/después de operaciones externas; guardas SQL en la publicación; operaciones UUID idempotentes y bloqueo de concurrencia. Los IDs anteriores no se interpretan como objetos nuevos. No hay función de importación histórica.

Las cargas originales van directamente al endpoint S3 de R2 en partes de 8 MiB, con URLs PUT firmadas de **cinco minutos**, limitadas al objeto, multipart, número de parte, MIME y longitud exactos. Los clientes no reciben la clave secreta ni permisos de listar/leer. JAC consulta las partes confirmadas, verifica tamaños/orden, finaliza la carga y valida HEAD, metadato propio y firma inicial del formato antes de publicar una sola entrada. Recupera respuestas perdidas por clave fija. Una URL ya emitida es una capacidad hasta su vencimiento: no prometer revocación instantánea; no permite publicar por sí sola. Cancelar aborta solo la multipart pendiente. La regla R2 de siete días recoge partes abandonadas. Se conserva el máximo anterior de 20 GiB por archivo.

Las miniaturas JPEG de hasta 640 px/512 KiB las genera el dispositivo o navegador al subir; el servidor valida formato/dimensiones/límite y las guarda por separado, dejando intacto el original. Fotos HEIC y portadas de video usan los decodificadores nativos de Apple; en web depende del códec que admita el navegador. Si este no lo decodifica, el original se conserva y la miniatura queda pendiente; no hay un servicio de transcodificación ni Images de pago activado. El panel usa solo las variantes pequeñas para la cuadrícula. Lectura privada de fotos y reproducción por rangos pasan por JAC/R2 con autorización actual, sin OAuth/ancestros de Google. No se habilita bucket público ni se presenta esto como un CDN público de originales.

iPhone/iPad **0.21.0 (33)** y Mac **1.7.0 (9)**, en los mismos proyectos. La caché cifrada recibe la identidad de colección y retira solamente las copias anteriores de Fotografía al conocer R2. Rechaza guardados tardíos de Drive, sin borrar sus originales, cerrar sesión ni retirar otros módulos. Conserva Disponible sin conexión, Guardar en Fotos, permisos, Llavero, privacidad y push suspendido. Actualizar con Run en el proyecto existente, sin sustituirlo por otro.

Verificación local: 104 pruebas de servidor/nómina/móvil, seis de acceso/cliente web y 14 Workerd correctas; los nueve casos del catálogo nuevo comprueban inicio vacío, retiro exclusivo de la conexión de Fotografía, multipart/reanudación, respuesta perdida, publicación única, datos inválidos, revocación, miniaturas y cancelación. Todas las salidas S3/Google están interceptadas. TypeScript/build correctos; tsconfig excluye `work/output/outputs/dist` para no verificar de nuevo un checkout anidado con otra identidad de tipos React. No se actualizan dependencias ni entradas existentes del lockfile.

Las 90 pruebas nativas de iPhone pasan, más una condición física omitida en simulador; Mac, 100 correctas. Se conservan informes intermedios: la primera ejecución iPhone sin firma falló en la comprobación existente del Llavero; con firma local ad hoc pasó completa, sin eliminar aserciones (`r2-native-unit-final.xcresult`). `r2-mac-unit.xcresult` correcto. La UI web real creó una carpeta y subió foto/video 2/2 con ambos JPEG ligeros, usando transferencia S3 simulada exclusivamente en localhost: `outputs/r2-galeria-local-miniaturas.png`. No se ha medido velocidad real desde Colombia ni subido archivos de prueba a producción.

Cierre nativo local: `r2-iphone-ui.xcresult` (tres recorridos correctos: subida/apertura, carpeta offline/Fotos simuladas y privacidad) y `r2-ipad-ui.xcresult` (dos correctos: galería restringida y offline/Fotos). Releases iphoneos sin firma y Mac universal con firma local compilan. Mac UI no pudo arrancar: AMFI rechazó el runner ad hoc con código -423 antes de cargar pruebas; informes `r2-mac-ui.xcresult` y `r2-mac-ui-final.xcresult`, diagnóstico `r2-mac-runner-diagnostic.log`. No se retiraron comprobaciones ni protecciones para ocultarlo. Mac sí completó sus 100 unitarias. No se instaló en iPhone/iPad físico ni se midió rendimiento de archivos reales.
