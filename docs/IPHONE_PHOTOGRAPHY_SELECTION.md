# Selección múltiple de Fotografía en iPhone

**Actualización vigente:** repositorio público y Actions reanudado por petición de Camilo. [Verificación completa aprobada](https://github.com/camiloidarraga98/nomina-jac/actions/runs/39187621827) sobre `7f73161f1cf7e5a3367d235f9227deebac5c5d03`: Release iPhone y Mac,156 unitarias aplicables y tres UI, cero fallos; una comprobación de protección física omitida en simulador. La selección/descarga/borrado en bloque está verificada online y se entrega en main. Ver [detalles y flujo de CI](PUBLIC_REPOSITORY_ACTIONS.md). Instalar en el teléfono sigue requiriendo Run en el mismo Xcode.

18 de octubre de 2026. Mismo proyecto `ios/JACNomina.xcodeproj`, esquema JACNomina y bundle `co.jacmusic.nomina`. Se conservan firma, entitlements, push suspendido y la distribución existente de iPad/Mac/web.

## Uso

- Mantener presionada la miniatura de una foto o un video inicia la selección sin abrir el visor. Después, tocar otros elementos los agrega o retira; una nueva pulsación larga sobre un elemento ya seleccionado lo conserva.
- Las marcas azules y el contador pertenecen a una selección compartida por las carpetas desplegadas, incluidas sus subcarpetas y páginas cargadas. No se seleccionan carpetas ni se incluyen archivos que el usuario no marcó.
- La barra inferior ofrece **Descargar → Guardar en Fotos** y **Descargar → Guardar sin conexión**. La revisión enumera solo los elementos seleccionados y comprueba el espacio. Fotos recibe los originales, incluidos videos, mediante el permiso de agregar de iOS; la otra opción fija la copia cifrada dentro de JAC.
- **Eliminar selección** aparece solo con administración vigente y permiso de borrado en los listados. La confirmación muestra la cantidad; cancelar conserva los archivos. Borrar no retira las carpetas ni los elementos no seleccionados.
- **Detener** cancela las operaciones pendientes. Los archivos ya exportados o eliminados conservan su resultado; no se promete deshacer un lote. Se muestran progreso, resultado y fallos por archivo.
- **Cancelar selección** restablece la apertura habitual de fotos/videos. Salir de la galería, cambiar sesión/colección o conocer una revocación retira la selección; un fallo de red no equivale a una revocación.

## Implementación y límites

`MediaInlineFolder.swift` incorpora `MediaBatchSelection` y `MediaSelectableTile`. El gesto exclusivo sobre la miniatura diferencia mantener presionado de tocar, con semántica de botón y acciones explícitas para VoiceOver. La selección guarda los metadatos/revisión observados, sin descargar originales para marcar miniaturas. Una página ausente no prueba un borrado; únicamente una eliminación, revisión cambiada o revocación confirmadas retiran elementos.

`DocumentsView.swift` integra la barra inferior y reutiliza las transferencias privadas existentes. Descargar es un botón normal con zona mínima de44pt y un diálogo nativo con las dos opciones; evita el Menu no pulsable observado en iOS26. Cada revisión de descarga queda vinculada al ámbito de acceso. El proceso vuelve a comprobarlo después del permiso de Fotos y antes/después de cada archivo, y limpia sus temporales. No hay una cola nueva de descargas en segundo plano.

El borrado usa `deleteMediaFileStep` y la API `deleteFile` existente, un archivo a la vez, conservando IDs, revisiones, marcadores duraderos y reintentos. No es una transacción atómica de todos los archivos: un conflicto se informa sin sobrescribir su revisión; una denegación detiene el lote. El cambio de generación causado por el propio borrado se adopta solo conservando la sesión y los permisos originales.

`DebugUITestBackend.swift` conserva las pruebas `.invalid` y normaliza los identificadores R2 del borrado individual. No se agregaron dependencias, archivos al proyecto Xcode, migraciones, recursos ni conexiones; los manifiestos, firmas y bundles permanecen iguales.

## Verificación y entrega

- **97 regresiones Node/Workerd aprobadas:** 5 de accesos, 37 de Drive histórico, 36 de galería R2, 3 del cliente de transferencia y 16 de Workerd. Todos los servicios externos son simulados, sin contenido, cuentas, envíos ni borrados reales de prueba. Informe local ignorado: `work/local/iphone-media-selection-regressions.log`.
- Se añadieron **nueve regresiones unitarias nativas y tres recorridos de interfaz**, incluyendo selección mixta, exclusión de otros archivos, revisiones, permisos, cancelación/reintentos, originales y cambio de sesión durante el permiso de Fotos. Se conservan en el proyecto para Xcode.
- **Release iPhone y Mac compilados; pruebas completas aprobadas:** fuente `7f73161f1cf7e5a3367d235f9227deebac5c5d03`, [ejecución39187621827](https://github.com/camiloidarraga98/nomina-jac/actions/runs/39187621827).156 unitarias y tres recorridos UI aprobados; una comprobación de NSFileProtectionKey/cifrado físico omitida en CoreSimulator. Xcode16.4, simulador iPhone17Pro/iOS26.2. No se instaló en un iPhone físico.
- Los fallos iniciales de compatibilidad SwiftUI/fixtures y accesibilidad quedaron corregidos. El contenedor de la barra conserva los identificadores propios de sus controles; Descargar usa un Button y un confirmationDialog, con opciones elegidas por sus etiquetas visibles en la prueba. Se mantienen las comprobaciones de pulsación, permisos, confirmación de borrado, originales y archivos no seleccionados. El historial de CI y la pausa/reanudación por cuota están en la guía enlazada.
- TypeScript, las 43 pruebas de nómina/auth/correo/Cloudflare y el build web ya habían pasado al preparar este chat. Se reutilizan porque ningún archivo de entrada web/API ni dependencia cambió por esta modificación.

**Web/API publicada, 19 de octubre:** Camilo autorizó expresamente el flujo automático, resolviendo los bloqueos iniciales de publicación. El Worker `jac-nomina` tiene activo al100% el despliegue `9875443e-9ed9-4435-8aae-81b49a36d553`, versión `b4c4b3a7-3823-45c5-b6c5-cafc34215a15`. Su código contiene `deleteFile`, `r2-delete-file` y `/api/media/offline`; DB y BUCKET conservan sus identificadores y permanecen los tres secretos de ejecución. Se usó `--keep-vars`, sin migraciones ni borrados/envíos reales de prueba.

Wrangler publicó el Worker y luego terminó con error al consultar `/workers/subdomain`, operación que el token de cuenta no permite. La API de despliegues y la lectura posterior del código confirman la versión activa; no se declara que todo el comando terminó correctamente. No se cambió configuración DNS ni dominio. La política de red del entorno no incluye el dominio público, por lo que no se repite aquí una prueba HTTP sobre él. Informes ignorados en `work/local/iphone-selection-*`.

**Entrega de la fuente:** código verificado incorporado a main. La implementación inicial fue93fbf07; la fuente canónica verificada es7f73161. `.github/workflows/native-checks.yml` está activo con tres jobs paralelos sobre runners estándar, únicamente si GitHub informa que el repositorio es público. El código, la firma, bundles y push NO se conservan.

En la misma carpeta del Mac, estando en `main`:

```sh
git status --short
git pull --ff-only origin main
```

Conservar y conciliar cualquier cambio personal si Git advierte un conflicto; no usar reset/checkout forzados ni retirar la firma. Abrir el mismo proyecto y usar **JACNomina → iPhone → Run**. La fuente nueva no instala por sí misma un binario en el teléfono.

Tras instalar en el iPhone físico, comprobar también: mantener presionada una foto y luego un video, tocar para agregar/retirar, cancelar y volver al visor; descargar solo la selección en Fotos/offline; con archivos de prueba elegidos por Camilo, cancelar la confirmación de borrado y comprobar luego que el lote conserva las carpetas y archivos no seleccionados. Los permisos administrativos y el guardado de originales deben conservarse.
