# Avisos automáticos de carpetas nuevas de Fotografía

Actualización del 25 de octubre de 2026. Al quedar disponible una carpeta nueva, JAC prepara el aviso **¡Nuevas fotos disponibles!** con el mensaje **Ya está disponible la carpeta «nombre de la carpeta».** Tocar el aviso abre esa carpeta completa, con sus fotos, videos y subcarpetas autorizados. El nombre puede aparecer en la pantalla bloqueada según los ajustes del dispositivo.

## Cuándo se prepara el aviso

La migración aditiva `0036_media_folder_notifications.sql` registra un candidato dentro de la misma transacción que crea una carpeta futura de R2. No anuncia carpetas anteriores a su aplicación ni archivos añadidos directamente a la raíz. Crear una carpeta vacía no envía nada.

El servidor espera al menos **120 segundos de quietud** desde la modificación más reciente de un archivo publicado correctamente dentro de la carpeta o sus subcarpetas. Debe existir al menos un original de foto/video validado y listo, sin subidas pendientes vigentes ni reservas activas de finalización o miniatura en ese árbol. Una miniatura que termina actualiza ese plazo; no se exige que todos los archivos tengan miniatura ni que Stream haya terminado de preparar los videos.

Es una regla de quietud del servidor compatible con los clientes existentes, no una confirmación matemática del final del lote del cliente: el servidor no conoce archivos todavía en preparación local ni una subida que se retome mucho después. El cron existente revisa los candidatos; los 120 segundos son un mínimo, no una promesa de entrega exacta a los dos minutos.

Cada carpeta tiene **un solo evento**. Reintentos, ejecuciones simultáneas y archivos añadidos después no generan otro aviso para esa carpeta. Cada dispositivo elegible recibe como máximo una entrega de ese evento; una cuenta con varios dispositivos puede recibirlo en cada uno. Un resultado incierto del proveedor no se reenvía automáticamente.

## Quién puede recibirlo

Al publicar el evento se registran los dispositivos habilitados de cuentas activadas y activas con acceso vigente a **Fotografía**, una sesión válida y permiso de notificaciones. No hace falta acceso a Alertas, Itinerarios ni Pases. Un dispositivo registrado después de la publicación no recibe ese evento anterior.

- **Web:** Camilo conserva la preparación de Navegador en Servicios conectados. Cada persona puede permitir o desactivar los avisos en **Configuración general → Notificaciones**, también si solo tiene Fotografía. El registro existente se conserva; el permiso del navegador y la preferencia local siguen siendo necesarios.
- **iPhone/iPad:** usar la app **0.30.0 (44)** o posterior para que tocar el aviso abra la carpeta. Cada persona conserva su permiso en **Gestión → Notificaciones** y en los ajustes del sistema. Las conexiones APNs de TestFlight y Xcode siguen separadas por entorno.
- **Mac:** este cambio no habilita APNs nativo en Mac. Los avisos del navegador de Mac usan el flujo web existente.

Los clientes anteriores pueden seguir creando carpetas y subiendo archivos sin un protocolo nuevo de lotes. Necesitan actualizar la app a la compilación 44 para resolver el destino de este aviso; publicar el servidor no actualiza un binario instalado.

## Apertura y revocación

El navegador abre `/fotografia?carpeta=r2_<UUID>` y conserva ese destino al pedir iniciar sesión. La API de Fotografía valida el acceso y la pertenencia real de la carpeta. El service worker acepta únicamente IDs de carpeta válidos y construye una ruta propia de JAC; no guarda archivos ni respuestas privadas de la API.

La app restaura o valida la sesión, actualiza los permisos y obtiene la carpeta por red antes de mostrarla. No usa la notificación como autorización ni abre una copia anterior si la consulta es rechazada. Descartar respuestas tardías tras cambiar de cuenta/sesión evita mostrar contenido de otra sesión.

