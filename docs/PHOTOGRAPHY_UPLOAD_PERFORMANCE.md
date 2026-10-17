# Fotografía: carga simultánea, progreso general y carpetas en iPhone

16 de octubre de 2026. Mismo Site, colección privada R2 y proyectos nativos. Sin cambios de datos reales, claves, permisos, dependencias, lockfile o esquema.

## Diagnóstico

La cola web y nativa enviaba un archivo completo, confirmaba sus partes y generaba/subía la miniatura antes de empezar el siguiente. Los tiempos de preparación y confirmación dejaban ociosa la conexión. El indicador solo recibía el desplazamiento confirmado al terminar cada bloque de hasta 8 MiB: durante una transferencia larga parecía detenido. No se midió el rendimiento de la conexión real de Camilo/R2 en Colombia; este diagnóstico no atribuye toda la lentitud al almacenamiento.

El fallo de descargar/guardar una carpeta se reprodujo con una prueba R2 antes de corregir el código: `transfer-r2-before.xcresult` falla con CancellationError en mediaDownloadPlan. Al reunir las páginas, el cliente construía otro MediaFeed sin provider/collectionID. pinFeed rechazaba correctamente una colección diferente de la R2 guardada; la UI interpretaba el error como cancelación y no mostraba nada. Las pruebas anteriores usaban el proveedor histórico sin collectionID y por eso no detectaban este caso.

## Cambios

- Dos archivos simultáneos por lote en web/iPhone/iPad/Mac. Web prepara una imagen a la vez para limitar memoria, mientras otra puede viajar a R2. Cada archivo conserva su UUID, reanudación, tamaño/tipo fijados y todas las confirmaciones del servidor. No hay cargas paralelas ilimitadas ni cambio a relay por JAC. La galería web se refresca al terminar el lote en lugar de repetir el listado completo por cada archivo.
- Un círculo general ponderado por bytes, archivos completados y velocidad reciente en B/KB/MB por segundo; detalles y reintentos por archivo dentro de «Ver archivos». No se marca 100% hasta confirmar los originales y terminar sus miniaturas. Las fases de preparación/confirmación no inventan tráfico; tras cuatro segundos sin bytes la velocidad deja de mostrarse como activa.
- Navegador: eventos de progreso XHR en un documento aislado por transferencia, con CSP connect-src exclusivo del host exacto R2, sin cookies de terceros ni Referer. Se valida de nuevo la URL de respuesta y el frame solo acepta mensajes del padre/origen esperados. La capacidad firmada va por memoria, nunca por atributos, archivos o logs. El fetch histórico conserva redirect:error. La prueba local de redirección fuera del host confirma cero peticiones al receptor bloqueado. No se permite un destino arbitrario para conseguir progreso.
- Nativo: progreso de bytes de URLSession por tarea, rechaza redirecciones y descarta callbacks al terminar/cambiar de sesión. Una respuesta perdida se reconcilia con el servidor sobre el mismo ID. Videos y modo original conservan bytes; calidad de imágenes y miniaturas siguen disponibles.
- Las carpetas completas conservan provider, collectionID y marcadores de borrado. Se comprueba que la colección/raíz/sesión no cambien al recorrer páginas/subcarpetas; se mantiene la comprobación estricta en pinFeed. La autorización de Fotos se inicia tras cerrar la hoja de revisión y los errores de permiso muestran un resultado visible.

## Verificación

Las pruebas usan .invalid/servicios simulados, fotos/videos ficticios, caché temporal y escritor de Fotos simulado. No se escriben fototecas reales ni se prueban cargas/borrados en producción. La prueba nueva R2 cubre plan, cifrado offline, guardado simulado y conservación de colección; la UI de iPhone/iPad también usa collectionID R2, conserva reapertura sin internet y todas las comprobaciones previas. Se prueba la negativa de permiso de Fotos y el cálculo de velocidad concurrente/expiración.

