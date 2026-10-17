# Contratos de presentación · web

Disponible para administradores con acceso al CRM, en CRM → Contratos (`/crm?seccion=contratos`). El formulario genera y descarga un PDF; no firma un documento nuevo, no envía mensajes, no crea eventos y no modifica precios, abonos ni datos de producción.

## Plantilla y campos

Se usa el PDF aprobado `Contrato-JAC-Soraca-propuesta-visual.pdf`, SHA256 `0f31bc77d634919e7b6377cc13a5b6b9e7701a3205e3e6a471e9f68e56770e31`. Sus cuatro páginas, gráficos, logo, cláusulas fijas, pie y firma de Jhon Alex/JAC se conservan como objetos PDF originales. Se eliminan los operadores de texto de los párrafos variables; no se cubren identidades antiguas con rectángulos. La aceptación con ciudad/día/mes en blanco y año2026 se conserva tal como fue suministrada.

Variables: razón social, NIT, representante, cédula, fecha/hora de presentación, sitio, municipio/departamento, precio, consignado y fecha para completar el50%. El bloque del contratante se completa con esos mismos datos. El pago final es exactamente el50% del total, no total menos abonos; el resumen calcula además cuánto falta para completar el primer50% y la fecha del pago final, cinco días calendario antes. Importes de entrada en pesos enteros, hasta1billón; una mitad con50centavos se expresa también en letras. No se altera la redacción jurídica de las cláusulas.

Para que la forma de pago de esta plantilla sea coherente, el abono inicial no puede superar el50% y el plazo de ese primer50% no puede ser posterior al pago final. Se validan fechas reales y horas. Los importes se convierten en letras en español; nombre del archivo: `Contrato JAC - Soracá - 31 de octubre 2026.pdf`.

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

Publicado como web v79 en el Site existente, fuente privada `aefa1f7778cf16e4335118b1d1b3d4715feb83eb`, despliegue `appgdep_6ad3eb33393881919410136d72ab9cfe` succeeded. Sin cambios de dominio, audiencia, DB, BUCKET, secretos o conexiones. Formato de nombre corregido antes de publicar y verificado en la descarga local; seis pruebas finales aprobadas.

## RUT y contratos en iPhone · 17 de octubre de 2026

La primera acción de Contratos ahora es **Subir RUT**. Se completan razón social, NIT/DV, representante legal principal y su cédula; los cuatro campos permanecen editables y pueden escribirse sin cargar un RUT. Los datos del evento y pagos siguen siendo manuales. El PDF, las cláusulas y el formato de nombre no cambian.

Se leen las casillas DIAN 35, 5/6 y 98–107 mediante posición y etiqueta, reconstruyendo nombres antes de apellidos. No se confunden sigla, solicitante del pie, socios/junta o contador con el representante principal. Se conservan dígitos y DV cero. El dígito de verificación se comprueba sin corregirlo silenciosamente. Si hay varios principales se pide selección; un principal incompleto o con documento diferente a cédula no se elige automáticamente. Ante datos ausentes se avisa y queda la alternativa manual. PDFs escaneados sin texto requieren entrada manual; no se incorpora un servicio OCR ni validación jurídica en línea.

Web: `lib/rut-extract.ts` interpreta el texto y `lib/rut-pdf-client.ts` lee el archivo en un Worker local. No se envía ni almacena el RUT; únicamente los campos del formulario llegan al servidor al generar el contrato. Límites de 10 MB/20 páginas, tiempo de lectura y complejidad; cancelación y limpieza del lector sin resultados tardíos. `app/crm-contract-rut.tsx` ocupa la primera posición y actualiza los cuatro datos juntos para no mezclar contratantes. PDF.js 6.4.299 queda fijado, con su worker de la misma versión y licencia local. Se usa el build compatible con navegadores anteriores. La carga del lector es diferida; no hay CDN ni claves nuevas.