El servidor vuelve a comprobar cuenta, permiso de Fotografía, sesión, versión del usuario, registro exacto del dispositivo, conexión R2, carpeta y ancestros antes de llamar al proveedor. Un borrado, cierre de sesión o revocación bloquea entregas pendientes y nuevas consultas. Un aviso ya aceptado por Apple o el navegador no puede retirarse; tocarlo sigue sujeto a los permisos actuales.

## Implementación y verificación

`lib/media-folder-notifications.ts` usa las tablas independientes `jac_media_folder_notifications` y `jac_media_folder_push_deliveries`. El disparador de la migración crea candidatos futuros; el mantenimiento existente publica y entrega. El evento no entra al feed de Alertas/Itinerarios y no cambia sus destinatarios, confirmaciones o adjuntos. El registro compartido de dispositivos admite Fotografía y `GET /api/notices?push=1` devuelve únicamente la clave pública de Web Push a una sesión autorizada para recibir avisos.

Verificación local completada con datos sintéticos y proveedores interceptados:

- **20 casos Node:** 9 del backend de carpetas, 2 de enlaces/permisos, 4 de separación APNs y 5 del service worker.
- **1 caso Workerd/D1:** migración, candidato durable, transacción y entrega única. Se corrigió la fecha del arnés antes de obtener el resultado aprobado.
- **TypeScript y build aprobados.**
- **Recorrido real del componente web:** 15 comprobaciones y dos capturas con APIs ficticias; apertura exacta, historial, inicio de sesión, permisos y retirada de acceso.

La [primera comprobación Apple](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40155833170), sobre la fuente funcional `a50cf3c`, aprobó ocho unitarias, un recorrido UI de iPhone y Release de iPhone/Mac. El bundle compilado confirma0.30.0(44), el mismo identificador y las orientaciones/configuración de documentos existentes. El recorrido iPad no llegó a ejecutarse por faltar el manifiesto de reutilización del producto de pruebas. La corrección `9c9928e` cambia exclusivamente el workflow: prepara ese manifiesto y ejecuta solo la prueba de iPad pendiente, conservando los resultados aprobados sin repetirlos.

El recorrido de iPad exigió ajustar el arnés al arranque de accesibilidad del simulador. La captura y jerarquía de [40157056950](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40157056950) muestran la carpeta exacta y su foto con miniatura cargada; el fallo conservaba un resultado falso de una espera anterior a esa captura. `35c18fd` consulta el estado actual del elemento exacto con una espera acotada de60s, manteniendo apertura de foto, nombre del archivo y regreso a la raíz. Estas correcciones afectan exclusivamente pruebas/workflow; la app sigue idéntica a `a50cf3c`.

**Límite observado en iPad:** [40157594315](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40157594315) se detuvo dentro del motor de accesibilidad con `Failed to get matching snapshots: Timed out while evaluating UI query`, antes de la captura y de las comprobaciones posteriores de esa ejecución. No demuestra un cierre de la app ni ausencia de la carpeta. La carpeta exacta y la miniatura de su foto están confirmadas visualmente por la captura anterior; el recorrido automático completo de iPad **no quedó aprobado**. Se detuvieron las repeticiones del mismo arranque en frío, conservando las ocho unitarias, UI de iPhone y ambas compilaciones aprobadas. Evidencias compactas: `output/photo-notices-native-ci/combined-evidence.json` y `ipad-visible-route-evidence.json`. La firma, instalación y recepción física de esta entrega siguen en el Mac/TestFlight y dispositivos de Camilo; no se deducen de CI.

**Web/API publicado:** fuente `a50cf3c` en main; migración0036 aplicada correctamente en D1 y nueva versión del Worker existente verificada activa al100%, conservando los14 bindings/secretos y ambos crons. No se crearon carpetas reales ni se enviaron notificaciones reales como prueba. Evidencia local de migración/despliegue en `work/local/photo-notices-*`. El workflow de inspección puntual se retiró después de obtener los diagnósticos; el límite de automatización de iPad queda registrado arriba.
