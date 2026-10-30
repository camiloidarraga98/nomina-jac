# Documentos JAC · identidad visual y composición

## Decisión del 30 de octubre de 2026

Camilo pidió aplicar a preliquidaciones y documentos generados la línea del contrato oficial `Modelo-Contrato-JAC-Borrador.pdf`, con alineación correcta y sin texto ni separadores superpuestos. La referencia visual, no sus cláusulas, define este cambio.

- Logo original extraído sin redibujarlo del PDF proporcionado: `public/document-jac-logo.png`, 298×116. La copia base64 en `lib/document-logo.json` permite generar PDF/Excel sin consultar un servidor de imágenes ni usar credenciales/red.
- Azul oscuro `#22394B`, celeste `#299ED3`, secciones `#D6EFF9`, líneas `#D5E0E7`, texto `#1F2B34` y secundario `#5B7184`. Fuente sans serif: Helvetica en PDF y Arial en Excel/impresión.
- Cabecera con logo, título, quincena y estado; razón social/NIT del cálculo guardado. Pie de contacto tomado del documento oficial. PDF tamaño carta, márgenes de48pt, banda superior y acento celeste como el contrato.

## Alcance

`lib/document-brand.ts`, `document-pdf.ts` y `document-xlsx.ts` centralizan la identidad. `payroll-pdf.ts` compone los informes y `payroll-export.ts` conserva su API pública, proyección y datos del Excel.

Se aplica a preliquidaciones, resumen definitivo, desprendibles individuales, PDF agrupado, cada PDF del ZIP y los adjuntos de los envíos de nómina. Las ocho hojas del Excel de revisión (siete del definitivo) llevan logo, título, contexto, formato monetario y ajustes de impresión. La vista web de impresión usa `SlipDocument` y una hoja CSS propia con la misma identidad, aislando los estilos globales de tablas.

Los contratos generados ya utilizan el membrete de esta referencia: se conserva la plantilla legal y sus cuatro páginas, comprobadas con la batería existente. No se reescriben contratos archivados, PDFs originales aportados por terceros ni documentos ya descargados/enviados. Las descargas nuevas consultan el generador del servidor; una copia offline anterior conserva su archivo.

## Reglas para no repetir el problema

- En PDF, el cursor representa el borde superior del bloque. Cada fila incluye margen superior/inferior y un separador al final. El texto de la siguiente fila nunca reutiliza la posición del separador.
- Altura según las líneas reales; nombres, observaciones, referencias y palabras sin espacios se ajustan al ancho. Importes alineados a la derecha, sin redondear o cortar valores para acomodarlos.
- Cabecera, logo, estado y pie en cada página. Repetir títulos de columnas después de un salto. Mantener juntos encabezado y primera fila; reservar el bloque de conciliación y el total. Contenido excepcionalmente largo puede continuar en otra página.
- Los desprendibles agrupan por identidad, no por número de páginas: una persona con recorridos y salario puede necesitar varias páginas, dentro del mismo PDF y adjunto. No duplicar totales o destinatarios.
- Excel: texto ajustado, alturas calculadas, cifras con ajuste al ancho, filas superiores fijas y títulos repetidos al imprimir. Filtros del resumen excluyen totales y comisión. A4 horizontal o A3 para hojas anchas; una página de ancho y las necesarias de alto.
- La nueva cabecera de Excel desplaza filas. Ajustar las referencias de fórmulas generadas junto con los datos; mantener los valores calculados en caché. Texto proporcionado por usuarios sigue siendo una cadena, nunca una fórmula.
- Los ajustes visuales no modifican cálculos, importes, instantáneas, permisos, estados, versión de nómina ni la política vigente de envío del cierre. La preliquidación sigue siendo una revisión editable sin correos.

## Comprobación

82 casos aprobados en `payroll`, `payroll-auth`, `payroll-mail`, `payroll-export-general`, `payroll-preliquidation`, `payroll-document-layout`, `payroll-routes`, `payroll-mobile`, `payroll-mobile-oauth` y `contracts`; ejecutados por archivo con `--test-isolation=none`. TypeScript y build Cloudflare correctos.

La nueva prueba de composición interpreta el PDF real: límites de texto, intersecciones entre textos y con los separadores, logo/pie/paginación en cada página, nombres y conceptos completos, personas con varias categorías, ZIP/agrupación e importes grandes. El caso extenso genera siete páginas sin superposiciones. Verifica también fórmulas desplazadas, logo y títulos de todas las hojas del Excel.

Verificación local adicional con PyMuPDF y openpyxl: separadores fuera del texto, Excel legible estructuralmente con imágenes, datos, fórmulas y valores almacenados. Chromium comprobó la vista de impresión en1440/390px y su PDF de varias páginas. No se ejecutó Excel de escritorio ni una impresión física.

Muestras con datos ficticios y evidencia local en `work/local/document-brand/`, fuera de Git. No se accedió a nómina real para generar pruebas, no hubo migraciones ni envíos reales. Este cambio no modifica binarios Apple ni necesita un nuevo TestFlight.

Fuente final `8d61d3b` en main. Worker `f71358fc-8e2c-4ed3-8800-816328bcf46b` activo al100% desde13:27 Colombia del30 de octubre, verificado mediante API, con14 bindings y los dos crons conservados. El CLI terminó con los errores auxiliares conocidos de subdominio/memberships tras activar la versión; no se amplió el token. Dominio de producción inaccesible desde la red del entorno: la comprobación visual fue local, con generación real y datos ficticios. La revisión final añadió espacio alrededor del total usando las métricas completas de impresión; PDF.js y PyMuPDF confirmaron ausencia de intersecciones.
