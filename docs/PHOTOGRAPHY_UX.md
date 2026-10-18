## Selector de subida de Mac · 17 de octubre de2026

Se reemplaza únicamente en macOS la hoja compartida List/NavigationStack/searchable por una ventana propia de680×620puntos: cabecera con cierre, dos tarjetas para crear carpeta o usar la ubicación actual, búsqueda dentro del contenido, filas amplias y pie con Cancelar/Escape. Crear carpeta tiene una hoja compacta de540puntos con nombre y acciones nativas. El recorte provenía de la hoja de560puntos frente al mínimo620de jacSurface, además del buscador en la barra de navegación. Las ramas iPhone/iPad, permisos, UUID, destinos, orden descendente, paginación, lectura/subida y privacidad se conservan.

Cambios de presentación acotados a DocumentsView.swift. Comprobación directa con instancia DEBUG .invalid de Anderson: búsqueda sin coincidencias y por Pereira, creación de carpeta y subida de PNG/MOV ficticios, ambos visibles al terminar. Captura outputs/mac-fotografia-subir.png. Debug Mac y compatibilidad iOS compilan; Release universal y entrega se anotan al cerrar. No se subieron archivos reales ni se modificaron carpetas R2 reales.

También se elimina en web la confirmación automática «Shows de Calendar revisados…» de CrmPanel.detect, tanto al abrir como al pulsar Actualizar. Se conserva sincronización, recarga, estado de progreso, guardas y manejo de errores, y las confirmaciones de guardado de acciones explícitas. Sin cambios de API, dependencias o migraciones. TypeScript y37pruebas obligatorias aprobadas; construcción/publicación exacta al cerrar.

# Fotografía: navegación, miniaturas y carpetas recientes

16 de octubre de 2026. Cambios sobre el ecosistema existente; conserva Drive, cuentas, permisos, privacidad y copia cifrada.

## Uso previsto

En iPhone, Fotografía ocupa una pestaña principal; Mi cuenta pasa a Gestión. En Mac, Fotografía permanece en la barra lateral principal y Mi cuenta pasa a Configuración. Gestión/Mi cuenta sigue disponible incluso para cuentas limitadas a una sola sección. No se concede Fotografía a quien no tenga ese acceso.

Las carpetas aparecen por creación descendente, con las más recientes primero. La fecha del nombre del evento no sustituye a la fecha de creación; la fecha de modificación sigue sirviendo para comprobar la versión de los archivos. La paginación conserva el mismo orden y los clientes ordenan el listado acumulado con desempates de nombre/ID.

Al entrar en una carpeta se muestran miniaturas ligeras de fotos y videos. No se descargan originales para llenar la cuadrícula. Cuando Drive todavía procesa una miniatura, se conserva un marcador y se permite actualizar o reintentar. Abrir una foto/video conserva la descarga privada y la vista dentro de JAC.

Subir archivos permite usar una carpeta existente o crear una carpeta de evento con fecha/nombre antes de subir el lote. Esto no crea un evento de Calendar ni del CRM. Se conservan el progreso, los identificadores de reintento y el control de permisos durante la transferencia.

Disponible sin conexión y Guardar carpeta en Fotos se encuentran en el menú de cada carpeta: mantener presionado en iPhone o clic derecho en Mac, con un menú de puntos como alternativa accesible. El destino es la carpeta seleccionada. La revisión de cantidad/tamaño, confirmación, progreso y cancelación se conservan. Guardar en Fotos pertenece al iPhone; la copia offline permanece dentro de JAC.

## Verificación y entrega

En este Mac con Node 24: 35 pruebas Drive/acceso y 11 Workerd aprobadas, incluidos orden entre páginas, creación/subida desde raíz, miniatura pendiente→lista, límite exacto de 512 KiB/rechazo de exceso, redirecciones, rangos y revocación durante la lectura. 49 regresiones de nómina/auth/correo/móvil/OAuth aprobadas. TypeScript correcto. Informes `work/local/media-previews-drive-final.log`, `media-previews-workerd.log` y `media-ux-regression.log`.

