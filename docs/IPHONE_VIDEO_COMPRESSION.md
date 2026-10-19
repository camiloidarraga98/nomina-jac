# Compresión de videos y sonido en iOS

Camilo mantiene la compresión obligatoria de todos los videos nuevos, incluidos HDR. Tras probar una reducción del95%, pidió suavizarla: buscar aproximadamente20–40% de ahorro y priorizar la calidad. Confirmó que el audio sí estaba en el archivo; el botón de silencio del iPhone impedía escucharlo. Pidió reproducción multimedia audible también en ese modo.

## Preparación vigente

Fotos/Archivos del compositor de iPhone y el importador alternativo de iPad pasan por AVFoundation antes de reservar la subida remota. Se usa HighestQuality, MP4 H.264, audio AAC cuando existe y composición SDR Rec.709. Se conservan resolución visible (redondeo máximo de dos píxeles para dimensiones pares), orientación y cadencia nominal. Se retiraron MediumQuality y los límites de1280píxeles/30fps que reducían drásticamente el detalle. HDR se convierte a SDR; la transparencia se aplana sobre negro.

El presupuesto de salida permite hasta85% del peso original antes del mínimo de calidad: deja margen al bitrate variable del exportador para buscar un ahorro próximo al extremo suave de20–40%. El techo anterior de70% agotaba bits en los últimos fotogramas del fixture detallado (31.8dB frente al mínimo34dB de la comprobación). Se amplía cuando es necesario para conservar calidad, considerando resolución, fps, bitrate original, el costo de convertir HEVC a H.264 y el audio/contenedor. No se fuerza el ahorro reduciendo resolución/fps. El codificador puede producir menos bytes que su presupuesto: no se garantiza20–40% para cualquier escena, codec o duración ni se añaden bytes de relleno. Un archivo muy pequeño o ya eficiente puede ahorrar menos o crecer. La conversión sigue siendo obligatoria: se envía la copia procesada, nunca un fallback al original. Si falla o no conserva pistas/dimensiones/cadencia/duración válidas, se rechaza ese video.

Se muestran tamaños anterior/nuevo y ahorro real, con reproducción antes de subir. Las fotos mantienen su ajuste independiente y el original de Fotos/Archivos queda intacto. Mantener JAC abierta durante la preparación; la cola recuperable conserva después su comportamiento en segundo plano. No hay servicios externos, dependencias, un límite nuevo por duración ni recodificación de cargas remotas iniciadas.

## Sonido

La revisión del compositor y el reproductor nativo iOS de streaming/descargas activan AVAudioSession `.playback` y `.moviePlayback`. Reproducen sonido con el botón de silencio activo; el volumen multimedia y la salida elegida siguen funcionando normalmente. Al cerrar se pausa y se desactiva la sesión con `notifyOthersOnDeactivation`.

## Comprobación

Se añaden un video ficticio1600×900/60fps con movimiento/detalle, medición de tamaño y comparación de tres fotogramas; tonos estéreo440/880Hz decodificados para comprobar canales/nivel/duración; y categoría de audio. Se conservan HDR, fotos intactas, video pequeño, archivo inválido y cancelación. La ronda final se agrupa con los cambios adicionales de Fotografía: ver PHOTOGRAPHY_MEDIA_DELIVERY.md. Fixtures locales, sin fototecas ni subidas reales. La calidad visual con material real y el interruptor físico requieren el iPhone de Camilo.

Mismos proyectos Xcode y Team AYHVYN8BJF. Pull de main y Run; bundles, firma automática y pushNO conservados. La nueva capacidad Associated Domains corresponde exclusivamente a los enlaces compartidos descritos en PHOTOGRAPHY_SHARES.md.
