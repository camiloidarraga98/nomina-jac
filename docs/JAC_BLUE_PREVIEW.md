# Identidad azul JAC

Identidad aprobada por Camilo el 15 de octubre de 2026 para toda la web y el mismo proyecto iPhone. La muestra original se amplió a acceso, configuración, avisos, pases, formularios y reportes. Publicada como web v63 en el Site existente; resultado y fuente registrados en PROJECT_CONTEXT.md.

| Uso | Color |
| --- | --- |
| Navegación y resúmenes | `#062F46` |
| Botones y enlaces | `#006FBD` |
| Detalles del logo y acentos | `#009DFF` |
| Selección suave | `#E8F3FC` |
| Fondo | `#F3F7FB` |
| Texto | `#163449` |
| Texto secundario | `#5B7184` |

Botones con texto blanco y azul oscuro suficiente para leerlos; cian reservado para acentos. Los estados de éxito, advertencia y eliminación conservan su significado. No cambian el logo, nombres, distribución, datos, permisos, cálculos, navegación, sesiones ni protección de privacidad.

Web: colores centralizados en `app/jac-blue.css`, importados desde el estilo existente. Muestra local de Quincena, CRM y Agenda con base SQLite en memoria, archivos/personas/eventos ficticios y salidas Google interceptadas. No usar esta vista como nómina real. Se comprueban escritorio de 1440 px y teléfono de 390 px.

iPhone: misma paleta en JACTheme, compatible con apariencia clara y oscura; la barra inferior conserva su apariencia nativa y usa una selección azul legible (azul claro sobre fondo oscuro). Se conservan cinco pestañas y controles nativos. La muestra se compila en el proyecto actual sin cambiar firma, esquema, identificador ni suspensión de push. No se instala en el iPhone físico durante esta revisión.

Capturas en `outputs/jac-azul-web-*.png` y `outputs/jac-azul-iphone-*.png`. Las capturas usan datos ficticios; se conserva el producto existente.

## Verificación local

TypeScript y build web correctos; 37 pruebas de nómina/autenticación/correo pasadas. Las tres vistas se revisaron con navegador en escritorio y teléfono; el autocompletado permanece blanco y legible. Xcode 27/iOS 27: `ios-blue-verified.xcresult` terminó TEST SUCCEEDED con Agenda, CRM y ciclo de documentos de Quincena (tres pruebas); privacidad/regreso con borrador pasó en `ios-blue-preview-final.xcresult`. Release para iPhone sin firma: BUILD SUCCEEDED en `ios-blue-release-verified.log`. No se probaron datos o conexiones reales ni un iPhone físico.

Xcode quedó esperando a recolectores adicionales de diagnóstico después de completar las comprobaciones. Se detuvo una ejecución previa atascada y se repitió la verificación con la fuente final. Se conservaron sus logs y no se modificaron pruebas; al terminar las tres verificaciones finales se detuvieron únicamente los recolectores de diagnóstico propios, incluido uno huérfano, y Xcode cerró correctamente con código 0 y TEST SUCCEEDED. El informe y las capturas finales son los de `ios-blue-verified.xcresult`.

Comparación de las seis capturas en `outputs/JAC-azul-muestra.html`. Respaldo nativo opcional `outputs/JAC-iPhone-muestra-azul.zip`, sin claves, estado local ni ajustes personales de firma. Se continúa con el proyecto de esta carpeta.

## Aplicación completa aprobada — iPhone 0.14.1 (25)

La web aplica la paleta compartida en Quincena, Agenda, CRM, Itinerarios, Pases, Alertas, Personal, Archivo, cuentas, configuración y formularios. Acceso, favicon, colores de la web instalada y encabezados PDF/XLSX también usan azul. Los PDF anteriores, archivos adjuntos y logos se conservan. Solo cambian colores y presentación; sin migraciones, dependencias nuevas o cambios a cálculos, permisos, navegación, privacidad, conexiones ni datos.

Verificación ampliada: TypeScript/build y 49 pruebas de nómina/auth/correo/móvil correctos. Se revisaron Itinerarios/Pases, detalle de adjuntos, Alertas/creación, Configuración y acceso en localhost desechable, con todas las salidas interceptadas. Itinerarios a 390 px no desborda. Un resumen PDF ficticio fue renderizado y revisado. Capturas adicionales `outputs/jac-azul-completo-*.png`.

Simulador nuevo iPhone 18 Pro/iOS 27, `ios-blue63.xcresult`: 65 pruebas unitarias y cinco pruebas de interfaz pasadas, una comprobación de protección física omitida con su condición existente porque requiere iPhone real; cero fallos. Se verifican acceso/regreso, Gestión, Itinerarios/Alertas, Pases y Gastos. No se modifican pruebas ni se eliminan comprobaciones. La ejecución terminó normalmente con TEST SUCCEEDED; Release para iPhone sin firma también BUILD SUCCEEDED (`ios-blue63-release.log`). Se reutilizan las comprobaciones de Agenda/CRM/Quincena y privacidad de la muestra, cuyas fuentes nativas no cambiaron.

El mismo `ios/JACNomina.xcodeproj` conserva ajustes personales, esquema y firma; versión 0.14.1/build 25, bundle `co.jacmusic.nomina`, `JACPushEnabled=NO`. Para instalar esta actualización conecta el iPhone y usa Run en este mismo proyecto. No se declara instalada en el teléfono físico. Respaldo opcional `outputs/JAC-iPhone-0.14.1-azul.zip`, sin claves ni ajustes personales. La fuente nativa actualizada queda local; no se publica en el Site.
