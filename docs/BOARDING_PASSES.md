# Pases de abordar — web e iPhone

Continuidad del Site existente appgprj_6aa0260b82a88191a47960614238350a y del proyecto ios/JACNomina.xcodeproj, esquema JACNomina, bundle co.jacmusic.nomina. App 0.9.0 (10).

## Acceso y fechas

- Itinerarios contiene una sección separada de Pases de abordar: hoy, próximos días en orden ascendente e historial plegado, anterior al día actual. El corte es medianoche America/Bogota; refresco al abrir, volver al primer plano y cada 30 segundos. El historial conserva los archivos, no los borra.
- Cada pase tiene un único destinatario. Ni siquiera Camilo hereda lectura de pases ajenos por ser administrador. Se comprueba el acceso en listados, detalles, lecturas y descargas autenticadas. R2 conserva archivos privados; las notificaciones de pases no revelan nombres, vuelos o fechas en la pantalla bloqueada.
- Slack usa la app existente JAC Itinerarios, su token y secreto cifrados. Solo se procesan eventos nuevos de los tres canales configurados; no se consulta el historial de mensajes.
- Canales: C0C7QKT2FJQ → Camilo; C0C8FAPHTCG → Jhon Alex Castaño (jhonalexcastano@gmail.com); C0C7K0QCMKQ → Alex Zuluaga (alexzuluagaazp@gmail.com). La cuenta se asigna expresamente por ID y se valida contra el correo autorizado en el servidor. El nombre del archivo nunca decide el destinatario.
- Formato de fecha: `Camilo 10 de octubre 2026.pdf`, también `10 de octubre de 2026`. Sin año se toma la ocurrencia más cercana al día de recepción, entre el año anterior, actual y siguiente. Conviene incluir el año. Fechas imposibles o múltiples no se importan. El error permite corregir y subir de nuevo; no se adivina una fecha.
- PDF/JPG/PNG hasta 10 MB. Slack valida canal y formato real, descarga solo desde files.slack.com, sin redirigir credenciales. Una asignación cambiada o cuenta revocada durante la descarga impide publicar. El ID de archivo conserva idempotencia; un reintento no redirige pases anteriores a otra persona.

## Publicación manual y cuentas

Configuración general → Alertas → Crear alerta → Publicar como: Pase de abordar. Seleccionar una sola persona, subir hasta 5 archivos que sumen 10 MB y revisar la fecha detectada; las fotos sin fecha admiten elegirla manualmente. Publicar días distintos por separado. La publicación va a Pases de abordar del destinatario, no a los itinerarios compartidos.

Servicios conectados permite guardar las tres asignaciones con control de revisión. Invitar primero el bot existente a los tres canales; no crear otra app de Slack ni copiar sus claves al proyecto.

Jhon Alex: consulta de nómina, sin edición ni exportación. Alex: Solo itinerarios, sin Nómina ni Agenda; conserva Mi cuenta y configuración de notificaciones. La restricción se aplica en páginas y API, incluso desde clientes antiguos. Los cambios de cuenta revocan sesiones. Los usuarios establecen su propia contraseña con un enlace de un solo uso, disponible en Usuarios; no se envían correos automáticamente.

## Migraciones y pruebas

0013_boarding_passes añade fecha de viaje, asignaciones por canal e identidad/revisión capturada en la cola Slack. 0014_itineraries_only_access añade la restricción de cuenta, por defecto desactivada para no modificar accesos existentes. No sustituyen tablas ni datos anteriores.

Pruebas: notifications, notifications-worker, payroll-auth, payroll-navigation, payroll-mobile, payroll-mobile-oauth y regresión de nómina/correo/Agenda. D1/R2 en memoria o Workerd local, con todas las salidas simuladas. Simulador nuevo 85B67AE7-2253-4103-905F-3FFC4EA95176, iPhone 18 Pro / iOS 27. Ver logs boarding33 e ios-boarding33 en work/local. Prueba física de protección de archivos conservada y omitida explícitamente por CoreSimulator; Llavero se prueba con firma ad hoc de simulador.

No usar producción para subir pases ficticios, enviar notificaciones de prueba ni comprobar eliminaciones. No guardar sesiones, enlaces de activación, claves APNs o datos locales en versiones o ZIP.

## Verificación y publicación del 7 de octubre de 2026

Se publicó v33 en el Site existente y se confirmó `https://jhonalexcastano.com` como URL activa, con rol propietario. Fuente Sites `bf5429bfad73cc99903b0305cff6cb1daf060a51`; versión `appgprj_6aa0260b82a88191a47960614238350a~appgver_2e1957034ddc8191a16f3f99c1702295`; despliegue `appgdep_6ac6f28c5eb48191b678205ca1265bc2`, resultado succeeded y revisión de entorno 2 conservada. Se mantuvieron hosting, conexiones y datos existentes; las migraciones 0013/0014 son aditivas.

