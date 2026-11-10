# Conciliación de abonos · 10 noviembre 2026

Camilo pidió relacionar consignaciones del archivo de contabilidad con los comprobantes que revisa manualmente en WhatsApp y alojar la herramienta dentro de JAC App. La subpestaña está en `CRM → Conciliación de abonos`, `/crm?seccion=conciliacion`. La vista ampliada es `/crm/reconciliation`.

El formulario permite buscar por fecha, valor y texto; asignar show y empresario; registrar pagador, necesidad de factura, NIT y razón social; adjuntar imágenes o PDF; identificar el abono; y descargar CSV/ZIP con soportes para contabilidad. La identificación requiere show y empresario. Un abono listo para contabilidad requiere identificación y soporte. No se emiten facturas ni se automatizan chats.

## Datos y acceso

- Usa la sesión propia de JAC y el permiso administrativo CRM. La vista, los datos y cada soporte validan esos permisos. No se acepta la cabecera de identidad del proveedor anterior.
- `GET /api/reconciliation/state` combina shows CRM existentes con referencias históricas manuales. Relacionar un show no crea otro ingreso ni modifica ventas, saldos, nómina o Calendar. Al abrir esta pestaña no se ejecuta la sincronización automática del panel CRM.
- Importaciones, anotaciones, soportes e historial viven en las cinco tablas nuevas `jac_reconciliation_*`. Migración aditiva `0039_crm_reconciliation.sql`; no cambia tablas anteriores.
- Los originales importados son inmutables. El guardado de anotaciones usa versión y comprobación de sesión en SQL. La identidad de importación usa SHA-256 del archivo y la hoja, junto con un manifiesto de los datos originales. Repetir la misma selección conserva el avance y completa lotes interrumpidos; una selección distinta bajo la misma identidad se rechaza. Los cambios de nombre del archivo no reescriben su origen.
- Soportes privados en el BUCKET existente, prefijo `crm/reconciliation/`. Máximo20MiB, PDF/JPG/PNG/WebP; tipo comprobado por firma. SHA-256 único entre soportes activos. Las lecturas y subidas revalidan acceso después de R2. Cada subida reserva primero una referencia privada. Un resultado incierto de D1 nunca borra bytes cuyo guardado ya se confirmó; repetir el mismo archivo en el mismo abono recupera su referencia. El retiro invalida el acceso antes de limpiar los bytes y permite reintentar esa limpieza. Las reservas interrumpidas vencen después de24horas. Las referencias históricas tienen identidad estable para evitar duplicados concurrentes.
- Los cinco archivos públicos de `/reconciliation/` contienen únicamente código, estilos y licencia. Nunca incluir archivos contables, seed, soportes, sesiones o exportaciones en el repositorio o Assets. La API lleva cabeceras privadas de JAC.

## Corrección de arranque

El HTML independiente anterior se generaba con cadenas de reemplazo de `String.replace`. Las secuencias `$'` y `$$` del JavaScript eran interpretadas al empaquetarlo, creando errores de sintaxis. El generador independiente usa reemplazos por función y comprueba todos los scripts resultantes. La versión integrada sirve scripts separados sin ese paso de sustitución. La carga inicial tiene límite de20segundos, error visible y reintento. Una respuesta atrasada no restaura datos después de perder el permiso. Las anotaciones pendientes se conservan durante la carga de soportes y el panel protege la salida con cambios sin guardar.

## Verificación y publicación

Las suites `reconciliation.test.mjs`, `reconciliation-view.test.mjs`, `reconciliation-assets.test.mjs` y `reconciliation-worker.test.mjs` comprueban sesión/CRM, origen, originales, concurrencia, reimportación, catálogo, revalidación de soportes y entrega estática. Usan SQLite y R2 simulado. No se prueban escrituras con registros reales.

La fuente se prepara para el Worker propio `jac-nomina` en `jhonalexcastano.com`, conservando DB/BUCKET y secretos mediante `--keep-vars`. Aplicar únicamente la migración nueva revisada y cargar el archivo contable por la importación privada o por el paquete local de importación inicial autorizado. El paquete con los datos de contabilidad permanece fuera de este repositorio público.

**Verificación previa:** TypeScript y compilación Cloudflare correctos.23pruebas del módulo (16de almacenamiento/API,4de vista/exportación,2de assets y1en Workerd/D1/R2) y103regresiones de nómina, autenticación, correo y CRM aprobadas. El arnés Workerd serializa multipart como bytes HTTP, sin depender de la clase FormData de otro runtime. Chromium comprobó la subpestaña real con296registros ficticios, búsquedas, edición, soportes, persistencia, referencias históricas, ZIP, revocación y anchura móvil. JSZip3.10.1 coincide byte por byte con la distribución oficial.

La exportación produce CSV UTF-8 compatible con Excel; el ZIP conserva los originales de los soportes, organizados por abono. Máximo200MiB por paquete para limitar memoria del navegador; filtros por fechas permiten dividirlo.

**Publicación:** pendiente de registrar la activación y la comprobación de datos reales. El entorno no tiene acceso HTTP al dominio (CONNECT403 de la política de red); no equiparar las pruebas locales con una sesión autenticada en producción.
