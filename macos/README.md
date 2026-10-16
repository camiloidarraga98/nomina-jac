# JAC Music para Mac

## Fotografía R2 · Mac 1.7.0 (9)

Mismo proyecto JACMac y misma outputs/JAC Music.app. Archivo nuevo R2, sin importar contenido histórico de Drive, con subidas directas reanudables y miniaturas nativas. Se renueva solo la copia cifrada de Fotografía al recibir la nueva colección; sesión, demás módulos y privacidad se conservan. Cierra y vuelve a abrir la app para ejecutar el binario actualizado. Ver docs/PHOTOGRAPHY_R2_MIGRATION.md para estado publicado y verificación.

Aplicación nativa de macOS en SwiftUI y AppKit, dentro de la misma carpeta del proyecto. Comparte modelos, formularios y API con el iPhone; no contiene un navegador incrustado ni crea una base de nómina distinta.

## Fotografía: actualización inmediata — Mac 1.5.1 (7)

Comparte la corrección del iPhone: copia guardada inmediata y consulta de Drive al abrir/volver, sin esperar el ciclo de 30 segundos. Precarga solo metadatos del listado raíz con sesión validada. Se conserva la copia offline, el Llavero, los permisos y los proyectos. Misma ruta `outputs/JAC Music.app`; ver [Fotografía: UX](../docs/PHOTOGRAPHY_UX.md).

## Fotografía principal — Mac 1.5.0 (6)

Fotografía permanece en la barra principal; **Mi cuenta** pasa a **Configuración** y sigue disponible en perfiles restringidos. La galería muestra miniaturas ligeras, carpetas recientes primero y un flujo de subida con destino o nueva carpeta de evento en la ubicación actual.

Para **Disponible sin conexión**, usa clic derecho sobre una carpeta o su menú de puntos. La acción opera sobre la carpeta seleccionada, con revisión de tamaño, progreso y cancelación; no hay botones permanentes de descarga ocupando la galería. Se conservan permisos, copia cifrada y privacidad. **Guardar carpeta en Fotos** pertenece al iPhone.

Mismo proyecto **JACMac → My Mac → Run** y misma ruta `outputs/JAC Music.app`. Ver [Fotografía: UX](../docs/PHOTOGRAPHY_UX.md) para pruebas y entrega; no hace falta reemplazar el proyecto.

## Accesos por sección — Mac 1.4.0 (5)

En **Configuración → Usuarios → Editar** se eligen módulos de forma independiente. Fotografía y subida se conceden por separado; Camilo y `jac` pueden crear carpetas y subir fotos/videos por su rol administrador. La barra lateral y los demás menús muestran únicamente las secciones autorizadas. CRM conserva su restricción administrativa y los pases siguen siendo privados.

La copia cifrada filtra los módulos permitidos y retira información/documentos revocados; una pérdida de internet conserva la sesión y la última copia permitida. La cuenta real de Anderson conserva sus permisos actuales hasta que Camilo guarde su selección. Ver [Accesos por sección](../docs/SECTION_ACCESS.md).

Continúa con **Run desde este mismo `macos/JACMac.xcodeproj`**, esquema **JACMac → My Mac**. La app se entrega en la misma ruta `outputs/JAC Music.app`; si una versión anterior sigue abierta, reábrela para cargar el binario nuevo. El iPhone conserva su mismo proyecto y firma.

Verificado en este Mac con fixtures `.invalid`: 84 unitarias más dos nuevas de revocación, tres recorridos UI distintos de permisos/subida/descarga y Release universal arm64/x86_64 correctos. Firma estricta verificada. Los informes intermedios y el detalle de las repeticiones se conservan en la guía de accesos; no se subieron archivos reales de prueba.

## Fotografía — Mac 1.3.0 (4)

La barra lateral incorpora **Fotografía** para Camilo y `jac`, con consulta de carpetas, fotos y videos dentro de JAC. La cuenta de Anderson muestra únicamente **Fotografía** y **Mi cuenta**: crea carpetas por show/día, elige varios archivos o los arrastra y los sube por partes con reintentos sin duplicados. Las imágenes usan vista previa nativa y los videos el reproductor AVKit del Mac. Se conservan el logo, los demás menús y todos los permisos existentes.

