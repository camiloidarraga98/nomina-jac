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

## Regla para la futura generación

La única persona reemplazable es el acompañante de la derecha, incluido el espacio necesario para adaptar su rostro, cabello y cuerpo. Jhon Alex, su traje, rostro, postura y gorro; el texto; el escenario y los objetos de la mesa son elementos protegidos. El nuevo acompañante mantiene el gorrito rojo y el brindis con líquido amarillo. No usar el acompañante provisional como referencia de identidad del fan.

Preparar una máscara específica para esta versión. La salida de la API debe componerse sobre el maestro: fuera de la máscara se conservan exactamente los píxeles aprobados. Una instrucción en el prompt por sí sola no garantiza esa conservación. Mantener el maestro como original inmutable; cualquier revisión futura tendrá otro archivo y otra huella.

Camilo aprobó integrar la API de OpenAI y pidió continuar con la implementación el 21 de octubre. La fase inicial que solo conservaba la referencia queda sustituida por la implementación descrita a continuación. La aprobación del maestro no equivale a una validación del parecido de todos los futuros resultados de IA.

## Experiencia web y generación

Página pública `/cumpleanos/`, independiente de las sesiones y menús administrativos de JAC. Usa HTML/CSS/JavaScript propios, con vista previa, consentimiento, verificación Turnstile, progreso real de subida y estados de cola/generación. El resultado se descarga o comparte como archivo con el menú del dispositivo; no publica automáticamente en redes sociales. No se inventa una URL de boletería.

API pública `/api/fans/cumpleanos`:

- `GET` sin ID devuelve disponibilidad, Site key pública de Turnstile, plazo de conservación y el UUID del último intento vigente de ese navegador; crea/renueva una cookie anónima HttpOnly, Secure y SameSite Strict, separada de las cuentas JAC. Esto permite recuperar el resultado al volver a abrir una pestaña, sin generar otra foto.
- `POST` recibe una foto JPEG/PNG/WebP, UUID estable del intento, consentimiento, confirmación de mayoría de edad y token Turnstile. Cuerpo acotado a 8 MiB de foto más envoltura; normalización con Images elimina metadatos y entrega un JPEG ligero de hasta 3 MiB. Se valida origen, hostname/action del desafío, sesión anónima, firma real del formato y decodificación.
- `GET ?id=…` consulta el estado. `GET ?id=…&image=1` devuelve el PNG privado; `download=1` añade disposición de descarga. Las lecturas requieren el mismo navegador y vencimiento vigente, también después de leer R2.
- `DELETE ?id=…` cancela/retira el acceso y solicita eliminación de los objetos privados. Conserva un marcador temporal para finalizar un PUT iniciado antes de cancelar, sin perder la ubicación del archivo.

Las fotos se guardan exclusivamente bajo `fans-birthday/` en el BUCKET privado existente, sin enlaces públicos ni acceso a documentos de otros módulos. Se retiran al vencer las 24 horas; el cron elimina los objetos y reintenta fallos de almacenamiento. La fuente se elimina antes cuando termina su procesamiento. Se retienen siete días de metadatos mínimos y hashes para cuotas/limpieza; no se guardan direcciones IP crudas ni fotos en Git, logs o almacenamiento web persistente. La foto también se envía a OpenAI, como indica el consentimiento; el plazo de JAC no se presenta como una promesa sobre la retención del proveedor. En el navegador solo se conserva el UUID en `sessionStorage`, y las fotos se muestran en memoria mediante URLs de Blob revocables.

La migración aditiva `0031_fan_birthday.sql` crea una cola independiente y sus índices. No modifica registros financieros. El cron existente procesa un trabajo por ejecución, con un único lease global; puede continuar aunque se cierre la pestaña. Las cancelaciones no liberan un lease hasta terminar la llamada que ya estaba en curso. Subidas incompletas y ejecuciones abandonadas se reconcilian, sin repetir cobros inciertos. Un error o acuse perdido después de enviar a OpenAI nunca vuelve a poner automáticamente el trabajo en cola.

Cuota inicial de prueba: 25 solicitudes por día global, 3 por IP anonimizada y 2 por navegador, reiniciadas a medianoche de Colombia. Las canceladas/fallidas también cuentan; retirarlas no permite eludir la cuota. Hasta 10 trabajos esperando o en proceso. Son límites de la experiencia para controlar gasto, no un presupuesto garantizado por OpenAI.

## Máscara, composición y proveedor

Ver `design/fans/cumpleanos/render-v1.json` para geometría y huellas, y `prepare-master-v1.py` para reproducir derivados técnicos. El maestro aprobado permanece intacto. La máscara traza al acompañante y deja protegidos artista, texto y objetos; su contorno permite cierto margen para el cabello. Un alfa independiente de composición limita el resultado final y difumina dos píxeles hacia el interior del área editable.

El maestro se adapta a un lienzo de API de 1024 × 1536, con la escena de 1024 × 1280 situada en `(0,128)`. Se envía primero el lienzo, luego la foto del fan; la máscara se aplica al primero. Se usa `gpt-image-1.5`, fidelidad alta, una salida PNG y calidad media. El prompt de servidor es fijo. No hay un campo público de instrucciones libres, redirecciones ni descargas desde URLs que devuelva el proveedor.

