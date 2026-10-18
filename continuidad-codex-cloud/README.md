# Continuar JAC desde un único chat Codex Cloud

Petición vigente de Camilo,18 de octubre2026: toda la edición de web/servidor/iPhone/iPad/Mac desde un nuevo chat Cloud con este GitHub privado. Las compilaciones de Apple se realizan después con pull y Xcode en su Mac. No habilitar acceso remoto, SSH o VPN al Mac. No se requieren dos chats.

## Contexto funcional que debe leer el nuevo chat

**[GUIA-FUNCIONAL-JAC.md](GUIA-FUNCIONAL-JAC.md)** explica el vocabulario de Camilo y el funcionamiento ya implementado: Fotografía R2, CRM y sus bolsas de abonos, Agenda, nómina/comisión/gastos, alertas/itinerarios/pases y contratos/RUT. Incluye relaciones entre módulos, permisos recientes, diferencias por plataforma, decisiones aplazadas y referencias al código/pruebas.

AGENTS.md y el mensaje de inicio exigen esta lectura. El nuevo chat debe conservar y actualizar la guía cuando cambie el producto; no necesita que Camilo vuelva a explicar decisiones resueltas. La conversación y las credenciales no se transfieren automáticamente: el contexto durable es la documentación versionada del repositorio.

## Abrir el entorno

1. En un nuevo chat selecciona **Work in / Trabajar en → Cloud** y el repositorio privado `camiloidarraga98/nomina-jac`, rama `main`.
2. Si no hay un entorno publicado, crea uno para ese repositorio y configura Node24. Autoriza GitHub con tu propia cuenta si lo solicita.
3. Copia el contenido de [PROMPT-PARA-EL-NUEVO-CHAT.txt](PROMPT-PARA-EL-NUEVO-CHAT.txt). Pide preparar las dependencias, las pruebas aisladas y el build siguiendo ese mensaje. Revisa el resultado antes de publicar el entorno.
4. Continúa en ese mismo chat para los cambios posteriores. El acceso GitHub y los accesos de publicación Cloudflare se comprueban por separado; no se heredan las sesiones locales del Mac.

Esta carpeta contiene instrucciones; el código completo ya está en la raíz del repositorio. Comprobado antes de prepararla:73 archivos nativos versionados (51 iPhone/iPad,22 Mac), sin fuentes nativas pendientes de agregar. La fuente inicial de esta entrega incluye la corrección de estilos `32d3a9de8466adf836fc8c4622d1ec5832a169e8`; usa main actual para recibir también estas instrucciones.

## Código, servicios y comprobaciones

- [Estado y recursos Cloudflare](../docs/CLOUDFLARE_MIGRATION.md).
- [Guía funcional y vocabulario](GUIA-FUNCIONAL-JAC.md), [reglas](../AGENTS.md), [historial de decisiones](../docs/PROJECT_CONTEXT.md).
- [iPhone/iPad](../ios/README.md), [Mac](../macos/README.md).
- [Permisos](../docs/SECTION_ACCESS.md), [pases privados](../docs/BOARDING_PASSES.md), [notificaciones](../docs/ITINERARIES_PUSH_SETUP.md).
- [Fotografía R2](../docs/PHOTOGRAPHY_R2_MIGRATION.md), [contratos](../docs/CONTRACTS.md).

Las guías conservan historia del proyecto: prevalecen este flujo y las decisiones posteriores del usuario. Producción vive en el Worker jac-nomina de Cloudflare; no volver a Sites ni inicializar recursos o datos.

## Actualizar Xcode en el mismo Mac

Dentro de `/Users/camiloidarraga/Documents/Proyectos/JAC`:

```sh
git status --short
git fetch origin
git diff --name-only HEAD..origin/main
git pull --ff-only
```

Abre el mismo `ios/JACNomina.xcodeproj` (esquema JACNomina) para iPhone/iPad o `macos/JACMac.xcodeproj` (esquema JACMac) para Mac y usa Run. Conserva la firma y bundles; push nativo sigue suspendido.

Existen tres cambios personales de Xcode en este Mac, preservados fuera de los commits: proyecto iOS, esquema compartido e Info.plist. Si un pull coincide con esos cambios, Git puede detenerlo. No uses reset --hard, clean, checkout forzado ni sobrescribas la firma. Conserva/revisa esos ajustes y concílialos con los cambios nuevos. No se ha hecho un pull ni una instalación física como parte de esta preparación.

La edición Swift en Cloud no equivale a compilar con Xcode: el chat debe informar las pruebas nativas pendientes si su ejecutor no dispone de macOS/Xcode. La publicación web sigue siendo en Cloudflare, no en GitHub Pages ni Actions.

## Accesos todavía por comprobar en el nuevo entorno

- Conexión Cloud → repositorio privado y capacidad de guardar/subir cambios.
- Node24 y npm ci en el sistema operativo de Cloud; no se ha afirmado una instalación Linux desde este Mac.
- Acceso de publicación Cloudflare si se quiere desplegar directamente desde Cloud. Configurarlo mediante la interfaz segura del entorno, sin copiar la sesión Wrangler del Mac o las claves de la aplicación.
- No trasladar bases, sesiones, Llavero, certificados o claves reales. Las pruebas usan claves nuevas y D1 local/fakes.

No se ha creado ni activado un entorno Cloud ni trasladado esta conversación automáticamente; esta carpeta deja preparado el relevo en GitHub.

Guía oficial consultada: [Entornos Cloud de Codex](https://learn.chatgpt.com/docs/environments/cloud-environments).