**Disponible sin conexión** incluye los archivos y subcarpetas de la carpeta seleccionada; revisa antes cantidad/tamaño y espacio, muestra progreso y permite detenerse. La copia está cifrada por bloques, excluida de respaldos y vinculada a la sesión/origen; se elimina al cerrar sesión o comprobar una revocación. La galería se actualiza al regresar y cada 30 segundos mientras está visible. La conexión inicial de Drive se administra en la web; no hay claves de Google en el proyecto. **Guardar carpeta en Fotos** pertenece al iPhone.

Continúa con **Run en este mismo `macos/JACMac.xcodeproj`**, esquema **JACMac → My Mac**. La entrega Release universal actualiza la misma ruta `outputs/JAC Music.app` a 1.3.0 (4); la versión anterior se conserva en `work/local/mac-media-previous`. Si la app anterior sigue abierta, ciérrala y abre la actualizada para cargar el nuevo binario. El ZIP es un respaldo opcional, no un proyecto de trabajo nuevo.

Verificado en este Mac: **80 unitarias y dos recorridos UI distintos aprobados**, incluido fotógrafo con creación/subida por lote, lector y carpeta sin conexión. Informes `work/local/mac-media-unit-final.xcresult`, recorridos UI de `mac-media-delivery.xcresult` y acabado final en `mac-media-design-accepted.xcresult`; los informes intermedios se conservan con sus diagnósticos. Release universal arm64/x86_64 compilado, versión 1.3.0 (4) y firma local verificadas (`mac-media-release-final.log`). Todo con datos `.invalid`, imágenes y video ficticios, sin servicios reales ni fototecas. Ver [guía de Fotografía](../docs/PHOTOGRAPHY.md).

## Abrir y usar

1. Abre `macos/JACMac.xcodeproj` en Xcode.
2. Selecciona el esquema **JACMac** y destino **My Mac**.
3. Pulsa **Run**. La firma local ad hoc no requiere seleccionar el equipo del iPhone.
4. Inicia sesión con tu cuenta habitual de JAC. Puedes marcar **Mantener la sesión iniciada**.
5. Espera en **Mi cuenta → Copia sin conexión** a que termine la descarga para poder consultar esa información y sus archivos sin internet.

La aplicación Release se entrega en `outputs/JAC Music.app`. Se puede abrir desde esta carpeta o copiar a Aplicaciones. El binario local no está notarizado para distribución a otros Macs; esa distribución requiere preparar Developer ID cuando Apple termine la aprobación de la cuenta. No se han copiado certificados ni contraseñas.

Requiere macOS 14 o posterior. El producto Release incluye Apple Silicon e Intel. La verificación de ejecución corresponde al Mac de Camilo, con Apple Silicon y macOS 27/Xcode 27; no implica haber probado todos los sistemas compatibles.

## Distribución de escritorio

En **1.2.0 (3)**, CRM comienza con fichas de show: fecha destacada, empresario, estado y venta/abonos/saldo separados. Haz clic en cualquier parte de una ficha para abrirla. La cabecera azul JAC resume cuántos shows hay, cuáles tienen saldo y cuáles no tienen precio. El botón de tabla conserva las columnas ordenables de la vista anterior; las fichas también pueden ordenarse desde su menú. Las cifras monetarias siguen viniendo del servidor.

Los campos de fecha del Mac abren el calendario desde toda la superficie del botón. Cada día responde en su celda completa, incluidos los bordes; también puedes escribir día/mes/año. Se respetan el rango permitido y la hora original del campo. En Agenda se amplía igualmente el área de clic de cada día; esta corrección compartida también queda en el proyecto de iPhone. Su selector del sistema se conserva. Ver `docs/MAC_CRM_DESIGN.md` para los resultados de esta revisión.

Desde **1.1.0 (2)**, la barra lateral muestra **CRM, Quincena, Agenda e Itinerarios**, y debajo **Mi cuenta y Configuración**. CRM aparece para administradores. Configuración reúne Alertas, Gastos, Archivo, Personal, Correos, Conceptos, Notificaciones, Servicios conectados y Usuarios según los permisos de la cuenta. La ventana se puede redimensionar y la barra lateral ocultar.

CRM dispone de una tabla con búsqueda por show o empresario, columnas ordenables de fecha, venta, abonos y saldo, filtros de saldo pendiente/sin precio y acceso a Semana y Empresarios. Selecciona un show y pulsa **Abrir show**, haz doble clic o utiliza su menú contextual. **Nuevo show** y **Registrar abono** están visibles en la barra superior. Se conservan los formularios, documentos privados, rentabilidad y preparación existentes; los importes provienen del servidor.

