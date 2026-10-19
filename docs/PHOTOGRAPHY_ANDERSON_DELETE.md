# Borrado de Fotografía para Anderson

19 de octubre de 2026. Camilo autoriza a la cuenta existente `anderson` a eliminar archivos ya subidos y carpetas de Fotografía, incluyendo contenido subido por otras cuentas.

## Alcance

La regla permite borrar a administradores existentes y a `anderson`, siempre con acceso actual a Fotografía. Es independiente del permiso de subir y no concede CRM, usuarios, conexiones ni nómina. El nombre de usuario único de la cuenta, no el nombre visible ni el correo, identifica esta autorización; renombrar esa cuenta retira la excepción. La cuenta no se convierte en administradora ni se reconfiguran sus secciones en D1.

La misma condición existe en `canDeleteMedia`, `mediaStoredGuard` y `PayrollUser.canDeleteMedia`. Las guardas SQL comprueban identidad real, sesión, revisión de cuenta y Fotografía durante la operación. El feed publica `canDelete` y las operaciones pendientes para los usuarios autorizados. Se mantienen origen, colección, ancestros, revisión del archivo, confirmación y recuperación de errores; la raíz no se puede borrar.

Web permite eliminar fotos y videos desde Opciones y su vista previa; carpetas desde la papelera existente. En iPhone, la selección múltiple permite borrar fotos y videos, y el menú de carpeta permite eliminarla. El cambio nativo requiere pull/Run. No se borran archivos reales como prueba.

## Verificación y publicación

Pendientes de registrar al finalizar: pruebas locales de API/SQL con D1 y S3 simulados, build web, comprobaciones nativas limitadas al permiso y despliegue del Worker propio. No requiere migración de datos ni cambios de credenciales/conexiones.
