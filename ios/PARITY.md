# Correspondencia del webapp y la app de iPhone

En 0.10.0/build 16 el push nativo sigue suspendido temporalmente mientras se aprueba la membresía Apple. Las nuevas funciones usan las API compartidas; ver `docs/TRAVEL_WORKFLOWS.md`.

Desde 0.8.0/build 9, Itinerarios y Alertas no incluyen controles de conexión/push. Gestión → Notificaciones permite desactivar o volver a permitir los avisos. El permiso nativo se solicita tras una sesión validada; rechazos y desactivación persistente se respetan.

La versión 0.7.0 (build 8) conserva las cuentas, los permisos y la base D1 del webapp. Toda liquidación procede de `lib/payroll.ts` en el servidor. SwiftUI muestra los resultados y envía comandos de edición; no implementa otro motor de nómina.

Las cinco pestañas son Quincena, Agenda, Itinerarios, Mi cuenta y Gestión. Archivo y Equipo se consultan dentro de Gestión junto con Alertas, Conceptos y reglas, Correos y Usuarios. Se conservan las funciones y comprobaciones de acceso existentes.

Agenda conserva hasta seis meses consultados en archivos cifrados con AES-GCM (límite total de 4 MB), vinculados a la sesión del Llavero y excluidos del respaldo. Muestra la descarga antes de esperar internet, incluidos detalles y próximos eventos; puede restaurarla tras cerrar la app sin señal. Actualiza al entrar, volver a primer plano, recuperar conexión y cada 30 segundos en primer plano. Indica fecha/hora, actualización y falta de señal; un mes no descargado necesita conexión. Salir, sesión vencida, denegación o cambio/desconexión de calendario retira la copia anterior. Las acciones de edición requieren validación actual del servidor; no se guardan quincenas ni ediciones sin conexión. Sin señal, una revocación remota solo puede comprobarse cuando se recupere internet.

| Función existente | Acceso nativo | Integración compartida |
| Confirmación explícita por versión | Alertas / Itinerarios → Confirmar recibido; administradores ven pendientes | Revisión esperada, sesión propia y reintentos idempotentes |
| Actualizar itinerario y destacar cambios | Detalle → Actualizar itinerario, solo administrador | Sustitución privada de adjuntos y notificaciones por revisión |
| Gastos de viaje con comprobante | Gestión → Gastos de viaje; Archivos, Fotos y Cámara | Registro privado; administrador elige persona/quincena; reintegro y aprobación atómicos |
| --- | --- | --- |
| Crear quincena por mes y mitad; búsqueda y consulta | Quincenas → +; búsqueda | Helpers originales de períodos y guardado CAS |
| Shows, fecha, ventas, participantes y honorarios manuales | Quincena → Actividad → Shows y honorarios | `updateShow`, `removeShow` y políticas originales |
| Novedades libres o por concepto, ingresos, reintegros y descuentos | Actividad → Novedades y descuentos | Movimientos originales; cantidades y tratamientos validados en servidor |
| Un recorrido por show para ambos conductores, registros anteriores y extras | Actividad → Recorridos y kilómetros | `setShowRoute`, tarifas y consolidación originales |
| Siete tipos de horas, días, vacaciones y notas | Actividad → Horas y salarios | Factores y cálculo originales, incluidos cortes mensuales |
| Liquidación por persona/grupo, ingresos, descuentos y condiciones utilizadas | Quincena → Pagos → Persona | Cálculo del corte, snapshot o condiciones históricas |
| Cerrar con instantánea y preparar envíos cuando Gmail esté conectado | Quincena → Cerrar quincena, con confirmación | Acción `close` original, validación y lotes idempotentes |
| Archivo y consulta de cierres | Gestión → Archivo → Quincena | Mismos períodos y snapshots |
| Reabrir, corregir condiciones y factores históricos, volver a cerrar | Cierre → Reabrir para corregir → Condiciones / Parámetros | `modifyClosed`, cálculo histórico y versiones anteriores conservadas |
| Eliminar totalmente una quincena | Quincena → Eliminar quincena, solo propietario | `deletePeriod`, confirmación del ID, CAS y protección frente a envíos en curso |
| Crear, editar, inactivar, eliminar y restaurar personal | Gestión → Equipo | Todas las condiciones originales; historia conservada y validación de registros abiertos |
| Conceptos y valores; empresa, NIT, divisor y siete factores | Gestión → Conceptos y reglas / Parámetros | Permiso `rules`, esquema original |
| Usuarios, permisos, estado activo, invitación y restablecimiento | Gestión → Usuarios y permisos, solo propietario | `/api/users`, revisión de usuario, enlaces privados de un uso y sesiones invalidadas |
| Acceso, activación/restablecimiento, contraseña y salir | Inicio de sesión / Mi cuenta | `/api/auth`, sesión segura en Llavero; cualquier contraseña no vacía |
| Calendario mensual, eventos del día y próximos 90 días; detalles | Agenda; Conexión solo propietario | `/api/calendar`, misma selección y autorización de eventos/lista que la web; `America/Bogota` |
| Crear/editar eventos: título, fechas/horas, todo el día, lugar, descripción | Agenda: + y Editar evento; Camilo, Luisa y Paula con sesión activa | `/api/calendar`, calendario elegido, ETag/If-Match, reintentos estables; recurrencia por ocurrencia |
| Configurar, conectar, renovar o desconectar Gmail | Gestión → Correo → Conexión, solo propietario | OAuth/PKCE original con entrega nativa protegida; credenciales cifradas en D1 |
| Consultar estados, modificar correo de personal y enviar desprendibles conjuntos/individuales | Correo → Quincena / Correos y envíos de este corte | `/api/payroll/email`, permisos `staff`/`send`, mismos estados e idempotencia |
| PDF de resumen y desprendibles, ZIP y Excel de siete hojas | Quincena cerrada → Documentos | `/api/payroll/export`, permiso `export`; mismos archivos del servidor |
| Buscar e imprimir desprendible individual; compartir documentos | Documentos → Persona / vista previa → Imprimir o compartir | PDF original, QuickLook, AirPrint y hoja de compartir de iOS |

