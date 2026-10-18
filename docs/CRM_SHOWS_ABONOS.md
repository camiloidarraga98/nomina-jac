# CRM: shows, abonos y comprobantes

## Uso

Camilo y la cuenta `jac`, como administradores, encuentran **CRM** en la barra lateral, en `/crm`. Las demás cuentas conservan su acceso previo, sin consulta de abonos o comprobantes.

El listado y sus totales muestran únicamente shows de hoy en adelante, usando la fecha de Colombia. Los registros anteriores, abonos y comprobantes se conservan y sus enlaces privados siguen funcionando. El selector comienza en el mes actual.

Al entrar se revisan seis meses de Agenda, desde el mes elegido. Se detectan títulos que contienen nombres de municipios colombianos; usa el listado público DIVIPOLA de DANE, con coincidencia de palabras completas y sin depender de tildes. También reconoce los nombres habituales «Cali» (Santiago de Cali) y «Bogotá» (Bogotá, D.C.), sin duplicar municipios ni aceptar fragmentos de otras palabras. La detección solo consulta Calendar; crear o eliminar un evento requiere su acción específica. Un título como «Reunión en Pereira» también puede ser detectado: revisa el registro y marca **Ignorar: no corresponde a un show** si hace falta. Un evento sin precio nunca entra automáticamente en nómina.

Abre un show, registra su precio de venta en COP y, opcionalmente, el empresario, observaciones y si es promocional. Cada show tiene su propio saldo:

**Saldo = venta − suma de abonos vigentes.**

Puedes registrar la fecha y el valor de cada abono, una observación y de uno a cinco comprobantes PDF/JPG/PNG, hasta 10 MB en total. **Arrastra los comprobantes a la zona de adjuntos** o pulsa **Seleccionar archivos** para abrir el explorador. Se leen y validan automáticamente, se acumulan al agregar más y puedes quitar uno antes de guardar. El valor y la fecha del abono se confirman con **Guardar abono**; arrastrar un archivo por sí solo no registra un pago. Los importes conservan centavos. Si hay un pago superior al precio, aparece **saldo a favor**. El saldo se actualiza al guardar y se consulta cada 15 segundos mientras el panel está visible, además de al recuperar el foco.

Para corregir un pago usa **Anular abono**, indicando un motivo. El pago deja de reducir el saldo; se conservan su historial y comprobantes. Los reintentos del mismo guardado no duplican pagos. Otro registro con el mismo show, valor, fecha y comprobante se rechaza mientras el anterior siga vigente.

Los comprobantes nuevos se nombran automáticamente con el show y un consecutivo por show, conservando la extensión real: `Copacabana-1.pdf`, `Copacabana-2.png`, etc. El contador continúa entre abonos, incluye los comprobantes de pagos anulados y no consume números ante errores o al reintentar un pago ya guardado. El nombre definitivo se reserva en la misma transacción que registra el abono para evitar colisiones concurrentes. Los comprobantes anteriores conservan su nombre y se tienen en cuenta para continuar el contador.

Los comprobantes se abren directamente desde JAC y requieren sesión activa de administrador. Los enlaces compartidos no hacen público el archivo. La autorización se comprueba antes y después de leer R2.

## Abonos y shows desde el listado

**Registrar abono** aparece arriba del CRM. Selecciona el show, registra valor/fecha/observación y adjunta comprobantes, sin abrir primero su cuenta. El selector incluye los shows activos de hoy en adelante del rango consultado, independientemente del texto de búsqueda. Los que aún no tienen precio aparecen deshabilitados con una indicación para registrarlo. La opción anterior dentro de cada cuenta sigue disponible.

**Crear show** abre un formulario completo para Camilo y `jac`: nombre, una **Fecha del evento**, todo el día u horas de Colombia, lugar y descripción compartida; valor de venta, empresario, observaciones internas y condición promocional; primer abono opcional con fecha, valor y PDF/JPG/PNG. Los shows se crean para un único día. En todo el día, JAC convierte internamente el fin al día siguiente exclusivo que requiere Google. Si eliges horas, el fin debe ser posterior al inicio dentro de la misma fecha de Colombia.

