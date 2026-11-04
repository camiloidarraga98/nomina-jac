# Comunicado de prensa · El Cumpleaños del Rey del Chupe

Página pública solicitada por Camilo: `https://jhonalexcastano.com/cumple-movistar`. Fuente en `public/cumple-movistar/`; entrega desde `worker/cloudflare.ts` mediante ASSETS. Independiente de `/cumple`, del CRM, de sesiones y de los documentos privados. Solo GET/HEAD después de READY, CSP con recursos propios y redirección de barra final/index.html a la URL canónica. Sin migraciones, servicios, conexiones o secretos nuevos.

## Contenido y recursos

El PDF aportado por Camilo, fechado **2 de noviembre de2026**, es la fuente literal del comunicado. Se conserva el título, las dos bajadas, todos los párrafos, ficha del evento, texto de Breakfast Live y cuatro contactos, sin resumir ni corregir nombres/correos. La única edición posterior del texto autorizada por Camilo sustituye las cuatro referencias a «popular» por «despecho», con ajustes gramaticales; el resto conserva la fuente y solo normaliza espacios y saltos de línea de maquetación. Los elementos `data-press-copy` conservan el orden de la fuente y definen el texto que copia el botón; las etiquetas de navegación quedan fuera. El adjunto original, SHA-256 `bdb05994d111541c2c97b3bafd4a30c006de766beadebcd963a35ffe6891307c`, se conserva como fuente del texto. Por petición posterior de Camilo, la descarga pública entrega una adaptación editorial de tres páginas con la misma estructura visual de la landing; ver «PDF adaptado» al final.

Diseño inspirado en el KV adjunto: vino/negro, dorado, trono y tipografía editorial sobre marfil. Camilo pidió sustituir el retrato rojo inicial por la escena del KV con **traje verde y ambas mesas**, retirando el nombre dorado inferior y colocando la firma oficial. La edición se hizo con ImageGen a partir del KV que volvió a adjuntar: retirada de letras, reconstrucción de la zona cubierta y encuadre vertical; no describir este derivado como un recorte de píxeles sin regeneración. La firma original se superpone como recurso independiente, sin fabricarla en la imagen. El encuadre usa la proporción completa y object-fit:contain para conservar las mesas en todos los anchos. Recursos versionados kv-traje-verde-640/1122.webp y compartir-kv.jpg; versión CSS press-kv-2. Corona oficial de1G8gycR0tG1S0RNGdxM7HXnr4ZUsM01Zz, firma existente en el rider y logo Breakfast Live extraído del PDF. La fotografía roja inicial15L00088.jpg se conserva únicamente como recurso histórico; la página y su vista previa social utilizan la escena verde.

Fuentes locales Cormorant Garamond600 y DM Sans400/600, distribuidas por Fontsource5.2.8 con licencias OFL adjuntas. No hay recursos externos al cargar la página ni nuevas cookies. Vista previa social1200×630 compuesta con esos mismos elementos, sin texto del comunicado reescrito. Descarga del PDF, copia del texto completo y compartir/copiar enlace; lectura y enlaces disponibles sin JavaScript. Preferencia de movimiento reducido y estilos de impresión.

El enlace **Accede acá a material de apoyo** conserva exactamente la carpeta del PDF: `https://drive.google.com/drive/folders/1oowQkZoiEKYWUcEKEMmHakoNmjgH59yj?usp=sharing`. La conexión de Drive devolvió esa carpeta, titulada Presskit: Jhon Alex Castaño, sin archivos el3 de noviembre. No se rellenó ni cambió su compartición. Boletería enlaza la dirección general indicada en el comunicado, `https://www.tuboleta.com`; no se inventa una ficha de venta ni un PULEP.

## Verificación

