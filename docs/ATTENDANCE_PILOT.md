# Asistencia de JAC · piloto local

La cuenta de prueba `admin` abre el kiosco integrado en **JACNomina**. Tiene acceso al registro de asistencia. Las operaciones de gestión requieren además una clave de operador. Los empleados y las marcaciones del piloto son ficticios.

## Probar en iPad o iPhone desde Xcode

1. Actualiza `main`, abre `ios/JACNomina.xcodeproj`, selecciona **JACNomina** y el iPad o iPhone de prueba. Pulsa **Run**.
2. Ingresa con usuario `admin` y contraseña `admin`. El indicador **Prueba en este dispositivo** identifica el piloto integrado. Encontrarás dos empleados ficticios para probar **Entrada** y **Salida** de inmediato.
3. En **Gestión supervisada** escribe `gestion-demo`. La autorización de operador dura cinco minutos. En **Empleados de prueba** puedes crear fichas. En **Marcaciones** puedes revisar y corregir un registro con motivo e historial.

El primer arranque y el registro funcionan directamente en la app de desarrollo, incluso en modo avión. El iPad conserva las marcaciones en un archivo protegido y excluido de las copias de seguridad. Cerrar sesión bloquea la gestión y conserva el historial para el siguiente acceso autorizado en ese dispositivo. Cada dispositivo de prueba tiene su propio historial. La comprobación presencial se registra como pendiente hasta la revisión del operador. La prueba local utiliza supervisión manual. La cuenta y la clave de demostración están limitadas a la compilación de desarrollo y a sus datos de prueba.

Al actualizar desde el piloto que dependía del Mac puede volver a aparecer el formulario de acceso. El nuevo historial empieza con las fichas de demostración. Los registros del servidor anterior pertenecen a aquel ensayo.

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

El servidor escucha en el loopback del Mac u ordenador de prueba. Usa Miniflare, D1 efímera y sesiones propias del motor JAC con su hash scrypt. La contraseña débil pertenece únicamente al kiosco ficticio. El inicio comprueba los dos nombres antes de insertar las cuentas. Detener el servidor descarta su base y volver a iniciarlo crea identidades nuevas. Para probar el reinicio de la aplicación, deja el servidor encendido y cierra el navegador o la app. La migración aditiva del piloto vive en `db/attendance-pilot/001.sql` y la aplica solo este ejecutor.

## Probar la sincronización en una compilación de desarrollo

Para conectar un dispositivo físico al piloto privado, configura `JAC_ATTENDANCE_ORIGIN` en el esquema con una dirección HTTPS que termine en `.local` o `.test` y use un certificado de confianza. En el simulador también se admite explícitamente `http://localhost:8789`. En ese modo rigen las cuentas, la clave de supervisión y los registros del servidor privado. Al quitar la variable del esquema, **Run** vuelve a la prueba del dispositivo. La distribución de producción utiliza la autenticación habitual de JAC.

## Qué se conserva

| Aspecto | Web | iPhone y iPad |
| --- | --- | --- |
| Interfaz y cola | Tras la primera carga, el Service Worker conserva la interfaz pública. IndexedDB guarda por cuenta el padrón y los envíos con cifrado AES-GCM. | WebKit muestra los recursos incluidos en el mismo target universal. La cola usa escrituras atómicas, protección completa de archivos y exclusión de copias de seguridad. |
| Identidad del kiosco | Cookie de sesión HttpOnly y una credencial acotada que permite abrir la copia cifrada de esa cuenta hasta el vencimiento o cierre de la sesión. La salida invalida el acceso a esa partición. | La sesión reside en Llavero. Un marcador asociado a esa sesión selecciona el kiosco antes de leer cachés de nómina o Agenda. |
| Gestión y supervisión | Requieren conexión y reautenticación de un operador. | En la prueba local, la app comprueba la autorización de operador en el dispositivo. El modo de sincronización usa las API del servidor privado. |
| Enrolamiento de prueba | Marcador sintético local, sin cámara. Expira a las 24 horas. | En la prueba local se utiliza supervisión presencial. En el modo de servidor privado se pueden probar marcadores sintéticos protegidos en el dispositivo. |

