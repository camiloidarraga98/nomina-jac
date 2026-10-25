# Rediseño aprobado de JAC para iPhone

## Corrección de compilación de Agenda · 25 de octubre de 2026

Camilo reportó en Xcode `The compiler is unable to type-check this expression in reasonable time` en `CalendarView`. iOS0.33.1(51) divide la expresión raíz en contenido, estados, variantes de dispositivo, toolbar, observación y hojas; también separa la celda del calendario y declara tipos concretos para los eventos agrupados, colores y callback de edición. Conserva estados en la vista original, jerarquía sin contenedores nuevos, accesibilidad, diseño, permisos, caché y operaciones de Agenda. No usa `AnyView` ni cambia la firma personal, APNs o los datos.

Las comprobaciones anteriores del rediseño usaron Xcode16.4. El scope focal `calendar-compile` selecciona el Xcode más reciente ya instalado en el runner estándar `macos-15`, registra sus versiones y compila iPhone Debug/Release y Mac. Reutiliza dos recorridos UI existentes de Agenda con fixtures: mes/próximos/detalle/cuenta y toque del borde de la celda.

Verificación final de la corrección, fuente de aplicación `eb7a210f67168d7e1823845222becf8fd1c06315`, Xcode26.3 y Swift6.2.4:

- [40217354037](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40217354037): Release iPhone y Mac correctos, incluido el bundle0.33.1(51). Debug también compiló. Los dos UI fallaron antes de tocar el menú porque el helper exigía44pt al contenedor de toolbar que iOS26 representa como50×36, aunque el botón real mantiene44×44. No fue un error de compilación de `CalendarView`.
- [40218235724](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40218235724), commit `ec340c0`: dos UI correctos en iPhone17Pro/iOS26.2, `TEST SUCCEEDED`: bordes de celda83.356s y mes/próximos/detalle/cuenta79.870s. El helper elige el botón real cuando el contenedor no cumple44pt, exige habilitación y conserva el toque real y la comprobación de que el panel abra. No se retiraron aserciones ni se invocaron acciones internas.

El seguimiento cambia solo workflow/pruebas: las fuentes de aplicación y proyecto son idénticas a `eb7a210`, por lo que se reutilizan ambas Release aprobadas. El marcador `[calendar-ui-only]` omite esas compilaciones ya válidas. Evidencia local en `output/calendar-51-ci` y `output/calendar-51-ui-ci`, exclusivamente fixtures y simuladores desechables, sin servicios/cuentas de producción. Fuente guardada en GitHub; firma, instalación y subida real a TestFlight siguen en el Mac del propietario. No hay cambios web/API ni despliegue de Cloudflare.

Observación visual de SDK26, independiente del timeout: la captura `output/calendar-51-ui-ci/diagnostics/attachments/5113C293-322F-49CF-8F03-C44F0066F3B9.png` muestra el título raíz Agenda comprimido por la nueva toolbar del sistema. Menú, mes, calendario, eventos y navegación están visibles/operativos. El ajuste de ancho intrínseco de `PhoneSidebarToolbar` queda separado de esta corrección de compilación y requiere comprobar títulos largos y Dynamic Type; no se modificó ese componente en0.33.1.

Camilo aprobó el 25 de octubre de 2026 la propuesta visual de seis vistas con «Me encanta, hazlo así». La implementación iOS0.33.0(50) lleva esa dirección a las funciones reales, con datos y permisos existentes. No incorpora los importes, nombres de eventos ni códigos de aeropuertos ilustrativos de las maquetas.

## Presentación

- Identidad azul/navy JAC, fondo claro neutro, bordes suaves, menos bloques decorativos y botones primarios planos. Apariencia oscura y Dynamic Type siguen disponibles.
- Una cabecera de raíz con menú y título alineados a la izquierda; los detalles conservan Volver y las hojas su cierre propio. Se mantiene el título nativo para accesibilidad y restauración.
- Menú sólido de314pt como máximo que desplaza el contenido, agrupado en Operación y Biblioteca; Gestión siempre accesible. Solo muestra módulos autorizados, conserva las secciones visitadas, reproducción y gesto de borde. El panel mueve el layout completo mediante `position`, y el destino activo usa `zIndex` superior para evitar que una barra UIKit de una sección visitada tape controles del calendario. El simulador puede conservar coordenadas AX desplazadas por el ancho del panel aunque el control visible esté en su lugar: las pruebas deben distinguir el envoltorio nativo y el toque real, mantener las comprobaciones de destino y no confundir el éxito de compilación con un recorrido funcional completo.
- Agenda inicial con mes compacto, selector Mes/Próximos, cuadrícula táctil de44pt y eventos del día en tarjetas. Crear está en el botón+, actualizar/conexión en el menú⋯. iPad mantiene sus columnas y Mac su distribución.
- Pases compactos con fecha breve, ruta/pasajero reales y Silla/Salida/En sala/Código. Próximos/Anteriores permite acceder al historial existente. La tarjeta abre el documento original y Código/⋯ son controles independientes. No se inventan IATA ni horarios.
- Música muestra cuatro playlists con conteos reales y disponibilidad offline, buscador, importación y minirreproductor navy. Los «Agregados recientemente» provienen de la fecha real del audio; no se simula historial de escucha. La hoja del reproductor conserva los controles completos.
- CRM iPhone agrupa Shows/Empresarios/Más; Más conserva Semana y Contratos y ofrece acceso a Prospectos2027 en la web existente. El menú+ contiene Nuevo show y Registrar abono. Saldos incompletos se muestran por completar, nunca como cero confirmado.
- Quincenas tiene creación en la cabecera y filas compactas. El detalle de iPhone abre Actividad, con resumen del cálculo del servidor, accesos a las cinco actividades y Ver liquidación. Pagos/Documentos y las acciones de cierre siguen disponibles; iPad/Mac mantienen Pagos inicial.

