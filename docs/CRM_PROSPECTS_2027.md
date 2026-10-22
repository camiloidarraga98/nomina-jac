# Prospectos de ferias y fiestas2027

## Alcance acordado

Camilo pidió un panel comercial dentro del CRM para trabajar el calendario adjunto de ferias y fiestas de Colombia2027, enviar propuestas individuales o en lotes de hasta20 y seguir las conversaciones. La dirección es `/crm?seccion=prospectos`, pestaña **Prospectos2027**, con los mismos permisos administrativos del CRM. No crea shows, reservas, contratos, eventos de Calendar, abonos o cambios de nómina.

Confirmó usar **jacmusicestudios@gmail.com** y permitir el saludo institucional «Señor alcalde y equipo de la Alcaldía de [municipio]» cuando no se conozca el nombre. El nombre se personaliza al completarlo en la ficha. La llamada a la acción es el WhatsApp **+57 3125064091**, `https://wa.me/573125064091`.

## Calendario y brochure

El Excel aportado contiene **666 oportunidades de eventos**, **504 municipios** y **24 etiquetas territoriales canónicas**:23 departamentos y Bogotá. Se normalizaron dos variantes por mayúsculas. Las666 fechas están por confirmar: se conservan periodo y mes proyectado; no se inventa un día de show. Una oportunidad tiene mes ambiguo. No incluye nombres de alcaldes.

Hay527 direcciones de correo diferentes y29 filas con más de un contacto. Varias celebraciones comparten correo: se elige una dirección por ficha y la reserva de destinatario evita enviar varias propuestas iniciales al mismo correo en2027. Los directorios auxiliares de territorios y localidades no se importan como otras oportunidades.

Los contactos, el Excel, su contenido original y el PDF permanecen fuera del repositorio público. La importación privada utiliza UUID deterministas, `source_id` estable e `INSERT ... ON CONFLICT DO NOTHING`; repetirla no sustituye fichas editadas ni crea lotes de correo. Los artefactos operativos están en `work/local/prospects-import-*`, ignorados por Git.

El brochure tiene10 páginas y7.461MiB. Se guarda privado e inmutable en R2 bajo `crm/prospects/brochures/<sha256>.pdf`, con referencia en D1. Solo se entrega por API tras verificar la sesión del CRM y volver a validarla al leer R2. No se publica como recurso estático. El correo adjunta el documento completo.

## Trabajo del equipo

- Buscar y filtrar por municipio, departamento, mes estimado o etapa comercial.
- Completar alcalde, correo elegido, fecha proyectada, notas y próximo seguimiento. La fecha no se convierte en una reserva.
- Seleccionar destinatarios distintos mediante las acciones de10,15 o20, o individualmente.
- Preparar una propuesta: revisar los correos concretos, destinatarios, asunto, cuerpo y brochure. Esta acción no envía.
- Confirmar **Enviar N correos individuales**. Cada mensaje tiene un único destinatario; no se usa un correo colectivo con CC/BCC.
- Consultar progreso, abrir la conversación en Gmail y registrar el siguiente paso comercial.

La plantilla permite `{{municipio}}`, `{{departamento}}`, `{{fiesta}}`, `{{alcalde}}`, `{{saludo}}`, `{{periodo}}`, `{{fecha}}`, `{{whatsapp}}` y `{{anio}}`. El mensaje se presenta como enviado por el management de Jhon Alex Castaño, ofrece su banda en vivo con nueve músicos y repertorio respaldado por el brochure, invita a conversar sobre programación y presupuesto y termina con el contacto de Camilo. No promete disponibilidad ni usa métricas externas sin comprobar. No necesita una llamada pagada de IA por destinatario.

Las etapas comerciales son **Nuevo, Contactado, Interesado, En negociación, Ganado, Descartado y No contactar**. Se distinguen de **En cola, Enviando, Enviado, Error, Por confirmar y Cancelado**, que describen el transporte del correo. Gmail puede confirmar que aceptó un envío; esto no acredita entrega ni lectura. Una respuesta no se convierte automáticamente en interés, venta o show confirmado.

## Envío y reintentos

El lote guarda una instantánea de destinatario, asunto, cuerpo y brochure con UUID idempotente. El hash de la vista previa impide confirmar silenciosamente un contenido distinto si cambió una ficha o el documento. Repetir el mismo UUID tras perder una respuesta recupera el lote existente; no duplica correos.

La cola D1 se procesa desde el mantenimiento existente, con reservas atómicas y un único emisor a la vez. Los mensajes se transmiten de forma acotada usando la API media upload de Gmail y un stream MIME: no se acumulan20 copias del PDF en memoria ni se codifica otra vez toda la petición en base64. Las credenciales permanecen cifradas. Se comprueba la sesión y el permiso que autorizaron el lote, así como el contacto y la cancelación, antes de contactar al proveedor.

