# Estado actual · 18 de octubre de2026

Producción ya está en la cuenta Cloudflare de JAC, con el mismo dominio y datos. La fuente se conserva en el repositorio privado `camiloidarraga98/nomina-jac`; no hay Actions ni PR. Continúa en esta misma carpeta del Mac y el mismo proyecto Xcode. Consulta `docs/CLOUDFLARE_MIGRATION.md` para recursos, comprobaciones y publicación. Las instrucciones históricas de Sites que siguen no son el destino de publicación actual. No reinstalar el proyecto ni copiar datos de localhost sobre producción.

# Continuar JAC desde tu Mac

Comprobación local del 6 de octubre de 2026: consulta `docs/MAC_LOCAL_VERIFICADO.md` para los resultados, las incidencias de simulador y el estado de firma. En este Mac Node/npm están instalados dentro de `work/local/toolchain`, sin modificar el PATH global. Usa `scripts/local-env.sh` antes de los comandos, por ejemplo `scripts/local-env.sh npm run dev -- --host 127.0.0.1`.

Este paquete contiene el proyecto completo, incluido el webapp y `ios/JACNomina.xcodeproj`. Parte de la fuente publicada en la versión 25 de https://jhonalexcastano.com. Los archivos de aplicación coinciden con esa fuente; las novedades de este paquete son las instrucciones de continuidad local y un ayudante de preparación. No incluye bases actuales, secretos, certificados, dependencias instaladas ni historial Git.

## 1. Descargar y guardar

Descarga el ZIP desde el enlace privado de Drive, ábrelo con Finder y mueve la carpeta `JAC` a `Documentos/Proyectos/JAC`. Usa una carpeta nueva; no reemplaces a ciegas una copia anterior con cambios o firma propia. Conserva el ZIP como respaldo. Desde ahora se trabaja sobre esta misma carpeta: no necesitas volver a descargar cada actualización ni usar GitHub.

## 2. Abrir Codex local

Abre la aplicación de escritorio que usabas antes. En la versión actual de ChatGPT para Mac, selecciona **Codex** en el menú superior izquierdo. Abre o añade la carpeta `Documentos/Proyectos/JAC`, donde están `AGENTS.md`, `package.json` e `ios`.

En un chat nuevo selecciona **Work in → This computer**, o **Local** si tu versión muestra ese nombre. La carpeta de trabajo debe ser la del Mac; no una ruta `/workspace` ni un entorno Cloud. Para empezar, usa la carpeta directamente sin activar Worktree. Si necesitas instalar la aplicación de escritorio, utiliza la descarga oficial: https://chatgpt.com/download/.

Copia en el nuevo chat el contenido de `CONTINUAR_EN_CODEX_LOCAL.txt`. El historial de este chat no se convierte automáticamente en una sesión local; `AGENTS.md` y `docs/PROJECT_CONTEXT.md` recuperan las condiciones y funciones acordadas.

La ejecución de archivos y compilaciones será local. Codex sigue usando el servicio de OpenAI para responder; este traslado no convierte el modelo en una aplicación sin conexión. La documentación oficial explica los modos en https://learn.chatgpt.com/docs/environments/modes.

## 3. Preparar la web en el Mac

Codex local comprobará Node.js 24 y las herramientas de Xcode. Si no tienes Node 24, instala la versión 24 desde https://nodejs.org/en/download o desde tu gestor existente, evitando sustituir otras instalaciones sin revisar su configuración.

Desde la carpeta JAC:

```sh
node -v
npm ci
```

La incidencia WASI heredada se reparó en este Mac añadiendo únicamente `@emnapi/core@1.10.0` y `@emnapi/runtime@1.10.0` al lockfile. Todas las entradas anteriores conservan su contenido y `package.json` permanece igual. `npm ci` pasó con Node 24.21.0/npm 11.19.0. No uses `npm update` ni borres el lockfile. No es necesario instalar Node para abrir y compilar el proyecto iPhone en Xcode.

Con las dependencias disponibles:

```sh
node scripts/prepare-local.mjs
npx --no-install wrangler d1 migrations apply site-creator-d1 --local --persist-to .wrangler/state --config work/local/wrangler.json
npm run dev -- --host 127.0.0.1
```

