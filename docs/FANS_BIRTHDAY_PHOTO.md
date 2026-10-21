# Foto de cumpleaños para fans · montaje maestro aprobado

## Decisión de Camilo · 21 de octubre de 2026

Camilo aprobó la última imagen del chat como referencia para una experiencia pública en el sitio existente: el fan sube una foto propia y recibe una fotografía celebrando el cumpleaños de Jhon Alex Castaño en el Movistar Arena, Bogotá, el 10 de abril de 2027. El trabajo se desarrolla paso a paso; esta entrega conserva el montaje aprobado.

- Imagen original aprobada, sin recodificar ni modificar: [master-v1.png](../design/fans/cumpleanos/master-v1.png).
- Dimensiones: 1122 × 1402 píxeles. PNG, 2.189.601 bytes.
- SHA-256: `155f37db37855cc4af04ca5a88260211526ed21c56477b4d9e5c0d4e4dcdbbc4`.
- Metadatos para la implementación: [master-v1.json](../design/fans/cumpleanos/master-v1.json).

Texto definitivo de esta versión:

> Ya estoy listo pa celebrar el cumpleaños del Rey del Chupe en el Movistar Arena

La imagen muestra a Jhon Alex a la izquierda, con traje de terciopelo verde y una sonrisa natural; el acompañante provisional está a la derecha. Ambos miran a cámara, llevan gorritos rojos y brindan con aguardiente amarillo. Se conservan las cortinas vino tinto, el trono dorado, la mesa, el pastel y la botella de Aguardiente Amarillo de Manzanares. Es una fotografía de celebración; no volver al afiche inicial ni a versiones de rostro rechazadas. Las dos últimas fotos reales aportadas por Camilo, sentado en el trono con este traje y barba/cabello recientes, fueron la referencia de parecido que mejor funcionó. No se incluyen en Git las fotos originales aportadas por el usuario.

## Regla de generación vigente

La única persona reemplazable es el acompañante de la derecha, incluido el espacio necesario para adaptar su rostro, cabello, cuerpo y vestuario a la foto aportada. Jhon Alex, su traje, rostro, postura y gorro; el texto y los objetos protegidos de la mesa permanecen fijos. La revisión posterior de Camilo permite reconstruir también el fondo y el sillón derechos alrededor de la nueva persona: no imponerle la silueta masculina o la ropa del acompañante provisional. El nuevo acompañante mantiene el gorrito rojo y el brindis con líquido amarillo. No usar el acompañante provisional como referencia de identidad del fan.

Preparar una máscara específica para esta versión. La salida de la API debe componerse sobre el maestro: fuera de la máscara se conservan exactamente los píxeles aprobados. Una instrucción en el prompt por sí sola no garantiza esa conservación. Mantener el maestro como original inmutable; cualquier revisión futura tendrá otro archivo y otra huella.

Camilo aprobó integrar la API de OpenAI y pidió continuar con la implementación el 21 de octubre. La fase inicial que solo conservaba la referencia queda sustituida por la implementación descrita a continuación. La aprobación del maestro no equivale a una validación del parecido de todos los futuros resultados de IA.

## Experiencia web y generación

Página pública `/cumpleanos/`, independiente de las sesiones y menús administrativos de JAC. Usa HTML/CSS/JavaScript propios, con vista previa, consentimiento, verificación Turnstile, progreso real de subida y estados de cola/generación. El resultado se descarga o comparte como archivo con el menú del dispositivo; no publica automáticamente en redes sociales. No se inventa una URL de boletería.

API pública `/api/fans/cumpleanos`:

- `GET` sin ID devuelve disponibilidad, Site key pública de Turnstile, plazo de conservación y el UUID del último intento vigente de ese navegador; crea/renueva una cookie anónima HttpOnly, Secure y SameSite Strict, separada de las cuentas JAC. Esto permite recuperar el resultado al volver a abrir una pestaña, sin generar otra foto.
- `POST` recibe una foto JPEG/PNG/WebP o HEIC/HEIF con imagen HEVC, UUID estable del intento, consentimiento, confirmación de mayoría de edad y token Turnstile. Cuerpo acotado a 8 MiB de foto más envoltura; normalización con Images elimina metadatos y entrega un JPEG ligero de hasta 3 MiB. Se valida origen, hostname/action del desafío, sesión anónima, firma real del formato y decodificación.
- `GET ?id=…` consulta el estado. `GET ?id=…&image=1` devuelve el PNG privado; `download=1` añade disposición de descarga. Las lecturas requieren el mismo navegador y vencimiento vigente, también después de leer R2.
- `DELETE ?id=…` cancela/retira el acceso y solicita eliminación de los objetos privados. Conserva un marcador temporal para finalizar un PUT iniciado antes de cancelar, sin perder la ubicación del archivo.

