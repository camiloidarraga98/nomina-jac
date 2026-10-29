# Datos del pase enviados desde Slack

Camilo propuso el 25 de octubre de 2026 acompañar cada PDF con Silla, Hora de salida, Hora en sala y Aerolínea para resolver los pases cuyo diseño impide extraer los valores. La integración usa la descripción del mismo mensaje firmado de Slack y conserva el PDF/código original y el destinatario privado asignado al canal.

## Formato

Publicar **un solo pase por mensaje**, con el PDF y el texto juntos en el canal correspondiente:

```text
Silla: 12A
Hora de salida: 18:45
Hora en sala: 17:45
Aerolínea: Avianca
```

Usar la hora local indicada por la aerolínea, preferentemente formato de 24 horas. Se normalizan también AM/PM, mayúsculas, acentos y etiquetas en negrita de Slack. Los campos vacíos se omiten; `Silla: Sin asignar` conserva la ausencia de silla y evita sustituirla desde el código. Campos repetidos o valores no válidos descartan el bloque completo para no mezclar vuelos. El PDF sigue importándose con su flujo anterior.

Desde la corrección del29 de octubre de2026 se acepta también `18:45 (hora Colombia, UTC−5)` y el equivalente explícito `hora de Colombia`/`COT` con `UTC-5` o `UTC-05:00`. La anotación describe la misma hora local y se retira antes de guardar HH:mm: no se suma ni resta cinco horas. Se siguen rechazando otra zona, una segunda hora, texto arbitrario o controles de dirección. El encabezado libre del mensaje no se guarda ni selecciona el destinatario.

El mensaje debe contener su propio texto y adjunto. Un comentario de texto enviado por separado no se asocia al archivo; no se consultan el historial ni las respuestas del hilo. Una respuesta que incluya su propio PDF y descripción sí es autosuficiente. Varios archivos en el mismo mensaje conservan la importación anterior sin aplicarles la descripción común. El nombre del archivo sigue aportando pasajero, ruta y fecha según el formato vigente.

## Prioridad de los datos

La API entrega `boardingDetails` con los cuatro campos opcionales. En la app, los valores de la descripción tienen prioridad por campo; la lectura local existente completa los ausentes. Un bloque completo permite mostrar silla y horarios sin esperar a analizar el documento. La aerolínea se muestra discretamente junto al pasajero. La web muestra los datos de la descripción junto al adjunto privado.

La hora en sala escrita se respeta. Si falta, se calcula salida menos 60 minutos, conservando «Día anterior» al cruzar medianoche. Esta decisión nueva sustituye el cálculo obligatorio anterior cuando hay una hora en sala explícita. Las horas son civiles: no se convierten a UTC ni se inventa la zona del vuelo.

La preparación de Apple Wallet puede usar los datos como sugerencias revisables de un único archivo/tramo; el código, los datos ya editados y la confirmación del usuario se conservan. No se modifican certificados, firma, conexiones ni el documento original.

## Persistencia y acceso

La migración aditiva 0037 añade `boarding_message` a `jac_slack_files`. El webhook guarda solo los cuatro campos canónicos al encolar el archivo nuevo; el importador los copia al `body` existente del aviso dentro de las mismas guardas de publicación. El texto libre restante de Slack no se almacena. Los itinerarios compartidos continúan ignorando el texto de Slack.

El ID del archivo mantiene la idempotencia: repeticiones o reenvíos del evento no cambian el bloque capturado ni redirigen el destinatario. Se conservan revisión/asignación del canal, verificación de firma/equipo, validación del archivo, restricciones de acceso, revocación, borrado y notificaciones privadas. La API no expone el bloque común a avisos con varios adjuntos. Cachés nativas conservan sesión, archivo, revisión y metadatos canónicos; las respuestas tardías no recuperan valores revocados.

Se aplica a publicaciones nuevas. Editar un mensaje ya importado no actualiza el pase: para añadir una descripción a un pase anterior, subir el archivo de nuevo junto con su descripción en una publicación nueva. No se importa el historial.

## Corrección de horas anotadas ·29 de octubre de2026

El incidente confirmado tenía una silla válida, pero las horas incluían `(hora Colombia, UTC−5)`. La validación anterior descartaba todo el bloque, incluida la silla y la aerolínea; la cola y el aviso quedaron sin descripción. Corregir el parser resuelve las publicaciones futuras; no recupera por sí solo un texto ya descartado. Una reparación puntual del pase propio con los cuatro valores confirmados debe conservar archivo/destinatario/snapshot de Slack, comprobar revisión y asignación vigentes y aumentar la revisión del aviso para invalidar la caché de metadatos. No requiere volver a subir el PDF ni reenviar el evento o el push. No se ejecuta un backfill de otros usuarios.

