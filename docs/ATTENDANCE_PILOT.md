# Asistencia de JAC · piloto local

La cuenta de prueba `admin` entra por el acceso habitual de JAC y abre directamente Asistencia. Solo su sesión de kiosco puede abrir la pantalla, registrar entradas y salidas, solicitar la comprobación facial de prueba o acceder a la gestión. El servidor comprueba la cuenta y su rol también en peticiones directas. Para gestionar empleados, enrolar una muestra o aprobar una marcación se necesita además la credencial de supervisión dentro de esa sesión. Cada empleado de la prueba tiene una ficha ficticia con nombre y código propios.

## Abrir el piloto desde Xcode

Después de actualizar `main`, abre `ios/JACNomina.xcodeproj` y pulsa **Run** con **JACNomina** y el simulador de iPhone o iPad. El formulario habitual abre el kiosco con la cuenta de prueba `admin`. Las demás cuentas siguen su recorrido de JAC. Al salir del kiosco vuelve el mismo formulario. Si la versión anterior había dejado dos sesiones guardadas en el dispositivo, el siguiente usuario debe identificarse de nuevo.

En el simulador, Xcode inicia el servidor de pruebas del Mac. Ingresa con usuario `admin` y contraseña temporal `admin`. La app espera a que el servidor termine de preparar las cuentas. La ventana de Terminal muestra la clave de supervisión del ensayo. Déjala abierta durante la prueba. Puedes detener el servidor con Control-C. El iniciador usa Node 24 y npm de `work/local/toolchain/node/bin` o de Terminal e instala las dependencias que falten en el primer arranque.

## Probar la web

Si abriste el piloto desde Xcode, la web utiliza ese mismo servidor. También puedes iniciarlo desde la raíz del repositorio con Node 24 y las dependencias de JAC instaladas.

```sh
npm run asistencia
```

1. Abre `http://127.0.0.1:8789/acceso`. Ingresa como `admin` con la contraseña temporal `admin`.
2. Pulsa **Gestión supervisada** dentro del kiosco e ingresa la clave aleatoria que muestra Terminal. Esta credencial autoriza la gestión durante cinco minutos y únicamente dentro de la sesión actual de `admin`.
3. En **Empleados de prueba** crea una ficha o genera un lote. **Enrolar muestra sintética** guarda un marcador de demostración en este dispositivo. **Borrar muestra** lo retira. Al retirar un empleado, Gestión elimina la ficha sin historial o la desactiva y conserva sus marcaciones.
4. Pulsa **Volver al kiosco**. Elige Entrada o Salida, selecciona al empleado, elige el método y confirma. El kiosco muestra cuándo la marcación está guardada localmente y cuándo el servidor confirma su recepción.
5. En Gestión abre **Marcaciones → Supervisar** y registra el motivo de tu confirmación presencial. Para una corrección indica el movimiento, la hora y el motivo. El original y cada revisión están en **Original e historial**. Corregir reabre la supervisión.
6. Para probar el modo offline, abre el kiosco una vez con conexión y empleados cargados. Desconecta la red de la pestaña, registra una salida y vuelve a abrir la misma dirección en ese perfil. Al recuperar la conexión, el mismo UUID se entrega al servidor. **Sincronizar ahora** permite adelantar el intento.

El servidor escucha en el loopback del Mac u ordenador de prueba. Usa Miniflare, D1 efímera y sesiones propias del motor JAC con su hash scrypt. La contraseña débil pertenece únicamente al kiosco ficticio. El inicio comprueba los dos nombres antes de insertar las cuentas. Detener el servidor descarta su base y volver a iniciarlo crea identidades nuevas. Para probar el reinicio de la aplicación, deja el servidor encendido y cierra el navegador o la app. La migración aditiva del piloto vive en `db/attendance-pilot/001.sql` y la aplica solo este ejecutor.

## iPhone y iPad físicos

En la compilación de desarrollo, abre **JACNomina** en el dispositivo e ingresa `admin`. En **Servidor privado de Asistencia**, escribe la dirección HTTPS de tu servidor de pruebas accesible desde ese iPhone o iPad. Debe terminar en `.local` o `.test` y usar un certificado de confianza. El dispositivo recuerda la dirección tras el primer acceso correcto. La app también admite una dirección preconfigurada mediante `JAC_ATTENDANCE_ORIGIN`. La distribución de producción utiliza la autenticación habitual de JAC.

El servidor automático del simulador escucha en el loopback del Mac. Para probar el recorrido automatizado con ese servidor activo, habilita `JAC_TEST_ATTENDANCE=1` para el proceso de pruebas y ejecuta `LaunchTests/testLocalAttendanceKioskLoginAndRestart` con el esquema JACNomina. La verificación física requiere Xcode, firma de desarrollo e instalación en el dispositivo.

## Qué se conserva

| Aspecto | Web | iPhone y iPad |
| --- | --- | --- |
| Interfaz y cola | Tras la primera carga, el Service Worker conserva la interfaz pública. IndexedDB guarda por cuenta el padrón y los envíos con cifrado AES-GCM. | WebKit muestra los recursos incluidos en el mismo target universal. La cola usa escrituras atómicas, protección completa de archivos y exclusión de copias de seguridad. |
| Identidad del kiosco | Cookie de sesión HttpOnly y una credencial acotada que permite abrir la copia cifrada de esa cuenta hasta el vencimiento o cierre de la sesión. La salida invalida el acceso a esa partición. | La sesión reside en Llavero. Un marcador asociado a esa sesión selecciona el kiosco antes de leer cachés de nómina o Agenda. |
| Gestión y supervisión | Requieren conexión y reautenticación de un operador. | Mismas API y autorización desde la aplicación. La credencial JAC permanece en el cliente nativo. |
| Enrolamiento de prueba | Marcador sintético local, sin cámara. Expira a las 24 horas. | Mismo simulador. El archivo de la muestra queda protegido en el dispositivo. |

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
node --test tests/attendance-pilot.test.mjs tests/payroll.test.mjs tests/payroll-auth.test.mjs tests/payroll-mail.test.mjs tests/payroll-mobile.test.mjs tests/payroll-mobile-oauth.test.mjs
```

Con Playwright y Chromium disponibles en el equipo, `node scripts/attendance-browser.mjs` comprueba el acceso desde el formulario de JAC, kiosco, gestión, creación y retiro de empleados, enrolamiento sintético, aprobación, cierre de sesión, recarga sin red, respuesta perdida y reintento con el mismo UUID. Acepta `JAC_PLAYWRIGHT_MODULE` y `CHROMIUM_PATH` para usar herramientas ya instaladas. Las capturas se guardan en `.sites-runtime/asistencia` o en la carpeta indicada mediante `JAC_ATTENDANCE_CAPTURES`. La compilación del binario Apple y los ensayos en hardware quedan pendientes en este entorno Linux.
