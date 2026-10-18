# Fotografía: transferencias directas y reproducción progresiva

16 de octubre de 2026. Continuidad del Site y de los mismos proyectos iPhone/Mac. No cambia hosting, DNS, carpeta raíz, conexiones, DB/BUCKET, permisos de usuarios, dependencias ni lockfile. No necesita migración: `jac_media_operations.kind` admite la nueva operación `direct` y conserva las anteriores `upload`/`folder`.

## Subida

Web, iPhone y Mac solicitan a JAC una sesión reanudable de Drive para un único ID de archivo nuevo, con nombre, MIME y tamaño fijados por el servidor. Los bloques normales de 8 MiB viajan del dispositivo a `www.googleapis.com`; no pasan por el Worker. El último bloque puede ser menor. Los clientes no reciben el token OAuth, refresh token ni secreto de Google. El enlace de subida sí es una capacidad sensible: solo se conserva en memoria del cliente; en D1 permanece cifrado. No se registra ni guarda en disco, localStorage, ZIP o informes.

Cada bloque confirmado se reconcilia desde JAC con el estado de Google. Una respuesta perdida continúa el mismo ID y desplazamiento, incluso si Google ya cerró la sesión o el movimiento final terminó sin devolver respuesta. Cuenta, revisión de sesión, permiso de subir, conexión vigente y ancestros actuales del destino se comprueban de nuevo. CAS protege las transiciones en D1. El protocolo anterior de 1 MiB permanece disponible para clientes anteriores.

Si el navegador o la red rechaza la petición directa y JAC confirma que el tramo no avanzó, el cliente usa una ruta compatible por JAC de 1 MiB, sobre **el mismo** archivo/sesión. No se inicia otra copia. Una denegación de sesión/permisos en JAC detiene la transferencia; no activa esa alternativa. No se promete una velocidad o porcentaje de mejora sin medir la conexión real.

## Publicación y revocación

Google documenta que una sesión reanudable puede durar una semana. No se asume que cerrar sesión en JAC invalide inmediatamente una URL ya entregada, ni se usa una cancelación DELETE no documentada para Drive v3 como garantía de seguridad.

El archivo se inicia sin un padre compartido: Google lo coloca en Mi unidad de `jacmusicestudios@gmail.com`. La capacidad solo puede completar ese archivo nuevo; no puede leer, listar, compartir o modificar otros archivos ni cambiar sus metadatos. JAC verifica el ID reservado, marca de operación, nombre, tipo, tamaño y los primeros hasta 64 bytes del contenido, además del acceso actual a la carpeta de destino. Solo entonces lo mueve al destino aprobado. Un archivo `direct` que no esté `ready` queda bloqueado por las API de lectura/miniaturas/metadatos y se excluye del listado, incluso si un movimiento terminó pero se perdió su respuesta.

Una sesión retirada no puede finalizar/publicar en Fotografía, aunque alguien conserve la capacidad de Google y complete los bytes aislados. Cancelar una operación en JAC la marca cancelada y retira su URL cifrada. **No se declara cancelada la capacidad de Google ni se borra automáticamente el archivo aislado:** una transferencia abandonada puede dejar un archivo privado de preparación en Mi unidad. No se añade limpieza destructiva de Drive ni se elimina contenido real como prueba.

El token de acceso OAuth se reutiliza únicamente en memoria del Worker, hasta su vencimiento menos un minuto (máximo una hora), ligado a las credenciales cifradas y versión de conexión. Cada solicitud conserva las comprobaciones de sesión/rol/configuración y ubicación actual en Drive. Un 401 de Google retira esa copia; no se reutiliza entre conexiones ni se entrega a clientes. Las instancias de Worker pueden perder esa caché en cualquier momento.

## Lectura y caché

Las descargas siguen autorizadas por JAC. No se hacen públicos los archivos ni se entrega la credencial de lectura del propietario. La web conserva su reproductor HTML con rangos privados; iPhone/Mac usan un cargador AVFoundation con esquema privado que pide rangos de hasta 1 MiB a JAC. Su memoria temporal está limitada a ocho bloques por reproducción, ligada a archivo/revisión/sesión. Una denegación detiene el reproductor, retira el elemento y vacía esa memoria. La revisión se valida antes y después de pedir cada tramo a Drive para no mezclar revisiones. Se mantienen rechazo de redirecciones, privacidad y limpieza de temporales.

Una foto abierta de hasta 24 MiB puede reutilizarse después de consultar sus metadatos y permisos actuales. La web conserva hasta 48 MiB de originales en memoria y retira sus Blob URL al salir/revocar. iPhone/Mac cifran las vistas abiertas con el caché existente (máximo 128 MiB automáticos), separado por origen/sesión y fuera de respaldos. Las carpetas descargadas explícitamente no se expulsan por ese límite. Cerrar sesión o recibir 403 retira las copias; una respuesta tardía no puede restablecerlas. Solo fallos de conectividad permiten el fallback a una copia existente. No se descargan carpetas completas automáticamente. Disponible sin conexión y Guardar en Fotos conservan sus recorridos y permisos.

