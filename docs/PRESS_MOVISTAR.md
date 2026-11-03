# Comunicado de prensa · El Cumpleaños del Rey del Chupe

Página pública solicitada por Camilo: `https://jhonalexcastano.com/cumple-movistar`. Fuente en `public/cumple-movistar/`; entrega desde `worker/cloudflare.ts` mediante ASSETS. Independiente de `/cumple`, del CRM, de sesiones y de los documentos privados. Solo GET/HEAD después de READY, CSP con recursos propios y redirección de barra final/index.html a la URL canónica. Sin migraciones, servicios, conexiones o secretos nuevos.

## Contenido y recursos

El PDF aportado por Camilo, fechado **2 de noviembre de2026**, es la fuente literal del comunicado. Se conserva el título, las dos bajadas, todos los párrafos, ficha del evento, texto de Breakfast Live y cuatro contactos, sin resumir ni corregir nombres/correos. Solo se normalizan espacios y saltos de línea de maquetación. Los elementos `data-press-copy` conservan el orden de la fuente y definen el texto que copia el botón; las etiquetas de navegación quedan fuera. El PDF descargable es el original completo, SHA-256 `bdb05994d111541c2c97b3bafd4a30c006de766beadebcd963a35ffe6891307c`.

Diseño inspirado en el KV adjunto: vino/negro, dorado, trono y tipografía editorial sobre marfil. La fotografía real utilizada es `15L00088.jpg`, de la sesión **8 Oct - Estudio promoción Movistar**, archivo Drive `1bo5REW1G6OZKYz4PJRLMT4fYcYvucBhm`; traje rojo, sin generación o alteración del rostro. La imagen inline del KV aportado no estuvo disponible como archivo descargable en este ejecutor; no se presenta el retrato alternativo como el mismo archivo. Se publican únicamente versiones optimizadas de640/1200px, sin EXIF. Corona oficial de `1G8gycR0tG1S0RNGdxM7HXnr4ZUsM01Zz`; firma oficial ya existente en el rider; logo Breakfast Live extraído del propio PDF. No usar fotografías personales/documentos de identidad encontrados incidentalmente en búsquedas.

Fuentes locales Cormorant Garamond600 y DM Sans400/600, distribuidas por Fontsource5.2.8 con licencias OFL adjuntas. No hay recursos externos al cargar la página ni nuevas cookies. Vista previa social1200×630 compuesta con esos mismos elementos, sin texto del comunicado reescrito. Descarga del PDF, copia del texto completo y compartir/copiar enlace; lectura y enlaces disponibles sin JavaScript. Preferencia de movimiento reducido y estilos de impresión.

El enlace **Accede acá a material de apoyo** conserva exactamente la carpeta del PDF: `https://drive.google.com/drive/folders/1oowQkZoiEKYWUcEKEMmHakoNmjgH59yj?usp=sharing`. La conexión de Drive devolvió esa carpeta, titulada Presskit: Jhon Alex Castaño, sin archivos el3 de noviembre. No se rellenó ni cambió su compartición. Boletería enlaza la dirección general indicada en el comunicado, `https://www.tuboleta.com`; no se inventa una ficha de venta ni un PULEP.

## Verificación

- Comparación automatizada del texto visible/copiable con la extracción del PDF: coincidencia íntegra y en orden, ignorando solo espacios/saltos y separadores Unicode invisibles del PDF. Descarga verificada con hash idéntico al adjunto.
- Chromium local:320,375,390,430,680,768,820,1024,1280 y1440px; sin desbordamiento, contenido fuera del viewport ni imágenes rotas. Copia, enlace compartido, descarga, cuatro contactos, navegación, sin JavaScript y movimiento reducido correctos. Cero errores de página o recursos externos bajo la CSP real. Inspección visual de portada móvil/escritorio y página completa.
- TypeScript, build Cloudflare y50 pruebas Node: Cloudflare11, nómina20, permisos12 y correo7. Servicios simulados; sin correos, notificaciones o modificaciones de datos reales.
- Worker construido en Workerd local: HTML, variantes de URL, CSS/JS, imagen social yPDF200, bytes idénticos al build, tipos/CSP correctos y HEAD vacío. La fecha local de compatibilidad se ajusta a2026-05-22 para el runtime instalado; producción conserva2026-10-17.

La comprobación visual es local. El dominio de producción no está permitido por la política de red del ejecutor; acreditar la publicación por la API de Cloudflare sin afirmar una visita remota al sitio. Registrar aquí la versión y porcentaje reales después del despliegue, conservando los14 bindings y los dos crons existentes.
