# Rediseño aprobado de JAC para iPhone

Camilo aprobó el 25 de octubre de 2026 la propuesta visual de seis vistas con «Me encanta, hazlo así». La implementación iOS0.33.0(50) lleva esa dirección a las funciones reales, con datos y permisos existentes. No incorpora los importes, nombres de eventos ni códigos de aeropuertos ilustrativos de las maquetas.

## Presentación

- Identidad azul/navy JAC, fondo claro neutro, bordes suaves, menos bloques decorativos y botones primarios planos. Apariencia oscura y Dynamic Type siguen disponibles.
- Una cabecera de raíz con menú y título alineados a la izquierda; los detalles conservan Volver y las hojas su cierre propio. Se mantiene el título nativo para accesibilidad y restauración.
- Menú sólido de314pt como máximo que desplaza el contenido, agrupado en Operación y Biblioteca; Gestión siempre accesible. Solo muestra módulos autorizados, conserva las secciones visitadas, reproducción y gesto de borde.
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
