# Asistencia de JAC

## Entrar al kiosco de JACNomina

En iPhone y iPad, escribe `admin` en **Usuario o correo** y `admin` en **Contraseña**. Se abre **Marca tu asistencia**. Esta cuenta permite elegir entrada o salida y escanear el rostro. **Mantener la sesión iniciada** vuelve a abrir el kiosco al reiniciar la app. **Salir** devuelve al inicio de sesión.

En un dispositivo nuevo puedes ver la pantalla con el indicador **Por habilitar**. Para activar las marcaciones, entra con tu cuenta administradora habitual a **Gestión → Asistencia → Kioscos** y pulsa **Habilitar este dispositivo**. En **Personal**, inscribe a los empleados con la cámara del iPad. La gestión del personal y el historial compartido requieren tu cuenta personal.

## Historial compartido

En la web abre **Configuración general → Asistencia**. En JACNomina abre **Gestión → Asistencia** con tu cuenta administradora habitual. Ambos consultan la misma base D1. El historial compartido empieza con las nuevas marcaciones. Las marcaciones anteriores del piloto siguen en su dispositivo.

1. En **Personal** crea una ficha por persona con código interno y nombre.
2. En cada iPad físico inicia sesión como administrador. En **Kioscos** nombra y habilita el dispositivo. En **Personal** confirma la identidad y el consentimiento del participante antes de pulsar **Inscribir rostro** junto a la ficha correcta. Repite la inscripción en el segundo iPad. Los identificadores de ficha e inscripción se comparten. La referencia facial cifrada permanece en el iPad y caduca a los 30 días.
3. Cierra la sesión administradora, toca **Marcar asistencia** y escribe la contraseña del kiosco. La persona elige **Entrada** o **Salida** y pulsa **Escanear**. Mira a la cámara un instante. JAC combina tres lecturas frontales compatibles, identifica al empleado y toma una foto del mismo escaneo para la marcación. Al confirmar, muestra y pronuncia el saludo de entrada o de salida con el nombre de la ficha. **Verificar con mi código de empleado** permite comprobar además que la coincidencia corresponde a la ficha declarada. La comparación dudosa, múltiple o con otro perfil bloquea la marcación. Un administrador puede comprobar una inscripción con **Verificar perfil**.
4. **Marcación recibida** indica que el servidor confirmó el registro. Con una lista sincronizada durante las últimas 12 horas, el iPad puede marcar sin red. Guarda una copia cifrada temporal y reintenta mientras el kiosco está abierto. Un UUID identifica cada operación, incluso después de reiniciar. Un registro revocado o en conflicto requiere intervención.
5. **Marcaciones** muestra la hora del movimiento en Colombia, la hora de recepción y el dispositivo o el supervisor. Filtra por persona y por fecha para consultar el historial. En las nuevas marcaciones hechas con la cámara, **Ver foto** abre el retrato asociado a la hora y al movimiento originales. Las marcaciones antiguas y las supervisadas manualmente conservan sus datos de origen. Para una excepción el administrador verifica la identidad en persona y registra el motivo. El panel se actualiza periódicamente. En **Revisar** puedes corregir la hora o el movimiento con motivo y consultar el original y sus revisiones. Retirar el rostro o desactivar una persona invalida sus inscripciones en ambos iPads. Las marcaciones existentes siguen en el historial.

El servidor acepta marcaciones automáticas únicamente de un kiosco habilitado y con una inscripción vigente para esa misma persona y dispositivo. La app firma los datos de la marcación y la huella SHA-256 del JPEG con la clave de esa inscripción. El servidor guarda la foto y el movimiento juntos. Solo los administradores pueden solicitar la foto desde el historial. La plantilla facial permanece cifrada en el iPad. Sin conexión, el registro y la foto esperan juntos en la cola cifrada del dispositivo hasta que el servidor confirma la recepción. Una foto presentada a la cámara podría engañar la comparación frontal. Antes del uso con personal real se requiere una prueba física con consentimiento y la revisión de privacidad aplicable. La supervisión presencial queda disponible como alternativa. La asistencia no produce cambios en nómina.

