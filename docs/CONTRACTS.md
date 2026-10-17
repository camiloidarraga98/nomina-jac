# Contratos de presentación · web

Disponible para administradores con acceso al CRM, en CRM → Contratos (`/crm?seccion=contratos`). El formulario genera y descarga un PDF; no firma un documento nuevo, no envía mensajes, no crea eventos y no modifica precios, abonos ni datos de producción.

## Plantilla y campos

Se usa el PDF aprobado `Contrato-JAC-Soraca-propuesta-visual.pdf`, SHA256 `0f31bc77d634919e7b6377cc13a5b6b9e7701a3205e3e6a471e9f68e56770e31`. Sus cuatro páginas, gráficos, logo, cláusulas fijas, pie y firma de Jhon Alex/JAC se conservan como objetos PDF originales. Se eliminan los operadores de texto de los párrafos variables; no se cubren identidades antiguas con rectángulos. La aceptación con ciudad/día/mes en blanco y año2026 se conserva tal como fue suministrada.

Variables: razón social, NIT, representante, cédula, fecha/hora de presentación, sitio, municipio/departamento, precio, consignado y fecha para completar el50%. El bloque del contratante se completa con esos mismos datos. El pago final es exactamente el50% del total, no total menos abonos; el resumen calcula además cuánto falta para completar el primer50% y la fecha del pago final, cinco días calendario antes. Importes de entrada en pesos enteros, hasta1billón; una mitad con50centavos se expresa también en letras. No se altera la redacción jurídica de las cláusulas.

Para que la forma de pago de esta plantilla sea coherente, el abono inicial no puede superar el50% y el plazo de ese primer50% no puede ser posterior al pago final. Se validan fechas reales y horas. Los importes se convierten en letras en español; nombre del archivo: `Contrato JAC - Soracá treinta y uno de octubre de dos mil veintiséis.pdf`.

Los párrafos variables se ajustan dentro de sus áreas originales, con Arial y sus negritas. Textos excepcionalmente largos se reducen de forma acotada o se rechazan con un mensaje; nunca se recortan ni se eliminan cláusulas para hacerlos caber. No hay conexión con servicios de IA ni envío del contrato a terceros.

## Archivos y seguridad

- `app/crm-contract-form.tsx`, pestaña nueva en `app/crm-panel.tsx` y estilos acotados en `app/crm.css`.
- `lib/contract-core.ts`: validación, números/fechas/50% y nombre seguro del archivo.
- `lib/contract-pdf.ts`, `lib/contract-template.json`: generador y recursos privados. La plantilla y la firma no entran al JavaScript público del navegador.
- `app/api/crm/contract/route.ts`: POST del mismo origen, sesión propia activa, permiso administrador del CRM y revalidación de la sesión después de generar. JSON limitado a8KiB; PDF privado/no-store con nombre UTF-8. Sin escrituras D1/R2.
- `scripts/prepare-contract-template.py`: mantenimiento local con pypdf/reportlab y Arial de macOS; solo acepta el SHA del modelo aprobado. No es una dependencia de ejecución. Conserva el PDF original de Descargas sin modificarlo.

Sin dependencias nuevas, cambios de lockfile, migraciones, permisos de otras secciones o cambios nativos.

## Comprobaciones locales · 17 de octubre de2026

-43 pruebas:6 del generador/API y37 obligatorias de nómina/autenticación/correo, aprobadas. Otras41 regresiones del CRM aprobadas. Servicios simulados y bases en memoria.
- TypeScript y compilación web correctos; la construcción exacta para Sites se vuelve a ejecutar desde la fuente privada al empaquetar.
- Reproducción del ejemplo y PDF ficticio renderizados con Poppler e inspeccionados en sus cuatro páginas. Píxeles de zonas fijas y toda la página3 idénticos al original; firma original conservada. Se comprobó la ausencia de razón social/NIT/representante/cédula/importes anteriores en el texto del PDF ficticio.
- Formulario local aislado en navegador: campos manuales, puntuación COP, resumen del50%, selección nativa de fechas, generación, enlace de vista y descarga correctos. Sin conectar Calendar, Sheets, correo o bases reales.
- Informes intermedios privados en `work/local/contract-template/`. No incluirlos ni los contratos generados en el repositorio.