106 pruebas web/servidor pasaron, además de TypeScript y build. En el simulador nuevo pasaron las comprobaciones unitarias (37 casos, una omisión explícita reservada al iPhone físico) y seis pruebas de interfaz distintas: pases/historial/archivo privado, publicación manual de pase, cuenta limitada, itinerario manual y adjuntos, lector y protección al volver de segundo plano. Debug y Release compilaron localmente; Release no contiene los fixtures `.invalid`. Se comprobó también la carga manual en localhost con un PDF ficticio; no se enviaron archivos, correos ni avisos de prueba a producción.

Las cuentas `jhon-alex` (Solo consulta) y `alex-zuluaga` (Solo itinerarios) están creadas y pendientes de activación. No se establecieron contraseñas ni generaron/enviaron enlaces. Camilo puede generarlos individualmente desde Usuarios; cada destinatario establece su propia contraseña. El bot JAC Itinerarios quedó agregado a los tres canales indicados y las asignaciones por persona se guardaron con resultado satisfactorio. Solo se recibirán archivos nuevos; no se importó el historial.

El proyecto existente del Mac está actualizado a 0.9.0 (10), conservando el equipo y ajuste local del esquema de Camilo. Debe instalarse con Run sobre cada iPhone; la publicación web no reemplaza el binario instalado. Firma de dispositivo, APNs y protección física de archivos permanecen pendientes de comprobar con el equipo Apple Developer aprobado y un dispositivo real. El ZIP en outputs es una copia opcional, no un proyecto que deba sustituir la carpeta de trabajo.

## Hoy, mañana y apertura directa — web v35 / iPhone 0.9.1 (11)

Se añade una sección explícita de mañana. Hoy va primero si tiene pases; en caso contrario mañana ocupa el primer lugar y el destacado. Ambas secciones conservan su estado vacío; los días posteriores siguen en orden cronológico y los anteriores en historial plegado, con el mismo corte America/Bogota en web y iPhone.

Desde la primera tarjeta se abre directamente cada PDF o imagen, sin pantalla intermedia de aviso. Si una publicación contiene varios archivos, cada uno tiene su propio botón. La web usa el endpoint autenticado de adjuntos; iPhone conserva la descarga validada, documento temporal protegido, vista nativa, compartir y eliminación del temporal al cerrar. Los enlaces no son públicos. Las alertas e itinerarios compartidos conservan su detalle y acciones.

Formato nuevo: `Camilo 16 de octubre Pereira-Bogota.pdf`, opcionalmente `Camilo 16 de octubre 2026 Pereira-Bogota.pdf`. Se muestra pasajero, origen → destino y fecha. Se admiten espacios y tildes en ciudades, con un guion entre las dos. Jhon Alex y Alex Zuluaga se reconocen separadamente. El pasajero se valida contra la cuenta configurada del canal o elegida manualmente; no se cambia el destinatario a partir del nombre. Un nombre con ruta de otra persona se rechaza antes de almacenar el archivo. Los pases existentes sin ruta conservan compatibilidad. No se agregan migraciones ni cambian secretos o canales.

Verificación local de esta actualización: Node 24.21.0, TypeScript y build web correctos; 85 pruebas de nómina/auth/correo/API móvil/notificaciones/Workerd pasadas, sin salidas reales. Xcode 27 / simulador nuevo 9ECCF2E6-95B5-4C72-B02E-AEB544C3EF51: 37 casos unitarios (36 pasados y la comprobación física omitida explícitamente), apertura directa/historial, mañana sin hoy, publicación manual y privacidad/regreso comprobados. La prueba manual inicial quedó en el formulario; se completó el título con Return y se añadió una comprobación de que el PDF esté adjunto antes de guardar, conservando permisos y todas las aserciones. El recorrido final pasó (`ios-passes34-manual-final.xcresult`); resultados anteriores y diagnósticos se conservan. La recopilación `simctl diagnose` del primer fallo se detuvo tras acabar las pruebas, sin detener ni omitir casos. Release 0.9.1 (11) compiló sin firma y no incluye los fixtures DEBUG. Capturas de hoy/mañana y prioridad en outputs/pases34-*.png; solo datos ficticios locales.

Ajuste visual adicional: las secciones secundarias (Hoy, Mañana o fechas posteriores) tienen espacio interior de 20 px, fondo blanco y borde suave; en pantallas estrechas se usa 16 px. El destacado conserva su color y el mismo margen interior, evitando títulos pegados a los bordes. Ver captura local outputs/pases35-espaciado-local.png.

Publicación confirmada de esta actualización: web v35, fuente Sites `0548ffb9b85c9f5505f4be323501208dce5a05e0`, versión `appgprj_6aa0260b82a88191a47960614238350a~appgver_7012203efcf081918174f3ef8a75147c`, despliegue `appgdep_6ac70421d3148191983e87dc4e71ad32` succeeded. Dominio canónico https://jhonalexcastano.com, propietario confirmado y revisión de entorno 2 conservada. v34 se guardó sin desplegar; el ajuste de márgenes se incorporó antes de publicar v35. Sin nuevas migraciones, cambios de secretos ni pruebas reales en producción. La instalación física sigue siendo Run desde el mismo proyecto Xcode 0.9.1 (11).
