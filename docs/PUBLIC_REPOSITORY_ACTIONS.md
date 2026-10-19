# Fuente pública y comprobaciones Apple online

Camilo pidió hacer público `camiloidarraga98/nomina-jac` y retomar las pruebas de GitHub Actions después de agotar su cuota privada. Autoriza la publicación del código/historial y las ejecuciones en runners estándar; sustituye la pausa anterior de CI. La visibilidad de la aplicación/datos de producción no cambia.

## Preparación y estado comprobado

GitHub confirmó `visibility: public` y `private: false` después de que Camilo completara el cambio desde los ajustes. El cambio quedó registrado a las20:04 del18 de octubre de2026 (Bogotá; API01:04:43 UTC del19). Se conserva el mismo repositorio e historial; no se creó otro repositorio.

El evento `public` inició automáticamente [la ejecución39183661700](https://github.com/camiloidarraga98/nomina-jac/actions/runs/39183661700), fuente `684cf2064fa07f58f75efcd528d54979cebda0eb` en main. Los dos pushes anteriores se omitieron por la guarda mientras el repositorio todavía era privado, sin arrancar runners. La ejecución pública usa el runner estándar `macos-15`.

La conexión permitió preparar/subir la fuente y consultar visibilidad/Actions; no ofrecía cambio de visibilidad y la política de red bloqueaba la CLI hacia `api.github.com`. Camilo lo completó en GitHub. El acceso y cambio reales están comprobados; no queda pendiente volver a pedirlos.

Se revisaron los174 commits y2870 objetos alcanzables del historial local: no se encontraron archivos de credenciales/bases/certificados por nombre ni bloques PEM privados completos con los patrones usados. Las coincidencias de cabeceras privadas son validadores/generación en pruebas y la coincidencia Slack pertenece al backend simulado. Esta comprobación acotada no certifica ausencia absoluta de secretos. El código/historial conserva información interna del proyecto, cuya exposición Camilo autorizó al pedir hacerlo público. `.dev.vars`, bases y claves de ejecución siguen ignoradas y no se agregan al repositorio.

## Workflow

`.github/workflows/native-checks.yml` usa `macos-15` estándar, acceso de lectura, sin claves personales o de producción. Solo ejecuta el job si GitHub informa que el repositorio es público. Mientras siga privado, el job se omite sin arrancar un runner ni ejecutar pruebas.

El evento `public` ejecuta la verificación al cambiar de privado a público; también se conservan push de fuentes nativas/workflow en main/codex y workflow_dispatch. Incluye Release iPhone, las unitarias iPhone y los tres recorridos UI nuevos de selección múltiple, y Release Mac con las fuentes compartidas. Simulador nuevo y fixtures `.invalid`, guardado en Fotos simulado y push suspendido. Los resultados/capturas no contienen datos de producción; se guardan siete días.

## Primera ejecución pública

La ejecución39183661700 compiló Release de iPhone y Mac. Las157 unitarias terminaron con156 aprobadas, una condición física omitida y cero fallos; los tres recorridos UI fallaron al localizar los controles de selección. La jerarquía de accesibilidad confirma fotos/videos seleccionados, contador y barra visibles: el identificador del contenedor `media.selection.actions` se heredaba a todos los controles y ocultaba sus identificadores propios. Se retira únicamente ese identificador del contenedor; los controles conservan sus identificadores y acciones. La prueba de selección usa el estado semántico `isSelected`, evitando depender del texto localizado de ese estado.

El informe indica Xcode16.4 y un simulador iPhone17Pro/iOS26.2. Las salidas de diagnóstico se publican ahora antes de compilar Mac para que los fallos de iPhone se puedan leer antes de terminar todo el job. La corrección mantiene las comprobaciones de permisos, confirmación de borrado y archivos no seleccionados; se ejecutará de nuevo antes de declarar aprobada la interfaz.

## Segunda ejecución pública

La ejecución39184981303, fuente `022bfd024f07df7fbc68145f6da69eb097b98084`, aprobó las156 unitarias aplicables (una comprobación física omitida), el recorrido de selección/cancelación/visor y el de cancelación/borrado administrativo conservando el resto. El único fallo restante fue la pulsación de Descargar: iOS expone su Menu como un contenedor Button alrededor del botón nativo. La prueba ahora elige el control nativo cuando el contenedor no es pulsable y conserva las comprobaciones de existencia/hittability. No se cambia la descarga, el producto ni los permisos por esta adaptación de la prueba. Se repite la verificación online del recorrido de descarga.

## Pendiente

Comprobar la ejecución online ya iniciada, corregir cualquier fallo y registrar la fuente/resultados finales. La instalación física sigue en el mismo proyecto Xcode del Mac de Camilo. No repetir el despliegue web/API, que ya quedó activo antes de este cambio de flujo.