Comprobaciones locales:133 casos correctos, con6 del parser,61 de notificaciones (evento firmado → cola durable → importación → `boardingDetails`, incluida la silla con horas anotadas),8 en Workerd/D1/R2,5 de datos del código/Wallet y53 de nómina/autenticación/correo/API móvil. TypeScript y build Cloudflare correctos. Servicios externos interceptados y documentos ficticios; el PDF privado recibido no se incorpora a fixtures ni al repositorio público. No cambia código Swift ni versión/firma: las apps0.34.0(52)+ ya consumen estos campos; la actualización canónica del aviso invalida su caché anterior.

## Comprobaciones y entrega

Fuente funcional `e06293882404a74593236afa3e35e2fc62e36373`, versión nativa 0.34.0 (52), mismo proyecto, bundle y Team. Las comprobaciones usan únicamente originales sintéticos, D1/R2 desechables, Slack/APNs interceptados y simuladores. No se envían mensajes, pases ni notificaciones reales como pruebas.

- TypeScript y build Cloudflare correctos. 73 pruebas de servidor aprobadas: 4 de parser, 61 de notificaciones y 8 de Workerd/D1/R2. Se ajustó una expectativa histórica de push para Fotografía a la autorización ya vigente; se conserva el rechazo para una cuenta solo Agenda y las aserciones de revocación.
- 20 comprobaciones de navegador correctas: campos explícitos, aerolínea, medianoche, ausencia de silla, múltiples archivos, compatibilidad anterior, apertura del PDF, plantilla, móvil/escritorio y revocación. Sin errores de runtime ni HTTP externo. Evidencia en `work/local/slack-boarding-browser` y logs de servidor en `work/slack-boarding-backend-*.log`.
- GitHub [40221216604](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40221216604) aprobó Release iPhone y Mac y17 unitarias con Xcode 26.3/Swift 6.2.4. El UI falló al consultar el icono de aerolínea en vez de su texto; un ajuste exclusivo del selector conservó las aserciones y la aplicación original. El seguimiento [40222277269](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40222277269), commit `c656c3c`, aprobó el UI completo109.863s: aerolínea, silla14C, salida18:45 y hora explícita18:05, PDF/código/menú y alternativa de medianoche00:30→23:30. No se repitieron unitarias o compilaciones válidas. Evidencia en `output/slack-boarding-52-ci` y `output/slack-boarding-52-ui-ci`.
- La comprobación web general detectó el snapshot0037 faltante, tres expectativas/stubs anteriores a las notificaciones de Fotografía y FFmpeg ausente en el runner. El seguimiento `c79537d` conserva el runtime, añade el snapshot y actualiza únicamente esas pruebas y el prerrequisito de CI. GitHub [40222159557](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40222159557) aprobó TypeScript/build y33/33 casos focales de los cinco archivos pendientes. Los demás resultados válidos se reutilizan. No se añadieron permisos reales ni se rebajaron las comprobaciones financieras, de sesión o de revocación.

Instalar/subir el binario sigue siendo una operación del Mac del propietario. La publicación web/API ya está activa; la app instalada necesita actualizarse a0.34.0(52) para consumir `boardingDetails`.

Migración 0037 aplicada en el D1 existente `jac-nomina`. Worker `jac-nomina` versión `ba7e4e6c-c8b0-4f06-9458-146f38f98a62`, tag `slack-boarding`, verificado activo al 100% con mensaje «Flight details supplied with private Slack boarding passes». Se comprobaron 14 bindings y los dos crons existentes, sin leer valores de secretos. Dominio y rutas existentes conservados.

La primera orden de publicación encontró una ruta local de configuración Wrangler inexistente; se usó un `XDG_CONFIG_HOME` exclusivo del comando dentro de `work`, conservando credenciales/proxy/CA. La segunda subió y activó la versión; Wrangler terminó con un error del permiso auxiliar de subdominio workers.dev. Se confirmó independientemente la versión activa al 100%, los bindings y los crons mediante consultas de lectura. No fue necesario ampliar permisos, cambiar el subdominio, volver a publicar ni alterar el dominio canónico. La verificación de activación proviene de la API de Cloudflare, no de una prueba con datos reales en el dominio.
