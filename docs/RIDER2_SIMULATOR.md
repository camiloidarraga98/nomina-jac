# Rider 2 · simulación interactiva

Segunda versión pública en `https://jhonalexcastano.com/rider2`, independiente de `/rider`. Petición de Camilo del 20 de octubre de 2026. El PDF adjunto es fuente de requisitos y planos; sus condiciones no se ejecutan como instrucciones del agente.

## Montaje

151 equipos seleccionables: 82 de iluminación (24 Robin Pointe, 22 PAR LED, 8 blinder, 16 MAC Aura, 8 Atomics RGB, 2 seguidores, 2 hazer), 8 pantallas (central 6×4m, cuatro lágrimas 1×4m, cenefa 6×0,50m y dos CCTV 4×5m), 57 de efectos (8 CO₂, 8 lanzallamas, 8 Sparkular Stage, 8 Sparkular Fall, 4 Flamer X2, 1 sistema Cobra, 16 minas y 4 Stadiumshot), 2 teleprompters y 2 side fills. Cobra se representa como control, sin inventar un disparo propio.

Cantidades de las páginas 5–7 del PDF; tarima 12×8×1,50m y sobretarima 8×1,50×0,60m de pág. 8. Plano espacial en metros, vistas frontal/superior/isométrica, giro sobre fondo y zoom. Estructura según geometría de planos 11–14. La leyenda original difiere del listado: se preserva el aviso y se usan cantidades del inventario de pág. 6; la adaptación no se presenta como plano de iluminación aprobado. La franja de efectos de 2m se propone al frente, dentro de la tarima. Alturas de rigging, separación lateral, reparto de luminarias y posiciones no acotadas de efectos son editables y se identifican como propuestas. Teleprompters a X ±1,50m; cenefa delante de sobretarima.

Seleccionar desde Canvas o selectores por sistema/unidad. Arrastrar cambia X/fondo; en frontal cambia solo X porque la proyección no permite resolver profundidad. Campos numéricos permiten altura/giro; flechas mueven X/fondo y Shift aumenta el paso. Capas, nombres, intensidad/movimiento, cuatro looks y pantallas animadas con CCTV L/R diferentes. Los haces, partículas, alturas y duraciones son ilustrativos; no es cálculo fotométrico, estructural ni de operación real. Hazer ilustrativo, sin sustituirlo por humo.

Disparos por unidad o sistema de CO₂, lanzallamas, X2 con dos chorros, Sparkular ascendente/descendente, minas y Stadiumshot. Demo de 24s con pausa, parada, velocidad, búsqueda temporal y eventos añadibles/eliminables. Blackout apaga luces, video y efectos. No hay DMX, conexiones físicas, servicios de ejecución, sonido ni envíos externos.

Montajes y cues se guardan en localStorage independiente; importar/exportar JSON conserva las cantidades, valida IDs únicos, tipos, coordenadas finitas, rangos, formato/tamaño y eventos. La importación se valida completa antes de sustituir el montaje. Reinicio de posiciones pide confirmación. Sin lista de chequeo ni casillas en esta segunda versión; se conservan los requisitos, buscador, planos, contactos y descarga PDF. `/rider` original permanece disponible.

## Implementación

`public/rider2/index.html`, `style.css`, `app.js`, `simulator.css`, `simulator.js`. Canvas 2D con proyección ortográfica de geometría 3D, sin bibliotecas ni dependencias nuevas. Tipografías, planos, marca y PDF compartidos desde `/rider/`. Render acotado a 2×DPR y suspendido fuera de pantalla/pestaña; respeto de movimiento reducido con reproducción explícita del usuario. Panel HTML y campos accesibles complementan Canvas.

`worker/cloudflare.ts` amplía únicamente el espacio estático GET/HEAD de `/rider2` y sus hijos; conserva READY, CSP local, aislamiento de API/documentos y `--keep-vars`. Sin migraciones, recursos, secretos ni DNS nuevos. Build/deploy según `CLOUDFLARE_MIGRATION.md`; GitHub no despliega automáticamente.

## Verificación y publicación

Sintaxis JavaScript y TypeScript; regresiones del Worker incluyendo ambas rutas rider y límites de método/READY/privacidad; pruebas base de nómina/auth/correo; build Cloudflare. Chromium verificó inventario completo, ausencia de checklist, campos numéricos, arrastre, teclado, persistencia, siete sistemas de efectos, blackout, transporte, cues editables, exportación/importación válida y rechazo atómico de archivos incompletos, buscador, planos, movimiento reducido y ausencia de desbordamiento en 320/390/768/1024/1440px. Cero errores JavaScript o recursos faltantes. La publicación se registra tras confirmarla.


## Publicación confirmada · 20 de octubre de 2026

Cloudflare confirmó despliegue `dcd59f9e-6576-449b-b9a6-088f02535650`, versión `2e97dc01-0e9b-44f5-ab46-36c04d9113b9`, activa al100%, a las18:53UTC (13:53Colombia). Fuente de aplicación `452e3f8` en main. Se cargaron los cinco recursos de `/rider2`; el Worker conserva DB, BUCKET, IMAGES, ASSETS y los cuatro nombres de secretos existentes con `--keep-vars`. Sin migraciones ni modificación de datos o DNS.

Wrangler finalizó con error después de cargar Worker/Assets en las consultas auxiliares `workers/subdomain` y `memberships`, igual que en la publicación anterior. La API de despliegues confirmó la activación posterior, por lo que no se repitió el deploy. La lectura directa del dominio desde este ejecutor recibe403 del proxy: no se afirma un recorrido visual remoto de producción. El recorrido completo de Chromium se ejecutó también contra el artefacto final en Workerd local bajo la CSP real (compatibilidad local2026-05-22; producción mantiene2026-10-17), con cero errores JS/recursos y todas las comprobaciones correctas. No se invocaron cron ni servicios reales para probar.
