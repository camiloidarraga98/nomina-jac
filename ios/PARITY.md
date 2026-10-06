# Correspondencia del webapp y la app de iPhone

La versión 0.2.0 conserva las cuentas, los permisos y la base D1 del webapp. Toda liquidación procede de `lib/payroll.ts` en el servidor. SwiftUI muestra los resultados y envía comandos de edición; no implementa otro motor de nómina.

| Función existente | Acceso nativo | Integración compartida |
| --- | --- | --- |
| Crear quincena por mes y mitad; búsqueda y consulta | Quincenas → +; búsqueda | Helpers originales de períodos y guardado CAS |
| Shows, fecha, ventas, participantes y honorarios manuales | Quincena → Actividad → Shows y honorarios | `updateShow`, `removeShow` y políticas originales |
| Novedades libres o por concepto, ingresos, reintegros y descuentos | Actividad → Novedades y descuentos | Movimientos originales; cantidades y tratamientos validados en servidor |
| Un recorrido por show para ambos conductores, registros anteriores y extras | Actividad → Recorridos y kilómetros | `setShowRoute`, tarifas y consolidación originales |
| Siete tipos de horas, días, vacaciones y notas | Actividad → Horas y salarios | Factores y cálculo originales, incluidos cortes mensuales |
| Liquidación por persona/grupo, ingresos, descuentos y condiciones utilizadas | Quincena → Pagos → Persona | Cálculo del corte, snapshot o condiciones históricas |
| Cerrar con instantánea y preparar envíos cuando Gmail esté conectado | Quincena → Cerrar quincena, con confirmación | Acción `close` original, validación y lotes idempotentes |
| Archivo y consulta de cierres | Archivo → Quincena | Mismos períodos y snapshots |
| Reabrir, corregir condiciones y factores históricos, volver a cerrar | Cierre → Reabrir para corregir → Condiciones / Parámetros | `modifyClosed`, cálculo histórico y versiones anteriores conservadas |
| Eliminar totalmente una quincena | Quincena → Eliminar quincena, solo propietario | `deletePeriod`, confirmación del ID, CAS y protección frente a envíos en curso |
| Crear, editar, inactivar, eliminar y restaurar personal | Equipo | Todas las condiciones originales; historia conservada y validación de registros abiertos |
| Conceptos y valores; empresa, NIT, divisor y siete factores | Gestión → Conceptos y reglas / Parámetros | Permiso `rules`, esquema original |
| Usuarios, permisos, estado activo, invitación y restablecimiento | Gestión → Usuarios y permisos, solo propietario | `/api/users`, revisión de usuario, enlaces privados de un uso y sesiones invalidadas |
| Acceso, activación/restablecimiento, contraseña y salir | Inicio de sesión / Mi cuenta | `/api/auth`, sesión segura en Llavero; cualquier contraseña no vacía |
| Configurar, conectar, renovar o desconectar Gmail | Gestión → Correo → Conexión, solo propietario | OAuth/PKCE original con entrega nativa protegida; credenciales cifradas en D1 |
| Consultar estados, modificar correo de personal y enviar desprendibles conjuntos/individuales | Correo → Quincena / Correos y envíos de este corte | `/api/payroll/email`, permisos `staff`/`send`, mismos estados e idempotencia |
| PDF de resumen y desprendibles, ZIP y Excel de siete hojas | Quincena cerrada → Documentos | `/api/payroll/export`, permiso `export`; mismos archivos del servidor |
| Buscar e imprimir desprendible individual; compartir documentos | Documentos → Persona / vista previa → Imprimir o compartir | PDF original, QuickLook, AirPrint y hoja de compartir de iOS |

## Guardado y concurrencia

`GET /api/mobile/payroll?workspace=1` entrega una revisión consistente. `?period=ID` entrega el detalle y los datos para los formularios. `POST` admite `edit`, `remove` y `previewEdit` y delega las acciones originales. Cada formulario conserva la revisión que vio al abrirse; el servidor aplica los helpers existentes, esquema, permisos y políticas antes del guardado original. No se envían períodos ni snapshots históricos reconstruidos por Swift.

La previsualización calcula en el servidor sin guardar ni preparar correo. Un error de edición o conflicto conserva la solicitud pendiente en memoria. Se puede reintentar exactamente esa solicitud, compartir una copia JSON protegida o descartarla y actualizar; nunca se guarda silenciosamente sobre otra revisión. Las listas de actividades se actualizan al guardar incluso cuando el resumen queda detrás de la pantalla actual.

Los permisos se verifican en servidor y en la interfaz: `payroll`, `staff`, `rules`, `close`, `send`, `export` y `modifyClosed`. Los cortes reabiertos continúan restringidos. Las acciones exclusivas del propietario permanecen exclusivas.

## Gmail, documentos y dispositivo

La ventana de autorización de Apple es el único flujo de navegador. Un ticket de dos minutos y de un uso entrega una cookie exclusiva de Gmail; no entrega una sesión de nómina al navegador. El callback verifica PKCE, la sesión vigente del propietario y la cookie, y devuelve resultado y nonce a `jacnomina://gmail`. La app verifica el nonce. No se agregan tablas, migraciones o secretos.

Los documentos y respaldos solicitados se crean temporalmente con protección de archivos y se eliminan al cerrar su vista, salir o arrancar de nuevo. No hay base de nómina ni edición sin conexión persistida. Compartir o guardar un archivo expresamente lo deja bajo control del usuario, igual que descargarlo desde la web.

## Evidencia y actualización

Las suites del servidor cubren las 30 pruebas originales y siete pruebas adicionales de API móvil y OAuth: edición, previsualización, rutas, horas, permisos, CAS, cierres, correcciones históricas, borrado, entrega de Gmail, expiración y sesión revocada. Usan D1 en memoria y Google simulado. TypeScript y build se verifican con las dependencias preparadas; la incidencia heredada de `npm ci` limpio está documentada en `docs/PROJECT_CONTEXT.md`.

El workflow macOS compila la app y ejecuta pruebas unitarias y de interfaz: Llavero, acceso, exportaciones, contrato móvil, conflictos, nonce y activación; formularios de quincenas/shows/rutas/novedades/horas, archivo, reapertura y cuenta de consulta. Las pruebas de red interceptan peticiones a `.invalid`. Las fixtures de interfaz solo existen en DEBUG; las pruebas nunca crean quincenas, borran datos ni envían correo real en producción. Las capturas y `.xcresult` se conservan en GitHub Actions.

La publicación actualiza el servidor. Para actualizar el binario, usa **Integrate → Pull → origin/main** y **Run** en Xcode, o distribuye una nueva versión ad hoc a los tres iPhones. La firma de dispositivos se hace con la cuenta Apple de Camilo en su Mac. Consulta `README.md` en esta carpeta para instalación y el ajuste local del depurador en Xcode 27.0.
