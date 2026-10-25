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

El mensaje debe contener su propio texto y adjunto. Un comentario de texto enviado por separado no se asocia al archivo; no se consultan el historial ni las respuestas del hilo. Una respuesta que incluya su propio PDF y descripción sí es autosuficiente. Varios archivos en el mismo mensaje conservan la importación anterior sin aplicarles la descripción común. El nombre del archivo sigue aportando pasajero, ruta y fecha según el formato vigente.

## Prioridad de los datos

La API entrega `boardingDetails` con los cuatro campos opcionales. En la app, los valores de la descripción tienen prioridad por campo; la lectura local existente completa los ausentes. Un bloque completo permite mostrar silla y horarios sin esperar a analizar el documento. La aerolínea se muestra discretamente junto al pasajero. La web muestra los datos de la descripción junto al adjunto privado.

La hora en sala escrita se respeta. Si falta, se calcula salida menos 60 minutos, conservando «Día anterior» al cruzar medianoche. Esta decisión nueva sustituye el cálculo obligatorio anterior cuando hay una hora en sala explícita. Las horas son civiles: no se convierten a UTC ni se inventa la zona del vuelo.

La preparación de Apple Wallet puede usar los datos como sugerencias revisables de un único archivo/tramo; el código, los datos ya editados y la confirmación del usuario se conservan. No se modifican certificados, firma, conexiones ni el documento original.

## Persistencia y acceso

La migración aditiva 0037 añade `boarding_message` a `jac_slack_files`. El webhook guarda solo los cuatro campos canónicos al encolar el archivo nuevo; el importador los copia al `body` existente del aviso dentro de las mismas guardas de publicación. El texto libre restante de Slack no se almacena. Los itinerarios compartidos continúan ignorando el texto de Slack.

El ID del archivo mantiene la idempotencia: repeticiones o reenvíos del evento no cambian el bloque capturado ni redirigen el destinatario. Se conservan revisión/asignación del canal, verificación de firma/equipo, validación del archivo, restricciones de acceso, revocación, borrado y notificaciones privadas. La API no expone el bloque común a avisos con varios adjuntos. Cachés nativas conservan sesión, archivo, revisión y metadatos canónicos; las respuestas tardías no recuperan valores revocados.

Se aplica a publicaciones nuevas. Editar un mensaje ya importado no actualiza el pase: para añadir una descripción a un pase anterior, subir el archivo de nuevo junto con su descripción en una publicación nueva. No se importa el historial.

## Comprobaciones y entrega

Versión nativa preparada 0.34.0 (52), mismo proyecto, bundle y Team. Las comprobaciones usan únicamente originales sintéticos, D1/R2 desechables, Slack/APNs interceptados y simuladores. No se envían mensajes, pases ni notificaciones reales como pruebas. Resultados de servidor, navegador, compilaciones y publicación se registrarán al finalizar; preparar el código no equivale a instalar la versión nativa ni a desplegar el Worker.