El ayudante genera claves independientes en `.dev.vars` solo si no existe, y una configuración de D1/R2 local bajo `work/`. Nunca imprime las claves ni sobreescribe un archivo existente. Las migraciones del comando llevan explícitamente `--local` y apuntan al identificador de desarrollo. `--persist-to .wrangler/state` hace que Wrangler y Vite usen la misma base local. Abre la dirección localhost que aparezca en la terminal; su base no contiene tus quincenas reales. Para el primer acceso propio, abre `/acceso?configurar=1` en esa dirección y crea un usuario de prueba local.

No conectes Gmail, Google Calendar, Slack o Apple reales en la copia de desarrollo. Sus conexiones de producción permanecen en el servidor publicado. Los scripts antiguos `install-ci.sh` y `build-verified.sh` contienen utilidades de Linux; en Mac utiliza los comandos de este documento.

## 4. Compilar e instalar el iPhone

Abre `JAC/ios/JACNomina.xcodeproj` con Xcode. Selecciona el esquema `JACNomina`, tu iPhone y, en **Signing & Capabilities**, tu Personal Team y firma automática mientras Apple aprueba la membresía. Desde 0.9.5 el push está suspendido temporalmente; ver `ios/README.md`. Conserva el identificador `co.jacmusic.nomina`. Pulsa **Run** para actualizar la app instalada; no hace falta borrarla.

Esta app consulta el servidor publicado y sus datos reales. Para probar cambios de datos utiliza las pruebas simuladas de **Product → Test**, no acciones reales de cierre, eliminación, correo o alertas. Si vuelve la pantalla en blanco conocida con tu Xcode, consulta `ios/README.md`: desmarcar **Debug executable** permitió abrir el acceso anteriormente.

La versión incluida es 0.5.0/build 6, con Itinerarios y Alertas en Gestión. Antes del traslado pasó 23 pruebas unitarias y 8 de interfaz en macOS. Esto no sustituye comprobar la instalación en tu Mac. Slack/APNs requieren la activación descrita en `docs/ITINERARIES_PUSH_SETUP.md`.

## 5. Publicar cambios futuros desde el Mac

La edición, los tests y el build se harán en esta carpeta. Codex local debe tener el plugin **Sites** disponible y acceso a la misma cuenta propietaria que publicó JAC. Comprobará el acceso leyendo el Site existente, sin crear otro ni cambiar DNS. El identificador ya está en `.openai/hosting.json`.

Las publicaciones siguen el flujo autenticado de Sites, con fuente y build coincidentes. GitHub y Actions no forman parte de ese flujo. Si el plugin o el acceso falta en el Mac, se configura allí; no se copian tokens ni claves desde este chat. El traslado por sí mismo no despliega nada ni cambia D1, R2, el dominio o las conexiones de producción.

No borres el entorno Cloud ni el repositorio histórico hasta confirmar que Codex local abre JAC, Xcode compila y Sites reconoce el proyecto existente. Puedes usar Git solo en tu Mac para guardar versiones y respaldar la carpeta con Time Machine; no hace falta un remoto GitHub.

## Sabrás que el traslado está terminado cuando

- Codex trabaja en `Documentos/Proyectos/JAC` y el modo indica This computer/Local.
- La web responde en localhost con D1 local y claves independientes.
- Xcode compila y actualiza JAC en tu iPhone.
- Codex local reconoce el mismo Site con la cuenta propietaria para futuras publicaciones.

Hasta comprobar estos puntos en tu Mac, el paquete está preparado para el traslado, pero el entorno local aún no está verificado.


## App nativa para Mac

Abre `macos/JACMac.xcodeproj`, esquema **JACMac**, destino **My Mac**, y pulsa **Run**. También puedes abrir `outputs/JAC Music.app` después de ejecutar `bash scripts/build-mac-local.sh`. La compilación local usa firma ad hoc y no requiere el equipo Apple del iPhone. Se reutilizan las cuentas y el servicio existentes; iniciar sesión es una acción de Camilo. Ver `macos/README.md` y `docs/MAC_NATIVE.md`. El proyecto iPhone y sus ajustes personales permanecen en su lugar.