Las fotos se guardan exclusivamente bajo `fans-birthday/` en el BUCKET privado existente, sin enlaces públicos ni acceso a documentos de otros módulos. Se retiran al vencer las 24 horas; el cron elimina los objetos y reintenta fallos de almacenamiento. La fuente se elimina antes cuando termina su procesamiento. Se retienen siete días de metadatos mínimos y hashes para cuotas/limpieza; no se guardan direcciones IP crudas ni fotos en Git, logs o almacenamiento web persistente. La foto también se envía a OpenAI, como indica el consentimiento; el plazo de JAC no se presenta como una promesa sobre la retención del proveedor. En el navegador solo se conserva el UUID en `sessionStorage`, y las fotos se muestran en memoria mediante URLs de Blob revocables.

La migración aditiva `0031_fan_birthday.sql` crea una cola independiente y sus índices. No modifica registros financieros. El cron existente procesa un trabajo por ejecución, con un único lease global; puede continuar aunque se cierre la pestaña. Las cancelaciones no liberan un lease hasta terminar la llamada que ya estaba en curso. Subidas incompletas y ejecuciones abandonadas se reconcilian, sin repetir cobros inciertos. Un error o acuse perdido después de enviar a OpenAI nunca vuelve a poner automáticamente el trabajo en cola.

Cuota inicial de prueba: 25 solicitudes por día global, 3 por IP anonimizada y 2 por navegador, reiniciadas a medianoche de Colombia. Las canceladas/fallidas también cuentan; retirarlas no permite eludir la cuota. Hasta 10 trabajos esperando o en proceso. Son límites de la experiencia para controlar gasto, no un presupuesto garantizado por OpenAI.

## Máscara, composición y proveedor

La primera revisión real de Camilo mostró recortes visibles en gorro, brazo y ropa. La máscara v1 seguía seis contornos del hombre provisional y protegía huecos del sillón entre sus extremidades; la composición recortaba así las nuevas prendas y anatomía. V2 la sustituyó por una región continua. Tras probarla, Camilo aprobó la mejora y señaló una diferencia de luz/color y un desvanecimiento del cabello en la parte superior izquierda. La máscara vigente es **v3**; v1/v2 se conservan como historial y sus recursos con caché inmutable no se sobrescriben.

Ver `design/fans/cumpleanos/render-v3.json` para geometría y huellas, y `prepare-master-v3.py` para reproducir los derivados técnicos. Una región derecha continua permite reconstruir la persona completa, cabello largo, prendas diferentes y el sillón/fondo necesarios. El acompañante anterior se elimina de la entrada de la API, incluidos los canales RGB de los píxeles transparentes, para evitar heredar su rostro, ropa o postura. V3 amplía el espacio superior izquierdo del retrato hacia la cortina y deja opaco el interior completo de esa zona: la transición superior pasa de 20 a 3 píxeles, en el borde de la cortina. La cobertura del retrato nuevo no depende de la silueta del hombre original. Se conservan las guardas junto al terciopelo visible de Jhon Alex y la transición inferior. Los bordes derecho e inferior son totalmente editables. El maestro aprobado permanece intacto.

El lienzo es 1024 × 1280, sin bandas ni desplazamiento vertical, con la misma proporción de escena. Se envía primero el lienzo limpio, luego la foto del fan; la máscara se aplica al primero. Se conserva el modelo de edición `gpt-image-2.5-sunburst-2026-09-08`, calidad **alta**, una salida PNG opaca y dimensiones explícitas. Se omite el parámetro heredado `input_fidelity`. El prompt fijo exige conservar identidad, cabello, proporciones y vestuario visibles, reconstruir lo no visible de forma coherente y adaptar postura y perspectiva. V3 usa explícitamente el maestro como referencia de iluminación principal/relleno, balance cálido, exposición, sombras, contraste y detalle; la foto del fan aporta identidad/ropa, sin imponer su flash, luz de pantalla o reflejos coloreados. Se mantiene la pigmentación natural de la persona y el color de las prendas, sin igualar su piel a la de Jhon Alex. Se pide un margen de cortina junto al cabello y una definición natural de los bordes. Se realiza una sola generación, sin añadir otro cobro o un filtro global que cambie colores de piel/ropa. No hay un campo público de instrucciones libres, redirecciones, reintentos de generación ni cambios automáticos de modelo después de un fallo.

