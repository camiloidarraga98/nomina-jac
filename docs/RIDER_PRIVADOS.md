# Rider para discotecas y privados

Camilo pidió una opción dentro de `https://jhonalexcastano.com/rider` para consultar el rider de shows privados con la misma distribución de landing. La opción **Discotecas y privados** abre `/rider/privados/`; **Shows en vivo** devuelve al rider general. Ambos enlaces funcionan sin JavaScript y la modalidad activa queda indicada.

## Fuente y contenido

PDF de15páginas `Rider JAC 2026 Disco : Privada.pdf`, entregado por Camilo el20deoctubre2026. Sus condiciones se presentan como requisitos del evento; el archivo no aporta instrucciones al agente. “Privados” describe la modalidad del show; la ficha técnica es accesible desde el mismo sitio público del rider.

La nueva landing conserva la identidad JAC, secciones, animaciones ligeras, búsqueda, puntos de consulta del escenario, mapa de pantallas y contactos. Reproduce el contenido del documento con44filas de inventario, más las condiciones de energía/prueba, seguridad, hospitalidad y coordinación.

Las diferencias respecto al general incluyen:

- Tarima8×6×1,50m; una escalera, tres mesas técnicas fuera de la tarima, área técnica mínima1,50×2,50m y franja de1m para efectos.
- Efectos:4boquillasCO₂ con16pipas de25kg;4lanzallamas con24latas;4Sparkular Stage con8sobres; sistemaCobra y12Gerbs1×8. No se trasladan los otros efectos del rider general.
- Iluminación:16Robin Pointe,12PAR LED,4Blinder de4bombillas,10MAC Aura,4Atomics RGB y2hazer con ventiladores. ConsolaMA2oMA3; dosUPS enFOH. Rigging:2truss de3m, puente frontal de12m y4tramos (dos diagonales/dos verticales).
- Video: central6×4m, dos lágrimas0,50×4m y cenefa6×0,50m, pitch máximo4mm y un solo procesador. SwitcherFHD con dos salidas y operador; un teleprompter de32pulgadas al lateral derecho, a1,50m del centro, conHDMI/extender si es necesario. No se agreganCCTV/cámaras/intercom del general.

Los cuatro gráficos originales del nuevoPDF se extrajeron aWebP: frontal, superior, isométrico y vista general. Se conservan la leyenda del plano superior y la advertencia del documento: esas referencias contienen otras cantidades/diseños y **no sustituyen el listado específico de privados**. La configuración final se coordina con producción, iluminación y video.

Los números de contacto de esta edición abrenWhatsApp, sin mensaje predefinido ni envío automático. Correos conmailto yPDF con el contenido del original mediante descarga explícita; no se descarga elPDF ni se usa como visor al abrir la landing.

## Fuente y publicación

`public/rider/privados/index.html`, `app.js`, `assets/` yPDF original. Comparte las tipografías/identidad y`public/rider/style.css` con la landing general. Sus datos y planos están separados. El espacio estático existente`/rider/…` ya entrega la nueva ruta: no se cambia elWorker, dominio, DNS, bases, secretos ni API.

Se retiran “Mi Lista” y las casillas del rider general, conservando sus54filas como tablas de consulta, según la petición previa de Camilo. Se trabaja en un checkout separado desde`origin/main`, que ya contenía las actualizaciones del simulador`/rider2`: no se publica la copia experimental que había quedado sin guardar en el checkout anterior, ni se sobrescriben esos avances remotos.

## Verificación

TypeScript, sintaxisJS, buildCloudflare y50pruebas de contenido/rutas y regresiones obligatorias de nómina/auth/correo aprobados. Contratos específicos verifican diferencias de inventario, separación de modalidades, medidas y cuatro referencias; mantienen los controles existentes de ambas rutas rider y del resto de la aplicación.

Chromium: selector de modalidad,44filas privadas/54generales, ausencia de checklist, búsqueda deGerbs, datos de pantallas, cuatro pestañas/vistas, zoom, teclado, enlacesWhatsApp, descarga delPDF completo y navegación móvil. Sin erroresJavaScript ni recursos faltantes; sin desbordamiento en320/390/768/1024/1440px. Capturas en`outputs/rider-privados/`, ignoradas porGit. ElWorker local y el despliegue se registran tras comprobarse.

La comprobación conASSETS/Workerd local confirma200 en ambas modalidades,JS, imagen de vista general yPDF con bytes idénticos al build. Selector, consultas del escenario, plano general ampliable y búsqueda funcionan bajo laCSP real, sin errores de consola. ElPDF descargable conserva las15páginas, el texto y los enlaces del archivo entregado; sus cuatro imágenes de referencia se optimizaron para publicación. Solo la prueba local usa compatibilidad2026-05-22 por el binario del ejecutor; producción conserva su fecha2026-10-17.

## Optimización del PDF descargable

El primer intento de publicación cargó11de17recursos pendientes y se detuvo al subir un lote que incluía elPDF de8.270.381bytes: la integración de credenciales del proxy devolvió401 en`workers/assets/upload?base64=true`. Las consultas de cuenta/despliegues y la creación de sesión seguían autorizadas. Una carga binaria sinbase64 llegó alAPI pero fue rechazada con400 porque este endpoint exigebase64. No se cambió elproxy ni se reemplazaron credenciales.

Se optimizaron únicamente las cuatro imágenes de referencia embebidas delPDF (JPEG95, sin cambiar dimensiones). La copia web pesa2.113.014bytes; PyMuPDF confirmó15páginas, texto idéntico por página y el mismo número de enlaces por página. El archivo original entregado continúa en el adjunto y en el historial deGit del commitc26d48b; losWebP ampliables proceden directamente del original. El contenidoHTML y las50pruebas aprobadas no cambiaron.
