# Borrado de Fotografía para Anderson

19 de octubre de 2026. Camilo autoriza a la cuenta existente `anderson` a eliminar archivos ya subidos y carpetas de Fotografía, incluyendo contenido subido por otras cuentas.

## Alcance

La regla permite borrar a administradores existentes y a `anderson`, siempre con acceso actual a Fotografía. Es independiente del permiso de subir y no concede CRM, usuarios, conexiones ni nómina. El nombre de usuario único de la cuenta, no el nombre visible ni el correo, identifica esta autorización; renombrar esa cuenta retira la excepción. La cuenta no se convierte en administradora ni se reconfiguran sus secciones en D1.

La misma condición existe en `canDeleteMedia`, `mediaStoredGuard` y `PayrollUser.canDeleteMedia`. Las guardas SQL comprueban identidad real, sesión, revisión de cuenta y Fotografía durante la operación. El feed publica `canDelete` y las operaciones pendientes para los usuarios autorizados. Se mantienen origen, colección, ancestros, revisión del archivo, confirmación y recuperación de errores; la raíz no se puede borrar.

Web permite eliminar fotos y videos desde Opciones y su vista previa; carpetas desde la papelera existente. En iPhone, la selección múltiple permite borrar fotos y videos, y el menú de carpeta permite eliminarla. El cambio nativo requiere pull/Run. No se borran archivos reales como prueba.

## Verificación y publicación

TypeScript y build web correctos. Las 45 pruebas de la galería R2 pasaron, incluidas tres nuevas de Anderson (archivos existentes de otra cuenta, fotos/videos/carpetas, guardas SQL y revocación durante la eliminación). También pasaron permisos de Fotografía, Drive, móvil/OAuth y las 16 pruebas Workerd con servicios interceptados. La primera ejecución Workerd no pudo abrir localhost por el sandbox; se repitió únicamente esa suite con red local habilitada y pasó. Sin datos ni servicios reales como pruebas.

Fuente publicada en `main`, commit `9c22c99c8f02b2b39d311a6c16d1431af2976e5a`. Build de esas mismas fuentes desplegado en Worker `jac-nomina`: versión `3d30e32b-8b7d-4f6b-b1e1-3ed8b2f1eb7c`, despliegue `a79fff45-85a0-4baf-abf1-8f517bae4464`, 100% confirmado mediante la API oficial de Cloudflare. Wrangler informó un error posterior al consultar workers.dev/memberships; la carga y la activación ya estaban completas y verificadas, por lo que no se repitió el despliegue. No requiere migración de datos ni cambios de credenciales/conexiones.

Actions `39280446327` selecciona únicamente cuatro pruebas nativas del permiso, aislamiento financiero y revocación. Compila Mac por el modelo compartido y omite una segunda Release iPhone. A las 15:53 UTC seguía en cola, sin pasos ejecutados. El resultado nativo queda pendiente; conservar los resultados previos de la galería porque sus algoritmos no cambiaron.

Actualización posterior: ejecución `39280446327` completada con **success**; cuatro casos de permisos/borrado iPhone y Release Mac aprobados sobre `9c22c99`. La ampliación posterior del menú a videos/iPad se documenta en PHOTOGRAPHY_LIGHTWEIGHT_PLAYBACK.md.