Calendar recibe exclusivamente el nombre, las fechas/horas, el lugar y la descripción compartida. **Precio, empresario, observaciones internas, abonos y comprobantes permanecen privados en CRM.** El mismo evento aparece en Agenda web, iPhone y Google Calendar porque se usa el calendario compartido existente. En iPhone se recibe al revalidar Agenda con internet; su copia descargada sigue funcionando como antes. No requiere un binario nuevo ni cambia la configuración de sus notificaciones.

Se reutilizan los permisos y la conexión de Agenda. No se añaden invitados ni envíos JAC al crear un show. Se usa el ID estable existente y se revalidan sesión y calendario antes de la escritura. Una nueva migración aditiva `0018_crm_creations.sql` conserva el identificador, huellas y etapa de cada solicitud; no almacena claves ni copias de comprobantes allí.

Google Calendar y D1/R2 son servicios distintos: puede quedar creado el evento mientras un adjunto o el primer abono aún no se confirman. El formulario lo indica y conserva el intento para **Reintentar creación**, sin crear otro evento ni duplicar el abono. No cierra quincenas ni borra un evento real para fingir una reversión. Un reintento completo tampoco vuelve a aplicar el precio si un administrador ya lo modificó. Si se cierra el formulario, una solicitud idéntica del mismo administrador recupera el identificador guardado; otros datos para el mismo evento se rechazan para evitar duplicados.

El primer abono utiliza la misma autorización, validación de archivos, suma atómica, auditoría y cola de Google Sheets que el registro ordinario.

## Quincenas

Al crear una quincena nueva, web e iPhone reciben automáticamente los shows activos, presentes en Calendar y con precio, dentro de las fechas del período. Se copia el precio, la condición promocional y el vínculo al CRM. Se cargan músicos/técnica activos y sus tarifas actuales; los recorridos de conductores empiezan con cero kilómetros. Revisa participantes, tarifas y kilómetros antes de liquidar.

Cambiar Calendar, el precio o los abonos no reescribe quincenas existentes ni cierres históricos. Los abonos no son un gasto ni reducen el valor de venta usado por la comisión. Los cálculos de nómina, gastos por show y comisión siguen sus reglas existentes. Un cambio concurrente del CRM durante la creación rechaza el guardado para que se vuelva a revisar, sin una quincena parcialmente creada.

## Eliminación y sincronización

Dentro de la cuenta del show, **Eliminar evento** pide confirmación con su nombre y fecha actuales. Camilo y `jac` pueden eliminar el evento correspondiente de Google Calendar y retirarlo del listado del CRM. Agenda web e iPhone dejan de mostrarlo al recibir la siguiente actualización con internet. Sin conexión se conserva la última copia descargada hasta reconectar; no es posible recibir un borrado remoto sin red.

Si se elimina directamente en Google Calendar, el CRM comprueba su identificador antes de retirarlo: una omisión del listado o un evento movido a otro mes no se confunden con eliminación. Confirma `cancelled`, 404 o 410 en el calendario accesible original; ante problemas de permisos, red o respuestas inválidas conserva los registros. La revisión cubre seis meses al entrar, al pulsar **Actualizar shows de Calendar** y cada minuto con el panel visible. No se añade un cron ni una conexión externa nueva.

Los eventos eliminados se excluyen de nuevas importaciones y totales del listado. **Abonos, comprobantes, filas de Sheets, auditoría y nóminas existentes se conservan como historial privado**, accesible por sus enlaces autorizados. No se borran archivos de R2 ni se anulan pagos automáticamente. No se pueden registrar nuevos abonos o cambiar precios en un evento eliminado.

