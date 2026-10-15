# Muestra local de identidad azul JAC

Propuesta del 15 de octubre de 2026, pendiente de revisión de Camilo antes de extenderla y publicarla. Producción conserva la versión 62.

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

Capturas en `outputs/jac-azul-web-*.png` y `outputs/jac-azul-iphone-*.png`. La muestra no es una publicación ni una nueva aplicación.

## Verificación local

TypeScript y build web correctos; 37 pruebas de nómina/autenticación/correo pasadas. Las tres vistas se revisaron con navegador en escritorio y teléfono; el autocompletado permanece blanco y legible. Xcode 27/iOS 27: `ios-blue-verified.xcresult` terminó TEST SUCCEEDED con Agenda, CRM y ciclo de documentos de Quincena (tres pruebas); privacidad/regreso con borrador pasó en `ios-blue-preview-final.xcresult`. Release para iPhone sin firma: BUILD SUCCEEDED en `ios-blue-release-verified.log`. No se probaron datos o conexiones reales ni un iPhone físico.

Xcode quedó esperando a recolectores adicionales de diagnóstico después de completar las comprobaciones. Se detuvo una ejecución previa atascada y se repitió la verificación con la fuente final. Se conservaron sus logs y no se modificaron pruebas; al terminar las tres verificaciones finales se detuvieron únicamente los recolectores de diagnóstico propios, incluido uno huérfano, y Xcode cerró correctamente con código 0 y TEST SUCCEEDED. El informe y las capturas finales son los de `ios-blue-verified.xcresult`.

Comparación de las seis capturas en `outputs/JAC-azul-muestra.html`. Respaldo nativo opcional `outputs/JAC-iPhone-muestra-azul.zip`, sin claves, estado local ni ajustes personales de firma. Se continúa con el proyecto de esta carpeta.