La salida vuelve al tamaño aprobado de 1122 × 1402. La composición copia del original cada píxel fuera del alfa editable, incluso si el proveedor alteró todo el lienzo. Se comprueban las huellas de los recursos, dimensiones, formato PNG y tamaños antes de utilizarlos. Esto garantiza la conservación técnica de las zonas protegidas; el parecido del fan y las transiciones del contorno requieren además revisión visual de resultados reales.

Referencia de los parámetros y convención de máscara: [API oficial de edición de imágenes de OpenAI](https://developers.openai.com/api/reference/python/resources/images/methods/edit).

## Configuración de producción

En el Worker existente `jac-nomina`:

- `OPENAI_API_KEY`: secreto de un proyecto OpenAI con facturación y acceso al modelo. La suscripción de ChatGPT no configura esta clave automáticamente.
- `JAC_FANS_TURNSTILE_SECRET`: Secret key del widget Managed de Turnstile.
- `JAC_FANS_TURNSTILE_SITE_KEY`: Site key pública del mismo widget, autorizado para `jhonalexcastano.com`.
- `JAC_FANS_ENABLED=1`: activación del piloto; sin ella o sin claves el formulario muestra una preparación pendiente y no acepta nuevas generaciones.

Camilo confirmó haber guardado las tres claves; se verificó únicamente la presencia de sus nombres en el Worker. No se leen, copian o publican valores. Publicar con `--keep-vars`, aplicar únicamente la migración aditiva necesaria y conservar todos los bindings, secretos, cron y conexiones previos. Para pausar nuevas generaciones se retira la activación; la limpieza de fotos continúa.

## Verificación de esta entrega

La primera entrega comprobó que el archivo guardado coincide byte por byte con la imagen aprobada, y que las dimensiones, tamaño y huella coinciden con el manifiesto.

Validación final: TypeScript y build Cloudflare correctos; 45 casos distintos aprobados en total, sin fallos ni omisiones: servidor/cola, codec/composición, rutas públicas protegidas, mantenimiento, migraciones y recorrido real de Workerd con D1/R2 desechables. Se reutilizaron los casos aprobados cuando no cambió su código; el ajuste final de recuperación volvió a comprobar únicamente backend y Workerd. La prueba de composición compara todos los píxeles protegidos, además de puntos de artista, texto, botella, pastel y sillones.

Chromium local en 390 × 844 y escritorio: 11 recorridos funcionales aprobados de subida, consentimiento, cola, resultado, descarga/compartir, cancelación, errores y recuperación, sin desbordamiento ni errores JavaScript. Dos descargas PNG verificadas byte por byte. Un corte de socket produjo reintentos de transporte del navegador con el mismo UUID; se comprobó que la aplicación no inicia otra solicitud lógica y que el backend conserva la idempotencia. La primera ejecución se reutiliza para los recorridos aprobados; solo se repitieron recuperación y capturas afectadas por la flecha SVG. Informes/capturas sintéticos bajo `work/local/fan-birthday-browser/`, fuera de Git.

Las pruebas utilizan fotos ficticias, almacenamiento desechable y OpenAI/Turnstile interceptados; no hacen generaciones pagadas ni envíos de fotos reales como pruebas. El parecido final del fan se revisa con la primera generación real desde la página.

## Publicación observada · 21 de octubre de 2026

Fuente funcional `0251d00` guardada en `main`. Página: **https://jhonalexcastano.com/cumpleanos/**. Migración `0031_fan_birthday.sql` aplicada y confirmada por el registro de D1; tabla previa y datos de otros módulos conservados.

El deploy convencional se detuvo antes de subir código: después de añadir las claves en el panel, Wrangler intentó descargar metadatos de rutas/subdominio para comparar la configuración y recibió 403. Se usó el flujo estándar `wrangler versions upload --keep-vars` sobre el mismo artefacto ya construido, sin repetir tests o builds. La versión `57dc8a5a-f099-42d4-a12e-088dbadd716b` conservaba todos los bindings requeridos; se activó mediante la API de deployments. No se modificaron rutas, DNS o cron.

La activación `JAC_FANS_ENABLED=1` creó la versión derivada **`d364ded3-29a4-4277-ab1a-3b7b2443ce54`**, despliegue **`2d2473ee-0fb1-479e-b854-76010b8dd446`**, confirmado al 100% a las **16:10 de Colombia**. Se comprobó por la API de versiones la presencia de DB, BUCKET, Images, Assets, activación, secretos anteriores, OpenAI y Turnstile, sin leer sus valores. Los archivos estáticos construidos coinciden byte por byte con sus fuentes finales.

La herramienta web del entorno no pudo abrir el dominio público, por lo que no se declara una comprobación HTTP de producción ni una generación pagada exitosa. La API de Cloudflare confirma el despliegue activo y la configuración; los recorridos de navegador fueron locales con servicios simulados. El primer resultado real se comprueba desde la página con una foto del participante.
