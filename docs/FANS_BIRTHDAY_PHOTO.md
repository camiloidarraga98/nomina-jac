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

Camilo propuso y aceptó integrar después la API de OpenAI para edición de imágenes con referencia y máscara. Modelo, parámetros, máscara, tratamiento temporal de las fotos y operación pública se definirán en la siguiente etapa. La máscara todavía no está creada ni validada. Esta entrega no incorpora una página de fans, un endpoint de generación, credenciales ni cambios en producción. Los prompts y la imagen del chat no constituyen una integración de API ya operativa.

## Verificación de esta entrega

Se comprobó que el archivo guardado coincide byte por byte con la imagen aprobada, y que las dimensiones, tamaño y huella coinciden con el manifiesto. Solo se conservan recursos de diseño y decisiones funcionales; no corresponde repetir compilaciones o pruebas de aplicación.
