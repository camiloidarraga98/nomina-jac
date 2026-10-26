# Fotografía nativa: originales, descargas y visor ·26 de octubre de2026

Camilo pidió retirar la espera de compresión de videos, eliminar descargas de carpetas para liberar espacio, guardar fotos directamente en el carrete, poder contraer carpetas durante una descarga y acercar el visor al comportamiento de Fotos del iPhone. App y widget se actualizan juntos a **0.37.0(55)**; Team, bundles, entitlements, AppGroup, permisos, servidor y formato de descargas se conservan.

## Videos

La nueva elección sustituye la compresión obligatoria anterior. Se envía el archivo original, sin exportación AVFoundation ni conversión HDR/SDR, conservando contenedor, nombre, audio y calidad. La revisión local lee sólo hasta64 bytes y comprueba tamaño/formato, fuera de la interfaz. Fotos usa `.current` para evitar pedir una conversión compatible al sistema. El importador sigue necesitando copiar el archivo al espacio privado de JAC y descargarlo desde iCloud si no está local: no se promete inicio instantáneo para cualquier tamaño/conexión.

La cola adopta el mismo UUID/archivo; ya no exige la marca histórica de compresión. Los trabajos guardados anteriormente mantienen sus bytes y desplazamientos, sin recodificarse ni sustituirse durante una reanudación. La generación de miniaturas y la reproducción adaptativa siguen sus procesos separados. Subir un original de mayor tamaño puede tardar más en la red; se elimina el trabajo de compresión previo, no el tiempo de transferencia.

## Descargas locales

El menú de cada carpeta con originales locales ofrece **Eliminar descarga sin conexión**. Abarca sus subcarpetas conocidas, retira originales cifrados y marcas locales de descarga, y conserva metadatos, otras carpetas, otras sesiones y todos los archivos remotos. No usa tombstones de borrado del servidor. Puede descargarse de nuevo. Una época local impide que una escritura iniciada antes de la retirada vuelva a instalar esos bytes. Se muestra cuánto espacio de originales se retiró; las miniaturas y vistas temporales conservan sus presupuestos independientes.

El estado del menú se prepara en una tarea fuera de la interfaz y se instala sólo para la misma sesión. No añadir consultas a disco/Llavero en el dibujo de las filas. La acción se deshabilita mientras hay una descarga de carpeta activa para evitar interferir con su resultado.

Contraer/expandir carpetas ya no depende del indicador global de transferencia. La descarga sigue en su controlador y no se cancela al cerrar una fila. Borrado y otras operaciones incompatibles mantienen sus controles.

## Guardar en Fotos y visor

Mantener presionada la foto visible ofrece **Guardar en Fotos**. Guarda el original mediante PhotoKit, sin hoja de compartir ni JPEG de vista previa. El menú individual y el botón de selección múltiple también guardan directamente; Disponible sin conexión continúa como una opción separada. Pedir permiso de agregar a Fotos antes de descargar, validar sesión/revisión alrededor del trabajo, limpiar temporales y no repetir escrituras al tocar de nuevo mientras hay una en curso. Una escritura ya aceptada por Fotos queda en la biblioteca del usuario.

El visor muestra el nombre de la carpeta en la cabecera y miniaturas navegables abajo, sin X, puntos suspensivos, nombre de archivo ni flechas. Deslizar horizontalmente cambia de foto; ampliar mantiene el paneo de la imagen; un arrastre vertical en escala normal cierra y restaura la misma carpeta. Los gestos de salida arriba/abajo y escape de accesibilidad sustituyen el botón de cierre. La tira usa miniaturas compartidas limitadas, nunca originales para sus celdas. Se conserva el modelo de selección inmediata, precarga, progreso, revalidación y límites de residentes.

## Verificación y entrega

Corrección posterior al reporte de Xcode: `gestureRecognizerShouldBegin(_:)` ya existe en `UIView`. La declaración del visor debe llevar `override`, incluso al implementar `UIGestureRecognizerDelegate`. Se añade esa palabra sin alterar la decisión de gestos, zoom ni versión55. La comprobación de esta corrección se limita a compilar el bundle iOS; los recorridos funcionales anteriores siguen pendientes si no hay resultados de Apple.

Pendiente de registrar la comprobación focal de Apple: videos originales y HDR, cola durable, eliminación local recursiva/aislada/repetible y barrera de escrituras tardías, permiso y sesión en guardado directo, modelo del visor, cinco recorridos de interfaz y seis presupuestos de fluidez; Release iPhone/Mac. Datos ficticios y servicios interceptados, sin biblioteca real ni avisos/subidas de producción. La instalación física sigue requiriendo pull/Run o Archive/Upload a TestFlight desde el Mac del propietario.

Fuente `695fdba` publicada en main. [Comprobación Apple40367049838](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40367049838): el primer intento permaneció15minutos en cola y terminó sin asignar runner a ninguno de sus tres jobs, con pasos vacíos y resultado `cancelled`; el resultado general figura `failure`. No hay registro de compilación (descarga del log devuelve404). **No representa pruebas de la aplicación aprobadas ni un error de compilador observado.** Se solicitó una única repetición del job de iPhone, que quedó en cola como121737592432; Release iPhone/Mac siguen sin ejecutarse. Revisar el estado actual antes de repetir o indicar que está validado. Linux no tiene Xcode/Swift ni simulador para sustituir esa comprobación.

Comprobaciones estáticas locales: YAML del workflow y sus12 bloques Bash analizados correctamente, diff sin errores de espacios, app/widget con cuatro configuraciones coincidentes55/0.37.0 y ausencia de AVAssetExportSession en el preparador de producción. La validación funcional, compilaciones y capturas nativas **permanecen pendientes**; no inferirlas de estas comprobaciones.