Informes y resultados finales se añaden al cierre de esta corrección. La instalación en dispositivos físicos requiere Run del mismo proyecto; una compilación o simulación no verifica el comportamiento físico de Fotos o la velocidad de internet.

### Resultados comprobados

- 130 pruebas Node correctas y 15 Workerd locales con salidas interceptadas; TypeScript correcto. Regresión del medidor/aislamiento repetida: 3/3.
- iPhone: 98 pruebas unitarias ejecutadas, una condición física omitida y cero fallos; dos UI completas correctas (subir/foto/video con círculo y carpeta R2 offline/Fotos/reapertura). Tres unitarias finales correctas, incluyendo permiso de Fotos denegado y plan R2 (`transfer-ios-final-unit.xcresult`).
- iPad: UI R2 descarga/Fotos/reapertura offline correcta (`transfer-ipad-tests.xcresult`). Mac: 107 unitarias correctas (`transfer-mac-tests.xcresult`); recorrido manual .invalid confirma «2 de 2 archivos disponibles sin conexión». No se usó el runner UI de Mac conocido por su bloqueo AMFI.
- Navegador local: lote ficticio 3/3, máximo dos transferencias simultáneas, fotos/video con SHA256 idéntico al origen y tres miniaturas. Eventos XHR mostraron velocidad y círculo; la redirección fuera del host tuvo cero peticiones receptoras. Registro `work/local/transfer-browser-check.json` y captura `outputs/fotografia-progreso-general-local.png`. No representa una medición de velocidad real a R2.
- Releases iPhone/iPad 0.24.0(36) y Mac 1.10.0(12) compiladas en este Mac (`transfer-ios-release.log`, `transfer-mac-release.log`). Firma/esquema personales comparados con baseline y preservados, bundle y pushNO conservados. La biblioteca física de Fotos aún requiere prueba en el iPhone del usuario tras Run.

Los informes `transfer-r2-before.xcresult` y `transfer-r2-after.xcresult` conservan el diagnóstico: el primero reproduce el CancellationError real del plan; el segundo confirmó offline y reveló que el nuevo mock también debía responder a metadata antes de Fotos. Se corrigió el mock sin retirar las verificaciones; el informe completo y la repetición final posteriores pasan.

### Publicación y entrega

Web v77 succeeded en el mismo Site appgprj_6aa0260b82a88191a47960614238350a: fuente privada95ae26209596ae62df6bc1a739a2ca21c376718f, versión appgprj_6aa0260b82a88191a47960614238350a~appgver_782f5f188d5481919c95322ee001912b, despliegue appgdep_6ad2c2b5b18481918ff816a7d2ecc99f, env_set_revision2. DB/BUCKET y26migraciones idénticas, misma audiencia/dominio/R2/conexiones. El build exacto transfer-site-build-verified.log/TypeScript se reutilizó para el añadido nativo final tras comparar y confirmar que ninguno de sus archivos web de entrada cambió. El helper requiere Node24 también en PATH para empaquetar; el primer intento guardó la fuente pero no pudo empaquetar al faltar ese PATH. Se repitió con el mismo commit ya guardado, sin crear otro Site ni versión duplicada. Credencial solo por entrada oculta, nunca archivos.

La entrega nativa final incorpora además la corrección de Agenda: iPhone/iPad0.24.1(37), Mac1.10.0(12), mismos proyectos. El teléfono conectado se actualizó y Camilo comprobó el detalle de Agenda con fixture.invalid; Fotos sigue validado mediante escritor simulado, sin modificar bibliotecas reales. Misma outputs/JAC Music.app actualizada con Release universal/firma estricta; copias previas en work/local/transfer-previous-mac y alex-agenda-previous-mac. No se cerró la app real de Mac. Respaldo opcional69archivos sin Team/secretos/estado: outputs/JAC-iPhone-iPad-0.24.1-Mac-1.10.0-fuente-nativa.zip, SHA256 b4d6ec4b9aafd86c031bc505726d72f2df1b84038f365c836803492f0179dd49. No requiere descargar otro proyecto.
