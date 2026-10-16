# JAC Music para Mac

Aplicación nativa de macOS en SwiftUI y AppKit, dentro de la misma carpeta del proyecto. Comparte modelos, formularios y API con el iPhone; no contiene un navegador incrustado ni crea una base de nómina distinta.

## Abrir y usar

1. Abre `macos/JACMac.xcodeproj` en Xcode.
2. Selecciona el esquema **JACMac** y destino **My Mac**.
3. Pulsa **Run**. La firma local ad hoc no requiere seleccionar el equipo del iPhone.
4. Inicia sesión con tu cuenta habitual de JAC. Puedes marcar **Mantener la sesión iniciada**.
5. Espera en **Mi cuenta → Copia sin conexión** a que termine la descarga para poder consultar esa información y sus archivos sin internet.

La aplicación Release se entrega en `outputs/JAC Music.app`. Se puede abrir desde esta carpeta o copiar a Aplicaciones. El binario local no está notarizado para distribución a otros Macs; esa distribución requiere preparar Developer ID cuando Apple termine la aprobación de la cuenta. No se han copiado certificados ni contraseñas.

Requiere macOS 14 o posterior. El producto Release incluye Apple Silicon e Intel. La verificación de ejecución corresponde al Mac de Camilo, con Apple Silicon y macOS 27/Xcode 27; no implica haber probado todos los sistemas compatibles.

## Distribución de escritorio

La barra lateral conserva **Quincena, Agenda, Itinerarios, Mi cuenta y Gestión**. Gestión reúne CRM, Alertas, Gastos, Archivo, Equipo, Correos, Conceptos y Usuarios según los permisos de la cuenta. La ventana se puede redimensionar y la barra lateral ocultar.

El menú **JAC** ofrece accesos de teclado: ⌘1–⌘5 para las secciones principales, ⌘6 para CRM cuando corresponde, ⌘7 para Alertas y ⌘R para actualizar. El sistema proporciona sus menús de edición y manejo de ventanas.

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

Las pruebas y capturas locales quedan en `work/local/mac-native-*.xcresult`. Los informes de intentos fallidos se conservan junto a las repeticiones corregidas. Ver `docs/MAC_NATIVE.md` para el registro final de comprobaciones y límites.
