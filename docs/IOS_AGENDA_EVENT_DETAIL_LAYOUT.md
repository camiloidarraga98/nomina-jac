# Agenda: cierre al abrir un evento después de cambiar de sección

16 de octubre de 2026. Solicitud de Camilo con el perfil de Alex: Agenda, Alertas, Fotografía y subida; sin Nómina, CRM, Itinerarios o Pases.

## Evidencia antes de modificar

El simulador nuevo C6C0DDA5-EC71-4C05-AD25-9A95832C019B, iOS27, pudo abrir/cerrar el evento de lectura al volver de Fotografía, Alertas, Gestión y segundo plano (`alex-calendar-details-verified.xcresult`). No se atribuyó el cierre a los permisos por no reproducirlo allí. Los dos primeros informes de prueba conservan un fallo de la automatización al buscar Cerrar sesión fuera de la parte visible; se corrigió el recorrido desplazándose, manteniendo la comprobación. No representan un crash de JAC.

Al conectar el iPhone físico se consultaron únicamente la app y sus informes de cierre. JAC instalada era0.24.0(36), iOS26.6.1(23G83). Los informes locales `alex-iphone-190923.ips` y `alex-iphone-191814.ips` muestran la misma terminación EXC_BREAKPOINT/SIGTRAP: assertionFailure, UICollectionView._setNeedsVisibleCellsUpdate, invalidación de UICollectionViewCompositionalLayout y múltiples llamadas recursivas a _updateVisibleCellsNow; después SwiftUI.UpdateCoalescingCollectionView.layoutSubviews. No es la excepción antigua de UINavigationBar ni el EnvironmentObject de CRM. Los informes privados permanecen exclusivamente en work/local, fuera de Git/Site/ZIP.

La evidencia directa identifica un ciclo de actualización de celdas/diseño de la lista. Su relación con la medición de las List de Agenda al presentar el detalle es una inferencia de esas pilas y del gesto informado, no una identificación de una celda concreta ni una medición de memoria. iOS27 no muestra el mismo fallo que ese teléfono26.6.1.

## Corrección

En iPhone/iPad, Agenda y el detalle ahora usan ScrollView/LazyVStack con secciones de ancho acotado y tarjetas. Esas superficies dejan de depender del reciclado de UICollectionView para medir el calendario, textos y detalles al presentar/cerrar la hoja. macOS conserva List a través de los mismos contenedores semánticos. No se cambia NavigationStack, TabView, destinos ni la identidad de navegación. No se intercepta la excepción ni se desactiva el control del sistema.

Se conservan fecha/hora/lugar/descripción completos, enlaces autorizados a Google, edición y edición de ocurrencias, permisos, selección del área entera de cada día, vista Próximos, refresco, caché cifrada/offline, privacidad del contenido y cubierta de escena. El fixture de permisos individuales representa un lector de Agenda y no ofrece Editar por accidente.

## Comprobaciones

- iPhone: dos UI correctas en `alex-calendar-after.xcresult`: cambio por las tres secciones, selección de días, apertura/cierre de detalles, regreso de segundo plano y área completa de la celda. Cuatro regresiones correctas en `alex-calendar-regression.xcresult`: permisos limitados, mes/Próximos/detalle/cuenta, reapertura offline/actualización, creación/edición simuladas. Se mantienen sus aserciones.
- API Calendar: pruebas en memoria/Google simulado correctas (`alex-calendar-node.log`). No cambian rutas o peticiones a Google.
- Release genérico iPhone/iPad0.24.1(37) correcto, sin firma (`alex-ios-release.log`). Debug para el teléfono conectado compilado con su firma existente (`alex-device-build.log`), sin cambiar Team, certificados, bundle o push.
- Se actualizó la app existente del teléfono a0.24.1(37), conservando sus datos. El primer intento encontró el dispositivo desconectado; el segundo pasó. Se abrió explícitamente con --uitest-payroll/reader/sections/R2: host.invalid, URLProtocol, sesión en memoria, caché temporal y Fotos simuladas. No se hizo login ni se consultaron/manipularon datos reales como prueba.
- Camilo confirmó en el mismo iPhone26.6.1: «Ahora abre y funciona», después de abrir el evento ficticio y cambiar de sección. La instancia ficticia se cerró por señal15 solicitada por nosotros, sin core dump; no fue otro crash. La siguiente apertura normal usa la cuenta y caché habituales, no los argumentos de prueba. No se restableció la contraseña ni se cerró la sesión real para esa instalación.

iPad: la prueba de Agenda lateral/rotación/CRM pasó (`alex-ipad-agenda.xcresult`). Mac:108 unitarias correctas y Release universal correcto (`alex-mac-regression.xcresult`, `alex-mac-release.log`), conservando List en macOS. La publicación web se registra al completarla. Xcode trasladó las cadenas de uso de cámara/Fotos y orientaciones iPad a sus ajustes de generación de Info durante el trabajo; se comprobó que los productos Debug físico y Release conservan ambos permisos, orientaciones y pushNO. No se sustituyen esas preferencias personales con el proyecto saneado de Git. La confirmación física corresponde al recorrido ficticio descrito; no se afirma haber probado todos los eventos reales ni todas las versiones de iOS.

El código final quedó guardado en Git local12954f5 y fuente privada del mismo Site95ae26209596ae62df6bc1a739a2ca21c376718f; publicación web77 succeeded. Se abrió/cerró también el detalle ficticio en la app de Mac con su List nativa, sin editar eventos. El esquema personal se comparó con baseline y permanece idéntico; los productos físico/Release conservan permisos de cámara/Fotos, orientaciones y pushNO. La distribución del mismo proyecto/ZIP usa la fuente saneada de Git conservando sus claves de uso en Info.plist, sin copiar ajustes personales ni informes físicos. Se respeta la reorganización equivalente de Info que Xcode hizo en la carpeta de trabajo.
