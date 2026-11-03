# Comunicado de prensa · El Cumpleaños del Rey del Chupe

Página pública solicitada por Camilo: `https://jhonalexcastano.com/cumple-movistar`. Fuente en `public/cumple-movistar/`; entrega desde `worker/cloudflare.ts` mediante ASSETS. Independiente de `/cumple`, del CRM, de sesiones y de los documentos privados. Solo GET/HEAD después de READY, CSP con recursos propios y redirección de barra final/index.html a la URL canónica. Sin migraciones, servicios, conexiones o secretos nuevos.

## Contenido y recursos

El PDF aportado por Camilo, fechado **2 de noviembre de2026**, es la fuente literal del comunicado. Se conserva el título, las dos bajadas, todos los párrafos, ficha del evento, texto de Breakfast Live y cuatro contactos, sin resumir ni corregir nombres/correos. Solo se normalizan espacios y saltos de línea de maquetación. Los elementos `data-press-copy` conservan el orden de la fuente y definen el texto que copia el botón; las etiquetas de navegación quedan fuera. El PDF descargable es el original completo, SHA-256 `bdb05994d111541c2c97b3bafd4a30c006de766beadebcd963a35ffe6891307c`.

Diseño inspirado en el KV adjunto: vino/negro, dorado, trono y tipografía editorial sobre marfil. Camilo pidió sustituir el retrato rojo inicial por la escena del KV con **traje verde y ambas mesas**, retirando el nombre dorado inferior y colocando la firma oficial. La edición se hizo con ImageGen a partir del KV que volvió a adjuntar: retirada de letras, reconstrucción de la zona cubierta y encuadre vertical; no describir este derivado como un recorte de píxeles sin regeneración. La firma original se superpone como recurso independiente, sin fabricarla en la imagen. El encuadre usa la proporción completa y object-fit:contain para conservar las mesas en todos los anchos. Recursos versionados kv-traje-verde-640/1122.webp y compartir-kv.jpg; versión CSS press-kv-2. Corona oficial de1G8gycR0tG1S0RNGdxM7HXnr4ZUsM01Zz, firma existente en el rider y logo Breakfast Live extraído del PDF. La fotografía roja inicial15L00088.jpg se conserva únicamente como recurso histórico; la página y su vista previa social utilizan la escena verde.

Fuentes locales Cormorant Garamond600 y DM Sans400/600, distribuidas por Fontsource5.2.8 con licencias OFL adjuntas. No hay recursos externos al cargar la página ni nuevas cookies. Vista previa social1200×630 compuesta con esos mismos elementos, sin texto del comunicado reescrito. Descarga del PDF, copia del texto completo y compartir/copiar enlace; lectura y enlaces disponibles sin JavaScript. Preferencia de movimiento reducido y estilos de impresión.

El enlace **Accede acá a material de apoyo** conserva exactamente la carpeta del PDF: `https://drive.google.com/drive/folders/1oowQkZoiEKYWUcEKEMmHakoNmjgH59yj?usp=sharing`. La conexión de Drive devolvió esa carpeta, titulada Presskit: Jhon Alex Castaño, sin archivos el3 de noviembre. No se rellenó ni cambió su compartición. Boletería enlaza la dirección general indicada en el comunicado, `https://www.tuboleta.com`; no se inventa una ficha de venta ni un PULEP.

## Verificación

- Comparación automatizada del texto visible/copiable con la extracción del PDF: coincidencia íntegra y en orden, ignorando solo espacios/saltos y separadores Unicode invisibles del PDF. Descarga verificada con hash idéntico al adjunto.
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
