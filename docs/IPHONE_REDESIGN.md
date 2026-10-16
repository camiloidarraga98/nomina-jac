# JAC para iPhone — nueva distribución visual

Propuesta implementada sobre el mismo proyecto local el 15 de octubre de 2026, a petición de Camilo: más personalidad y color, manteniendo elegancia y sobriedad. Versión 0.15.0 (26). La web conserva su identidad azul v63; este rediseño es nativo.

## Diseño y accesos

- Azul profundo y cian de JAC, con acentos verde azulado para viajes/agenda, violeta para administración y ámbar para avisos. Éxitos, errores y eliminación conservan sus colores semánticos.
- Encabezados con degradado sobrio, tipografía redondeada y un detalle de barras de audio; logo original conservado. Tarjetas claras con separación amplia, sin animaciones nuevas. Tema adaptativo claro/oscuro.
- Quincena muestra un resumen y **Nueva quincena** visible sobre el listado, con los mismos permisos y bloqueo de escritura. En Actividad, accesos en dos columnas en lugar de una lista larga; una columna para tamaños de texto de accesibilidad.
- Gestión organiza Gastos/Alertas y Administración en tarjetas; Notificaciones, Conceptos y permisos quedan agrupados en Preferencias y acceso. Conserva Archivo, Equipo, CRM y Correos con sus permisos anteriores.
- CRM destaca **Registrar abono**; **Más** conserva Crear show, Registrar abono y sincronización de Calendar. Cuenta, Rentabilidad y Preparación permanecen fuera del área desplazable para poder cambiar de vista en cualquier momento. El autocompletado adapta fondo y texto al modo oscuro.
- Agenda comienza con el calendario. **Hoy**, actualización y **Nuevo evento** se agrupan bajo el mes. Los días seleccionados tienen fondo azul; los eventos usan un acento verde azulado. Se conserva conexión/edición, copia offline, actualizaciones y horas de Colombia.
- Itinerarios presenta un acceso destacado a Pases; las publicaciones se muestran en tarjetas. Los pases tienen diseño de boleto con pasajero, ruta, fecha y apertura directa. Hoy/mañana/historial, privacidad del destinatario y eliminación con gesto/confirmación se conservan.
- Alertas ofrece creación visible; Mi cuenta presenta una tarjeta personal, acceso, permisos y copia sin conexión. Cerrar sesión sigue confirmado. Acceso rediseñado conserva campos, opción de sesión, activación y foco.

No se sustituyen las cinco pestañas nativas ni se modifica su orden. Las tarjetas usan destinos explícitos dentro de la pila existente; no se agregan pilas de navegación anidadas, servicios, datos de prueba a producción, permisos o cálculos locales. No hay cambios de API, dependencias, migraciones, claves ni firma. La cubierta de privacidad y sus comprobaciones permanecen. El bundle sigue siendo `co.jacmusic.nomina`, push `NO`.

## Verificación

Verificado en este Mac con Xcode 27/iOS 27, simuladores nuevos iPhone 18 Pro (`97496DC2-9909-4C8E-AFBF-88404C31D78D`, claro) y iPhone SE de tercera generación (`91E424B9-7091-41F1-ADAC-D8B9C7707169`, oscuro). Compilación final para pruebas y Release iPhone sin firma correctas (`ios-personality-accepted-build-for-testing.log`, `ios-personality-iphone-final.log`). La fuente comprobada quedó registrada en `work/local/ios-personality-source-hashes.json` y no cambió después de compilar/probar.

65 pruebas unitarias pasadas, una comprobación de protección física omitida con su condición existente porque requiere iPhone real. Se verificaron 20 recorridos de interfaz distintos, reutilizando los resultados cuando sus entradas no cambiaron y repitiendo los afectados después de cada ajuste. Cubren acceso/activación/regreso, sesión persistente, privacidad sobre formularios, quincena/actividad, permisos de Camilo/lector/Alex, Agenda, CRM, documentos privados, Alertas/Itinerarios, pases hoy/mañana, gestos/confirmación de borrado, gastos y arranque sin internet. No se retiró ninguna comprobación ni se realizaron pruebas con servicios/datos reales.

Informes principales: `ios-personality-verified.xcresult` (65 unitarias, un skip físico y 11 UI; TEST SUCCEEDED), `ios-personality-navigation.xcresult` (dos UI), `ios-personality-final-light.xcresult` (Gestión y offline con la distribución final), `ios-personality-accepted-light.xcresult` (cuatro UI finales) y `ios-personality-accepted-dark.xcresult` (CRM final en pantalla pequeña); estos dos últimos terminaron TEST EXECUTE SUCCEEDED con cero fallos. Acceso/sesión y Agenda también se conservan aprobados en smoke; creación de show/primer abono y navegación compacta tienen resultados individuales aprobados en los informes oscuros anteriores.

Incidencias intermedias conservadas para diagnóstico: varios NavigationLink dentro de la misma fila activaban más de un destino (Archivo acababa en Correos). Las tarjetas usan ahora botones con destino explícito en la pila existente. En el tamaño pequeño, la reutilización de filas retiraba accesos previos del árbol de accesibilidad al regresar; Gestión conserva sus pocas tarjetas en un ScrollView sin reciclaje. En CRM, el dato de comisión está bajo el presupuesto: la prueba ahora se desplaza de forma acotada hasta él y conserva la misma aserción. El primer intento de fijar el selector con safeAreaInset quedaba visible pero no se podía tocar en el iPhone SE; el selector final es un hermano de la lista dentro de un VStack. La prueba original del CRM pasó finalmente en ambos tamaños. Los informes con fallos intermedios se conservan; no se presentan como aprobados.

Xcode volvió a dejar procesos propios de `simctl diagnose` esperando después de terminar las pruebas. Se conservaron diagnósticos, capturas y logs, y se cerraron únicamente esos recolectores adicionales para finalizar los informes; no se detuvieron pruebas ni se eliminaron verificaciones.

Capturas nativas reales, con datos ficticios, en `outputs/jac-iphone-nuev*.png`, `outputs/jac-iphone-crm-*.png`. Respaldo opcional `outputs/JAC-iPhone-0.15.0-rediseno.zip`, sin claves, estado de simulador ni ajustes personales de firma. La web conserva v63 y no se publica fuente nativa en el Site.

Se actualiza con Run en el mismo `ios/JACNomina.xcodeproj`, conservando la configuración personal. El respaldo ZIP es opcional; no se debe reemplazar el proyecto actual ni borrar la app instalada. La compilación sin firma no equivale a instalar la actualización en el teléfono físico.