## Piloto local de desarrollo

La cuenta de desarrollo `admin@attendance.invalid` abre el piloto local en la compilación Debug de **JACNomina**. Tiene acceso al registro de asistencia. Las operaciones de gestión requieren además una clave de operador. Los empleados y las marcaciones del piloto son ficticios.

## Probar en iPad o iPhone desde Xcode

1. Actualiza `main`, abre `ios/JACNomina.xcodeproj`, selecciona **JACNomina** y el iPad o iPhone de prueba. Pulsa **Run**.
2. Ingresa con usuario `admin@attendance.invalid` y contraseña `admin`. El indicador **Prueba en este dispositivo** identifica el piloto integrado. Encontrarás dos empleados ficticios para probar **Entrada** y **Salida** de inmediato.
3. En **Gestión supervisada** escribe `admin`. La autorización de operador dura cinco minutos. En **Empleados de prueba** puedes crear fichas. En **Marcaciones** puedes revisar y corregir un registro con motivo e historial.

El primer arranque y el registro funcionan directamente en la app de desarrollo, incluso en modo avión. El iPad conserva las marcaciones en un archivo protegido y excluido de las copias de seguridad. Cerrar sesión bloquea la gestión y conserva el historial para el siguiente acceso autorizado en ese dispositivo. Cada dispositivo de prueba tiene su propio historial. Una marcación manual queda pendiente de revisión. En un dispositivo con cámara frontal también se puede elegir la comparación visual descrita más abajo. La cuenta y la clave de demostración están limitadas a la compilación de desarrollo y a sus datos de prueba.

Al actualizar desde el piloto que dependía del Mac puede volver a aparecer el formulario de acceso. El nuevo historial empieza con las fichas de demostración. Los registros del servidor anterior pertenecen a aquel ensayo.

## Ensayar la comparación en el simulador de Xcode

1. En **JACNomina**, entra al piloto como `admin@attendance.invalid` con contraseña `admin`. Abre **Gestión supervisada** con `admin` y toca **Empleados de prueba**.
2. En una ficha toca **Registrar rostro de prueba** y escoge **Rostro A** como referencia. Pulsa **Volver al kiosco**. Quedará seleccionado ese empleado.
3. Elige **Entrada**, **Rostro A** y **Confirmar marcación**. Verás **Coincidencia de prueba**. Para probar el otro resultado, elige **Salida**, vuelve a seleccionar al mismo empleado y confirma con **Rostro B**. Verás **Rostros de prueba distintos**.
4. Ambas marcaciones aparecen pendientes en **Gestión supervisada → Marcaciones**. Para hacer una marcación manual, elige **Solicitar supervisión presencial** en el selector de método.

El simulador usa dos retratos ficticios incluidos en la app. El comparador de JAC calcula el parecido entre la referencia del empleado y otra imagen de prueba con distinta iluminación. Este ensayo funciona sin cámara ni servidor. La lectura frontal con cámara se prueba en un dispositivo físico. Puedes borrar la referencia ficticia desde la ficha del empleado.

## Probar la web con el servidor de desarrollo

La web conserva el piloto que permite ensayar el intercambio con un servidor, la sincronización entre clientes y los marcadores sintéticos. Para usarlo, abre `scripts/asistencia-mac.command` en el Mac o ejecuta este comando desde la raíz del repositorio con Node 24 y las dependencias de JAC instaladas.

```sh
npm run asistencia
```

