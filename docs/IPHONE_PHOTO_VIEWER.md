# Visor de fotos del iPhone — 0.26.0 (39)

El mismo proyecto JACNomina abre ahora las fotos del iPhone a pantalla completa, con fondo negro y desplazamiento horizontal continuo. El nombre y el contador cambian al elegir la página, aunque su archivo siga cargando. Un círculo muestra el progreso recibido; la página no conserva la imagen anterior bajo el nombre de la siguiente. Doble toque y pellizco amplían; ampliada, la foto se puede arrastrar. Se conservan flechas, reintentos y accesibilidad.

El visor anterior esperaba el archivo antes de cambiar la selección y descartaba su temporal al avanzar. Ya existía una caché cifrada; una reapertura podía esperar la comprobación y el descifrado aunque no descargara otra vez el original. Ahora el visor mantiene hasta cinco documentos temporales autorizados, prepara la siguiente foto y reutiliza los residentes al volver. La caché persistente existente conserva su límite de 128 MiB para imágenes automáticas de hasta 24 MiB; actualiza su recencia al leer, como máximo cada 30 segundos. Las carpetas descargadas expresamente continúan fuera de ese recorte. La copia reciente también puede abrirse sin conexión.

## Privacidad y rendimiento

- `MediaFullscreenPhotoModel.swift` separa selección, descarga, progreso y error por foto. Limita a dos cargas y rechaza resultados tardíos, páginas ajenas y cursores cíclicos. Revalida los residentes y cancela al cambiar sesión, permisos, carpeta o colección.
- `MediaFullscreenPhotoPager.swift` usa tres paneles UIKit reciclados, sin List, UICollectionView ni otra navegación. Decodifica en serie fuera del hilo principal: imagen seleccionada hasta 4096 px y vecinas hasta 2048 px. Retira bitmaps al salir o pasar a segundo plano.
- `MediaFullscreenPhotoView.swift` presenta la superficie completa del iPhone. iPad/Mac conservan su distribución anterior. La galería distingue abrir este visor de salir realmente del módulo para evitar cerrarlo durante su propia presentación.
- El cliente reutiliza la sesión de red y usa `downloadTask(with:)` con delegado, cancelación y continuación de una sola finalización. El progreso procede de bytes recibidos; no se genera con un reloj. La prueba detectó que `download(for:delegate:)` no entregaba avances intermedios en este recorrido; se sustituyó sin retirar la aserción. El temporal se reclama y protege dentro del callback antes de que URLSession lo elimine. Se mantienen límites de tamaño/MIME, rechazo de redirecciones y controles de sesión.
- La caché continúa cifrada y ligada a origen/sesión/revisión/colección. Un 403 no permite fallback. Un 404/410 confirmado al revalidar retira únicamente ese archivo; el descifrado también comprueba que el archivo no haya sido retirado mientras se leía.

## Verificación local

Se usaron exclusivamente `.invalid`, fotos/videos ficticios y guardado en Fotos simulado. No se abrieron ni descargaron fotos reales como prueba.

- iPhone: 112 unitarias ejecutadas, 111 aprobadas y una comprobación de protección física omitida por CoreSimulator; ocho pruebas nuevas del modelo, cinco nuevas del cliente/caché y las anteriores conservadas. Informe `work/local/photo-viewer-verified.xcresult`.
- Mac: 113 unitarias aprobadas, incluidas las nuevas del descargador y la caché. `photo-viewer-mac-all.xcresult`.
- UI: pantalla completa, cambio inmediato a una foto pendiente, progreso intermedio de 50 % desde bytes reales del fixture, swipe, zoom, regreso a copia guardada, reapertura offline/Fotos y carpetas desplegables. `photo-viewer-final.xcresult`, `photo-viewer-verified.xcresult` y `photo-viewer-ui.xcresult`. El recorrido final exige un bitmap realmente dibujado; reabrir desde caché debe terminar antes de los doce segundos que tardaría repetir la descarga ficticia.
- Las ocho pruebas finales del modelo aprobaron en `work/local/photo-viewer-scope.xcresult`, incluida la retirada de un original ya visible cuando cambia el ámbito. Release de iPhone compilado correctamente con la fuente final: `work/local/photo-viewer-release-verified.log`; versión 0.26.0 (39), bundle, cámara/Fotos, orientaciones iPad y push suspendido comprobados en el producto.
- Se reutilizan TypeScript/build y las 37 pruebas web obligatorias aprobadas en la entrega anterior: sus entradas web/servidor/dependencias no cambiaron. No hay cambios de API del servidor, migraciones ni publicación web; continúa v77.

Mismo bundle `co.jacmusic.nomina`, firma personal y push suspendido. El iPhone físico aparece desconectado: instalar con **Run en el mismo proyecto**, sin sustituir ni descargar otro proyecto.

Fuente guardada en Git local `4d5caeea2c2ef1810a989eff8a1e822c7d6398cd` y en el repositorio privado del Site existente `df4d4350e896ad600e1f6404566ef5c28d7339d2`. Se verificó el acceso propietario; la web continúa en v77, sin despliegue. Respaldo nativo opcional de 77 archivos: `outputs/JAC-iPhone-iPad-0.26.0-Mac-1.10.0-fuente-nativa.zip`, SHA256 `f3b739aa4cc129d0ee19f24e10f187209f64deeb0c0dc4f685960a458d707910`; conserva ejecutables y excluye equipo personal, claves y estado local. Capturas ficticias en `outputs/iphone-fotografia-{visor,progreso,gestos}-0.26.png`. El producto instalado de Mac no se sustituyó en esta entrega.

## Pausa al subir archivos

La revisión encontró una espera entre el envío del original, su confirmación en R2 y la generación/subida de miniatura. Incluso una foto pequeña usa multipart y ocupa uno de los dos turnos durante toda esa secuencia. Ambos turnos pueden estar confirmando sin enviar nuevos bytes. No hay una pausa artificial entre archivos; el tiempo real de cada fase aún requiere medición. Esta entrega corrige el visor y su carga; el protocolo de subida conserva su comportamiento.