Dependencias: única dependencia directa nueva `pdfjs-dist` con versión exacta; 13 entradas nuevas en el lock (incluidos canvas/binarios opcionales). Todos los objetos anteriores del lock se conservaron íntegros, sin actualizar versiones/URLs/integridades ni metadatos ajenos. `npm ci --ignore-scripts` y el instalador oficial de Sites comprobaron la instalación desde el lock. No se borró ni regeneró indiscriminadamente.

iPhone: CRM → Contratos en el mismo proyecto `ios/JACNomina.xcodeproj`. PDFKit procesa el RUT localmente, con límite de tamaño/páginas y cancelación. El contrato se genera con la misma plantilla del servidor, se presenta y se puede compartir; requiere internet para generarlo. No se añade el RUT al caché ni se envía su archivo. El PDF se guarda solo como temporal protegido y se retira al cerrar/revocar. Se conserva la cubierta de privacidad y la sesión en Llavero. Nueva API `POST /api/mobile/contracts`: Bearer exclusivo con la sesión nativa existente, administrador CRM, cuerpo de 8 KiB y revalidación de sesión/perfil antes y después del PDF. Sin escrituras D1/R2 ni nuevos secretos.

Cambios nativos acotados a `CRMView.swift`, `PayrollClient.swift`, fixture DEBUG y pruebas existentes. Proyecto/esquema/Info/firma/bundle/push suspendido se conservan. No hay que descargar otro proyecto; usar Run en este mismo para instalar en el teléfono.

Verificación final:

- 77 pruebas Node aprobadas: nómina/autenticación/correo/móvil, contratos y 22 comprobaciones nuevas de RUT/lector/API móvil. D1 en memoria y servicios interceptados.
- TypeScript y build web correctos. Instalación limpia desde lock comprobada; la construcción exacta se ejecuta al empaquetar para Sites.
- RUT suministrado contrastado en privado con extracción independiente, PDF.js y PDFKit: los cuatro datos y un principal coinciden sin advertencias. Documento original sin modificar; ningún identificador real se copió a código, pruebas o documentación.
- Navegador local: carga del RUT, edición posterior y creación manual sin RUT hasta descarga con nombre correcto. El primer fallo de descarga fue del orden del middleware de la vista aislada y se corrigió allí; no alteraba la API real. Captura ficticia `outputs/contratos-rut-web.png`.
- 134 unitarias nativas ejecutadas: 133 aprobadas y una condición física de protección omitida por CoreSimulator. UI de contratos aprobada con regreso desde Home, edición manual y contenido del PDF visible; una captura inicial se tomó antes de renderizar QuickLook y se reforzó la espera manteniendo las aserciones. Release iPhone y compilación de compatibilidad Mac correctas. Informes `contracts-native-verified.xcresult`, `contracts-native-rendered.xcresult`, `contracts-native-release.log` y `contracts-mac-compatibility.log` bajo `work/local/`.
- No se instaló en el iPhone físico, ni se probaron servicios/datos reales mediante envíos, ni se cambiaron firma, push o versiones nativas. La instalación requiere Run del usuario.

Cierre: web v80 y API móvil publicadas en el Site existente; fuente `f3cba1722267779ab2495c972643dd8a2461b96a`, versión `appgprj_6aa0260b82a88191a47960614238350a~appgver_15beb38e29f88191a1ddf91b8ae50a2a`, despliegue `appgdep_6ad3f28d9eb8819180b305c824792bcc` succeeded, env_set_revision2. Dominio/audiencia/DB/BUCKET/R2/secretos/conexiones preservados. Respaldo nativo opcional de76archivos `outputs/JAC-Contratos-RUT-iPhone-Mac-fuente.zip`, sin firma personal/claves/estado, SHA256 `6dc673fc362d3914d6501b71666c13e5f5729af0b610262badfcd0c7dbb4c324`. El proyecto de trabajo existente conserva su firma y se actualiza con Run; no se instaló en teléfono físico.