1. Abre `http://127.0.0.1:8789/acceso`. Ingresa como `admin` con la contraseña temporal `admin`.
2. Pulsa **Gestión supervisada** dentro del kiosco. Si abriste el script del Mac, usa la clave de `work/local/asistencia/supervision.txt`. Si ejecutaste `npm run asistencia`, usa la que muestra Terminal. Esta credencial autoriza la gestión durante cinco minutos y únicamente dentro de la sesión actual de `admin`.
3. En **Empleados de prueba** crea una ficha o genera un lote. **Enrolar muestra sintética** guarda un marcador de demostración en este dispositivo. **Borrar muestra** lo retira. Al retirar un empleado, Gestión elimina la ficha sin historial o la desactiva y conserva sus marcaciones.
4. Pulsa **Volver al kiosco**. Elige Entrada o Salida, selecciona al empleado, elige el método y confirma. El kiosco muestra cuándo la marcación está guardada localmente y cuándo el servidor confirma su recepción.
5. En Gestión abre **Marcaciones → Supervisar** y registra el motivo de tu confirmación presencial. Para una corrección indica el movimiento, la hora y el motivo. El original y cada revisión están en **Original e historial**. Corregir reabre la supervisión.
6. Para probar el modo offline, abre el kiosco una vez con conexión y empleados cargados. Desconecta la red de la pestaña, registra una salida y vuelve a abrir la misma dirección en ese perfil. Al recuperar la conexión, el mismo UUID se entrega al servidor. **Sincronizar ahora** permite adelantar el intento.

El servidor escucha en el loopback del Mac u ordenador de prueba. Usa Miniflare, D1 efímera y sesiones propias del motor JAC con su hash scrypt. Este servidor de pruebas mantiene su propia cuenta ficticia. El inicio comprueba los dos nombres antes de insertar las cuentas. Detener el servidor descarta su base y volver a iniciarlo crea identidades nuevas. Para probar el reinicio de la aplicación, deja el servidor encendido y cierra el navegador o la app. La migración aditiva del piloto vive en `db/attendance-pilot/001.sql` y la aplica solo este ejecutor.

## Probar la sincronización en una compilación de desarrollo

Para conectar un dispositivo físico al piloto privado, configura `JAC_ATTENDANCE_ORIGIN` en el esquema con una dirección HTTPS que termine en `.local` o `.test` y use un certificado de confianza. En el simulador también se admite explícitamente `http://localhost:8789`. En ese modo rigen las cuentas, la clave de supervisión y los registros del servidor privado. Al quitar la variable del esquema, **Run** vuelve a la prueba del dispositivo. La distribución de producción utiliza la autenticación habitual de JAC.

## Qué se conserva

| Aspecto | Web | iPhone y iPad |
| --- | --- | --- |
| Interfaz y cola | Tras la primera carga, el Service Worker conserva la interfaz pública. IndexedDB guarda por cuenta el padrón y los envíos con cifrado AES-GCM. | WebKit muestra los recursos incluidos en el mismo target universal. La cola usa escrituras atómicas, protección completa de archivos y exclusión de copias de seguridad. |
| Identidad del kiosco | Cookie de sesión HttpOnly y una credencial acotada que permite abrir la copia cifrada de esa cuenta hasta el vencimiento o cierre de la sesión. La salida invalida el acceso a esa partición. | La sesión reside en Llavero. Un marcador asociado a esa sesión selecciona el kiosco antes de leer cachés de nómina o Agenda. |
| Gestión y supervisión | Requieren conexión y reautenticación de un operador. | En la prueba local, la app comprueba la autorización de operador en el dispositivo. El modo de sincronización usa las API del servidor privado. |
| Enrolamiento de prueba | Marcador sintético local, sin cámara. Expira a las 24 horas. | En el piloto del dispositivo se puede registrar una referencia facial local con consentimiento o usar supervisión presencial. El modo de servidor privado admite marcadores sintéticos. |

Al abrir el kiosco o consultar una muestra se retiran los marcadores caducados. El operador también puede borrarlos en el momento. Al terminar el ensayo se pueden retirar los datos del sitio en el perfil de navegador de pruebas o eliminar la instalación de prueba del dispositivo. Conserva las marcaciones pendientes hasta comprobar su recepción.

