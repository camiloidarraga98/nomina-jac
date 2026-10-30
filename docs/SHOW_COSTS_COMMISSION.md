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
- Desde el 29 de octubre de 2026, por confirmación de Camilo, **se suma en el total general**: neto del equipo + comisión del 5%. El30 de octubre pidió incluirlo en el listado general: PDF definitivo, preliquidación y Excel muestran **Camilo Idarraga · Comisión del 5%** como fila de la tabla de pagos, antes de los totales, en lugar de dejarlo debajo como una línea aislada. Esta fila es solo presentación de la comisión guardada; el subtotal del equipo la excluye y el total general la suma una sola vez. No se crea un empleado/pago/envío ficticio ni se incorpora esa comisión a los desprendibles de otras personas.

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

Pruebas locales con fixtures: 10 casos del motor de comisión/promocionales, 9 de la API móvil, 3 de exportaciones, 20 de nómina, 12 de acceso, 7 de correo, 4 de OAuth móvil, 12 del workspace CRM, 28 de contratos/archivo/API y 15 de RUT: 120 casos aprobados. Se ejecutan suites en procesos separados con `--test-isolation=none`, comprobando sus nombres y conteos. La antigua suite `payroll-corrections` requiere un servidor desechable y quedó omitida, sin incluirla en esa cifra; reapertura/CAS/cierre se comprueban en las suites de motor/API. No usar producción como alternativa.

Chromium local recorre el formulario real: opción disponible solo para promocionales, total reducido, tarifas completas conservadas, guardar y volver a editar, retirar/reponer clasificación sin mantener una reducción oculta, y general = equipo + Camilo. El guardado de esa prueba usa un servidor ficticio; la validación/persistencia real se comprueba en la API contra SQLite en memoria. PDF revisado visualmente y Excel con fórmulas/cachés coherentes, incluido redondeo a dos decimales por persona y comisión cuando no hay participantes por pagar. Evidencias ignoradas bajo `work/local/payroll-promotional/`.

App/widget0.40.0(59), junto a las opciones nuevas de contratos; ámbito Apple `payroll-promotional` incluye los contratos, el editor promocional, decodificación del general y las seis guardas de fluidez. Web/API de la ampliación activados el 29 de octubre a las14:10 Colombia, fuente `a3acba4`, versión Worker `3d0a928a-aab7-4509-ab78-cb8496a5cdfb`, despliegue `a129a193-c222-44b3-bcb2-9284f20b56f2` al100%. Confirmado por API tras el error final del CLI al leer el subdominio/membresías; se conservaron14 bindings y ambos cron. [Apple40937560584](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40937560584) comprueba esa fuente. Una prueba anterior de contratos pasó12 unitarias/guardas y ambas Release, pero falló antes del formulario al localizar el menú CRM con el desplazamiento antiguo del drawer en XCTest; el seguimiento usa solo el rectángulo real medido y exige abrir el menú real. El seguimiento final [Apple40938925040](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40938925040), fuente de pruebas `e690950`, añade comprobaciones del total general, creación/edición y cierre/reapertura; sigue en cola por disponibilidad del ejecutor, sin resultado todavía. Reutiliza las entradas de aplicación `a3acba4` para las Release iPhone/Mac de40937560584, también en cola. El seguimiento anterior40938120097 fue sustituido/cancelado, sin afirmar que pasó. No equivale a distribución por TestFlight ni instalación física.

Despliegue final de Excel: fuente web/API `5ec401e`, versión Worker `9a59e36b-c7a9-4bb6-8844-8eb521f26cce`, despliegue `4fa6bbc6-56ab-44d5-8319-b3662269f610`, activo al100% desde2026-10-29T19:16:28Z (14:16 Colombia).14 bindings y2 cron idénticos al estado previo. [Web40938581198](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40938581198) terminó correctamente sobre esa fuente. Commits posteriores solo cambian pruebas/workflow Apple y documentación; no requieren desplegar de nuevo el Worker. TypeScript/build finales correctos. Los cambios en contratos y nómina no se han distribuido ni instalado en un iPhone mediante esta tarea.
