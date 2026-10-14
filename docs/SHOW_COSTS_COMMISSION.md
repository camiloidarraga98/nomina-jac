# Costos por show y comisión de Camilo

La quincena tiene la pestaña **Gastos** (`/quincena/gastos`), junto a Shows, Novedades y Recorridos. En iPhone está en **Quincena → Actividad → Gastos por show**. Cada registro exige show, tipo (Tiquetes, Hoteles, Alimentación u Otros), fecha del gasto, concepto y valor en COP; la observación es opcional. La fecha corresponde al comprobante y puede diferir de la fecha/quincena del show. Los costos pertenecen al show de la quincena seleccionada.

Se pueden agregar, editar y eliminar gastos con los permisos de nómina existentes; un cierre requiere reapertura autorizada antes de editar. La eliminación tiene confirmación. Eliminar un show también retira sus gastos y su recorrido compartido, y la confirmación lo explica. Filtrar por show muestra sus gastos y el total de la selección.

Estos registros son costos para análisis y comisión: **no generan pagos ni reintegros**. Gastos de viaje conserva su flujo independiente de comprobantes/revisión. No se importan registros de ese flujo automáticamente; registra cada costo directo aquí una sola vez para el cálculo.

## Regla confirmada por Camilo

`Comisión = 5% × máximo(0, ventas de todos los shows − costos de shows no promocionales)`

- Ventas: suma del valor registrado en todos los shows, incluidos los promocionales si tienen venta.
- Costos: honorarios brutos por show de músicos y técnica, pagos por kilómetros de sus conductores y gastos directos registrados en esta pestaña.
- No se descuentan salarios/dependientes, honorarios fijos quincenales, novedades, retenciones al empleado, reintegros ni recorridos extra.
- Las tarifas utilizadas son las guardadas en cada show/recorrido; no se sustituyen por las tarifas actuales del personal.
- La casilla **Show promocional**, al final del formulario de show, excluye todos sus honorarios, kilómetros y gastos de la base de comisión. Conserva los pagos al equipo y los costos reales en el análisis.
- El resultado negativo deja la comisión en cero, sin arrastre a otra quincena.
- Es un **cálculo revisable**. No se agrega automáticamente como pago a Camilo ni se suma al neto de nómina.

El cuadro **Comisión de Camilo · 5%** muestra ventas, costos descontados, costos promocionales excluidos, base y comisión. **Costos y resultado por show** permite consultar ventas, músicos, técnica, conductores/km, gastos, costo total, resultado económico y costo descontado de la comisión. El filtro de gastos no cambia la comisión de la quincena.

Los recorridos compartidos se vinculan por ID de show. Los anteriores se asignan solo si el nombre/fecha o un único show de ese día permiten identificarlo. Una coincidencia con varios shows deja la comisión pendiente hasta vincular el recorrido; no se duplica el costo. Los kilómetros anteriores sin show identificado se muestran como excluidos para revisión, y los recorridos explícitamente extra se excluyen.

## Continuidad y controles

Los campos opcionales `Show.promotional`, `Period.showExpenses` y `Snapshot.camiloCommission` se guardan en los JSON de nómina existentes. No hay nueva tabla ni migración SQL. La validación exige referencia a un show de esa quincena, IDs únicos, categoría/fecha válidas y valor positivo. Se mantienen permisos, origen, versión/CAS y cierre/reapertura.

El cálculo central de servidor conserva el desglose en los cierres nuevos. Las instantáneas y revisiones anteriores no se recalculan ni rellenan: un cierre antiguo sin comisión guardada lo indica. Al reabrir se conservan las condiciones históricas. Los documentos de pagos mantienen sus importes; esta comisión revisable no se añade a desprendibles o filas de nómina.

Los clientes móviles anteriores que omiten la casilla al editar un show conservan su valor actual. Un guardado completo que pierda un promocional marcado o una colección de gastos existente se rechaza y pide actualizar el formulario. La app nueva lee el cálculo de la API, sin replicar fórmulas financieras en Swift; su copia cifrada conserva la última respuesta autorizada disponible offline y las escrituras requieren conexión. Mantiene `co.jacmusic.nomina`, la firma personal local y push suspendido.

Las pruebas son locales: D1 SQLite en memoria, HTTP falso/React con nombres ficticios y simulador `.invalid`. No registrar gastos, cerrar/borrar quincenas, enviar comprobantes o usar servicios reales como prueba.