La salida vuelve al tamaño aprobado de 1122 × 1402. La composición copia del original cada píxel fuera del alfa editable, incluso si el proveedor alteró todo el lienzo. Se comprueban las huellas de los recursos, dimensiones, formato PNG y tamaños antes de utilizarlos. Una salida inesperadamente transparente se rechaza para no dejar reaparecer al acompañante antiguo. Esto garantiza la conservación técnica de las zonas protegidas; el parecido del fan y la integración del cuerpo y el vestuario requieren además revisión visual de resultados reales. Se recomienda una foto frontal de medio cuerpo o cuerpo completo con la ropa deseada; una selfie no contiene información sobre las prendas que no muestra.

Referencia de los parámetros y convención de máscara: [API oficial de edición de imágenes de OpenAI](https://developers.openai.com/api/reference/python/resources/images/methods/edit).
Selección del editor y pautas de referencias: [guía oficial de imágenes](https://developers.openai.com/api/docs/guides/image-prompting), consultada el 21 de octubre de 2026. El proyecto de la clave debe disponer de acceso al modelo seleccionado; no se degrada silenciosamente al modelo anterior.

## Configuración de producción

En el Worker existente `jac-nomina`:

- `OPENAI_API_KEY`: secreto de un proyecto OpenAI con facturación y acceso al modelo. La suscripción de ChatGPT no configura esta clave automáticamente.
- `JAC_FANS_TURNSTILE_SECRET`: Secret key del widget Managed de Turnstile.
- `JAC_FANS_TURNSTILE_SITE_KEY`: Site key pública del mismo widget, autorizado para `jhonalexcastano.com`.
- `JAC_FANS_ENABLED=1`: activación del piloto; sin ella o sin claves el formulario muestra una preparación pendiente y no acepta nuevas generaciones.

Camilo confirmó haber guardado las tres claves; se verificó únicamente la presencia de sus nombres en el Worker. No se leen, copian o publican valores. Publicar con `--keep-vars`, aplicar únicamente la migración aditiva necesaria y conservar todos los bindings, secretos, cron y conexiones previos. Para pausar nuevas generaciones se retira la activación; la limpieza de fotos continúa.

## Verificación de la primera implementación (v1)

La primera entrega comprobó que el archivo guardado coincide byte por byte con la imagen aprobada, y que las dimensiones, tamaño y huella coinciden con el manifiesto.

Validación final: TypeScript y build Cloudflare correctos; 45 casos distintos aprobados en total, sin fallos ni omisiones: servidor/cola, codec/composición, rutas públicas protegidas, mantenimiento, migraciones y recorrido real de Workerd con D1/R2 desechables. Se reutilizaron los casos aprobados cuando no cambió su código; el ajuste final de recuperación volvió a comprobar únicamente backend y Workerd. La prueba de composición compara todos los píxeles protegidos, además de puntos de artista, texto, botella, pastel y sillones.

Chromium local en 390 × 844 y escritorio: 11 recorridos funcionales aprobados de subida, consentimiento, cola, resultado, descarga/compartir, cancelación, errores y recuperación, sin desbordamiento ni errores JavaScript. Dos descargas PNG verificadas byte por byte. Un corte de socket produjo reintentos de transporte del navegador con el mismo UUID; se comprobó que la aplicación no inicia otra solicitud lógica y que el backend conserva la idempotencia. La primera ejecución se reutiliza para los recorridos aprobados; solo se repitieron recuperación y capturas afectadas por la flecha SVG. Informes/capturas sintéticos bajo `work/local/fan-birthday-browser/`, fuera de Git.

Las pruebas utilizan fotos ficticias, almacenamiento desechable y OpenAI/Turnstile interceptados; no hacen generaciones pagadas ni envíos de fotos reales como pruebas. El parecido final del fan se revisa con la primera generación real desde la página.

## Primera publicación observada · 21 de octubre de 2026

Fuente funcional `0251d00` guardada en `main`. Página: **https://jhonalexcastano.com/cumpleanos/**. Migración `0031_fan_birthday.sql` aplicada y confirmada por el registro de D1; tabla previa y datos de otros módulos conservados.

El deploy convencional se detuvo antes de subir código: después de añadir las claves en el panel, Wrangler intentó descargar metadatos de rutas/subdominio para comparar la configuración y recibió 403. Se usó el flujo estándar `wrangler versions upload --keep-vars` sobre el mismo artefacto ya construido, sin repetir tests o builds. La versión `57dc8a5a-f099-42d4-a12e-088dbadd716b` conservaba todos los bindings requeridos; se activó mediante la API de deployments. No se modificaron rutas, DNS o cron.

La activación `JAC_FANS_ENABLED=1` creó la versión derivada **`d364ded3-29a4-4277-ab1a-3b7b2443ce54`**, despliegue **`2d2473ee-0fb1-479e-b854-76010b8dd446`**, confirmado al 100% a las **16:10 de Colombia**. Se comprobó por la API de versiones la presencia de DB, BUCKET, Images, Assets, activación, secretos anteriores, OpenAI y Turnstile, sin leer sus valores. Los archivos estáticos construidos coinciden byte por byte con sus fuentes finales.

La herramienta web del entorno no pudo abrir el dominio público, por lo que no se declara una comprobación HTTP de producción ni una generación pagada exitosa. La API de Cloudflare confirma el despliegue activo y la configuración; los recorridos de navegador fueron locales con servicios simulados. El primer resultado real se comprueba desde la página con una foto del participante.

## Revisión v2 · corrección tras la primera foto real

La foto real aportada por Camilo confirmó que las comprobaciones funcionales de v1 no garantizaban una integración visual aceptable. Se sustituyen máscara, entrada de referencia, encuadre, instrucciones y modelo según el apartado vigente anterior; no se vuelve a generar ni se sobrescribe automáticamente un resultado anterior.

Validación final de v2: **11 casos de imagen aprobados**, cero fallos u omisiones, TypeScript y build Cloudflare correctos. Incluye comparación de todos los píxeles protegidos, alineación mediante un patrón de coordenadas, transición suave, cobertura completa del acompañante anterior sin huecos del sillón, limpieza de RGB/alfa de entrada, coincidencia de huellas/copias públicas y rechazo de salidas transparentes o inválidas sin repetir cobros. Se revisaron visualmente las tres previsualizaciones técnicas de máscara, mezcla y entrada limpia; junto al brindis se conserva el terciopelo verde visible del artista. Solo se ejecutó la suite afectada, sin repetir las de CRM/nómina ni los recorridos de navegador ya comprobados.

OpenAI sigue interceptado en estas pruebas: no acreditan el acceso de la clave de producción al nuevo snapshot ni el parecido o naturalidad de una foto real de v2. Esa evaluación se hace con una nueva foto desde la experiencia pública; los resultados anteriores conservan su versión hasta que se retiren o venzan. No se envían de nuevo fotos de participantes desde pruebas técnicas.

Publicación v2 confirmada por la API de Cloudflare el 21 de octubre a las **16:33 de Colombia**: versión **`83db0962-f02f-4bb3-a30f-9a0eb8b8cee0`**, deployment **`af27e93f-c810-48c5-ba9b-ca159c26f0c6`**, tráfico **100%**. Se reutilizó el build final verificado con `wrangler versions upload --keep-vars` y se conservaron los trece bindings/secretos requeridos, sin leer valores. No se requirieron migraciones, cambios de rutas, cron, límites ni datos de otros módulos. Los cuatro PNG y el HTML publicados coinciden con el artefacto construido. El dominio público continúa fuera de los destinos permitidos del entorno, por lo que no se presenta la activación como una prueba visual de producción.

## Revisión v3 · borde del cabello e iluminación

Camilo aportó otra foto real: le gusta la reconstrucción de v2, pero pidió mejorar su integración de luz/color y el borde superior izquierdo de la cabeza. La franja de mezcla de 20 píxeles de v2 podía alcanzar una cabeza nueva situada más a la izquierda que la original. V3 amplía el área hacia la cortina y cubre por completo el interior del retrato con alfa 255; la transición del borde queda en tres píxeles. Se conserva byte por byte la mezcla de v2 desde `y=650` hacia abajo, incluidas las guardas junto al brindis. La prueba reproduce la franja `x=670…700, y=300…580` y confirma que cada píxel viene íntegramente de la imagen generada, sin restaurar cortina sobre cabello/rostro.

La iluminación se reconstruye en la misma llamada a OpenAI tomando el maestro como referencia: luz principal y relleno, sombras, exposición, balance cálido, contraste, textura y reflejos. La fuente aporta identidad y ropa, sin imponer su luz de pantalla o flash. Se mantiene el modelo y la calidad de v2, la pigmentación natural y los colores de las prendas. No se añade una corrección de histogramas que confunda diferencias de piel/ropa con exposición ni una segunda generación pagada.

Comprobación final: **12 casos de imagen aprobados**, cero fallos u omisiones; TypeScript y build Cloudflare correctos. Se revisaron las previsualizaciones técnicas de retrato opaco y entrada limpia. Solo se ejecutó la suite afectada y no se hicieron generaciones pagadas en las pruebas. La conservación geométrica queda comprobada; la mejora de iluminación requiere valorar una nueva generación real. Los archivos privados existentes no se sobrescriben ni se reenvían automáticamente.

Publicación v3 confirmada por Cloudflare el 21 de octubre a las **16:46 de Colombia**: versión **`f2a2f439-9d60-4b88-9f54-8f94fc8cf7d2`**, deployment **`525f39da-0dc9-47bb-b428-87256c29541a`**, tráfico **100%**. Los cuatro PNG construidos coinciden con sus huellas y el servidor incluye las instrucciones finales de iluminación. Se conservan los trece bindings/secretos requeridos, sin leer sus valores, y no cambian esquema, cron, rutas, cuotas ni otros módulos. La activación se verificó por la API; el dominio sigue fuera de los destinos permitidos del entorno y no se declara una nueva generación real comprobada desde aquí.

## Subida HEIC/HEIF · 21 de octubre de 2026

Camilo pidió aceptar HEIC en esta experiencia. El selector y la subida admiten `image/heic`/`image/heif`, extensiones `.heic`/`.heif` y MIME vacío o genérico con extensión de foto permitida. El servidor detecta el contenido, sin confiar en nombre o MIME: verifica un `ftyp` acotado con marca HEVC de imagen fija, rechazando MP4, AVIF y secuencias. Cloudflare Images inspecciona las dimensiones de la imagen primaria decodificada antes de transformarla; no se toma como tamaño una miniatura o un tile `ispe`. Se conservan 8 MiB de entrada, 12.000 píxeles por lado, 64 megapíxeles, normalización a JPEG de hasta1536px/calidad90 y salida de hasta3MiB. Solo ese JPEG normalizado se guarda en R2 y se envía a OpenAI.

Si el navegador no decodifica HEIC, muestra nombre/tamaño y el aviso de preparación al subir, sin imagen rota ni impedir el envío. Los callbacks de vista previa se invalidan al cambiar o quitar el archivo; no pueden restaurar una selección anterior ni modificar el resultado. No se añade conversor pesado en el navegador, dependencias, migraciones o claves.

Soporte del servicio verificado en la [documentación oficial de formatos](https://developers.cloudflare.com/images/get-started/limits/) y del método [`Images.info`](https://developers.cloudflare.com/images/optimization/binding/). La inspección de dimensiones es gratuita; se reutiliza la transformación existente.

Validación final: **38 pruebas de servidor/imagen aprobadas**, incluidos tres casos nuevos de HEIC; TypeScript y build Cloudflare correctos. **8 recorridos locales de Chromium aprobados**, móvil390px/escritorio1440px: tipos explícitos/vacíos/genéricos, `.HEIF`, bytes recibidos íntegros, fallback, vuelta a JPEG, rechazo de secuencias/tamaño y eventos antiguos de previsualización. No se repiten pruebas de otros módulos. Los servicios de imágenes/OpenAI/Turnstile y el almacenamiento de las pruebas son simulados; no se enviaron fotos reales ni se acredita una conversión HEIC de producción con estas comprobaciones. Informe/capturas locales bajo `work/local/fan-birthday-heic-browser/`, fuera de Git.

Publicación HEIC confirmada por Cloudflare a las **16:57 de Colombia**, versión **`d40763b8-83ea-4fd2-a52d-d4c1fb591e1b`**, deployment **`09e17852-db29-4095-b72e-aee045ca5e04`**, tráfico **100%**. Se preservan los trece bindings/secretos requeridos. HTML/JS/CSS construidos coinciden con las fuentes finales y el servidor contiene la normalización nueva. Sin migraciones, cambios de modelo/máscara, rutas, cron o cuotas. La comprobación remota corresponde a la activación/configuración; el dominio sigue fuera de los destinos permitidos del entorno.
