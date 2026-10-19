# JAC Music para iPad — 0.20.0 (32)

La app existente es universal para iPhone y iPad. Se actualiza en el mismo `ios/JACNomina.xcodeproj`, esquema `JACNomina`, con el mismo identificador `co.jacmusic.nomina`; no hay un proyecto, cuenta o servidor nuevo.

## Distribución

- iPad usa una barra lateral nativa con CRM, Quincena, Agenda, Itinerarios/Pases, Fotografía y Gestión, según los accesos de la cuenta. Mi cuenta está dentro de Gestión. Un fotógrafo sin otros accesos conserva únicamente Fotografía y Gestión/Mi cuenta.
- Agenda coloca el mes y los eventos del día en dos columnas cuando el ancho disponible lo permite. En ventanas más estrechas los coloca verticalmente; la selección del día permanece al girar. El área completa de cada día es seleccionable.
- La barra lateral se puede ocultar con el control nativo. En ancho compacto la navegación usa las columnas adaptadas del sistema. No se fuerza pantalla completa.
- Acceso y Gestión tienen un ancho máximo para evitar formularios excesivamente extendidos. Las hojas, el visor PDF, fotos y video usan los componentes nativos existentes.
- El iPhone usa ahora el [menú lateral desplegable](IPHONE_SIDEBAR.md) solicitado por Camilo; el Mac conserva su distribución. Se mantienen funciones, cálculos, permisos del servidor, pases privados, Llavero, caché cifrada y cubierta de privacidad, también sobre formularios al pasar a segundo plano.

## Navegación y pruebas

Las primeras pruebas encontraron que el contenedor de `NavigationSplitView` retenía el detalle de CRM al seleccionar Gestión. Reiniciar solo la vista interna no retiraba la ruta alojada por el contenedor. La identidad del contenedor cambia ahora al seleccionar otra sección; las pruebas entran a un show, cambian a Gestión y abren Mi cuenta. La rotación no cambia esa identidad ni la selección de Agenda. No se eliminaron comprobaciones de privacidad ni pruebas anteriores.

Las pruebas nuevas de `IPadTests` usan el backend interceptado `.invalid`, PDF/foto/video ficticios y guardado en Fotos simulado. Los informes intermedios se conservan para diagnóstico.

Verificado en este Mac con Xcode 27.1 e iOS Simulator 27.0, en simuladores nuevos de iPad Pro 13 (M5), iPad mini (A17 Pro) e iPhone 18 Pro:

- 87 pruebas unitarias nativas aprobadas; una condición de protección de archivos se omite únicamente en CoreSimulator porque requiere dispositivo físico. Informe `work/local/ipad-native-first.xcresult` (unitarias sin fallos; conserva los dos fallos UI iniciales de navegación/selector ya resueltos).
- Cinco recorridos UI distintos de iPad aprobados: barra lateral/rotación/calendario/CRM/Mi cuenta, cuenta restringida/subida/foto/video, descarga/offline/Fotos simuladas, privacidad/borrador al volver y documentos privados/Alertas. Cuatro pasan en `ipad-native-final.xcresult`; el recorrido de documentos pasa en `ipad-native-documents.xcresult`. Navegación/CRM y fotógrafo se repiten correctamente en iPad mini (`ipad-mini-final.xcresult`).
- iPhone: tres regresiones UI aprobadas (`ipad-iphone-regression.xcresult`), incluida Agenda, permisos híbridos y privacidad; selección por bordes de días repetida sobre el código final en `ipad-iphone-final.xcresult`. Sus 87 unitarias también pasan, con la misma condición física omitida.
- Mac: 97 unitarias aprobadas en `ipad-mac-regression.xcresult`; selector de fechas/Agenda aprobado otra vez sobre el código compartido final en `ipad-mac-calendar-final.xcresult`.
- 60 regresiones de servidor de nómina/auth/correo/Agenda aprobadas con servicios simulados. No cambian las entradas del build web ni sus pruebas anteriores de v72.
- Build **Release de dispositivo correcto**, sin firma, `work/local/ipad-native-release.log`. El producto confirma `UIDeviceFamily = [1,2]`, cuatro orientaciones para iPad, versión `0.20.0 (32)`, bundle ID conservado y push `NO`.

Revisadas las capturas de Agenda horizontal/vertical, CRM, Mi cuenta y galería. Firma personal y esquema comparados contra sus copias previas: solo cambian familia de dispositivo y versión/build. Git/respaldo usan el proyecto sin equipo personal. No se instaló en un iPad o iPhone físico ni se usó información o fototeca reales.

## Instalación en el iPad

1. Abre el mismo proyecto de Xcode y selecciona el esquema **JACNomina**.
2. Conecta y desbloquea el iPad, confía en el Mac y activa Modo de desarrollador si el dispositivo lo solicita.
3. Elige el iPad como destino y pulsa **Run**. Usa tu equipo Apple ya configurado; no copies certificados ni contraseñas al proyecto.

Push continúa suspendido (`JAC_PUSH_ENABLED = NO`) mientras Apple revisa la membresía. La versión de dispositivo compilada sin firma confirma la compilación, no una instalación física. La primera instalación/firma y la comprobación de cámara/fototeca reales requieren el iPad del usuario.

## Producción y fotografía

Este cambio no modifica API, datos, migraciones, dependencias, hosting, DNS ni la web publicada v72. No requiere un despliegue de Sites. Drive sigue conectado: Camilo está evaluando sustituir únicamente el almacenamiento de Fotografía por un servicio privado con miniaturas/CDN; todavía no se ha contratado, migrado ni desconectado nada.
