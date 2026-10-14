# CRM: shows, abonos y comprobantes

## Uso

Camilo y la cuenta `jac`, como administradores, encuentran **CRM** en la barra lateral, en `/crm`. Las demás cuentas conservan su acceso previo, sin consulta de abonos o comprobantes.

El listado y sus totales muestran únicamente shows de hoy en adelante, usando la fecha de Colombia. Los registros anteriores, abonos y comprobantes se conservan y sus enlaces privados siguen funcionando. El selector comienza en el mes actual.

Al entrar se revisan seis meses de Agenda, desde el mes elegido. Se detectan títulos que contienen nombres de municipios colombianos; usa el listado público DIVIPOLA de DANE, con coincidencia de palabras completas y sin depender de tildes. La detección solo consulta Calendar; crear o eliminar un evento requiere su acción específica. Un título como «Reunión en Pereira» también puede ser detectado: revisa el registro y marca **Ignorar: no corresponde a un show** si hace falta. Un evento sin precio nunca entra automáticamente en nómina.

Abre un show, registra su precio de venta en COP y, opcionalmente, el empresario, observaciones y si es promocional. Cada show tiene su propio saldo:

**Saldo = venta − suma de abonos vigentes.**

Puedes registrar la fecha y el valor de cada abono, una observación y de uno a cinco comprobantes PDF/JPG/PNG, hasta 10 MB en total. Los importes conservan centavos. Si hay un pago superior al precio, aparece **saldo a favor**. El saldo se actualiza al guardar y se consulta cada 15 segundos mientras el panel está visible, además de al recuperar el foco.

Para corregir un pago usa **Anular abono**, indicando un motivo. El pago deja de reducir el saldo; se conservan su historial y comprobantes. Los reintentos del mismo guardado no duplican pagos. Otro registro con el mismo show, valor, fecha y comprobante se rechaza mientras el anterior siga vigente.

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

La pestaña **Abonos** contiene nombre del show/municipio, fecha del show, fecha del abono, valor COP, enlace privado al comprobante en JAC y estado Registrado/Anulado. Hay un identificador oculto para evitar duplicados. Cuando un abono tiene varios archivos, el enlace abre su cuenta en JAC y muestra todos sus comprobantes. Solo los administradores activos pueden abrirlos.

JAC guarda primero el abono y su saldo. La exportación queda pendiente en D1 y se intenta en segundo plano; un fallo de Google no pierde ni duplica el pago. El panel reintenta pendientes mientras está abierto, cada minuto, y permite reintento manual. No es necesario mantener la hoja abierta. Si se cierra el panel antes de completar una entrega fallida, vuelve a abrir CRM para que se reintente.

Cada pago ocupa una fila estable y se escribe como datos literales, no fórmulas. No muevas, borres ni reordenes físicamente sus filas: usa vistas de filtro para consultas. Si una fila pertenece a otro pago, JAC detiene la exportación antes de sobrescribirlo. El límite inicial es 9.999 pagos; ampliar la capacidad requiere ajustar también el límite de integración.

Si Google pierde la respuesta al crear el archivo, JAC busca la hoja por su solicitud estable antes de continuar y no crea una segunda hoja automáticamente. Si sigue sin encontrarla, muestra una verificación pendiente; revisar acceso/Drive antes de intentar cualquier recuperación administrativa.

Hasta completar la autorización y recibir el identificador/enlace reales de Google, no considerar creada ni conectada la hoja.

## Implementación y validación

Migración aditiva `0017_crm_shows.sql`, conservando 0000–0016 y los enlaces D1/BUCKET existentes. Tablas separadas de shows, pagos, auditoría, conexión y cola de exportación. No se reinicializa nómina ni se introducen datos de localhost en producción.

API `/api/crm` y `/api/crm/file`: administradores, sesión/revisión vigente, origen estricto para escrituras, valores enteros en centavos, operaciones atómicas y control de concurrencia. Adjuntos privados en el BUCKET existente. Campos opcionales `crmShowId`/`crmVersion` en nómina; edición móvil anterior conserva los vínculos.

La conexión real y los registros financieros reales no se utilizan como pruebas. La prueba automatizada `tests/crm.test.mjs` usa SQLite en memoria, R2 simulado y todas las salidas Google interceptadas. Las regresiones de nómina, correo, móvil/OAuth, Agenda/Workerd e Itinerarios/Alertas se conservan.

Fuente de municipios: [DIVIPOLA — códigos de municipios, DANE](https://www.datos.gov.co/Mapas-Nacionales/DIVIPOLA-C-digos-municipios/gdxc-w37w), 1.103 registros Municipio, consultados el 14 de octubre de 2026. Revisión futura del catálogo debe conservar las identificaciones de shows existentes.

Google: [permisos de Sheets](https://developers.google.com/workspace/sheets/api/scopes), [autorización por archivo de Drive](https://developers.google.com/workspace/drive/api/guides/api-specific-auth), [OAuth para servidor web](https://developers.google.com/identity/protocols/oauth2/web-server).