La hora indicada por el dispositivo y la hora de recepción del servidor se guardan por separado. Un segundo intento con el mismo UUID y contenido devuelve el recibo existente. Un cambio de contenido con ese UUID queda en conflicto. Dos marcaciones del mismo tipo y empleado con horas próximas se señalan para revisión. Una diferencia superior a cinco minutos puede deberse al reloj o al envío sin conexión. Estas señales son informativas. El piloto guarda sus datos en tablas propias y carece de salidas a cálculos y cierres de nómina.

## Comparación facial en el piloto del iPad

1. En un iPad físico, abre **Gestión supervisada → Empleados de prueba**. Junto a la ficha del voluntario, toca **Registrar rostro**. Con su consentimiento, pulsa **Autorizar y abrir cámara**. Mira a la cámara un instante. La app usa la cámara frontal al iniciar esa acción.
2. En el kiosco, selecciona **Entrada** o **Salida** y el empleado. Si su referencia está disponible, el método **Comparar mi rostro** queda seleccionado. Toca **Confirmar marcación** y sigue las indicaciones de la cámara.
3. Un parecido suficiente deja la marcación con **Coincidencia visual**. Una comparación dudosa muestra un aviso y bloquea la marcación facial. También puedes elegir **Solicitar supervisión presencial**. Si cancelas o no se consigue capturar una muestra, puedes reintentar sin crear otra marcación.
4. **Borrar referencia facial** permite retirar el consentimiento en Gestión. Retirar al empleado también borra su referencia. Cada uno de los dos iPads conserva un historial independiente y requiere su propio registro del rostro.

La cámara requiere una sola cara y combina tres lecturas frontales consecutivas. Vision localiza los ojos para alinear las vistas. JAC compara proporciones de los rasgos, textura y distribución de luz del interior de la cara únicamente con la referencia del empleado seleccionado. Una fotografía o un video pueden engañar al sistema. Luz, postura y cambios de apariencia también pueden afectar el resultado. La semejanza y la aprobación presencial quedan diferenciadas en el historial. El piloto carece de efectos sobre nómina.

Las imágenes de cámara se procesan en memoria. La referencia se cifra con AES-GCM y una clave del Llavero exclusiva del dispositivo. Su archivo tiene protección completa y se excluye de copias de seguridad. La referencia caduca a los 30 días y se elimina al siguiente acceso al registro. Solo se expone el resultado al módulo de Asistencia. La comparación funciona sin internet y sin un SDK de pago.

La prueba facial está integrada en **JACNomina** para desarrollo. El simulador de Xcode ofrece la comparación con retratos ficticios y la supervisión presencial. La web y el modo de servidor privado ofrecen supervisión y marcadores sintéticos. Las pruebas automáticas usan patrones ficticios para verificar comparación, permisos e historial. La precisión con personas requiere una prueba física con voluntarios autorizados, consentimiento y revisión de privacidad antes de incorporar empleados reales.

## Comprobaciones reproducibles

```sh
mkdir -p work
npm run lint
npx tsc --noEmit
npm run build
node --test tests/attendance-launcher.test.mjs tests/attendance-pilot.test.mjs tests/payroll.test.mjs tests/payroll-auth.test.mjs tests/payroll-mail.test.mjs tests/payroll-mobile.test.mjs tests/payroll-mobile-oauth.test.mjs
```

Con Playwright y Chromium disponibles en el equipo, `node scripts/attendance-browser.mjs` comprueba el acceso desde el formulario de JAC, kiosco, gestión, creación y retiro de empleados, enrolamiento sintético, aprobación, cierre de sesión, recarga sin red, respuesta perdida y reintento con el mismo UUID. Acepta `JAC_PLAYWRIGHT_MODULE` y `CHROMIUM_PATH` para usar herramientas ya instaladas. Las capturas se guardan en `.sites-runtime/asistencia` o en la carpeta indicada mediante `JAC_ATTENDANCE_CAPTURES`. El flujo de GitHub Actions para Asistencia compila JACNomina y prueba el acceso al kiosco y a Gestión en un simulador de iPad sin iniciar el servicio del Mac. La instalación física requiere la firma de desarrollo del equipo.
