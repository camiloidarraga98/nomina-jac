# Fuente pública y comprobaciones Apple online

Camilo pidió hacer público `camiloidarraga98/nomina-jac` y retomar las pruebas de GitHub Actions después de agotar su cuota privada. Autoriza la publicación del código/historial y las ejecuciones en runners estándar; sustituye la pausa anterior de CI. La visibilidad de la aplicación/datos de producción no cambia.

## Preparación y estado comprobado

La última consulta de metadatos todavía muestra `visibility: private`; no declarar público hasta observar el cambio. El conector disponible permite consultar el repositorio, subir fuente y leer Actions, pero no tiene una operación para cambiar visibilidad. La CLI no puede llegar a `api.github.com`: la política de red devuelve Forbidden. El cambio de visibilidad necesita hacerse desde los ajustes de GitHub o mediante un acceso autorizado que admita esa operación; no evadir la política de red.

Se revisaron los174 commits y2870 objetos alcanzables del historial local: no se encontraron archivos de credenciales/bases/certificados por nombre ni bloques PEM privados completos con los patrones usados. Las coincidencias de cabeceras privadas son validadores/generación en pruebas y la coincidencia Slack pertenece al backend simulado. Esta comprobación acotada no certifica ausencia absoluta de secretos. El código/historial conserva información interna del proyecto, cuya exposición Camilo autorizó al pedir hacerlo público. `.dev.vars`, bases y claves de ejecución siguen ignoradas y no se agregan al repositorio.

## Workflow

`.github/workflows/native-checks.yml` usa `macos-15` estándar, acceso de lectura, sin claves personales o de producción. Solo ejecuta el job si GitHub informa que el repositorio es público. Mientras siga privado, el job se omite sin arrancar un runner ni ejecutar pruebas.

El evento `public` ejecuta la verificación al cambiar de privado a público; también se conservan push de fuentes nativas/workflow en main/codex y workflow_dispatch. Incluye Release iPhone, las unitarias iPhone y los tres recorridos UI nuevos de selección múltiple, y Release Mac con las fuentes compartidas. Simulador nuevo y fixtures `.invalid`, guardado en Fotos simulado y push suspendido. Los resultados/capturas no contienen datos de producción; se guardan siete días.

## Pendiente

Observar el cambio real a público, comprobar la ejecución online, corregir cualquier fallo y registrar la fuente/resultados finales. La instalación física sigue en el mismo proyecto Xcode del Mac de Camilo. No repetir el despliegue web/API, que ya quedó activo antes de este cambio de flujo.