Un timeout,5xx, respuesta inválida o resultado que pudo haberse enviado queda **Por confirmar**. Nunca se reenvía automáticamente; se revisa Enviados en Gmail. Los rechazos seguros permiten corregir y preparar otra propuesta explícita. Cancelar un lote retira los mensajes que todavía no han comenzado: un envío que ya llegó al proveedor puede terminar y debe conservar su estado real.

## Respuestas

La conexión previa de Gmail permite enviar, pero no leer respuestas. **Activar seguimiento de respuestas** solicita una autorización opcional separada para el mismo correo, con `gmail.send` y `gmail.metadata`. Reutiliza el cliente y callback de Google registrados; no modifica los tokens ni permisos de nómina.

El seguimiento consulta exclusivamente los hilos que creó este módulo. Lee cabeceras y fechas, sin descargar cuerpos, adjuntos ni otras conversaciones del buzón. Diferencia respuesta humana, respuesta automática y rebote. Las revisiones se acotan por pasada; también hay consulta manual y registro de respuesta recibida sin autorizar lectura automática.

El callback está vinculado al navegador, sesión, actor y revisión de configuración, con state de un solo uso y PKCE. La autorización requiere la interacción del administrador con Google; publicar el botón no concede ese permiso por sí solo.

## Implementación

Migración aditiva `0035_crm_prospects.sql`: prospectos, brochures, lotes, entregas, reserva del emisor y conexión opcional de seguimiento. Fuente compartida client-safe en `lib/crm-prospects-core.ts`; datos y cola en `lib/crm-prospects-store.ts`; correo y OAuth en sus módulos independientes. API `/api/crm/prospects` privada, sin caché compartida, con validación de origen y cuerpo JSON limitado. El panel no inicia sincronizaciones de Calendar o Sheets al trabajar en esta sección.

Las comprobaciones de correo utilizan exclusivamente destinatarios `.invalid`, credenciales ficticias, D1/R2 desechables y proveedores interceptados. No se envían propuestas reales como prueba. La carga del calendario y brochure es la importación de producción pedida por Camilo y mantiene la cola vacía hasta que un administrador confirme un lote.

## Verificación y carga inicial ·22 de octubre de2026

**28 casos de servidor, correo, OAuth, API, mantenimiento y Workerd aprobados**, más **cinco recorridos de navegador con65 aserciones distintas** en390/1440px. Incluyen copia íntegra de un PDF sintético de7.823.266bytes después de MIME streaming, preview sin correo, deduplicación, UUID estable/reintento tras acuse perdido, cambios de contacto/PDF/permisos, robo del lease, aceptación Gmail seguida de fallo D1, respuestas humanas/automáticas/rebotes y OAuth separado. La integración Workerd usa D1/R2 desechables y Gmail interceptado. Se comprobó que abrir esta pestaña no ejecuta Calendar, Sheets o acciones de shows.

TypeScript y build final Cloudflare correctos. Se conservan resultados ya aprobados: solo se repiten los casos afectados por ajustes. El navegador detectó que403 retiraba los datos pero no mostraba el aviso; se corrigió y se repitió únicamente ese recorrido. El build final incluye ese cambio del cliente. La primera integración Workerd requería una fecha más nueva que el binario local; se ajustó exclusivamente la fecha del runtime de prueba y se repitió ese caso, conservando los otros seis aprobados. La fecha de compatibilidad de producción no cambia. Las fuentes de UI coinciden con el informe final y el snapshot/journal0035 son coherentes.

Migración0035 aplicada en D1. Importación privada confirmada: **666 oportunidades,504 municipios,666 fechas proyectadas sin día inventado y cero lotes/entregas**. No se modificaron fichas de Empresarios, shows, abonos o nómina. La primera carga directa a R2 recibió403 (`Authentication error`, código10000). Camilo actualizó el permiso y confirmó reintentar: el PDF se subió, se leyó de vuelta por completo y coincidieron sus7.823.266bytes y SHA256. Solo entonces se registró como listo en D1. La conexión de envío compartida figura activa; el seguimiento automático permanece opcional hasta autorizarlo con Google. No se envió ningún correo durante esta preparación.

Publicación confirmada el22 de octubre a las **09:26 de Colombia**: fuente funcional `063a3ba`, versión **`217b018f-3913-4edc-ac9f-57e91b15659a`**, deployment **`a041f8c5-b4cb-40f3-9c0f-903885e1a41e`**, tráfico **100%**. Se conservaron los14 bindings/secretos requeridos mediante `versions upload --keep-vars`, los dos cron y las conexiones existentes; sin cambios de DNS o recursos nuevos. Acceso: **https://jhonalexcastano.com/crm?seccion=prospectos**, con sesión administrativa JAC. La activación/configuración se verificó por API de Cloudflare; el dominio público no está permitido por la política de red del entorno, por lo que la comprobación visual y de correo fue local con servicios interceptados. Autorizar Gmail para seguimiento es una acción pendiente del administrador desde el botón de la página, y no impide usar el envío ya conectado ni el seguimiento manual.
