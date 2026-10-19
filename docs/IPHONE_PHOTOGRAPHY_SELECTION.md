# Selección múltiple de Fotografía en iPhone

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

`DocumentsView.swift` integra la barra inferior y reutiliza las transferencias privadas existentes. Cada revisión de descarga queda vinculada al ámbito de acceso. El proceso vuelve a comprobarlo después del permiso de Fotos y antes/después de cada archivo, y limpia sus temporales. No hay una cola nueva de descargas en segundo plano.

El borrado usa `deleteMediaFileStep` y la API `deleteFile` existente, un archivo a la vez, conservando IDs, revisiones, marcadores duraderos y reintentos. No es una transacción atómica de todos los archivos: un conflicto se informa sin sobrescribir su revisión; una denegación detiene el lote. El cambio de generación causado por el propio borrado se adopta solo conservando la sesión y los permisos originales.

`DebugUITestBackend.swift` conserva las pruebas `.invalid` y normaliza los identificadores R2 del borrado individual. No se agregaron dependencias, archivos al proyecto Xcode, migraciones, recursos ni conexiones; los manifiestos, firmas y bundles permanecen iguales.

## Verificación y entrega

- **97 regresiones Node/Workerd aprobadas:** 5 de accesos, 37 de Drive histórico, 36 de galería R2, 3 del cliente de transferencia y 16 de Workerd. Todos los servicios externos son simulados, sin contenido, cuentas, envíos ni borrados reales de prueba. Informe local ignorado: `work/local/iphone-media-selection-regressions.log`.
- Se añadieron **nueve regresiones unitarias nativas y tres recorridos de interfaz**, incluyendo selección mixta, exclusión de otros archivos, revisiones, permisos, cancelación/reintentos, originales y cambio de sesión durante el permiso de Fotos. GitHub Actions ejecuta Xcode 16.4 con SDK iOS18.5 en macOS15; los resultados definitivos se registran al terminar. No se instaló en un iPhone físico.
- TypeScript, las 43 pruebas de nómina/auth/correo/Cloudflare y el build web ya habían pasado al preparar este chat. Se reutilizan porque ningún archivo de entrada web/API ni dependencia cambió por esta modificación.

**Web/API publicada, 19 de octubre:** Camilo autorizó expresamente el flujo automático, resolviendo los bloqueos iniciales de publicación. El Worker `jac-nomina` tiene activo al100% el despliegue `9875443e-9ed9-4435-8aae-81b49a36d553`, versión `b4c4b3a7-3823-45c5-b6c5-cafc34215a15`. Su código contiene `deleteFile`, `r2-delete-file` y `/api/media/offline`; DB y BUCKET conservan sus identificadores y permanecen los tres secretos de ejecución. Se usó `--keep-vars`, sin migraciones ni borrados/envíos reales de prueba.

Wrangler publicó el Worker y luego terminó con error al consultar `/workers/subdomain`, operación que el token de cuenta no permite. La API de despliegues y la lectura posterior del código confirman la versión activa; no se declara que todo el comando terminó correctamente. No se cambió configuración DNS ni dominio. La política de red del entorno no incluye el dominio público, por lo que no se repite aquí una prueba HTTP sobre él. Informes ignorados en `work/local/iphone-selection-*`.

**Entrega de la fuente:** rama privada `codex/iphone-media-selection`; implementación inicial `93fbf07`. Camilo autorizó incorporar a `main` después de verificar Apple; esa verificación está en curso. El workflow `.github/workflows/native-checks.yml` comprueba automáticamente cambios nativos en `main`/`codex/**`, sin claves Apple/Cloudflare ni servicios reales para probar.

Para probar desde esa rama, en la misma carpeta del Mac:

```sh
git status --short
git fetch origin
git switch codex/iphone-media-selection
```

Conservar y conciliar cualquier cambio personal si Git advierte un conflicto; no usar reset/checkout forzados ni retirar la firma. Abrir el mismo proyecto y usar **JACNomina → iPhone → Run**. La fuente nueva no instala por sí misma un binario en el teléfono.
