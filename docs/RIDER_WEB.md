# Rider técnico web · Jhon Alex Castaño · 2026

Landing pública en `https://jhonalexcastano.com/rider`, integrada en el Worker existente `jac-nomina`. Fuente: el PDF actualizado de 15 páginas entregado por Camilo el 20 de octubre de 2026. El documento aporta requisitos técnicos y contenido; sus condiciones se muestran al visitante y no son instrucciones de ejecución del agente.

## Contenido y experiencia

- HTML estático con todos los requisitos: energía/prueba, P.A., monitores/backline/efectos, iluminación/rigging/consolas, video/pantallas/señal, tarima, seguridad/accesos, camerino/alimentación y producción.
- Directorio de cinco contactos con enlaces telefónicos y de correo; los enlaces no envían mensajes automáticamente.
- Tres planos originales optimizados a WebP, pestañas accesibles, ampliación y zoom; leyenda de la vista superior. Se conserva la advertencia sobre las diferencias entre planos e inventario y su conciliación con iluminación.
- Escenario conceptual SVG con cuatro puntos interactivos y mapa de pantallas por sistema. Las medidas finales siguen requiriendo coordinación con producción/video.
- Búsqueda en requisitos y contactos, navegación por anclas y seguimiento de sección. Lista personal de 54 filas, guardada exclusivamente en localStorage del navegador, con reinicio; no constituye aceptación ni aprobación de producción.
- Animaciones CSS, aparición de encabezados, pausa y respeto de `prefers-reduced-motion`. Diseño adaptable y controles por teclado.
- PDF original disponible como descarga explícita; la página no usa un visor PDF ni necesita descargar ese archivo para funcionar. No carga React, analítica ni bibliotecas externas; tipografías y recursos son locales.

## Implementación y publicación

Los archivos editables son `public/rider/index.html`, `style.css`, `app.js` y `assets/`. Es contenido estático: editar esos archivos y usar el build/deploy Cloudflare vigente del repositorio. Fuentes Barlow Condensed y DejaVu Sans (símbolos) con sus licencias en assets. Los planos se extrajeron directamente del PDF, sin reinterpretar sus posiciones o cantidades.

`worker/cloudflare.ts` entrega solamente GET/HEAD del espacio `/rider` y `/rider/…` mediante ASSETS, después de comprobar READY. Rechaza otros métodos con405. `/rider` resuelve internamente a `/rider/`, sin cambiar el dominio. Se añaden CSP sin recursos externos, no-sniff y caché pública de cinco minutos (una hora para PDF). Las API/documentos privados y rutas ajenas conservan su flujo anterior. No hay tablas, migraciones, bindings o secretos nuevos.

Verificación local: TypeScript, 46 pruebas (Cloudflare y las obligatorias de nómina/auth/correo), sintaxis JS y build Cloudflare correctos. Chromium comprueba persistencia de lista, buscador/navegación, hotspots, mapa de pantallas, pestañas y teclado, ampliación/zoom, menú móvil, movimiento reducido y ausencia de desbordamiento en320/390/768/1024/1440px; cero errores JavaScript. Capturas en `outputs/rider/` (ignoradas en Git). La publicación se registra después de confirmar el resultado real.

Verificación adicional con ASSETS/Workerd local: `/rider` y `/rider/`, HTML/CSS/JS, tipografía y PDF responden200 con bytes idénticos al build. Chromium funciona bajo la CSP real, sin errores ni bloqueos, y no solicita PDF/planos al cargar la portada. El ejecutor local requiere `--compatibility-date 2026-05-22` para esta comprobación porque su Workerd no admite aún la fecha de producción; el manifiesto publicado conserva2026-10-17. Escape cierra directamente la búsqueda aunque tenga texto.

## Despliegue confirmado · 20 de octubre de 2026

Publicación en Cloudflare propio mediante `npm run deploy:cloudflare` con `--keep-vars`. La API confirma despliegue `cfa6277e-7b81-478c-b2e4-fb12ed0e70f2`, versión `8386f054-4bfd-4fc7-b90c-b54982a03ec2`, activa al100% a las17:55UTC (12:55Colombia). Se conservaron DB `74f39547-ed41-4456-a4b3-e32b2dd13b03`, BUCKET `jac-documentos`, IMAGES y los cuatro nombres de secretos existentes, sin migraciones ni modificación de datos o DNS.

Wrangler cargó el Worker y14 recursos estáticos nuevos/modificados; después terminó con error en las consultas auxiliares `workers/subdomain` y `memberships`, por permisos del token. La consulta posterior de despliegues confirmó la activación; no se repitió la publicación. La lectura directa de `https://jhonalexcastano.com/rider` desde este ejecutor recibe403 del proxy de red, por lo que el smoke HTTP/navegador completo corresponde al Worker local. El despliegue de producción se acredita por la API de Cloudflare y se solicitó abrir su URL en Codex.


## Segunda versión interactiva

Camilo pidió una segunda versión en `/rider2`, con simulación espacial a escala, equipos movibles, previsualización de efectos y sin checklist. `/rider` conserva su versión original. Ver [implementación, cantidades, limitaciones y publicación confirmada](RIDER2_SIMULATOR.md).