| PDF de itinerarios nuevos de Slack | Itinerarios → Abrir PDF → Compartir | `/api/notices` y `/api/notices/pdf`, R2 privado y sesión propia; conexión solo Camilo en la web |
| Alertas y destinatarios | Gestión → Alertas → +, solo Camilo | Mismos registros/destinatarios que la web, UUID estable, autorización en servidor |
| Notificaciones push y apertura privada | Itinerarios/Alertas → Activar en este iPhone | APNs con clave configurada por Camilo; dispositivo ligado a cuenta/revisión/sesión, baja al salir; web usa Web Push |

## Guardado y concurrencia

`GET /api/mobile/payroll?workspace=1` entrega una revisión consistente. `?period=ID` entrega el detalle y los datos para los formularios. `POST` admite `edit`, `remove` y `previewEdit` y delega las acciones originales. Cada formulario conserva la revisión que vio al abrirse; el servidor aplica los helpers existentes, esquema, permisos y políticas antes del guardado original. No se envían períodos ni snapshots históricos reconstruidos por Swift.

La previsualización calcula en el servidor sin guardar ni preparar correo. Un error de edición o conflicto conserva la solicitud pendiente en memoria. Se puede reintentar exactamente esa solicitud, compartir una copia JSON protegida o descartarla y actualizar; nunca se guarda silenciosamente sobre otra revisión. Las listas de actividades se actualizan al guardar incluso cuando el resumen queda detrás de la pantalla actual.

Los permisos se verifican en servidor y en la interfaz: `payroll`, `staff`, `rules`, `close`, `send`, `export` y `modifyClosed`. Los cortes reabiertos continúan restringidos. Las acciones exclusivas del propietario permanecen exclusivas.

## Gmail, documentos y dispositivo

La ventana de autorización de Apple se utiliza para Gmail y Agenda. Gmail usa un ticket de dos minutos y de un uso que entrega una cookie exclusiva; no entrega una sesión de nómina al navegador. El callback verifica PKCE, la sesión vigente del propietario y la cookie, y devuelve resultado y nonce a `jacnomina://gmail`. La app verifica el nonce. La entrega nativa de Gmail conserva sus tablas y secretos.

Agenda reutiliza el callback registrado y los client ID/secret de Google, con scopes `calendar.events` y `calendar.calendarlist.readonly`, guard independiente y retorno `jacnomina://calendar`. Su conexión y calendario compartido se guardan cifrados y con CAS en `payroll_calendar`, migración `0007`. Solo el propietario puede autorizar y seleccionar; todos los usuarios propios activos pueden consultar. Desconectar Agenda no revoca el grant ni modifica Gmail. La preparación de Google Calendar API y el consentimiento único se describen en `README.md`.

Los documentos y respaldos solicitados se crean temporalmente con protección de archivos y se eliminan al cerrar su vista, salir o arrancar de nuevo. No hay base de nómina ni edición sin conexión persistida. Compartir o guardar un archivo expresamente lo deja bajo control del usuario, igual que descargarlo desde la web.

## Evidencia y actualización

Las suites del servidor cubren 60 pruebas de nómina, autenticación, correo, API/OAuth móvil, Calendar y Workerd: edición, previsualización, rutas, horas, permisos, CAS, cierres, correcciones históricas, borrado, entrega de Gmail, expiración, sesión revocada, OAuth de Agenda, lectura compartida, paginación, fechas y desconexión independiente. Usan D1 en memoria y Google simulado. TypeScript y build se verifican con las dependencias preparadas; la incidencia heredada de `npm ci` limpio está documentada en `docs/PROJECT_CONTEXT.md`.

El workflow macOS compila la app y ejecuta pruebas unitarias y de interfaz: Llavero, acceso, exportaciones, contrato móvil, conflictos, nonce y activación; formularios de quincenas/shows/rutas/novedades/horas, archivo, reapertura y cuenta de consulta. Las pruebas de red interceptan peticiones a `.invalid`. Las fixtures de interfaz solo existen en DEBUG; las pruebas nunca crean quincenas, borran datos ni envían correo real en producción. Las capturas y `.xcresult` se conservan en GitHub Actions.

La publicación actualiza el servidor. Para actualizar el binario, abre el mismo proyecto de esta carpeta y usa **Run** en Xcode, o distribuye una nueva versión ad hoc a los tres iPhones. La firma de dispositivos se hace con la cuenta Apple de Camilo en su Mac. Consulta `README.md` en esta carpeta para instalación y el ajuste local del depurador en Xcode 27.0.

La identidad nativa comparte verde oscuro, lima y superficies claras del webapp, con colores adaptados al modo oscuro y controles SwiftUI. Se conservan las capacidades y el cálculo en servidor.

## Itinerarios y Alertas (0.6.0/build 7)

Web e iPhone comparten consulta, lectura, notificaciones con contenido, creación manual de alerta o itinerario desde Alertas, destinatarios y hasta cinco adjuntos PDF/JPG/PNG (10 MB en total). Camilo puede borrar alertas e itinerarios con confirmación. Itinerarios sigue admitiendo Slack; la creación manual no usa Slack. Los adjuntos privados se descargan con sesión y permisos; en iPhone se abren con QuickLook y compartir, en temporales protegidos. Las conexiones Slack/APNs/Web Push se preparan desde la web. No se cambian funciones, rutas ni permisos de nómina o Agenda.
