# Preliquidación y envío manual de nómina

Camilo pidió el30 de octubre de2026 un reporte PDF/Excel para revisar los pagos sin cerrar la quincena ni enviar desprendibles. Tras revisarlo, el cierre y el envío se ejecutan expresamente. Esta decisión sustituye el envío automático asociado al cierre.

## Flujo

- Web: Quincena → **Preliquidación** → PDF o Excel. Guardar los cambios pendientes antes de descargar.
- iPhone/iPad/Mac: quincena → **Preliquidación** o **Documentos** → Preliquidación PDF/Excel.
- La quincena permanece abierta; se pueden ajustar shows, recorridos, horas y novedades y volver a descargar. No hace falta reabrirla.
- **Cerrar quincena** valida y conserva la liquidación definitiva con sus condiciones. Habilita documentos definitivos y desprendibles; no prepara ni envía correos.
- **Correos → Enviar** inicia explícitamente el envío del cierre. Una selección individual prepara únicamente a esa persona; el resto sigue visible y pendiente de autorización de envío. El lote omite mensajes ya enviados y conserva los resultados inciertos sin repetirlos automáticamente.

La preliquidación incluye devengados, adiciones/reintegros, descuentos, netos, comisión de Camilo y total general. PDF marcado en todas las páginas; Excel con resumen, detalle y actividades, más hoja Revisión. Ambos indican versión y momento de generación. Los pendientes del cálculo se muestran para revisión y no impiden generar el borrador. No se inventan valores faltantes ni se relajan las validaciones del cierre.

## Contrato y protección

`GET /api/payroll/export?period=…&format=pdf|xlsx&mode=preliquidation&version=…` requiere sesión, sección Nómina y permiso exportar, periodo abierto y versión guardada vigente. Solo reportes generales; se rechazan employee, slips y zip. Una nueva lectura de versión y la revalidación de sesión después de generar impiden entregar resultados de una revisión concurrentemente reemplazada o un acceso revocado. Respuestas privadas/no-store; el cliente nativo exige conexión y evita caché/fallback de este reporte mutable.

`payrollReview` es una proyección efímera con el cálculo central, normalización de ensayos y condiciones históricas de cortes reabiertos. No cambia estado, snapshot, revisiones, versión, contactos ni tablas/colas de correo; no genera desprendibles individuales ni guarda una falsa fecha de cierre. Reutiliza PDF/Excel con un modo explícito de revisión. Exportación definitiva sigue leyendo exclusivamente la instantánea cerrada.

El cierre compartido web/móvil ya no llama `planMail`, `mailWrites` ni `drainMail`. Solo `POST /api/payroll/email` con acción send autoriza crear trabajos. GET muestra la previsión sin persistirla; consulta y cron no preparan nuevos lotes. Los lotes que ya fueron autorizados mantienen su procesamiento durable. No se cancelan envíos existentes ni se alteran datos reales para probar.

## Verificación y entrega

Pruebas financieras y de API con D1 local, cuentas/documentos ficticios y Gmail interceptado: generación sin escrituras/correos, edición posterior, PDF/Excel con importes, revisión histórica, permisos, conflictos/revocación durante generación y cierre seguido de envío individual/lote idempotente. Pruebas nativas focales de solicitud/versionado/caché y recorrido de preliquidación/cierre/reapertura. No se cierra ni envía una quincena real como prueba.

App/widget0.42.0(61), misma firma/Team/bundles/AppGroup/APNs. La entrega al dispositivo depende de la compilación instalada; CI no equivale a instalación ni distribución TestFlight.

Entrega web/API del30 de octubre: fuente `c5cfb78`, Worker `fc79a875-1f97-4faa-b08e-8f30a9a56ebf`, activo al100% a las11:45 de Colombia. Comprobación por API de Cloudflare: conserva los14 bindings y los dos crons; sin migraciones ni modificaciones de datos reales. Wrangler subió/activó correctamente, aunque terminó con los errores auxiliares de permisos ya conocidos al consultar subdominio/memberships; la versión activa se comprobó de forma independiente. La red de este entorno no permite consultar el dominio de producción; no se afirma una prueba autenticada allí.

Comprobaciones locales:80 casos reales, cero fallos: payroll20, auth12, mobile10, OAuth móvil4, correo7, recorridos8, comisión10, exportación5 y API de preliquidación4. TypeScript y build Cloudflare completos. Navegador Chromium con UI real y servidor simulado: descarga de ambos formatos sin POST, edición y nueva versión, cierre explícito sin correo; modal contenido en1440px y390px. Los PDF/Excel y las capturas de evidencia usan personas ficticias y quedan en `work/local/payroll-preliquidation/`, fuera de Git.

Apple: ejecución focal [41092667149](https://github.com/camiloidarraga98/nomina-jac/actions/runs/41092667149) sobre `c5cfb78`, en cola al publicar esta nota: GitHub todavía no había asignado ejecutores a ninguno de los tres jobs. Incluye contrato de descarga fresca/versionada, permisos, acciones compartidas, recorrido UI de revisión/cierre/reapertura y seis guardas de fluidez; Release iPhone y Mac independientes. La compilación y las pruebas Apple aún no están comprobadas; consultar esta ejecución antes de dar por verificada la actualización nativa.