La eliminación comprueba sesión, administrador, origen, revisión y calendario original. Usa ETag/If-Match y `sendUpdates=none`, sin invitados ni avisos JAC. Un cambio ajeno exige actualizar y confirmar de nuevo. La intención se guarda atómicamente en el estado y auditoría existentes antes de contactar Google. Una respuesta perdida permite reintentar el mismo evento y confirmar si ya no existe; no se recrea al recibir un listado viejo ni al repetir una creación anterior. Mientras está pendiente, el show queda bloqueado para cambios financieros; **Reintentar eliminación** permite resolverlo. No se importan precios externos ni se adivinan valores.

## Google Sheets: último paso de conexión

En CRM, pulsa **Conectar Google Sheets** y autoriza con `jacmusicestudios@gmail.com`, la cuenta compartida de Agenda. Esta autorización separada usa el mismo cliente OAuth de JAC y su callback vigente, con PKCE y validación de navegador/sesión/cuenta. En el proyecto de Google de ese cliente deben estar habilitadas **Google Drive API** y **Google Sheets API**. No copies claves ni contraseñas al proyecto.

La autorización permite acceso por archivo (`drive.file`), más identificación de la cuenta. JAC crea una hoja privada nueva llamada **Control de abonos JAC**, sin modificar otras hojas ni compartirla públicamente. Las credenciales quedan cifradas y separadas de Agenda y Gmail; no se revoca su autorización al desconectar Sheets.

La pestaña **Abonos** contiene nombre del show/municipio, fecha del show, fecha del abono, valor COP, enlace privado al comprobante en JAC y estado Registrado/Anulado. Hay un identificador oculto para evitar duplicados. El enlace abre directamente la imagen o el PDF, sin pasar por el panel de abonos. Cuando un abono tiene varios archivos, abre el primero que se adjuntó; los demás siguen disponibles en su cuenta del CRM. Si falta sesión, el navegador pasa por el acceso y vuelve al archivo. Los enlaces continúan siendo privados y no contienen credenciales.

La migración `0019_crm_receipt_sequence.sql` deja pendientes las filas anteriores para sustituir sus enlaces al panel por enlaces directos. Se actualizan en las mismas filas mediante la sincronización existente al abrir CRM o pulsar **Reintentar sincronización**, sin crear otro documento ni duplicar pagos. Solo los administradores activos pueden abrirlos.

JAC guarda primero el abono y su saldo. La exportación queda pendiente en D1 y se intenta en segundo plano; un fallo de Google no pierde ni duplica el pago. El panel reintenta pendientes mientras está abierto, cada minuto, y permite reintento manual. No es necesario mantener la hoja abierta. Si se cierra el panel antes de completar una entrega fallida, vuelve a abrir CRM para que se reintente.

Cada pago ocupa una fila estable y se escribe como datos literales, no fórmulas. No muevas, borres ni reordenes físicamente sus filas: usa vistas de filtro para consultas. Si una fila pertenece a otro pago, JAC detiene la exportación antes de sobrescribirlo. El límite inicial es 9.999 pagos; ampliar la capacidad requiere ajustar también el límite de integración.

Si Google pierde la respuesta al crear el archivo, JAC busca la hoja por su solicitud estable antes de continuar y no crea una segunda hoja automáticamente. Si sigue sin encontrarla, muestra una verificación pendiente; revisar acceso/Drive antes de intentar cualquier recuperación administrativa.

Hasta completar la autorización y recibir el identificador/enlace reales de Google, no considerar creada ni conectada la hoja.

## Implementación y validación

Migración aditiva `0017_crm_shows.sql`, conservando 0000–0016 y los enlaces D1/BUCKET existentes. Tablas separadas de shows, pagos, auditoría, conexión y cola de exportación. No se reinicializa nómina ni se introducen datos de localhost en producción.

API `/api/crm` y `/api/crm/file`: administradores, sesión/revisión vigente, origen estricto para escrituras, valores enteros en centavos, operaciones atómicas y control de concurrencia. Adjuntos privados en el BUCKET existente. Campos opcionales `crmShowId`/`crmVersion` en nómina; edición móvil anterior conserva los vínculos.