- Comparación automatizada del texto visible/copiable con la extracción del PDF: coincidencia íntegra y en orden, ignorando solo espacios/saltos y separadores Unicode invisibles del PDF. La entrega inicial descargaba el adjunto con hash idéntico; la verificación del PDF adaptado se documenta al final.
- Chromium local:320,375,390,430,680,768,820,1024,1280 y1440px; sin desbordamiento, contenido fuera del viewport ni imágenes rotas. Copia, enlace compartido, descarga, cuatro contactos, navegación, sin JavaScript y movimiento reducido correctos. Cero errores de página o recursos externos bajo la CSP real. Inspección visual de portada móvil/escritorio y página completa.
- TypeScript, build Cloudflare y50 pruebas Node: Cloudflare11, nómina20, permisos12 y correo7. Servicios simulados; sin correos, notificaciones o modificaciones de datos reales.
- Worker construido en Workerd local: HTML, variantes de URL, CSS/JS, imagen social yPDF200, bytes idénticos al build, tipos/CSP correctos y HEAD vacío. La fecha local de compatibilidad se ajusta a2026-05-22 para el runtime instalado; producción conserva2026-10-17.

## Publicación confirmada ·3 de noviembre de2026

Fuente funcional `bb6aad3` en main. Cloudflare confirmó a las **13:32 de Colombia** el deployment `ba6e33e9-ae82-46d3-85b6-a429cecfa171`, versión `56d8a808-3f76-4738-b393-4440a44b6226`, al100%. Los14 bindings y los dos crons coinciden con la comprobación previa. Se cargaron14 recursos nuevos; publicación con `--keep-vars`, sin migraciones o cambios de datos. Wrangler terminó con el error auxiliar conocido al consultar subdomain/memberships después de cargar y activar: la API de deployments confirmó el resultado y no se repitió la publicación.

La comprobación visual y HTTP es local, incluido Chromium contra el Worker construido bajo su CSP, sin errores. El dominio de producción no está permitido por la política de red del ejecutor; no se afirma una visita remota al sitio. Capturas y evidencias en `work/local/cumple-movistar/` (ignoradas en Git).


## KV verde aplicado en la landing ·3 de noviembre de2026

Por corrección de Camilo, el KV editado del traje verde sustituye el retrato rojo directamente en la portada y en la vista previa social. Ambas mesas completas, firma oficial independiente y encuadre conservado en10 anchos. Comunicado/copiar/PDF comprobados de nuevo; build final coincide con HTML/CSS/recursos publicados. Fuente `696bd6e` en main. Worker `be9b19a4-ffb5-4976-882c-84ae90a8fce7`, deployment `9174c609-0c67-4671-b336-2511e18f0abf`, al100% desde13:40 Colombia.14 bindings y dos crons idénticos; confirmado por API tras el error auxiliar de Wrangler. Enlace para renovar la caché de página: `https://jhonalexcastano.com/cumple-movistar?v=kv-2`.


## Presentadores · JAC Music en blanco

Camilo pidió añadir JAC Music junto a Breakfast Live bajo PRESENTA. Se reutiliza el logo oficial transparente del rider sin cambiar su geometría; CSS brightness(0) invert(1), opacidad1 y sin mezcla lo muestra totalmente blanco, incluida la flecha. Logos alineados con separador discreto; en anchos pequeños PRESENTA queda encima. Recurso propio jac-music.webp y revisión press-logos-3. Navegador en10 anchos, copia exacta del comunicado, descarga y build correctos; sin cambios de texto o servidor.

Publicado el3 de noviembre a las13:45 Colombia: fuente fa6acd4; Worker af9532ad-bdd8-407c-8398-88d21ffb5f54, deployment5675e797-d4f8-4548-92e8-3e5f6357b44f, al100%.14 bindings y dos crons conservados, comprobado por API. Enlace de actualización: https://jhonalexcastano.com/cumple-movistar?v=logos-3.


## PDF adaptado ·3 de noviembre de2026

Camilo pidió que Descargar PDF entregara una adaptación del comunicado con la estructura de la landing, en lugar del archivo plano original. Ambos botones descargan ahora `comunicado-de-prensa.pdf?v=diseno-1`, conservando el nombre de descarga. Documento A4 de tres páginas: portada con KV verde/firma/corona/logos, título y bajadas; comunicado completo con cierre destacado; ficha del evento, Breakfast Live y cuatro contactos. Paleta vino/dorado/marfil y las mismas fuentes locales, texto seleccionable, enlaces activos y numeración de página. El PDF pesa aproximadamente2MB; no requiere generación en el servidor.