## Verificación

Pruebas exclusivamente locales: Google interceptado, D1 en memoria/Workerd local, archivos ficticios y fototeca simulada. La prueba visual de localhost sustituye **solo en su paquete desechable** el origen Google por un servidor simulado local; la aplicación de producción conserva la validación estricta de `https://www.googleapis.com`. No se declara comprobado el CORS de Google ni el rendimiento de una transferencia real por haber pasado esta prueba.

Verifica las suites `media-drive`, `media-access`, `media-worker`, `media-transfer-client` y nómina/auth/correo/móvil/OAuth. Incluyen aislamiento antes de publicar, URL limitada sin credenciales JAC, firma/tamaño, destino movido, revocación, conexión rotada, respuesta perdida, rangos/revisión, reanudación y ruta compatible sin duplicados. Las pruebas nativas conservan todas las comprobaciones existentes y añaden carga directa/compatibilidad, reutilización cifrada con revalidación/403 y reproducción real de un clip ficticio mediante el cargador de rangos.

La primera ejecución UI detectó que el interceptador de pruebas rechazaba el host de la nueva sesión antes de llegar al Drive simulado. Se amplió exclusivamente el URLProtocol de fixtures para reconocer esa ruta y responder localmente; ninguna salida se envía a Google. Se conservan los fallos intermedios y se repiten las mismas aserciones, sin quitarlas ni sustituirlas.

Los resultados finales, compilaciones y publicación se registran al terminar la entrega.

### Resultados finales en este Mac

Node 24.21.0; TypeScript correcto, build web exacto correcto y 104 pruebas de servidor/Workerd/cliente web aprobadas (`work/local/media-direct-regression.log`). El lockfile local y el del Site conservaron sus estados anteriores: no cambió ninguna versión común; la copia local ya contenía las dos entradas opcionales heredadas `@emnapi/core`/`@emnapi/runtime`. No se ejecutó instalación ni actualización de dependencias.

Localhost: foto y video, 2/2 guardados; el registro comprueba dos PUT al Drive **simulado**, sin Cookie/Authorization de JAC, y ningún PUT binario a la API JAC en ese recorrido. Abrir dos veces una foto hizo una sola descarga original y una consulta de metadatos; un 403 retiró galería/preview y la copia de memoria. Clip de dos segundos, 128×96, listo en el reproductor web sin error. Captura `outputs/fotografia-transferencia-directa-local.png`, registro `work/local/media-direct-web-inspect.json`. El origen Google se sustituyó solo en el bundle de prueba local. No hubo fotos, videos ni notificaciones reales enviados como prueba.

iPhone: 87 unitarias aprobadas y una condición física omitida en simulador en `media-direct-ios-final.xcresult`; dos UI de subida/preview aprobadas allí. Carpeta offline/Fotos simuladas y privacidad se verifican en `media-direct-ios-offline-privacy.xcresult`. Simulador nuevo `9B28DBE2-69F0-48FE-BF91-1B4B3DDB97DF`. Se conserva el aviso preexistente «Invalid frame dimension» de la prueba del editor; no se declara corregido en esta entrega. Mac: 97 unitarias y recorrido de fotógrafo/reproductor aprobados en `media-direct-mac-final.xcresult`; descarga de carpeta y privacidad en `media-direct-mac-offline-privacy.xcresult`. Los informes intermedios no se borran.

Release iPhone sin firma y Mac universal arm64/x86_64: BUILD SUCCEEDED. Mismos proyectos y esquemas, identidad y firma personal intactas salvo cuatro valores de versión/build por aplicación. iPhone **0.19.0(31)**, bundle `co.jacmusic.nomina`; Mac **1.6.0(8)**, bundle `co.jacmusic.nomina.mac`. Push sigue NO. Firma estricta de Mac comprobada; misma `outputs/JAC Music.app` reemplazada y versión anterior respaldada en `work/local/media-direct-previous-app`. No se cierra la instancia del usuario ni se instala en un iPhone físico: cerrar/reabrir Mac y usar Run sobre el mismo proyecto iPhone para ejecutar los nuevos binarios.

Web **v72** publicada con Sites, estado **succeeded**. Fuente privada `3a5eb54b707e839bd98d05242221d625d80166bc`; versión `appgprj_6aa0260b82a88191a47960614238350a~appgver_c3516597fed48191a790ec5cf216ccc1`; despliegue `appgdep_6ad26c436dc88191b5520dbac870cb82`, env_set_revision 2. Artefacto SHA256 `019083f566cabee52b7f113febbd356b8ffe6d3ade3bfb2b9362a61bfd99ea89`, 87 archivos. URL de publicación devuelta: https://jhon-alex-cumpleanos.camilo107389.chatgpt.site ; dominio conservado https://jhonalexcastano.com, acceso público `/acceso` HTTP 200 tras publicar. Los seis archivos de aplicación web publicados coinciden byte a byte con la fuente local comprobada. DB/BUCKET, secretos, conexiones, audiencia y DNS no cambiaron; no hubo escrituras de datos de prueba en producción ni GitHub/Actions/Cloud.
