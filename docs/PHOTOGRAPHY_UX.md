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
