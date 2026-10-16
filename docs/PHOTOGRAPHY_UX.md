# Fotografía: navegación, miniaturas y carpetas recientes

16 de octubre de 2026. Cambios sobre el ecosistema existente; conserva Drive, cuentas, permisos, privacidad y copia cifrada.

## Uso previsto

En iPhone, Fotografía ocupa una pestaña principal; Mi cuenta pasa a Gestión. En Mac, Fotografía permanece en la barra lateral principal y Mi cuenta pasa a Configuración. Gestión/Mi cuenta sigue disponible incluso para cuentas limitadas a una sola sección. No se concede Fotografía a quien no tenga ese acceso.

Las carpetas aparecen por creación descendente, con las más recientes primero. La fecha del nombre del evento no sustituye a la fecha de creación; la fecha de modificación sigue sirviendo para comprobar la versión de los archivos. La paginación conserva el mismo orden y los clientes ordenan el listado acumulado con desempates de nombre/ID.

Al entrar en una carpeta se muestran miniaturas ligeras de fotos y videos. No se descargan originales para llenar la cuadrícula. Cuando Drive todavía procesa una miniatura, se conserva un marcador y se permite actualizar o reintentar. Abrir una foto/video conserva la descarga privada y la vista dentro de JAC.

Subir archivos permite usar una carpeta existente o crear una carpeta de evento con fecha/nombre antes de subir el lote. Esto no crea un evento de Calendar ni del CRM. Se conservan el progreso, los identificadores de reintento y el control de permisos durante la transferencia.

Disponible sin conexión y Guardar carpeta en Fotos se encuentran en el menú de cada carpeta: mantener presionado en iPhone o clic derecho en Mac, con un menú de puntos como alternativa accesible. El destino es la carpeta seleccionada. La revisión de cantidad/tamaño, confirmación, progreso y cancelación se conservan. Guardar en Fotos pertenece al iPhone; la copia offline permanece dentro de JAC.

## Verificación y entrega

En este Mac con Node24:35pruebas Drive/acceso y11Workerd aprobadas, incluidos orden entre páginas, creación/subida desde raíz, miniatura pendiente→lista, límite exacto512KiB/rechazo de exceso, redirecciones, rangos y revocación durante la lectura.49regresiones de nómina/auth/correo/móvil/OAuth aprobadas. TypeScript correcto. Informes `work/local/media-previews-drive-final.log`, `media-previews-workerd.log` y `media-ux-regression.log`.

La vista local mostró siete miniaturas cargadas, completó una foto y un video en un evento creado desde raíz (2/2) y otra imagen en un evento dentro de la carpeta actual (1/1). El registro de la instancia ficticia confirmó que antes de abrir originales solo hubo peticiones thumbnail y que los bytes del lote llegaron a su carpeta correspondiente. Una respuesta403 retiró todas las miniaturas y controles. Captura `outputs/fotografia-miniaturas-local.png`. Sin comprobación móvil del navegador: iPhone se verifica con la app nativa. No se crearon carpetas, subieron fotos ni guardaron contenidos reales de prueba en Drive o Fotos. La publicación y los resultados nativos se registran al completarlos.

## Publicación web

Web **v71** publicada **succeeded** en el mismo Site `appgprj_6aa0260b82a88191a47960614238350a`. Fuente privada `5e2d283062e246cc6b717a46766e69cc45fff572`, despliegue `appgdep_6ad257533d1c81918fe4250f964f8e40`, env_set_revision2. Artefacto87entradas, SHA256 `646defe74fc5f0250232af083dab991efd2c1af137f73dac132db680b4ffb483`. Build exacto del Site aprobado con Node24 y proceso oficial de Sites. Se conservan dominio, audiencia, hosting.json, DB/BUCKET, secretos y conexiones; no hay migraciones ni cambios de dependencias/lockfile. Fuente nativa local, sin GitHub ni trabajos Cloud.
