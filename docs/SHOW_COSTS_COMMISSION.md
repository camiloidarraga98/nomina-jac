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
- Desde el 29 de octubre de 2026, por confirmación de Camilo, **se suma en el total general**, con una línea independiente: neto del equipo + Camilo · comisión del 5%. No se crea un empleado/pago/envío ficticio ni se incorpora esa comisión a los desprendibles de otras personas.

El cuadro **Comisión de Camilo · 5%** muestra ventas, costos descontados, costos promocionales excluidos, base y comisión. **Costos y resultado por show** permite consultar ventas, músicos, técnica, conductores/km, gastos, costo total, resultado económico y costo descontado de la comisión. El filtro de gastos no cambia la comisión de la quincena.

Los recorridos compartidos se vinculan por ID de show. Los anteriores se asignan solo si el nombre/fecha o un único show de ese día permiten identificarlo. Una coincidencia con varios shows deja la comisión pendiente hasta vincular el recorrido; no se duplica el costo. Los kilómetros anteriores sin show identificado se muestran como excluidos para revisión, y los recorridos explícitamente extra se excluyen.

## Honorarios promocionales al 50% · 29 de octubre de 2026

En **Quincena → Shows → Agregar/Editar**, al marcar **Show promocional** aparece **Pagar el 50% de honorarios a cada participante**. Por defecto permanece desactivado. Los campos son tarifas completas; la liquidación y los costos reales aplican el porcentaje una sola vez, con redondeo a centavos por persona. Al desmarcar promocional se retira la reducción. Los kilómetros, salarios, honorarios fijos y novedades conservan su valor. Los costos promocionales efectivos siguen excluidos de la base del 5%, como antes.

`Show.halfPay` opcional se guarda en el JSON existente, sin migración. El servidor rechaza activarlo en un show normal. Una edición móvil anterior que omita el campo conserva el indicador; un guardado completo que lo elimine por omisión exige actualizar el formulario. Las tarifas permanecen completas durante guardados, cierre y reapertura; no se aplica otro 50% al volver a editar. Los cierres y sus revisiones no se recalculan. El Excel de Shows distingue tarifa completa, porcentaje y honorario liquidado.

La app muestra los totales generales recibidos del servidor mediante `calculation.general`; no replica fórmulas de comisión en Swift. En Actividad, el distintivo indica el 50% y los importes están identificados como tarifas completas; Pagos muestra los importes liquidados. API antigua/sin `general` mantiene el neto del equipo claramente identificado.

## Continuidad y controles

Los campos opcionales `Show.halfPay`, `Show.promotional`, `Period.showExpenses` y `Snapshot.camiloCommission` se guardan en los JSON de nómina existentes. No hay nueva tabla ni migración SQL. La validación exige referencia a un show de esa quincena, IDs únicos, categoría/fecha válidas y valor positivo. Se mantienen permisos, origen, versión/CAS y cierre/reapertura.

El cálculo central de servidor conserva el desglose en los cierres nuevos. Las instantáneas y revisiones anteriores no se recalculan ni rellenan: un cierre antiguo sin comisión guardada lo indica. Al reabrir se conservan las condiciones históricas. Los desprendibles individuales mantienen sus importes; PDF de resumen y Excel muestran neto del equipo, comisión y total general. `Snapshot.total` conserva la suma del equipo por compatibilidad; `payrollGeneral` deriva el general de la comisión ya congelada, sin reescribir snapshots. Si falta esa comisión histórica o está pendiente, se indica «Pendiente de revisión» y no se inventa un total.

Los clientes móviles anteriores que omiten la casilla al editar un show conservan su valor actual. Un guardado completo que pierda un promocional marcado o una colección de gastos existente se rechaza y pide actualizar el formulario. La app nueva lee el cálculo de la API, sin replicar fórmulas financieras en Swift; su copia cifrada conserva la última respuesta autorizada disponible offline y las escrituras requieren conexión. Mantiene `co.jacmusic.nomina`, Team `AYHVYN8BJF`, AppGroup y configuración APNs vigentes.

Las pruebas son locales: D1 SQLite en memoria, HTTP falso/React con nombres ficticios y simulador `.invalid`. No registrar gastos, cerrar/borrar quincenas, enviar comprobantes o usar servicios reales como prueba.

## Verificación de esta entrega · 29 de octubre de 2026

Pruebas locales con fixtures: 9 casos del motor de comisión/promocionales, 9 de la API móvil, 2 de exportaciones, 20 de nómina, 12 de acceso, 7 de correo, 4 de OAuth móvil, 12 del workspace CRM, 28 de contratos/archivo/API y 15 de RUT: 118 casos aprobados. Se ejecutan suites en procesos separados con `--test-isolation=none`, comprobando sus nombres y conteos. La antigua suite `payroll-corrections` requiere un servidor desechable y quedó omitida, sin incluirla en esa cifra; reapertura/CAS/cierre se comprueban en las suites de motor/API. No usar producción como alternativa.

Chromium local recorre el formulario real: opción disponible solo para promocionales, total reducido, tarifas completas conservadas, guardar y volver a editar, retirar/reponer clasificación sin mantener una reducción oculta, y general = equipo + Camilo. El guardado de esa prueba usa un servidor ficticio; la validación/persistencia real se comprueba en la API contra SQLite en memoria. PDF revisado visualmente y Excel con fórmulas/cachés coherentes. Evidencias ignoradas bajo `work/local/payroll-promotional/`.

App/widget0.40.0(59), junto a las opciones nuevas de contratos; ámbito Apple `payroll-promotional` incluye los contratos, el editor promocional, decodificación del general y las seis guardas de fluidez. Publicación de esta ampliación y resultado de compilaciones Apple pendientes de registrar. No equivale a distribución por TestFlight ni instalación física.