Al abrir el kiosco o consultar una muestra se retiran los marcadores caducados. El operador también puede borrarlos en el momento. Al terminar el ensayo se pueden retirar los datos del sitio en el perfil de navegador de pruebas o eliminar la instalación de prueba del dispositivo. Conserva las marcaciones pendientes hasta comprobar su recepción.

La hora indicada por el dispositivo y la hora de recepción del servidor se guardan por separado. Un segundo intento con el mismo UUID y contenido devuelve el recibo existente. Un cambio de contenido con ese UUID queda en conflicto. Dos marcaciones del mismo tipo y empleado con horas próximas se señalan para revisión. Una diferencia superior a cinco minutos puede deberse al reloj o al envío sin conexión. Estas señales son informativas. El piloto guarda sus datos en tablas propias y carece de salidas a cálculos y cierres de nómina.

## Biometría

El prototipo anterior y una licencia de SDK facial utilizable no estaban disponibles en este espacio de trabajo. El adaptador local de `public/attendance/biometrics.js` expone la disponibilidad, el enrolamiento, el borrado y la evaluación. Su implementación actual trabaja con identificadores sintéticos. Los resultados de demostración y de fallo dejan la marcación pendiente. El servidor solo registra una aprobación después de revalidar una autorización de operador, el motivo y la revisión.

Para una evaluación futura en iPad, el candidato es **Innovatrics DOT iOS Face**. El fabricante documenta comparación facial y prueba de vida pasiva en el propio dispositivo. Exige un archivo de licencia y describe reportes de uso asociados a ciertas licencias. La autorización de JAC, sus condiciones para control de asistencia, el funcionamiento offline en el modelo de iPad y el tráfico efectivo del SDK requieren verificación previa. [Documentación de iOS](https://developers.innovatrics.com/docs/enterprise-identity/idv-toolkit/technical/ios-development/) · [Licenciamiento y reportes de uso](https://developers.innovatrics.com/docs/enterprise-identity/idv-toolkit/technical/transactions/)

El flujo propuesto para una prueba expresamente autorizada es enrolamiento supervisado y consentido, plantilla por dispositivo, captura en vivo iniciada con una acción del empleado, prueba de vida y comparación 1:1 con su referencia. Las fotos cargadas desde una galería sirven como posible referencia supervisada. La presencia al ponchar necesita una captura en ese momento. La propuesta de custodia es cifrado de la plantilla con clave exclusiva del dispositivo en Llavero, protección completa del archivo, exclusión de copias y borrado por retiro de consentimiento, baja o fin del piloto. La pérdida del iPad requiere un nuevo enrolamiento en el sustituto. La web conserva la alternativa supervisada. Quedan pendientes la revisión de privacidad, la licencia, la prueba con el hardware y el diseño de una constancia de dispositivo validable por el servidor antes de habilitar aprobación biométrica.

## Comprobaciones reproducibles

```sh
mkdir -p work
npm run lint
npx tsc --noEmit
npm run build
node --test tests/attendance-launcher.test.mjs tests/attendance-pilot.test.mjs tests/payroll.test.mjs tests/payroll-auth.test.mjs tests/payroll-mail.test.mjs tests/payroll-mobile.test.mjs tests/payroll-mobile-oauth.test.mjs
```

Con Playwright y Chromium disponibles en el equipo, `node scripts/attendance-browser.mjs` comprueba el acceso desde el formulario de JAC, kiosco, gestión, creación y retiro de empleados, enrolamiento sintético, aprobación, cierre de sesión, recarga sin red, respuesta perdida y reintento con el mismo UUID. Acepta `JAC_PLAYWRIGHT_MODULE` y `CHROMIUM_PATH` para usar herramientas ya instaladas. Las capturas se guardan en `.sites-runtime/asistencia` o en la carpeta indicada mediante `JAC_ATTENDANCE_CAPTURES`. El flujo de GitHub Actions para Asistencia compila JACNomina y prueba el acceso al kiosco y a Gestión en un simulador de iPad sin iniciar el servicio del Mac. La instalación física requiere la firma de desarrollo del equipo.
