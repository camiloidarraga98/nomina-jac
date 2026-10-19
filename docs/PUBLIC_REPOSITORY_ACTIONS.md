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

## Botón de descarga y jobs paralelos

La ejecución39185991596 volvió a aprobar las unitarias y los recorridos de selección/borrado, pero confirmó que tampoco el botón interno del Menu era pulsable en la prueba de iOS26. Se sustituye ese Menu de la barra por un Button normal con una zona mínima de44pt y un confirmationDialog que conserva Guardar en Fotos y Guardar sin conexión. Se retira el helper experimental de la prueba: el recorrido vuelve a exigir la pulsación normal de cada botón. El diálogo se cierra al cambiar ámbito/colección o salir; las transferencias, revisiones y permisos se conservan.

La CI separa ahora tres jobs independientes: pruebas iPhone con simulador, Release iPhone y Release Mac. Todos usan macos-15 estándar y la misma guarda de repositorio público. Ejecutarlos en paralelo reduce la espera sin omitir compilaciones ni pruebas. Los logs Release se guardan en artefactos propios; el resumen de pruebas y xcresult siguen en los artefactos de diagnóstico/iPhone.

## Verificación de la versión con diálogo de descarga

Fuente canónica `7f73161f1cf7e5a3367d235f9227deebac5c5d03`, [ejecución39187621827](https://github.com/camiloidarraga98/nomina-jac/actions/runs/39187621827). Los jobs paralelos de Release iPhone y Release Mac aprobaron. El recorrido usa el botón normal de Descargar y elige las opciones nativas por sus etiquetas visibles; conserva comprobaciones de existencia, pulsación y resultados de Fotos/offline. El job iPhone también terminó aprobado:156 unitarias y los tres recorridos UI, cero fallos y una comprobación física omitida en CoreSimulator.

La sesión de escritura Git por terminal dejó de autenticar; las fuentes se publicaron con el conector integrado mediante blobs/tree/commit y avance de ref con SHA esperado, sin force push. Las huellas de los blobs y del árbol coinciden con la fuente local; las lecturas Git públicas funcionan sin credenciales. No se cambió ninguna credencial ni se pidió copiar claves. Los commits locales de preparación se conservan; la fuente canónica para CI/main es la publicada por el conector.

## Resultado y entrega

**Verificación completa aprobada:** [ejecución39187621827](https://github.com/camiloidarraga98/nomina-jac/actions/runs/39187621827), fuente `7f73161f1cf7e5a3367d235f9227deebac5c5d03`. Los tres jobs paralelos terminaron success: Release iPhone, Release Mac y pruebas iPhone. El resumen contiene160 comprobaciones:159 aprobadas, cero fallos y una omitida; son156 unitarias aplicables y tres UI. La omitida comprueba NSFileProtectionKey/cifrado de un iPhone físico, que CoreSimulator no reproduce. Simulador iPhone17Pro/iOS26.2, Xcode16.4.

Los recorridos UI aprobados incluyen selección mixta y cancelación/visor, guardar solo los dos archivos elegidos en Fotos y sin conexión, y cancelar/confirmar el borrado administrativo preservando carpetas y archivos no seleccionados. No hubo lecturas/escrituras de contenido real para probar. Los artefactos de pruebas y logs Release permanecen siete días.

La fuente verificada se incorporó a main mediante avance seguro desde684cf20, conservando el historial y sin force push. El avance dispara la comprobación automática habitual de main del mismo código; el cierre documental posterior reutiliza el resultado anterior porque no cambia fuentes nativas ni el workflow. Actions queda activo para cambios nativos futuros, con runners estándar gratuitos en el repositorio público y guarda para no gastar la cuota privada si cambia su visibilidad.

Instalación física pendiente de Camilo: pull de main en su carpeta habitual y Run en el mismo Xcode/proyecto/firma. No se repitió el despliegue web/API, que ya estaba activo con sus recursos y secretos conservados antes de publicar la fuente.
