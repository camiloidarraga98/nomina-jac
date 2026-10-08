# Recepción, gastos y versiones de itinerarios

Continuidad del Site `appgprj_6aa0260b82a88191a47960614238350a`, en web e iPhone 0.10.0 (16). No cambia hosting, dominio, DB, BUCKET ni conexiones. La migración 0015 es aditiva; conserva 0000–0014 y todos los registros existentes.

## Confirmar recibido

Alertas e itinerarios tienen un botón explícito **Confirmar recibido**. Abrir el aviso conserva su marca de lectura y no confirma recepción. La confirmación pertenece al usuario autenticado y a la revisión que leyó; reintentar no cambia su fecha ni duplica registros. Un aviso eliminado o una revisión anterior no se pueden confirmar. Los administradores ven confirmaciones y pendientes al abrir el aviso; los demás solo ven su propia confirmación. No se agrega lectura administradora de pases privados.

## Actualizar un itinerario

Un administrador abre el itinerario y elige **Actualizar itinerario**. Debe indicar qué cambió y adjuntar la versión completa (hasta cinco PDF/JPG/PNG, 10 MB en conjunto). Se conserva el ID, origen y destinatarios del itinerario; no se modifican el archivo original ni los mensajes de Slack. El itinerario actualizado aparece primero y muestra versión, fecha y resumen de cambios. Las confirmaciones previas no cuentan para la nueva versión.

`POST /api/notices/publish?update=1` exige revisión esperada y UUID de solicitud estable. La sustitución de archivos, incremento de revisión y auditoría se confirman en un lote D1. Los archivos anteriores quedan inaccesibles antes de limpiar R2; fallos de limpieza se reintentan. Un reintento de la misma solicitud no incrementa otra vez la versión. Las entregas push se identifican por aviso/dispositivo/revisión y se revalidan inmediatamente antes del proveedor; las pendientes de la revisión vieja se desactivan. La nueva notificación dice “JAC · Itinerario actualizado” y muestra el resumen de cambios. Eliminar un itinerario también retira sus resúmenes de revisión; su tombstone impide recrearlo por un reintento tardío.

## Gastos de viaje

Web: **Configuración general → Gastos de viaje**, `/gastos-de-viaje`. iPhone: **Gestión → Gastos de viaje**.

Cada usuario activo puede registrar sus propios gastos: concepto, valor entero en COP (máximo mil millones), fecha civil, nota opcional y uno a cinco comprobantes PDF/JPG/PNG, máximo 10 MB en conjunto. El iPhone permite Archivos, Fotos o fotografiar un comprobante. No se envían correos ni avisos por registrar/revisar un gasto.

El gasto comienza pendiente. Su autor y los administradores pueden consultar el registro y los comprobantes privados. Una cuenta limitada como Alex puede registrar y consultar sus gastos; no recibe empleados, quincenas, administración ni acceso a nómina. Los otros usuarios no ven gastos ajenos.

Solo administradores revisan gastos. **Rechazar con motivo** conserva el comprobante y no cambia nómina. **Aprobar e incorporar** exige elegir explícitamente una persona activa y una quincena abierta sin corrección de cierre, donde no esté excluida. La incorporación crea un movimiento `reintegro`, cantidad 1 e ID estable del gasto; utiliza el motor y tratamientos existentes de nómina. La revisión y el movimiento se escriben atómicamente con la revisión de nómina y un guard del gasto pendiente. Una carrera o un fallo D1 revierte todo. Reintentar la misma aprobación no vuelve a pagar el gasto. No se cierran quincenas ni se envían desprendibles.

`/api/expenses` y `/api/expenses/file` usan sesión propia, origen validado para escritura y respuestas privadas sin caché. Los comprobantes usan un espacio de pertenencia `expense:<UUID>` dentro de los adjuntos privados para impedir acceso cruzado mediante las rutas de avisos. Se valida la firma del archivo, no solo su extensión. La sesión y pertenencia se revisan de nuevo tras leer R2. El formulario conserva UUID/datos ante resultados inciertos para reintentar sin duplicados.

## Verificación local

- `npx tsc --noEmit` y build web.
- Pruebas de nómina, autenticación, correo simulado y API móvil existentes.
- `tests/notifications.test.mjs`: recepción explícita, revisiones, revocación, privacidad, origen, reintentos, rechazo y carrera de aprobación.
- `tests/notifications-worker.test.mjs`: D1/R2 reales de Workerd local, rollback atómico y aprobaciones concurrentes; todas las salidas interceptadas.
- Xcode: `PayrollClientTests` y `LaunchTests`, incluyendo los nuevos contratos, recepción/actualización y envío/revisión de gasto. Fixtures `.invalid`, sin cuentas ni servicios reales.
- El simulador no verifica cámara física, firma/confianza del iPhone ni protección de archivos del dispositivo. El push iPhone sigue suspendido (`JAC_PUSH_ENABLED=NO`); no se reactivan APNs ni entitlements.

## OCR de comprobantes en iPhone — 0.12.0 (20)

`ExpenseReceipt.swift` agrega Vision con `VNRecognizeTextRequest` en modo preciso, español/inglés soportados por el dispositivo, sin API de OCR ni nuevas dependencias. La cámara conserva su solicitud de permiso de iOS y Fotos usa el selector del sistema. Las fotos se normalizan de orientación y se limitan a 4096 píxeles antes de reconocer. No se conserva ni transmite la transcripción completa; se guardan los campos revisables y la foto elegida. El OCR no envía el gasto: el usuario aplica las sugerencias y después pulsa Enviar a revisión.

El parser distingue total explícito, subtotal/impuestos, efectivo/cambio, rechaza valores incompatibles, otra moneda explícita, importes negativos, más de mil millones o centavos no nulos. Fechas civiles válidas en Colombia: ISO, día/mes/año y mes en español; ignora vencimiento/resolución y deja ambigüedades para el usuario. El tipo es una sugerencia por palabras clave o selección manual (Alimentación, Transporte, Hospedaje, Combustible, Otros). Se conserva en la nota existente, sin cambiar API, esquema ni movimientos/cálculos de nómina.

`ExpenseDraft` contiene el UUID estable, campos, comprobantes y estado de intento; se guarda en `OfflineResponseCache` como recurso local separado, bajo el mismo cifrado AES-GCM, ámbito token/origen, protección completa y exclusión de backup. Se valida pertenencia de sesión al guardar/eliminar/aplicar una lectura. No hay cola de escritura, reenvío ni expiración arbitraria. Un único borrador por sesión se restaura sin internet. Antes del envío se persisten los datos bloqueados para que un resultado incierto conserve idempotencia. Tras confirmar el envío se retira el borrador. Salida/revocación purgan el almacenamiento existente.

Pruebas nuevas: Vision sobre JPEG generado de factura ficticia y hoja vacía; total/IVA/cambio, fechas inválidas y contradictorias, moneda extranjera, clases ambiguas; cifrado/restauración/ámbito/revocación/eliminación de borradores, archivos inválidos y UUID de reintento. Interfaz: aplicar y corregir OCR, privacidad al volver de segundo plano, guardar/reabrir offline, OCR sin red, envío manual al reconectar y revisión existente.