## Límites funcionales

Solo presentación nativa: sin cambios de API, bases de datos, precios, cálculos, permisos o secretos. No se crean eventos compartidos desde pases ni se convierten las maquetas en información de negocio. Se conservan la privacidad individual de pases, cachés por sesión/revisión, código original, preparación Wallet, reproducción/descarga e importación, y estados de las operaciones financieras.

Bundle `co.jacmusic.nomina`, Team `AYHVYN8BJF`, entitlements/APNs y firma se conservan. Mac mantiene su versión y distribución; sus fuentes compartidas se compilan para comprobar compatibilidad. Instalar en un dispositivo real requiere el flujo habitual de Xcode/Archive/TestFlight del propietario.

## Verificación

El scope `redesign` de GitHub Actions ejecuta ocho recorridos UI existentes y una unitaria de permisos usando servicios `.invalid`, simulador desechable y `JAC_PUSH_ENABLED=NO`, además de compilar Release de iPhone y Mac. Incluye navegación/estado/gestos, Agenda, búsqueda y permisos de Música, apertura/código/menú de pases, formularios CRM y actividades de Quincena. Las capturas usan exclusivamente fixtures. Los resultados concretos se registran al finalizar CI; la propuesta HTML no constituye evidencia de ejecución nativa.


## Resultado final · 25 de octubre de 2026

Producción nativa final `783a9af2fba1b8e247c5164f9955d0610f82a0d6`, iOS0.33.0(50). Los commits posteriores solo ajustan pruebas/workflow/documentación; el árbol `ios/JACNomina` sigue siendo `6ae2e178fedb4e19d2605ae5aff3c31a5006c2e8` y no se modificaron el proyecto ni las fuentes de Mac.

| Comprobación | Ejecución | Resultado |
| --- | --- | --- |
| Release iPhone final y metadatos del bundle | [40168205829](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40168205829) | Correcto; versión0.33.0(50), iPhone/iPad y apertura de documentos conservados. |
| Release Mac de fuentes compartidas | [40167292526](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40167292526) | Correcto; reutilizado tras correcciones del menú de iPhone, sin cambios de comportamiento Mac. |
| Permisos modernos, Pases y dos recorridos de Música | [40167292526](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40167292526) | Una unitaria y tres UI correctas. Pases abre PDF/código/menú y comprueba medianoche; Música busca y conserva permisos. |
| Agenda y dos recorridos de menú/estado | [40168205829](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40168205829) | Tres UI correctas:154.257s,117.715s y52.087s. |
| Crear quincena y gestionar actividades | [40171098011](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40171098011) | UI correcta257.945s: show, recorrido120km, reemplazo de novedad y horas2. |
| Crear show, primer abono y resumen semanal | [40172103215](https://github.com/camiloidarraga98/nomina-jac/actions/runs/40172103215) | UI correcta154.000s, TEST SUCCEEDED: venta140M, abono50M con adjunto, saldo90M y resumen semanal. |

Son ocho recorridos UI distintos y una unitaria aprobados, con reutilización explícita de los resultados válidos. Las primeras ejecuciones detectaron una oclusión real del calendario por una barra de una sección oculta, corregida con el orden activo de las vistas. Los seguimientos se limitaron después a los casos pendientes: coordenadas AX del simulador, foco dentro de filas con padding y mayúsculas de un encabezado. Las pruebas conservan controles reales, permisos, teclado, valores completos y comprobaciones de destino/saldos; no invocan acciones internas para simular un toque ni eliminan aserciones financieras.

Evidencia local en `output/redesign-50-ci`, `output/redesign-50-followup-ci`, `output/redesign-50-forms-verified-ci` y `output/redesign-50-crm-verified-ci`. Capturas nativas sin alteración en `output/jac-redesign-0.33.0`; todos los importes y personas pertenecen a fixtures. No se realizaron operaciones con cuentas, pagos, pases, notificaciones o archivos de producción. Web/API/Cloudflare no requieren publicación por este rediseño. No se ha firmado, instalado ni subido esta versión a TestFlight desde CI: el propietario debe hacer pull, Archive y Upload en su Mac.