La vista local mostró siete miniaturas cargadas, completó una foto y un video en un evento creado desde raíz (2/2) y otra imagen en un evento dentro de la carpeta actual (1/1). El registro de la instancia ficticia confirmó que antes de abrir originales solo hubo peticiones thumbnail y que los bytes del lote llegaron a su carpeta correspondiente. Una respuesta 403 retiró todas las miniaturas y controles. Captura `outputs/fotografia-miniaturas-local.png`. Sin comprobación móvil del navegador: iPhone se verifica con la app nativa. No se crearon carpetas, subieron fotos ni guardaron contenidos reales de prueba en Drive o Fotos. Los resultados de las apps nativas se detallan más abajo.

## Publicación web

Web **v71** publicada **succeeded** en el mismo Site `appgprj_6aa0260b82a88191a47960614238350a`. Fuente privada `5e2d283062e246cc6b717a46766e69cc45fff572`, despliegue `appgdep_6ad257533d1c81918fe4250f964f8e40`, env_set_revision 2. Artefacto de 87 entradas, SHA256 `646defe74fc5f0250232af083dab991efd2c1af137f73dac132db680b4ffb483`. Build exacto del Site aprobado con Node 24 y proceso oficial de Sites. Se conservan dominio, audiencia, hosting.json, DB/BUCKET, secretos y conexiones; no hay migraciones ni cambios de dependencias/lockfile. Fuente nativa local, sin GitHub ni trabajos Cloud.

Se verificó la web publicada con la sesión de Camilo: vista compacta, carpetas de OCTUBRE en orden reciente y seis miniaturas reales de 213 × 320 al iniciar la carga en una carpeta existente. Solo lectura: no se abrieron originales ni se subieron/modificaron archivos de Drive durante esa comprobación. La cola terminó cargando 44/44 miniaturas y se guardó `outputs/fotografia-miniaturas-publicadas-v71.png`. No se descargaron los originales de esa carpeta.

## Apps nativas

iPhone **0.18.0 (29)** y Mac **1.5.0 (6)** en los mismos proyectos/bundle IDs. Fotografía ocupa el acceso principal y Mi cuenta se encuentra en Gestión/Configuración, también para perfiles sin otras secciones. Subir conserva la opción de guardar en la raíz general y permite elegir carpeta o crear la del evento en la ubicación actual. No se impone una organización distinta a los archivos existentes.

Mac: **89 unitarias aprobadas** y seis recorridos UI distintos aprobados entre `mac-gallery-ux-ui.xcresult` y `mac-gallery-ux-target-ui.xcresult`. El informe inicial conserva un fallo de espera: la prueba consultaba el nombre de la carpeta antes de terminar el plan asíncrono; se mantuvo la aserción BOGOTÁ/1 de 1 y se esperó correctamente. La prueba también subió a PEREIRA y confirmó que BOGOTÁ no recibió ese lote. La revisión visual detectó que la imagen podía aumentar el ancho mínimo de la tarjeta; se convirtió en overlay. El recorrido de fotógrafo con aserción de margen y las 89 unitarias volvieron a pasar con esa fuente en `mac-gallery-ux-final.xcresult` (**TEST SUCCEEDED**). No se quitaron comprobaciones para ocultar fallos.

iPhone: **79 unitarias aprobadas y una comprobación física omitida** en `ios-gallery-ux-unit.xcresult`; **nueve recorridos UI completados sin fallos**, registrados en `ios-gallery-ux-ui.log`. Incluyen cinco pestañas/cuenta en Gestión, perfiles aislados/vacío y cierre de sesión, creación/subida, destinos independientes, guardado en Fotos simulado, reapertura sin conexión y privacidad/regreso desde segundo plano. Simulador nuevo `F1B5F977-2F78-4B30-B603-15DFBA735D04`; no se instaló ni se probó un iPhone físico ni una fototeca real. La recolección opcional de diagnósticos de Xcode demoró el cierre del informe original después de terminar los nueve casos. Al inspeccionar las capturas se corrigió el encabezado de iPhone para que el título tenga todo el ancho, con Subir en la fila siguiente. La repetición del recorrido de Fotos/reapertura offline, con aserciones de ambos márgenes, terminó **TEST SUCCEEDED** en `ios-gallery-ux-heading-ui.xcresult`; esta ejecución desactiva únicamente la recolección opcional de diagnósticos.