Fuente de composición en `scripts/build-press-pdf.mjs` y `design/press-movistar/pdf.css`. Con Playwright y Chromium instalados, ejecutar `node scripts/build-press-pdf.mjs` desde el repositorio; puede indicarse otra salida como argumento y la ruta del navegador mediante `PRESS_CHROMIUM_PATH`. El generador toma las secciones directamente del HTML público, carga solo recursos locales, comprueba los33 bloques de texto en orden, las tres páginas y los márgenes antes de escribir. No requiere conexiones de producción. Evidencias ignoradas en `work/local/cumple-movistar/pdf/`.

Comprobación del PDF real con PyMuPDF:33 bloques presentes y en orden tras normalizar espacios y excluir únicamente los iconos decorativos de la ficha; ninguna caja de texto fuera de página. Enlaces al material de apoyo, boletería, cuatro correos y landing correctos. Inspección visual de las tres páginas, fuentes incluidas y separación suficiente entre contenido y pie. La comparación DOM conserva íntegro el texto del original, incluidos los iconos. No se altera el comunicado web ni su función Copiar.

Descarga real en Chromium local: los bytes recibidos coinciden con el PDF diseñado (SHA-256 `3850bc73d6e825426b2aa689f4c1709c00e9952206ab0dc86139ec35b90e6c45`), ambos enlaces llevan la revisión nueva y el nombre de descarga se conserva. Revisión web en10 anchos, sin JavaScript, copia exacta y CSP correctas. TypeScript, build Cloudflare y50 pruebas requeridas correctos; HTML/PDF en dist idénticos a fuente.

Publicado el3 de noviembre a las14:58 Colombia: fuente `13c6df2` en main; Worker `876b9b98-0252-4be5-b779-f071fe233ba7`, deployment `99e1b98f-ccc5-4299-89b5-71b5762c2f0e`, al100%. Los14 bindings y dos crons coinciden con la comprobación anterior. Solo2 recursos estáticos actualizados. API confirma activación tras los errores auxiliares conocidos de Wrangler en subdomain/memberships; no se repitió despliegue. Descarga nueva: `https://jhonalexcastano.com/cumple-movistar/comunicado-de-prensa.pdf?v=diseno-1`.


## Comunicado centrado en despecho

Camilo pidió retirar cualquier mención de «popular» tanto de la landing como del PDF. Cuatro frases se actualizan a «fiesta de despecho», «el despecho y la parranda», «referentes del despecho en Colombia» y «si hay despecho de por medio». Esta petición sustituye la literalidad del adjunto únicamente en esos pasajes. El texto copiable deriva del mismo HTML; el PDF se regenera desde esa fuente y ambos enlaces de descarga llevan `?v=despecho-2` para renovar la caché.

Verificado que no queda la palabra retirada en el HTML público, texto/metadata del PDF o los33 bloques aprobados. PDF de tres páginas, márgenes y enlaces conservados; revisión visual de las dos páginas afectadas. No cambia el diseño ni la información del evento y contactos.

Comprobaciones adicionales: Chromium local en10 anchos, copia con los cambios autorizados y descarga con bytes idénticos al PDF nuevo; build Cloudflare correcto y recursos dist idénticos a fuente. Se conservan las comprobaciones TypeScript y50 casos Node anteriores, cuyas entradas no cambian en esta edición estática.

Publicado 04/11/2026 06:47 Colombia: fuente `bae4dda`; Worker `50386477-3401-4782-b8fc-913c628e95d4`, deployment `6671dc69-1613-457a-89e3-fb1b101869a2`, al100%. Los14 bindings y dos crons coinciden con la versión previa. Activación confirmada por API tras el error auxiliar conocido de Wrangler; no se repitió despliegue. Enlace con revisión nueva: https://jhonalexcastano.com/cumple-movistar?v=despecho-2.