El menú **JAC** conserva accesos de teclado: ⌘1 Quincena, ⌘2 Agenda, ⌘3 Itinerarios, ⌘4 Mi cuenta, ⌘5 Configuración, ⌘6 CRM cuando corresponde, ⌘7 Alertas y ⌘R para actualizar la sección activa de CRM/Agenda o la información general. El sistema proporciona sus menús de edición y manejo de ventanas. Los editores mantienen su hoja abierta al usar accesos de navegación.

Los documentos se abren en una vista previa nativa de Mac con **Guardar una copia**, **Compartir** e **Imprimir** para PDF. Se conservan la autorización y la descarga privada antes de abrirlos. En abonos, gastos y publicaciones puedes elegir archivos o arrastrar PDF/JPG/PNG al formulario, dentro de los límites existentes. El OCR usa Vision localmente y admite archivos y cámara; siempre muestra los datos para revisión antes de enviar. La cámara necesita el permiso de macOS y una cámara disponible.

## Misma información y protección

- Origen existente: `https://jhonalexcastano.com`. No hay otro Site, servidor o base de producción.
- Mismas cuentas, destinatarios privados, permisos, revisiones, cálculos, históricos y reintentos. El Mac no calcula una nómina alternativa.
- Sesión en el Llavero, sin guardar contraseñas. Caché cifrada con AES-GCM, separada por cuenta/sesión/origen, excluida del respaldo. Carpetas privadas 0700 y archivos 0600 en Mac; iPhone conserva protección completa de archivos de iOS.
- La última copia descargada aparece antes de esperar la red. Las modificaciones requieren conexión; no se encolan envíos. Cerrar sesión o comprobar una revocación retira las copias correspondientes.
- La cubierta de privacidad cubre las ventanas y hojas de edición cuando JAC pierde el foco; al regresar conserva los formularios. Los archivos que guardes expresamente quedan bajo tu control.
- Identificador de Mac: `co.jacmusic.nomina.mac`. El iPhone conserva `co.jacmusic.nomina`, su proyecto, esquema, equipo y firma personal.
- Push continúa suspendido, igual que en el iPhone, mientras se aprueba Apple Developer. Alertas, itinerarios y pases se consultan en la app y se actualizan al abrirla/volver y por consulta periódica. No se afirma haber activado APNs para Mac. La web conserva sus notificaciones actuales.
- Las conexiones compartidas existentes de Calendar, Slack, Gmail y Sheets se reutilizan. Gmail/Agenda conservan la autorización nativa de Apple. La configuración inicial de Slack/APNs y la autorización inicial de Sheets conservan su flujo de administración web; no se trasladan secretos al proyecto.

## Desarrollo y comprobaciones

Los archivos de `ios/JACNomina` se referencian directamente desde el proyecto Mac. `JACMacApp.swift` proporciona la ventana, barra lateral, comandos y privacidad de escritorio. `MacPlatform.swift` adapta Quick Look, impresión, cámara y manejo de imágenes. Las ramas de iOS conservan los controles de teléfono.

Pruebas de Mac:

```sh
xcodebuild -project macos/JACMac.xcodeproj -scheme JACMac \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath work/local/mac-native \
  -parallel-testing-enabled NO test
```

Las mismas pruebas de cliente se compilan para ambos sistemas, incluidas API, concurrencia, permisos, cifrado, restauración sin red, borradores, adjuntos, CRM, OCR y OAuth. La comprobación de protección física de iOS se conserva; en Mac verifica permisos privados de los archivos. Los UI tests usan solo `.invalid` y una sesión ficticia, sin tocar el Llavero ni conexiones reales. La excepción de validación de bibliotecas está restringida al **ejecutor de UI tests** para permitir su firma local; no pertenece al producto JAC.

Las pruebas y capturas locales quedan en `work/local/mac-native-*.xcresult` y `work/local/mac-ux-*.xcresult`. Los informes de intentos fallidos se conservan junto a las repeticiones corregidas. Ver `docs/MAC_NATIVE.md` para la entrega inicial y `docs/MAC_UX.md` para la distribución 1.1.0.

## Fotografía 1.6.0 (8)

La misma app incorpora subida directa limitada a cada archivo, reproducción progresiva y caché privada para fotos. Conserva sesión, permisos y copia offline cifrada. Ver [transferencias y verificación](../docs/PHOTOGRAPHY_TRANSFER.md). App universal compilada y firma estricta comprobada en outputs/JAC Music.app; cerrar y reabrir la instancia anterior para usar esta versión.
