# Subidas web de Fotografía · 26 de octubre de 2026

Camilo informó un lote atascado en 0 %, con archivos pendientes y el aviso de conexión interrumpida incluso al reintentar. Corrigió el navegador reportado a **Safari**. La consulta de metadatos confirmó operaciones pendientes con cero bytes confirmados; no demuestra que se hubiera cortado su conexión a Internet. El CORS del bucket ya permite el dominio de JAC, PUT y lectura de ETag. No se leyeron originales ni se hicieron subidas de prueba en producción.

## Corrección

Safari/WebKit usa PUT con fetch desde el documento principal, sin depender del iframe oculto para iniciar la transferencia. Conserva los bytes, destino R2 exacto, credencial de un solo archivo, omisión de cookies/referrer y rechazo de redirecciones. Los demás navegadores mantienen XHR aislado para medir el progreso. El iframe ahora debe confirmar que está listo antes de recibir la capacidad y el Blob: si no arranca en cinco segundos se retira y se usa fetch. Esa alternativa ocurre antes de entregar bytes al iframe, evitando dos PUT simultáneos.

Un ETag válido puede confirmar archivos de una sola parte mediante el recibo que ya admite el servidor. Sigue siendo una pista: R2 y el servidor verifican el objeto final, tamaño, tipo, firma, propietario y acceso antes de publicarlo. Los archivos de varias partes siguen usando el estado canónico del servidor; no se confía en el porcentaje del navegador.

Ante un envío o respuesta inciertos, consultar primero el estado. Si avanzó o ya terminó, no repetir esos bytes. Si sigue en el mismo desplazamiento, permitir hasta dos reintentos automáticos sobre el mismo UUID y número de parte, con la capacidad devuelta por el servidor y fetch como alternativa. Un fallo persistente queda pendiente, con su error específico; Reintentar conserva el UUID. Revocación y desmontaje detienen el proceso. No se agrega un relay de originales por el Worker.

El resumen muestra preparación, envío, confirmación o reintento. Fetch no expone progreso de subida: su confirmación final no se convierte en una velocidad ficticia. El porcentaje final sigue esperando original, miniatura y vista ligera.

## Verificación

- TypeScript y build de Cloudflare; resultados finales registrados al publicar.
- 132 casos Node/Workerd aprobados: 5 de transporte/medidor, 69 de galería R2 y 58 de acceso/Drive/Worker.
- 14 recorridos locales del transporte real minificado y la cola React: bytes intactos, progreso aislado, ruta de compatibilidad, iframe bloqueado, rechazo de redirecciones, cancelación, dos subidas simultáneas, recibo, respuesta de almacenamiento perdida, confirmación final perdida, recuperación transitoria, límite de reintentos/reintento manual sin duplicados, revocación y desmontaje durante la espera.

El navegador automatizado es **Chromium**. La ruta Safari se ejercita con su user-agent y prohibiendo crear el iframe; no equivale a una comprobación en Safari/WebKit real. El bloqueo de scripts de un iframe se reprodujo localmente, pero no se confirmó como causa exacta del dispositivo de Camilo. Los servicios externos y archivos de las pruebas son ficticios, con solicitudes interceptadas; no se envían notificaciones reales.

## Instalación y avisos

Es un cambio web, sin actualización de iOS ni migración de base de datos. Una pestaña ya abierta conserva el JavaScript anterior: esperar a que termine su intento, recargar y seleccionar de nuevo **solo los archivos que no quedaron guardados**, dentro de la carpeta existente. La selección de archivos está en memoria y no sobrevive a una recarga; no prometer conservar el UUID de una selección nueva tras recargar. Durante los reintentos de una misma cola sí se conserva.

Los avisos automáticos mantienen su contrato: un evento por **carpeta nueva**, después de originales listos, ausencia de pendientes y al menos 120 s de quietud, sujeto al cron y permisos de dispositivos. Añadir más archivos a una carpeta ya anunciada no produce otro evento. Las subidas sin confirmar no disparan el aviso. Ver [notificaciones de carpetas](PHOTOGRAPHY_FOLDER_NOTIFICATIONS.md).

Publicación pendiente de registrar.
