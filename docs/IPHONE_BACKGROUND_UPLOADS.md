# Subidas del iPhone en segundo plano — 0.27.0 (40)

La cola de Fotografía pertenece a la app y sobrevive al cambiar de menú. Al confirmar el lote, mueve los archivos preparados a una bandeja persistente; no usa la carpeta temporal que se borra al restaurar la sesión. Conserva el mismo identificador al reabrir y concilia con el servidor para evitar duplicados. El círculo general, la velocidad reciente, los destinos, errores, pausa y reintentos se conservan.

## Menos espera entre archivos

Dos originales pueden viajar simultáneamente. La miniatura tiene un turno separado: confirmar un original libera su turno para el siguiente mientras se prepara/sube la miniatura. Hay una sola miniatura activa y un máximo de cuatro reservas, para acotar memoria, disco y trabajo pendiente. Los videos conservan sus bytes y la calidad elegida para imágenes no cambia. El 100 % requiere terminar también las miniaturas.

Para un original R2 de una sola parte, el cliente puede enviar el ETag recibido del PUT. La confirmación pasa de cinco a tres llamadas S3 en el camino feliz. R2 comprueba el recibo y JAC conserva HEAD final, tamaño, MIME, metadatos, firma del archivo, pertenencia, permisos y CAS. Una respuesta perdida se recupera sobre el mismo identificador. Clientes anteriores sin recibo siguen usando el protocolo existente.

## Continuidad y privacidad

- iPhone/iPad usan `URLSessionConfiguration.background` y `uploadTask(with:fromFile:)` tanto para los bloques R2 como para las pequeñas órdenes de inicio/confirmación y miniaturas. El delegado recupera tareas por identificadores derivados, rechaza redirecciones y acota las respuestas. R2 recibe exclusivamente su capacidad firmada, sin cookie JAC ni credencial de propietario.
- El manifiesto está cifrado con AES-GCM. Archivos de cola, cuerpos y claves dedicadas usan protección después del primer desbloqueo, necesaria para transferir con la pantalla bloqueada. La sesión principal y las copias privadas existentes mantienen su protección anterior. La copia de sesión de la cola y su clave se guardan solo en Llavero de este dispositivo mientras hay pendientes, nunca en archivos; se retiran al terminar o revocar.
- Cerrar sesión, cambiar de cuenta o perder permisos cancela las tareas y retira los pendientes locales. La autorización del servidor se vuelve a comprobar antes de publicar. Un enlace R2 ya emitido no se revoca instantáneamente; los archivos enviados sin confirmación no aparecen en la galería.
- Las capacidades R2 vencidas se concilian y renuevan con reintentos acotados. Un fallo de red conserva los pendientes. Una negativa de JAC por sesión/permisos no permite continuar.

iOS decide cuándo ejecuta transferencias en segundo plano; ahorro de energía, conectividad y demoras del sistema pueden influir. **Forzar el cierre desde el selector de apps cancela las transferencias del sistema hasta volver a abrir JAC**. La cola guardada permite retomarlas al abrir. Esto no se puede sustituir por un proceso ilimitado de la app. Referencias de Apple: [sesiones en segundo plano](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:)) y [transferencias con archivos y relanzamiento](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background).

## Verificación

Pruebas exclusivamente con archivos ficticios, servicios interceptados y dominios `.invalid`. No se suben ni borran fotos reales como prueba.

- Node24: 137 pruebas aprobadas, incluidos nómina/autenticación/correo, API móvil y Fotografía; 15 Workerd con salidas interceptadas. TypeScript y build web correctos. Informes `work/local/upload-background-{node,worker,tsc,build}.log`.
- Simulador iPhone nuevo: 127 unitarias ejecutadas, 126 aprobadas y una condición de protección física omitida por CoreSimulator. Incluye once casos nuevos de cola, progreso/cancelación del transporte, recibo R2/URL vencida y recuperación de sesión tras desbloquear sin internet. `upload-background-verified.xcresult`.
- Regresión de subir fotos/video y verlos en iPhone aprobada; visor completo/caché/progreso real aprobado en el primer informe. Subida y vista previa de iPad aprobadas reutilizando la misma compilación. `upload-background-{tests,verified,ipad}.xcresult`.
- Mac: 114 unitarias aprobadas y un recorrido unitario final de desbloqueo/offline aprobado; su distribución y producto instalado se conservan. `upload-background-mac-all.xcresult` y `upload-background-unlock-mac.xcresult`.
- Release final y Debug firmado para el iPhone conectado compilados: `upload-background-release-verified.log`, `upload-background-device-build.log`. Se verificaron versión0.27.0(40), bundle, pushNO, cámara/Fotos y cuatro orientaciones iPad; configuración de firma/esquema personales comparada con la base y conservada.

Los informes iniciales de UI se conservan: el ID de un contenedor reemplazaba los del anillo/velocidad y se corrigió sin retirar las aserciones. El recorrido Home espera ahora la ventana interactiva y conserva el estado ya desplegado de la carpeta. Pasó en `upload-background-home-verified.xcresult`: dos archivos conservados/completados tras cambiar de menú, salir a Inicio y volver; ambos visibles en su carpeta. La prueba conserva todas las comprobaciones y añade estado de carpeta y conteo final.

Instalación de0.27.0 sobre el mismo bundle del iPhone de Camilo conectado confirmada por CoreDevice (`upload-background-device-install.json`, outcome success). No se borró la app ni se abrió su contenido real como prueba. El simulador y las inyecciones no demuestran la planificación real de iOS con pantalla bloqueada o relanzamiento: esa comprobación y la velocidad real de la conexión requieren uso físico; no se afirma que se hayan medido. La publicación del servidor se registra al verificarla.

Mismo proyecto, bundle `co.jacmusic.nomina`, firma personal y push suspendido; actualizar con Run.