Releases finales correctas en `ios-gallery-ux-release-final2.log` (iphoneos sin firma) y `mac-gallery-ux-release-final2.log` (universal x86_64/arm64, firma estricta verificada). Se incluye el último ajuste visual y el texto offline correcto. La comparación con `work/local/native-gallery-ux-baseline` confirma solo cuatro cambios de versión/build por proyecto y esquema personal intacto; push permanece NO. No se copiaron certificados, claves o contraseñas.

La misma `outputs/JAC Music.app` se actualizó a 1.5.0 (6), con la anterior en `work/local/mac-gallery-ux-previous/JAC Music.app`; firma verificada también tras copiar. Para cargar el binario nuevo, reabrir esa app. En iPhone instalar con **Run en el mismo proyecto JACNomina**, eligiendo el teléfono y conservando la firma personal. Fuente y respaldo ZIP locales; no hace falta descargar otro proyecto.


## Consulta inmediata al arrancar — iPhone 0.18.1 (30) / Mac 1.5.1 (7)

La bandera de copia local restaurada no significa que se haya comprobado una caída de internet. Antes media() devolvía el listado cifrado al entrar; cuando terminaba el workspace online, la galería seguía con ese listado hasta el ciclo de 30 segundos. Ahora muestra la copia enseguida mientras consulta metadatos por red al abrir, volver al primer plano o actualizar. Solo muestra Sin conexión después de un fallo de red real con una copia disponible; 401/403 no usan la copia como alternativa.

Al abrir la app y después de validar la sesión se precarga exclusivamente el listado raíz permitido, sin descargar originales ni recorrer el árbol. Precarga y apertura simultánea de la raíz comparten una petición; cada consumidor comprueba cancelación y ámbito/generación al terminar. Las demás secciones no reciben permiso de escritura por una respuesta de Drive: la galería espera la revalidación de sesión para recuperar sus controles. Los 30 segundos quedan como actualización periódica mientras la vista sigue abierta, sin retrasar la primera consulta.

Cambios nativos compartidos en cliente, store, lifecycle y galería; misma web v71 y conexiones existentes. Sin migraciones, datos reales de prueba, notificaciones ni despliegue. Las comprobaciones y compilaciones finales se detallan al final de esta guía.


La primera prueba de arranque lento conservó la copia y pasó la ausencia del falso aviso, pero no recibió la carpeta nueva dentro del plazo: `media-immediate-ios-ui.log` conserva esos dos fallos; offline/Fotos y privacidad sí pasaron en ese lote. La revisión encontró que request imponía cinco segundos si había caché incluso a las consultas explícitas, mientras el fixture retenía la sesión ocho segundos. Para lecturas explícitas se conserva ahora el timeout normal de 30 segundos; la copia ya se muestra sin esperar y una conexión lenta puede terminar. El límite de cinco segundos se mantiene para lecturas con fallback. La prueba de red forzada comprueba también este timeout. Se conservan las aserciones de actualización antes del siguiente ciclo y los informes intermedios.


La repetición de ambos arranques con el límite de cinco segundos retirado pasó, usando un plazo total de 15 segundos desde el segundo lanzamiento para recibir BOGOTÁ y recuperar Subir sin pulsar Actualizar. La revisión unitaria detectó que URLRequest conserva 60 como valor propio aunque la sesión configure 30; se hizo explícito el timeout de la sesión en cada petición para que el contrato sea verificable. El informe intermedio mantiene esa aserción fallida (60 frente a 30), sin eliminarla. Los resultados finales corresponden a la asignación explícita de 30 segundos y se registran a continuación.


Verificación de la fuente final con timeout explícito: **83 unitarias iPhone aprobadas y una comprobación física omitida**, más los **dos arranques de administrador/fotógrafo aprobados** en `media-immediate-ios-final2.xcresult` (**TEST SUCCEEDED**). Se verifica copia antes de recibir el nuevo listado, ausencia inicial de login/Sin conexión y actualización/acción Subir en un plazo total de 15 segundos sin refresco manual. Offline/Fotos simuladas y privacidad pasaron en el primer lote y se reutilizan: la corrección final solo aumenta el plazo de lecturas explícitas. **93 unitarias Mac aprobadas** en `media-immediate-mac-unit-final2.xcresult`. Release iPhone sin firma y Mac universal correctos en `media-immediate-ios-release-final.log` / `media-immediate-mac-release-final.log`; metadatos, IDs y firma estricta de Mac verificados por separado.

