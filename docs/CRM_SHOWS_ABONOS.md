# CRM: shows, abonos y comprobantes

## Uso

Camilo y la cuenta `jac`, como administradores, encuentran **CRM** en la barra lateral, en `/crm`. Las demás cuentas conservan su acceso previo, sin consulta de abonos o comprobantes.

El listado y sus totales muestran únicamente shows de hoy en adelante, usando la fecha de Colombia. Los registros anteriores, abonos y comprobantes se conservan y sus enlaces privados siguen funcionando. El selector comienza en el mes actual.

Al entrar se revisan seis meses de Agenda, desde el mes elegido. Se detectan títulos que contienen nombres de municipios colombianos; usa el listado público DIVIPOLA de DANE, con coincidencia de palabras completas y sin depender de tildes. No se modifica ningún evento de Calendar. Un título como «Reunión en Pereira» también puede ser detectado: revisa el registro y marca **Ignorar: no corresponde a un show** si hace falta. Un evento sin precio nunca entra automáticamente en nómina.

Abre un show, registra su precio de venta en COP y, opcionalmente, el empresario, observaciones y si es promocional. Cada show tiene su propio saldo:

**Saldo = venta − suma de abonos vigentes.**

Puedes registrar la fecha y el valor de cada abono, una observación y de uno a cinco comprobantes PDF/JPG/PNG, hasta 10 MB en total. Los importes conservan centavos. Si hay un pago superior al precio, aparece **saldo a favor**. El saldo se actualiza al guardar y se consulta cada 15 segundos mientras el panel está visible, además de al recuperar el foco.

Para corregir un pago usa **Anular abono**, indicando un motivo. El pago deja de reducir el saldo; se conservan su historial y comprobantes. Los reintentos del mismo guardado no duplican pagos. Otro registro con el mismo show, valor, fecha y comprobante se rechaza mientras el anterior siga vigente.

Los comprobantes se abren directamente desde JAC y requieren sesión activa de administrador. Los enlaces compartidos no hacen público el archivo. La autorización se comprueba antes y después de leer R2.

## Quincenas

Al crear una quincena nueva, web e iPhone reciben automáticamente los shows activos, presentes en Calendar y con precio, dentro de las fechas del período. Se copia el precio, la condición promocional y el vínculo al CRM. Se cargan músicos/técnica activos y sus tarifas actuales; los recorridos de conductores empiezan con cero kilómetros. Revisa participantes, tarifas y kilómetros antes de liquidar.

Cambiar Calendar, el precio o los abonos no reescribe quincenas existentes ni cierres históricos. Los abonos no son un gasto ni reducen el valor de venta usado por la comisión. Los cálculos de nómina, gastos por show y comisión siguen sus reglas existentes. Un cambio concurrente del CRM durante la creación rechaza el guardado para que se vuelva a revisar, sin una quincena parcialmente creada.

Un evento que deja de aparecer queda marcado **Revisar: ya no aparece en Calendar**. Su cuenta y comprobantes se conservan; se excluye de nuevas importaciones. Actualizar shows de Calendar vuelve a revisar la ventana de seis meses. No se importan precios de un calendario externo ni se adivinan valores.

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
