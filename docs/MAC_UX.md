# JAC para Mac 1.1.0 (2) — distribución y controles de escritorio

Continuidad del mismo proyecto local, el 15 de octubre de 2026. Camilo pidió acercar la distribución a la web, mostrar CRM en la barra lateral y perfeccionar la experiencia de macOS. El icono anterior se conserva.

## Cambios

- Barra lateral: CRM, Quincena, Agenda, Itinerarios; grupo personal con Mi cuenta y Configuración. Las restricciones financieras y el acceso de administradores siguen vigentes. Los atajos anteriores se conservan aunque CRM esté ahora primero visualmente.
- CRM de escritorio: tabla nativa con selección, doble clic, menú contextual y columnas ordenables. Búsqueda por show/empresario, filtros Todos/Con saldo/Sin precio, fechas legibles e importes COP alineados. Muestra shows de hoy en adelante y excluye eventos eliminados/en eliminación. Venta, abonos y saldo se leen del servidor, sin recalcularlos en el Mac.
- Nuevo show y Registrar abono visibles en la barra superior; acceso a Semana, Empresarios y la hoja existente. Guardar y Cerrar permanecen en el pie nativo del editor Mac, fuera del formulario desplazable. Se reutilizan los editores, autocompletado, adjuntos privados, creación de día único, presupuesto, rentabilidad, preparación y controles de revisión/idempotencia existentes.
- Configuración reúne herramientas por trabajo diario, administración y preferencias/acceso. Los servicios conectados remiten al panel web existente; no se recrean conexiones ni se trasladan secretos.
- Encabezados compactos y botones estándar de macOS, con azul JAC, espaciado consistente y adaptación al modo claro/oscuro. Las vistas previas tienen una sola zona para guardar, compartir e imprimir.
- ⌘R actualiza CRM/Agenda cuando están activos. Cerrar un editor o regresar de un show vuelve a consultar el listado; una actualización simultánea conserva la recarga pendiente. Los accesos de navegación respetan las hojas de edición abiertas.

## Fuente

Nuevo `macos/JACMac/MacWorkspaceViews.swift`, ajustes de ventana/comandos en `JACMacApp.swift` y referencia/versión en el proyecto Mac. Las ramas macOS de los estilos compartidos sustituyen botones grandes y banners del teléfono por controles y encabezados de escritorio. Se adaptan las herramientas de documentos y el comando de actualizar; las ramas visuales de iPhone se conservan.

Se mantienen API, motor financiero, permisos del servidor, Llavero, caché cifrada, protección de privacidad y documentos privados. No hay cambios de migraciones, dependencias, lockfile ni archivos web. El proyecto/esquema y la firma personal de iPhone se comparan con la copia previa y se conservan. Identificadores y suspensión de push intactos.

## Comprobación local

Comprobado con Xcode 27/macOS 27 en el Mac de Camilo:

- **71 pruebas de lógica/permisos Mac aprobadas** en `work/local/mac-ux-accepted.xcresult`: 66 compartidas y cinco específicas de Mac. Se comprueba también que los saldos del servidor se presentan literalmente, sin calcular otra comisión o cuenta local.
- **Seis recorridos UI distintos aprobados** entre las ejecuciones: nómina/Agenda/CRM/documentos, privacidad y regreso al editor, relanzamiento sin red con pase PDF privado, bloqueo de lectores, tabla/búsqueda/formularios/abono y ventana pequeña oscura. Los cuatro recorridos previos permanecen y pasan en `mac-ux-accepted.xcresult`; los dos afectados por la distribución/formularios se repiten en `mac-ux-form-final.xcresult` y `mac-ux-desktop-delivery.xcresult`. El abono ficticio de 50 millones modifica el saldo mostrado de 140 a 90 millones. Capturas `outputs/mac-ux-*.png` con datos ficticios.
- Ventana de **1000 × 752 puntos**, modo oscuro de esta app y controles accesibles comprobados; el tamaño se prepara únicamente con argumentos de fixture DEBUG, después de restaurar la escena. No modifica la apariencia general de macOS. Los intentos previos conservaron el tamaño restaurado de 1240 puntos; se conservaron las aserciones de tamaño/acceso y se corrigió la preparación del fixture. La revisión visual permitió fijar Guardar al pie del editor y ajustar anchos de columnas.
- **iPhone: 65 pruebas de lógica y tres recorridos UI aprobados**, más una comprobación preexistente de protección física omitida explícitamente por CoreSimulator. CRM/autocompletar/abono/preparación, itinerario PDF/alerta selectiva y privacidad/regreso desde segundo plano: `work/local/mac-ux-iphone-regression.xcresult`, TEST EXECUTE SUCCEEDED. Se cerró únicamente su recopilador adicional `simctl diagnose` atascado después de que finalizaran todos los tests; informes y capturas conservados. Las ramas visuales de iOS se mantienen y se reutiliza esta regresión; el último ajuste de Guardar es exclusivo de macOS.
- **Release Mac universal arm64/x86_64 e iPhone sin firma compilados** con la fuente final: `work/local/mac-ux-release-delivery.log` y `mac-ux-iphone-release-delivery.log`, BUILD SUCCEEDED. La ejecución comprobada es Apple Silicon; no se afirma una ejecución en Intel ni una instalación en un iPhone físico.
- Proyecto y esquema personales de iPhone idénticos a `work/local/mac-ux-baseline/`; iconos sin cambios. Huellas de fuente en `work/local/mac-ux-source-sha256.txt`. No cambian las entradas de las pruebas del servidor/web y se reutiliza su verificación previa.

Los intentos intermedios y sus diagnósticos se conservan en `work/local/mac-ux-*.xcresult`. Se ajustaron las consultas de accesibilidad de los menús y se espera el cierre completo de hojas antes de usar atajos. No se eliminaron aserciones ni pruebas existentes para aprobar. Los ajustes finales de presentación repiten los dos recorridos afectados; se reutilizan las comprobaciones no afectadas.

Todas las pruebas usan sesiones ficticias `.invalid` y servicios interceptados. No se utilizan datos reales ni se envían mensajes, correos, eventos o comprobantes como pruebas. La web mantiene su versión publicada y no se ejecuta ningún despliegue durante esta actualización nativa.

Referencia de interacción: [barras laterales de macOS, Apple HIG](https://developer.apple.com/design/human-interface-guidelines/sidebars). La ejecución comprobada corresponde al Mac de Camilo con Xcode 27/macOS 27; no implica una prueba en todos los Macs compatibles.