Misma app `outputs/JAC Music.app` actualizada a **1.5.1 (7)**, con la anterior en `work/local/mac-media-immediate-previous/JAC Music.app`. iPhone **0.18.1 (30)** queda en el mismo proyecto para **Run sobre el teléfono**; no se afirma instalada en un iPhone físico. Los esquemas y la firma personal se conservan; frente al baseline solo cambian los cuatro valores de versión/build en cada PBX. Push sigue suspendido. Fuente/Git/respaldos locales, sin GitHub ni publicación web.


La revisión detectó la misma dependencia en miniaturas: si los metadatos llegaban antes que el workspace, MediaTile podía omitir la descarga por usar copia local y su tarea no despertaba al volver online. El estado offline pasa ahora explícitamente a la celda y forma parte de la identidad de su tarea; al validar la sesión reintenta la miniatura inmediatamente, sin descargar originales ni esperar otra vuelta de 30 segundos. Se añade un arranque con workspace retenido de forma asíncrona para probar ese orden de respuestas.


Cierre de miniaturas: `media-immediate-ios-thumbnails-final.xcresult` terminó **TEST SUCCEEDED**, repitiendo las **83 unitarias y una comprobación física omitida** y el nuevo recorrido con workspace asíncrono de ocho segundos. Se abre la carpeta mientras Subir aún está oculto, se comprueba el marcador y después miniatura/Subir antes del plazo total de 15 segundos sin refrescar. Son **cinco recorridos iPhone distintos aprobados** entre los lotes (dos arranques, miniaturas, offline/Fotos ficticias y privacidad). Mac repitió **93 unitarias** con esa fuente en `media-immediate-mac-unit-final3.xcresult`.

El primer runner UI de Mac no llegó a ejecutar casos por timeout al activar la automatización. No se cambiaron TCC, seguridad ni preferencias. Tras comprobar que no quedaban runners/xcodebuild activos, se reinició solo testmanagerd del usuario de estas pruebas; el único reintento de los tres casos pasó en `media-immediate-mac-ui-retry.xcresult` (galería, reapertura offline/documento privado y privacidad). Se conserva también el informe de infraestructura fallido.


Última fuente de miniaturas: el recorrido Mac fotógrafo/foto/video se repitió y pasó en `media-immediate-mac-gallery-final3.xcresult`. Las compilaciones que se entregan son `media-immediate-ios-release-final3.log` y `media-immediate-mac-release-final3.log`, ambas **BUILD SUCCEEDED**, posteriores a ese ajuste. La web sigue en v71 sin cambios de servidor o publicación durante esta corrección. Captura final de galería revalidada en `work/local/media-immediate-ios-screens/iphone-fotografia-revalidada.png` y manifiesto de entradas local para comprobar la fuente compilada.

Cierre: Release Mac universal correcto y actualizado en outputs/JAC Music.app, firma estricta verificada; copia anterior en work/local/mac-photo-upload-menu-previous. Compatibilidad iOS compilada, iPhone/iPad sin cambios de distribución y sin instalación física. Búsqueda/creación/subida ficticia PNG+MOV comprobadas directamente en Mac, sin repetir el ejecutor UI que antes no inicializaba. Web v84 publicada en Site appgprj_6aa0260b82a88191a47960614238350a, fuente privada bf15d6707fa98db6275922ed015ba8c1c5074d57; versión appgprj_6aa0260b82a88191a47960614238350a~appgver_d33bfcbbe3948191bdbab50a10f9e3c1, despliegue appgdep_6ad4160410f88191b3f01880cd95b64d succeeded, env_set_revision2. Misma audiencia/dominio/DB/BUCKET/R2/secretos/conexiones; sin nuevas migraciones. Git local b329445. ZIP opcional76archivos outputs/JAC-Mac-Fotografia-menu-fuente.zip SHA256 4624d37a0c759245770e2f52e79bff8182e66ae48dac872e38df80b92acc82ba, desde Git portátil sin claves ni configuración personal. Sin GitHub, Actions ni nuevos trabajos Cloud.