La conexión real y los registros financieros reales no se utilizan como pruebas. Las pruebas `tests/crm-files.test.mjs` comprueban preparación, validación, acumulación y nombres; `tests/crm.test.mjs` usa SQLite en memoria, R2 simulado y todas las salidas Google interceptadas. Las regresiones de nómina, correo, móvil/OAuth, Agenda/Workerd e Itinerarios/Alertas se conservan.

Fuente de municipios: [DIVIPOLA — códigos de municipios, DANE](https://www.datos.gov.co/Mapas-Nacionales/DIVIPOLA-C-digos-municipios/gdxc-w37w), 1.103 registros Municipio, consultados el 14 de octubre de 2026. Revisión futura del catálogo debe conservar las identificaciones de shows existentes.

Google: [permisos de Sheets](https://developers.google.com/workspace/sheets/api/scopes), [autorización por archivo de Drive](https://developers.google.com/workspace/drive/api/guides/api-specific-auth), [OAuth para servidor web](https://developers.google.com/identity/protocols/oauth2/web-server).

## Rentabilidad, empresarios, preparación y resumen semanal — 15 de octubre de 2026

El CRM conserva el acceso financiero exclusivo de Camilo y `jac`. Las nuevas pestañas principales son **Shows y abonos**, **Resumen semanal** y **Empresarios**. Al abrir un show se encuentran **Cuenta y abonos**, **Rentabilidad** y **Preparación**.

### Rentabilidad por show

**Rentabilidad** permite definir un presupuesto estimado de músicos, técnica, conductores/kilómetros, tiquetes, hoteles, alimentación y otros gastos. Se compara con los costos registrados en la nómina vinculada; el presupuesto no se suma como gasto ni modifica precios, pagos o nómina. El resultado registrado usa el valor de venta de esa nómina y sus costos centrales existentes: honorarios de músicos/técnica/conductores, kilómetros de ese show y gastos directos vinculados. No incluye salarios fijos/dependientes ni recorridos extra, reintegros o viajes ajenos al show.

Los shows importados desde CRM a una quincena se reconocen por su identificador. Para shows antiguos agregados manualmente puede seleccionarse **Vincular show existente de nómina**, sin modificarla. No se adivina el vínculo por nombre o fecha ni se suman vínculos duplicados. Un show de nómina no puede asignarse a dos cuentas CRM; la escritura revisa la versión actual de nómina y preparación.

En una nómina abierta los costos están en construcción. En una cerrada se usa la instantánea histórica; cierres anteriores sin desglose se indican como no disponibles y no se recalculan. Si el precio de CRM difiere de la venta de nómina, se señala y se conserva el valor de la nómina.

Los shows promocionales conservan sus costos reales en rentabilidad, pero esos costos se excluyen de la comisión de Camilo según las reglas existentes. Se muestra el aporte del show a la base y la **comisión revisable de toda la quincena**. El mínimo cero se aplica a la quincena completa; no se crea un pago automático ni una segunda fórmula de liquidación.

### Ficha del empresario

**Empresarios → Nuevo empresario** guarda nombre, empresa, teléfono, correo, ciudad y observaciones. Se puede buscar y editar la ficha, consultar sus shows/saldos y adjuntar contratos o documentos PDF/JPG/PNG. Al crear un show o editar su precio, escribe en **Empresario** y elige una sugerencia para reutilizar el contacto. Busca por nombre o empresa, con o sin tildes. Puedes conservar un nombre escrito libremente; no crea una ficha automáticamente. Al modificar el nombre se retira el vínculo anterior hasta que elijas otra sugerencia.

Los documentos son privados, con autorización de administrador y sesión antes y después de leer R2. Se aceptan hasta 5 archivos/10 MB por envío y 100 documentos por ficha. Los reintentos usan un identificador estable; incluso dos envíos simultáneos del mismo intento publican un único conjunto de adjuntos. No se generan enlaces públicos ni se exportan contratos a Google Sheets.

La migración aditiva `0020_crm_workspace.sql` convierte nombres de empresarios ya registrados en fichas reutilizables, agrupando coincidencias exactas sin distinguir mayúsculas y espacios extremos. No inventa teléfonos/correos ni altera ventas, abonos o versiones financieras. Modificar una ficha no reescribe automáticamente el texto histórico de sus shows.

### Preparación del show

**Preparación** incluye contrato firmado, hotel, transporte e itinerario, con estado **Pendiente / Listo / No aplica**, responsable, fecha límite y observación. Se pueden añadir tareas propias, hasta 30 en total. **Anticipo recibido** se calcula automáticamente con los abonos vigentes, sin una casilla manual que pueda contradecirlos.

Pulsa **Guardar preparación** para confirmar los cambios. Presupuesto y tareas tienen una revisión independiente de la cuenta financiera. Si otro administrador cambia la preparación, el borrador se conserva y se requiere recargar antes de guardar. Cambiar entre pestañas del show conserva el borrador; **Recargar y descartar borrador** lo reemplaza explícitamente. No envía mensajes, hace reservas ni consulta pases privados.

### Resumen semanal

La semana va de lunes a domingo en Colombia. Muestra los shows de hoy en adelante dentro de la semana elegida, su saldo por cobrar, abonos recibidos por fecha del pago, gastos directos por fecha de registro, costos acumulados de los shows de esa semana y tareas pendientes hasta el domingo, incluyendo atrasadas de shows futuros. Se distingue la falta de precio o de costos vinculados; un dato pendiente no se presenta como costo cero confirmado. Las tareas abren directamente **Preparación** del show.

Los gastos registrados en la semana y los costos de shows de esa semana son medidas distintas: un hotel puede registrarse antes del día del show. El resumen excluye eventos eliminados de shows/costos/tareas; los abonos vigentes siguen reflejando su fecha de recepción como historial financiero. Consulta periódicamente mientras el panel está visible y permite actualizar manualmente. Es una vista dentro de CRM, sin correos, notificaciones, cron ni nuevas conexiones externas.

### Validación de esta ampliación

Node 24 local, TypeScript y 184 pruebas sin omisiones: CRM/archivos/concurrencia/contratos privados/migración, nómina/auth/correo/móvil/OAuth, Calendar y avisos con Workerd/D1/R2 locales y todas las salidas simuladas. UI verificada en `127.0.0.1:8773/crm` con empresario/PDF/presupuesto/nómina/tareas ficticios; se comprobó guardado, edición, vínculo a show, cifras y navegación desde el resumen. Captura `outputs/crm60-resumen-local.png`. No se usaron pagos, contratos, eventos ni conexiones reales para pruebas. Esta ampliación es del CRM web; no modifica el binario ni la firma de iOS.

Ajuste visual del 15 de octubre de 2026 (v61): un solo campo **Empresario**, alineado con Valor de venta, sustituye al selector «Sin ficha vinculada» y el segundo campo. Sugerencias blancas con nombre/empresa, navegación con flechas y Enter, cierre con Escape o al salir del campo. Escape cierra primero las sugerencias sin perder el formulario ni su borrador; el cierre habitual del diálogo se conserva cuando la lista ya está cerrada. Mismo componente en Crear show y Editar precio. Sin cambios de API, permisos, esquema o cálculos.

## CRM en la app nativa del iPhone — 0.14.0 (24)

Gestión → CRM reúne las mismas cuentas y API del servidor: próximos shows, precio/empresario con autocompletado, abonos con PDF/fotos y consecutivos existentes, evento de un solo día con primer abono opcional, eliminación confirmada, fichas/contratos privados, presupuesto/rentabilidad/preparación y resumen semanal. Consulta la guía de uso en ios/README.md. Se conserva la conexión existente a Sheets; la autorización inicial se configura desde la web. El acceso se mantiene exclusivo para administradores.

La consulta descargada usa el almacenamiento cifrado por sesión del iPhone. Las escrituras no se encolan offline. No hay cambios de esquema, API o web en esta entrega; el Site sigue en v61. La actualización requiere Run sobre la aplicación instalada y no se instala al publicar la web.
