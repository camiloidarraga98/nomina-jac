# Cómo funciona JAC y qué quiere decir Camilo

Estado de continuidad: **18 de octubre de 2026**. Esta guía resume decisiones de producto ya tomadas; no es una lista de funcionalidades por implementar. Léela al comenzar el nuevo chat Cloud, antes de reinterpretar los módulos. Complétala cuando Camilo cambie una regla o un flujo.

JAC Music coordina la operación de los shows de Jhon Alex Castaño: agenda, venta y cobro, nómina, contratos, viajes, comunicaciones y contenido audiovisual. Web, iPhone, iPad y Mac forman el mismo ecosistema y usan el mismo servidor y las mismas cuentas. No son cuatro productos independientes.

## 1. Vocabulario de Camilo

| Cuando dice… | Se refiere a… |
| --- | --- |
| Webapp, página, sitio, JAC | La aplicación privada de `https://jhonalexcastano.com`, con acceso por usuario. |
| App, teléfono, celular | Normalmente la app nativa del iPhone. Si menciona Mac o iPad, atender esa plataforma. «Todo el ecosistema» incluye las cuatro interfaces. |
| Show, fecha, evento | Una presentación de un solo día. Un evento de Agenda no es necesariamente un show comercial. |
| Agenda, calendario, Calendar | Agenda es la interfaz de JAC; Google Calendar es su fuente compartida. No son calendarios independientes. |
| CRM, bolsa del show | Control comercial individual: venta, empresario, abonos, comprobantes, saldo, preparación, rentabilidad y contratos. |
| Abono, separaron el show | Dinero recibido del empresario a cuenta de la venta. Reduce el saldo por cobrar; no es un gasto ni una rebaja del precio de venta. |
| Comprobante del abono | Imagen/PDF privado que acredita ese ingreso. No confundir con factura de un gasto. |
| Quincena, nómina | Liquidación del equipo de trabajo por periodo, con shows, tarifas, novedades, recorridos, gastos y pagos. |
| Gastos del show | Costos directos asociados a un show concreto; participan en su análisis y en la comisión de Camilo. |
| Gastos de viaje, factura, reintegro | Flujo personal de comprobantes, revisión y eventual incorporación explícita a nómina. No se importa solo a Gastos del show. |
| Promocional | Casilla del show que excluye sus costos de la base de comisión de Camilo. El equipo conserva sus pagos. |
| Itinerario | Documento compartido de organización del viaje/trabajo. Puede venir de Slack o crearse manualmente. |
| Pase de abordar, pase | Documento de embarque privado de una sola persona. No es un itinerario compartido. |
| Alertas | Avisos a destinatarios; su creador también permite publicar itinerarios o pases manuales con adjuntos. |
| Fotografía, fotos, galería | Biblioteca privada de fotos/videos del equipo, organizada en carpetas de shows o días de trabajo en R2. No son imágenes decorativas del sitio. |
| Carpeta de evento en Fotos | Organización audiovisual. Crearla no crea por sí misma un evento en Calendar ni un show en CRM. |
| Descargar carpeta | Hay dos acciones diferentes: guardar copia dentro de JAC sin conexión o exportar todos sus archivos a Fotos del teléfono. Conservar ambas. |
| Contrato diligenciado/generado | PDF de la plantilla aprobada, guardado en el archivo de Contratos. Generarlo no significa que esté firmado. |
| Gestión, configuración general | Menú de opciones secundarias, permisos, servicios y ajustes; no eliminar las funciones al quitarlas de la navegación principal. |
| `jac` | Usuario de **Jhon Alex Castaño**. No es Alex Zuluaga ni un usuario técnico del servidor. |

## 2. Cómo se relacionan los módulos

1. **Calendar → Agenda → CRM:** Agenda comparte los eventos del calendario conectado. El CRM identifica shows y agrega información comercial privada.
2. **CRM → nueva quincena:** al crearla se incorporan los shows elegibles y sus precios dentro del periodo. La nómina conserva sus propias tarifas/datos e instantáneas; no se reescribe después por cambiar Calendar o CRM.
3. **Shows + costos → comisión:** los abonos no cambian la venta usada para el cálculo; los costos promocionales tienen una excepción específica.
4. **Alertas → publicación manual:** el mismo creador puede enviar una alerta, un itinerario compartido o un pase privado. Slack es otra entrada para los dos últimos.
5. **Contrato → show CRM:** la asociación es documental. No registra un abono, no modifica el precio ni crea un evento.
6. **Fotografía → carpetas R2:** es una biblioteca independiente. No se sincroniza con Google Drive ni convierte carpetas en shows automáticamente.

## 3. Personas y permisos que ya se decidieron

- **Camilo:** administrador de control total y propietario que autoriza las conexiones. Hablarle en español, con explicaciones claras y sin exigirle repetir el contexto.
- **Jhon Alex Castaño, usuario `jac`:** administrador de control total, incluyendo nómina y gestión/borrado de itinerarios. Las notas antiguas que lo limitan a consultar nómina están superadas.
- **Alex Zuluaga, usuario `alex`:** última selección confirmada: **Agenda, Alertas y Fotografía con creación de carpetas/subida**. Sin Nómina, CRM, Itinerarios ni Pases. Sustituye su antiguo perfil «Solo itinerarios».
- **Anderson:** fotógrafo; cuenta ya creada como `anderson`. Desde el 19 de octubre de 2026 Camilo autoriza también borrar archivos ya subidos (fotos/videos, incluso de otros usuarios) y carpetas con su contenido en Fotografía. Requiere que conserve acceso a Fotografía y sesión activa; no concede CRM, administración ni otros módulos. La autorización inicial fue Fotografía y subida. Ahora el administrador puede elegir sus secciones una por una; no volver a bloquearlas con un perfil exclusivo obligatorio.
- **Luisa y Paula:** pueden editar Agenda por la política existente; tener acceso a Agenda no concede automáticamente edición a cualquier usuario. El código vigente también permite editar a administradores válidos.
- Camilo y `jac` también pueden crear carpetas y subir fotos/videos. La subida no es exclusiva de Anderson.

Esta lista describe las decisiones de continuidad, **no ordena modificar cuentas al arrancar Cloud**. La respuesta autorizada del servidor es la fuente vigente de permisos de cada sesión. No sobrescribir cambios posteriores guardados en Usuarios basándose en documentación.

Se eligen secciones por separado: Nómina, Agenda, Itinerarios, Alertas, Pases, Fotografía y subida. Subir requiere Fotografía; CRM y administración permanecen restringidos. Mi cuenta siempre es accesible. `sections` prevalece sobre los indicadores antiguos `mediaOnly`/`itinerariesOnly`, que siguen protegiendo a clientes anteriores. Los permisos se aplican en servidor, SQL, archivos, destinatarios y caché, además de ocultar menús.

**Excepción de privacidad fundamental:** un administrador no puede leer ni borrar pases ajenos por su rol. Cada pase pertenece a un solo destinatario. Cambiar permisos puede revocar sesiones; no generar invitaciones, restablecer contraseñas ni reenviar correos automáticamente.

## 4. Quincena, costos y comisión de Camilo

La primera quincena abarca del 1 al 15; la segunda del 16 al último día del mes. Se conservan Shows, Novedades, Recorridos, Gastos, Horas y salarios y Liquidación, aunque la distribución nativa sea distinta. Personal, conceptos/reglas, correos y Archivo siguen disponibles desde Gestión/configuración.

- Los participantes y tarifas se guardan con el show/recorrido. Un cambio de tarifa actual no reemplaza valores históricos.
- La nómina dependiente de **Jenny se paga solo en la segunda quincena**, al cierre mensual; no incluirla en la primera.
- Los campos COP permiten borrar el valor completo y escriben separadores de miles, por ejemplo `140.000.000`; no imponer un cero inicial imborrable.
- Los cierres guardan instantáneas y requieren reapertura/corrección autorizada para editar. No recalcular cierres antiguos con reglas o tarifas nuevas ni probar cerrando quincenas reales.

Regla acordada:

`Comisión de Camilo = 5% × máximo(0, ventas de todos los shows − costos de shows no promocionales)`

| Elemento | Tratamiento en la comisión |
| --- | --- |
| Venta registrada de cada show | Se suma completa, también si es promocional y tiene venta. No depende de cuánto hayan abonado. |
| Honorarios brutos de músicos/técnica por show | Se descuentan si el show no es promocional. |
| Pagos por kilómetros de conductores vinculados al show | Se descuentan si el show no es promocional, usando sus tarifas guardadas. |
| Tiquetes, hoteles, alimentación y otros gastos directos del show | Se descuentan si el show no es promocional. |
| Nómina fija/dependientes, honorarios fijos quincenales, novedades, retenciones, reintegros, recorridos extra | Se excluyen. |
| Todos los costos de un show marcado promocional | Se excluyen de esta base; permanecen en el costo real y en los pagos del equipo. |

Es un **cálculo revisable**, no un pago automático a Camilo ni una suma al neto. Si la base es negativa, comisión cero, sin arrastrar una deuda a la quincena siguiente. Un recorrido compartido no se cobra dos veces; si su asociación es ambigua se pide resolverla, no se inventa un reparto.

**Gastos por show**: pestaña Gastos en web; en iPhone, Quincena → Actividad → Gastos por show. Cada registro tiene show, categoría, fecha, concepto, COP y observación opcional. La fecha del comprobante puede diferir de la fecha del show. Permite editar/eliminar con permisos y periodo abierto. **No genera un reintegro ni un pago**. No duplicar automáticamente el mismo gasto desde Gastos de viaje.

Referencia: [SHOW_COSTS_COMMISSION.md](../docs/SHOW_COSTS_COMMISSION.md).

## 5. CRM: venta, abonos, empresario y preparación

Acceso solo administrativo, principalmente Camilo y `jac`. El listado normal muestra **hoy y próximos shows**, según Colombia, sin borrar los históricos. Reconoce municipios en el nombre del evento, incluidos títulos como `PRIVADO-CALI` y `CALI - LA COMADRE`; el filtro no debe exigir que el título sea únicamente un municipio. Se puede ignorar una coincidencia que no sea un show.

Cada show tiene una bolsa independiente: valor de venta, empresario, observaciones privadas, abonos activos y saldo. **Saldo = venta − abonos activos**; un excedente se conserva como saldo a favor. No mezclar fondos entre shows.

### Registrar y consultar abonos

- Se puede entrar al show o pulsar **Registrar/Agregar abono** en la cabecera y elegir el show. Hace falta registrar su precio.
- Fecha, valor COP, nota y comprobantes PDF/JPG/PNG: hasta cinco, máximo 10 MB en conjunto. Arrastrar o usar el explorador prepara los adjuntos; **guardar confirma el abono**, no el mero arrastre.
- Nombres de comprobantes con consecutivo por show, por ejemplo `Copacabana-1.pdf`, `Copacabana-2.jpg`. El consecutivo no se reinicia en cada abono ni reutiliza cancelados; no renombrar históricos en lote.
- Anular un abono exige motivo, mantiene trazabilidad/comprobantes y lo retira del saldo. Reintentar una solicitud no duplica el ingreso.
- La hoja privada **Control de abonos JAC**, de la conexión de `jacmusicestudios@gmail.com`, recibe show/municipio, fecha del show, fecha/valor del abono, enlace directo al comprobante y estado. El enlace abre la imagen/PDF con autorización, no el panel del CRM; no convertirlo en público.
- Primero se guarda en JAC; si Sheets falla, queda pendiente de sincronización/reintento sin perder ni duplicar el abono. No borrar/reordenar físicamente las filas usadas por la sincronización.

### Crear o eliminar un show

**Nuevo show** desde CRM permite nombre, **un día del evento**, hora/lugar/descripción compartida, valor, empresario, notas privadas y primer abono opcional con comprobante. No pedir días de inicio y fin distintos para un show de un día.

A Calendar solo se envían nombre, fecha/hora, lugar y descripción compartida. Precio, abonos, comprobantes y datos financieros quedan privados en CRM. Agenda web/iPhone/iPad/Mac los ve a través de la misma conexión. Los reintentos conservan IDs; si un paso posterior falla, no crear otro evento para completar el abono.

Eliminar desde CRM elimina el evento correspondiente en Calendar y lo retira del listado activo. Una cancelación confirmada en Calendar también se refleja al actualizar JAC. Que no aparezca en una página, cambie de mes o falle la red no prueba que se haya eliminado. **Se conservan abonos, comprobantes, hoja, auditoría, contratos e historial de nómina**; no purgarlos por borrar la fecha. Una copia offline conoce la eliminación al revalidar.

Al crear una quincena se traen los shows elegibles con precio y fecha del periodo, promoción y relación al CRM. La nómina conserva su propia copia y permite revisión; los kilómetros iniciales requieren completar. Editar luego el precio en CRM no debe reescribir quincenas existentes/cerradas. Vincular un show manual antiguo exige selección expresa, no una unión financiera solo por nombre parecido.

### Otras herramientas del CRM ya existentes

- **Empresarios:** ficha reutilizable con contacto, empresa, ciudad, notas y documentos privados. En el formulario se escribe el nombre y se autocompleta desde fichas guardadas. No restaurar el selector «Sin ficha vinculada» encima de un campo separado. Se permite texto libre; editar el nombre puede retirar la asociación anterior. Cambiar una ficha no reescribe silenciosamente textos históricos.
- **Rentabilidad:** compara presupuesto por rubros con costos reales vinculados a nómina. Un presupuesto no es un gasto ejecutado ni genera pagos. Mantener diferencias visibles entre precio comercial y precio guardado en nómina.
- **Preparación:** contrato firmado, hotel, transporte e itinerario, con pendiente/listo/no aplica, responsable, plazo, nota y tareas adicionales. Abonos recibidos se calculan desde los pagos; no se rellenan creando un pago ficticio. No reservar hoteles ni enviar avisos por marcar una tarea.
- **Resumen semanal:** lunes a domingo en Colombia; shows, saldos, abonos recibidos, costos/gastos y tareas pendientes. Distinguir fecha del show de fecha del abono/gasto. No tratar un precio/costo faltante como cero confirmado.
- **Contratos:** archivo y generador descritos más abajo.

No volver a mostrar el aviso rutinario «Shows de Calendar revisados. Guarda el precio…»: Camilo pidió retirarlo.

Referencia: [CRM_SHOWS_ABONOS.md](../docs/CRM_SHOWS_ABONOS.md).

## 6. Agenda: calendario compartido y lectura inmediata

La fuente es el Google Calendar conectado de `jacmusicestudios@gmail.com`; Camilo autoriza y selecciona el calendario. No crear otra agenda ni cambiar el calendario conectado para resolver una vista. Consulta y edición son permisos distintos; preservar la política existente y las guardas ETag/concurrencia.

- Mostrar inmediatamente la última agenda autorizada descargada mientras se actualiza por red. No vaciar la vista ni cerrar sesión por red lenta.
- Web precarga el mes actual y cinco posteriores; revalida el visible y actualiza al volver/reconectar. Esto no es una conexión streaming ni garantiza abrir toda la web offline desde cero.
- La app nativa puede reabrirse sin internet con sesión persistente y consultar su copia. Escribir/editar requiere conexión y permisos vigentes; no hay cola genérica de ediciones Calendar offline.
- No reintroducir «Mostrando última agenda, actualizando», «Última descarga…», el botón superior «Actualizar agenda» ni «Eventos Jhon Alex Castaño» encima del calendario que Camilo pidió quitar.
- El área seleccionable de una fecha abarca el botón completo. Mantener las correcciones del detalle/retorno de segundo plano; no ocultar crashes retirando comprobaciones o privacidad.

Referencias: [WEB_AGENDA_CACHE.md](../docs/WEB_AGENDA_CACHE.md), [IOS_AGENDA_EVENT_DETAIL_LAYOUT.md](../docs/IOS_AGENDA_EVENT_DETAIL_LAYOUT.md), [IOS_REGRESO_SEGUNDO_PLANO.md](../docs/IOS_REGRESO_SEGUNDO_PLANO.md).

## 7. Alertas e itinerarios: contenido, recepción y avisos

**Alertas** está en Gestión/configuración. El creador administrativo permite Alerta, Itinerario o Pase de abordar; PDF e imágenes se adjuntan desde ahí. Una alerta manual respeta sus destinatarios. Un itinerario se comparte con las cuentas que tienen el módulo permitido; un pase siempre es individual.

Los itinerarios nuevos también llegan desde **Slack JAC Music → #itinerarios-finales**. Solo PDF nuevos del canal configurado: no texto, otros canales ni historial. No reinstalar otra app Slack para empezar Cloud: la conexión existente ya está configurada.

- Itinerarios muestra los itinerarios y el apartado privado de pases. Quitar controles de conexión/notificaciones de ese panel fue intencional: viven en **Servicios conectados** y **Notificaciones** dentro de configuración.
- Abrir un aviso marca lectura; **Confirmar recibido** es una acción expresa y distinta. Pertenece al usuario y a la versión; el administrador puede ver recibidos/pendientes, sin ganar lectura de pases ajenos.
- Actualizar itinerario requiere resumen de cambios y versión completa de adjuntos. Conserva identidad/destinatarios, incrementa versión y exige nueva confirmación; no edita el original en Slack.
- Eliminar requiere confirmación y permisos. Retira el contenido de JAC y las entregas pendientes; el original Slack se conserva. No se pueden retirar avisos que el sistema operativo ya recibió.
- Mantener adjuntos separados y espaciados, papeleras discretas y confirmaciones breves; no restaurar botones grandes invasivos.

**Texto push acordado:** itinerario nuevo Slack: título `JAC`, cuerpo `Ya llegó tu itinerario para el día de hoy`. Alerta manual: su título y descripción, con recorte si el proveedor limita tamaño. Itinerario actualizado: `JAC · Itinerario actualizado` y resumen. Los pases mantienen protección de su información privada.

La web ofrece el permiso tras iniciar sesión y registra el navegador si ya lo tiene. Algunos navegadores requieren un gesto explícito; no se puede forzar el permiso del sistema. Las preferencias son propias de cada navegador/dispositivo y una desactivación voluntaria se conserva. Safari/Chrome pueden presentar avisos distintos según versión del service worker y ajustes de macOS; no prometer prioridad ni recepción por abrir sesión en otro navegador.

**APNs nativo sigue suspendido (`JAC_PUSH_ENABLED=NO`)** mientras Apple no habilite el equipo y Camilo no pida reactivarlo. No añadir entitlements push para resolver otro cambio. El permiso web no habilita APNs.

Referencias: [ITINERARIES_PUSH_SETUP.md](../docs/ITINERARIES_PUSH_SETUP.md), [TRAVEL_WORKFLOWS.md](../docs/TRAVEL_WORKFLOWS.md). Sus primeras instrucciones de configuración/push contienen historia: prevalecen las decisiones posteriores resumidas aquí y el código actual.

## 8. Pases de abordar y código para escanear

Son documentos individuales, importados de canales configurados por persona (`#pases-camilo`, `#pases-jhon-alex`, `#pases-alex`) o publicados manualmente eligiendo destinatario. Una configuración histórica de canal no concede acceso a una cuenta que hoy tenga Pases revocado.

- Nombre esperado, por ejemplo: **`Camilo 16 de octubre Pereira-Bogota.pdf`**. Persona, fecha y ruta origen-destino se interpretan para mostrarlo. El **canal configurado decide el destinatario**, no el nombre; un nombre incompatible no redirige el pase a otra cuenta.
- Hoy, **mañana**, próximos días cronológicos e historial plegado. Si hoy está vacío, dar prioridad a mañana. Los anteriores pasan al historial al comenzar el siguiente día en **America/Bogota**, sin borrarse automáticamente.
- Abrir lleva directamente al PDF/imagen, sin una página intermedia con otro botón Abrir.
- El borrado permitido a administradores se limita a **sus propios pases**, nunca los ajenos. En web papelera discreta; en iPhone pulsación larga o deslizar a la izquierda, luego confirmación. No borrar por deslizamiento completo sin preguntar.
- Confirmación breve: «¿Estás seguro de que quieres eliminar este pase de abordar?». Una publicación con varios adjuntos se elimina como conjunto.
- **Mostrar código**, nativo: detecta y recorta el código original QR/PDF417/Aztec/Data Matrix, sin recrear su contenido. Pantalla completa blanca en iPhone/iPad, brillo 100% solo mientras esté activo; restaurarlo al cerrar o ir a segundo plano. Selector si hay varios códigos y opción del documento completo si no se detecta.
- Mac muestra el código en hoja nativa sin cambiar brillo. Los archivos ya descargados permiten esta lectura offline con la misma privacidad.
- **Apple Wallet está aplazado por decisión expresa de Camilo.** No crear pases Wallet ni regenerar códigos como parte de otra mejora. Mostrar código todavía no es un visor web equivalente.

Referencias: [BOARDING_PASSES.md](../docs/BOARDING_PASSES.md), [BOARDING_CODE.md](../docs/BOARDING_CODE.md). Los perfiles antiguos de Alex/Jhon Alex de esas guías están sustituidos por el apartado 3.

## 9. Gastos de viaje y OCR de facturas

Gestión → Gastos de viaje permite al usuario con acceso registrar concepto, fecha, COP, nota y comprobantes privados; comienza pendiente. El autor y los administradores pueden consultarlo. No exponer gastos de otras personas a usuarios normales.

El administrador rechaza con motivo o **Aprueba e incorpora** eligiendo persona y quincena abierta. Solo esta acción crea un movimiento de reintegro, con ID estable y una única incorporación. Registrar una factura no cierra quincena, no paga automáticamente, no manda correo y no crea por sí mismo un costo directo de show.

El OCR del iPhone usa Vision **local**, propone datos y permite corregir antes de enviar. Fecha: la primera válida en orden visual de arriba hacia abajo, izquierda a derecha si están en la misma línea, con su propia hora cuando exista. Categoría sugerida desde el contenido. Concepto: encabezado/nombre del comercio o letras de su logo; no identificar un símbolo sin texto inventando una marca. No confundir IVA/subtotal/cambio con total. Borrador cifrado disponible offline, pero envío manual al reconectar; no es una cola automática.

Referencia: [TRAVEL_WORKFLOWS.md](../docs/TRAVEL_WORKFLOWS.md).

## 10. Fotografía: biblioteca R2, subida, visor y descargas

**Estado actual: R2 privado `jac-fotografia`, colección nueva independiente.** Camilo ordenó empezar desde cero y retirar Drive de esta sección: no inventariar, migrar, copiar, borrar ni volver a conectar fotos antiguas de Drive. Esta decisión **no elimina Google Calendar, Gmail ni Sheets** del resto de JAC.

### Carpetas y visualización

- Carpetas por show/día de trabajo con **el nombre exacto que escribe el usuario**. No añadir fecha automáticamente ni renombrar las existentes.
- Más recientes primero, por **fecha de creación descendente**, no última modificación.
- iPhone: vista simple de carpetas desplegables, archivos dentro de la misma pantalla, sin encabezados repetidos de Fotografía/nombre de show. El botón Subir aparece desde el permiso conocido al entrar; no esperar el feed ni mostrar «Verificando acceso». El servidor sigue validando cada operación.
- Estabilidad solicitada el 19 de octubre: las miniaturas y el contenido no deben desaparecer al desplazarse, esperar en la carpeta o actualizar su caché. Conservar el orden y todas las páginas ya visibles durante la revalidación. Un archivo nuevo, eliminado o cambiado sí puede actualizar la lista autorizada. No invalidar toda la galería por una miniatura pendiente; ver `../docs/IPHONE_GALLERY_SCROLL.md`.
- Web, Mac e iPad conservan sus distribuciones adaptadas; no trasladar mecánicamente un modal iPhone a un formulario Mac enorme o recortado. Fotografía pertenece a la navegación principal nativa; Mi cuenta está en Gestión/configuración.
- Miniaturas privadas independientes, pequeñas (JPEG hasta 640 px y 512 KiB), para elegir qué abrir. No descargar originales de 8–15 MB para dibujar cada celda ni usarlos como fallback de miniatura.
- Visor iPhone a pantalla completa, pasar deslizando, zoom y precarga acotada. Si la siguiente foto aún no está, mostrar su pantalla con círculo de progreso. Mantener caché privada para no volver a bajar una foto visitada al retroceder.
- Web/Mac mantienen botones/teclado; videos con reproductor. Las páginas de archivos de una carpeta forman un recorrido, no un slideshow limitado a la primera página.

### Subida y calidad

Subir desde la raíz ofrece **nombre de nueva carpeta + selección de fotos/videos en el mismo menú**; desde una carpeta se conserva ese destino. Formatos de trabajo: JPEG/HEIC y MP4/MOV. No se pidió un flujo RAW.

En ajustes/menú se elige **hasta 2 MB, 4 MB, 6 MB o Sin compresión** para imágenes. Preferencia local del dispositivo/navegador, inicial 2 MB. Son máximos en MB decimales, no tamaños exactos ni una calidad global compartida.

- Imagen por debajo del límite: conservarla. Si necesita reducción, prepararla antes del envío y usar JPG/extensión coherente cuando se recodifica. El original de la cámara/disco queda intacto.
- **Sin compresión** conserva bytes del archivo. **Los videos siempre se suben originales**, cualquiera que sea el ajuste. No comprimir videos por extensión del cambio de imágenes.
- Las miniaturas son independientes, incluso con originales sin compresión. La compatibilidad HEIC depende del códec del cliente; no prometer decodificación universal en navegador.
- Los bytes se suben directamente a R2 mediante capacidades S3 firmadas y temporales. El Worker conserva autorización, preparación, confirmación y metadatos; no entregar claves R2 a clientes ni afirmar que no existe ninguna llamada al servidor.
- Concurrencia limitada y preparación/miniaturas separadas reducen pausas entre archivos. Mantener **círculo de progreso global y velocidad de subida reciente**, no una barra invasiva por archivo. No prometer una velocidad que no se haya medido.
- iPhone: cola cifrada persistente y `URLSession` en segundo plano desde archivos. Salir a otra pantalla/Home no cancela por sí mismo la cola. Si el usuario fuerza el cierre de iOS, puede requerir reabrir para retomarla; no prometer transferencias perpetuas.

### Descargar, guardar y eliminar

**Selección múltiple en iPhone, 18 de octubre:** mantener presionada una foto o un video inicia la selección; después se agregan/retiran elementos tocándolos, incluso entre carpetas desplegadas. La barra inferior muestra cantidad, **Descargar → Guardar en Fotos / Guardar sin conexión** y borrado administrativo con confirmación. Incluye únicamente lo seleccionado, conserva originales y carpetas, muestra progreso/fallos y permite detener pendientes. No es una eliminación atómica de todo el lote. Cancelar selección vuelve a la apertura normal. Véase [selección múltiple](../docs/IPHONE_PHOTOGRAPHY_SELECTION.md). Después de la pausa por cuota, Camilo pidió publicar la fuente y reanudar las pruebas online. El workflow solo ejecuta runners si GitHub confirma el repositorio público; ver [estado de Actions](../docs/PUBLIC_REPOSITORY_ACTIONS.md). Run en el Mac sigue siendo necesario para instalar. La API necesaria ya está publicada en el Worker propio desde el19 de octubre, con la autorización automática posterior de Camilo. La verificación online ya aprobó Release iPhone/Mac,156 unitarias y tres UI; una comprobación de protección física se omite en simulador. La instalación física sigue mediante Run en el mismo Xcode.

Actualización del 18 de octubre: cada **foto individual** tiene opciones para descargar el original, guardarla sin conexión en ese dispositivo/navegador y eliminarla con confirmación administrativa. El borrado conserva carpeta y otras fotos; el permiso de subida no concede eliminación. Las apps fijan la foto en su copia cifrada; la web agrega una vista de fotos guardadas que puede reabrirse sin internet. Las acciones de carpetas descritas abajo se conservan. Véase [acciones individuales](../docs/PHOTOGRAPHY_INDIVIDUAL_PHOTOS.md) para límites y verificaciones. Web/API publicado el19 de octubre con la selección múltiple; verificación Apple manual mediante pull y el mismo Xcode, con Actions suspendido por cuota.

En el menú contextual/selección de carpeta, sin botones grandes permanentes:

- **Disponible sin conexión:** descarga a la caché privada de JAC para consultar allí; separada por sesión y protegida.
- **Guardar en Fotos:** exporta las fotos/videos a la fototeca del teléfono, con permiso del sistema, progreso, espacio y cancelación. No basta con obtener un plan de descarga sin ejecutar las transferencias.
- **Eliminar carpeta:** función administrativa con confirmación, incluyendo su contenido y controles de subidas pendientes; la raíz está protegida. Tener permiso de subida no concede borrado administrativo.

Conservar pertenencia/revisión/autorización de cada archivo. Una denegación confirmada no debe mostrar una copia retirada por fallback. No borrar carpetas o subir lotes reales para verificar un cambio.

Referencias: [PHOTOGRAPHY_R2_MIGRATION.md](../docs/PHOTOGRAPHY_R2_MIGRATION.md), [PHOTOGRAPHY_UX.md](../docs/PHOTOGRAPHY_UX.md), [PHOTOGRAPHY_VIEWER_QUALITY.md](../docs/PHOTOGRAPHY_VIEWER_QUALITY.md), [IPHONE_PHOTOGRAPHY_SIMPLE.md](../docs/IPHONE_PHOTOGRAPHY_SIMPLE.md), [IPHONE_PHOTO_VIEWER.md](../docs/IPHONE_PHOTO_VIEWER.md), [IPHONE_BACKGROUND_UPLOADS.md](../docs/IPHONE_BACKGROUND_UPLOADS.md), [PHOTOGRAPHY_FOLDER_DELETE.md](../docs/PHOTOGRAPHY_FOLDER_DELETE.md).

## 11. Contratos y extracción de RUT

CRM → **Contratos**, para administradores. Generador, archivo de contratos guardados, apertura, asociación a un show existente y borrado manual están incorporados en web y apps nativas.

- Primera opción **Subir RUT**; extrae razón social, NIT/DV y representante legal principal con cédula. Todos los campos quedan editables; también se puede diligenciar todo manualmente sin RUT.
- RUT se interpreta localmente: no subirlo, almacenarlo ni usar sus datos como fixture real. Un PDF escaneado sin texto no tiene OCR genérico implementado. Si hay varios principales o datos incompletos, pedir revisar/seleccionar, no usar contador, socios o solicitante como representante.
- Completar manualmente fecha/hora, sitio, municipio/departamento, precio, consignado y fecha para completar el primer 50%.
- Mantener **exactamente la plantilla aprobada de cuatro páginas**, cláusulas, logo, pie y firma de Jhon Alex/JAC. El bloque del contratante se rellena desde sus datos. No rediseñar ni reescribir texto jurídico por iniciativa propia.
- COP en números → letras según el formato. Pago final **50% del precio**, cinco días calendario antes del show; no confundir con total menos cualquier abono. El resumen también calcula cuánto falta para el primer 50%. El abono inicial de esta plantilla no supera el 50% y su plazo no va después del pago final.
- Nombre: **`Contrato JAC - Soracá - 31 de octubre 2026.pdf`**. Fecha con día/año numéricos y mes en letras, no todos los números escritos en palabras.
- Las versiones actuales guardan automáticamente el PDF privado inmutable. Los contratos descargados antes del archivo no se recuperan solos porque no se habían almacenado.
- Se puede asignar/cambiar/quitar asociación a un show, incluido histórico. No reescribe el PDF, no marca firma, no crea precio/abono/Calendar. Si se elimina el show, conservar contrato.
- Papelera discreta y confirmación «¿Estás seguro de que quieres eliminar este contrato?». Retira contrato/PDF y sus copias privadas de JAC, sin borrar show ni abonos. Crear/asignar/eliminar requiere red; abrir offline necesita haber descargado antes ese PDF.

Almacenamiento: metadatos/instantánea en D1 y PDF bajo `crm/contracts/` en **`jac-documentos`**, no `jac-fotografia`. No enviar contratos/RUT a un servicio de IA externo.

Referencia: [CONTRACTS.md](../docs/CONTRACTS.md), leyendo primero sus apartados recientes de archivo/borrado. Los párrafos originales «sin escrituras D1/R2» describen el generador inicial, sustituido por el archivo actual.

## 12. Sesión, offline y diseño: decisiones transversales

- «Mantener sesión iniciada» en nativo conserva sesión en Llavero y última copia autorizada al cerrar/reabrir o perder internet. Una cancelación, timeout o fallo de red **no equivale a credenciales inválidas**. No expulsar al usuario por no poder consultar el servidor.
- Mantener revocación real, cambios de cuenta/permiso y cierre manual. Retirar solo datos autorizadamente revocados y proteger caché/temporales; no usar fallback de datos privados ante 403.
- Offline significa última información descargada, incluidos documentos descargados, no archivos jamás recibidos ni actualización en vivo sin señal. No crear una cola general de operaciones financieras offline. Fotografía tiene su cola de subida específica.
- El aviso automático grande «Sin conexión» al arrancar fue retirado. El estado nativo se muestra con icono superior: gris comprobando, azul conectado, tachado sin conexión. Conservar errores accionables, como un archivo que nunca se descargó.
- Conservar cubierta de privacidad al ir a segundo plano, cifrado, sesión por origen/usuario y protección de archivos. No desactivarlos para corregir navegación o mejorar velocidad.
- Identidad visual **azul JAC Music**, elegante y sobria, con el logo anterior aprobado. El cambio experimental a isotipo fue rechazado. Los ajustes de navegación no deben quitar módulos ni convertir una app nativa en un navegador de páginas externas.
- Web tiene rutas independientes por sección. Usar las existentes: `/`, `/agenda`, `/itinerarios`, `/fotografia`, `/crm`, `/alertas`, `/gastos-de-viaje`, `/configuracion`, `/mi-cuenta`; Contratos en `/crm?seccion=contratos`.
- iPhone/iPad comparten la app universal `co.jacmusic.nomina`; Mac `co.jacmusic.nomina.mac` reutiliza fuentes Swift. Mantener proyectos existentes, firma personal local y push suspendido. No pedir descargar otro proyecto para cada cambio.

Referencias: [CONNECTION_STATUS.md](../docs/CONNECTION_STATUS.md), [SECTION_ACCESS.md](../docs/SECTION_ACCESS.md), [WEB_URLS.md](../docs/WEB_URLS.md), [IPAD_APP.md](../docs/IPAD_APP.md), [MAC_NATIVE.md](../docs/MAC_NATIVE.md).

## 13. Dónde está cada parte y qué revisar

| Área | Entradas principales de código | Guías/pruebas de referencia |
| --- | --- | --- |
| Navegación, permisos, nómina | `app/payroll-app.tsx`, `lib/payroll-navigation.ts`, `lib/payroll-permissions.ts`, `lib/payroll.ts`, `app/show-costs.tsx` | `tests/payroll*.test.mjs`, especialmente comisión, autenticación y móvil; `tests/section-access.test.mjs` |
| Agenda | `app/agenda-panel.tsx`, `lib/calendar*.ts`, `lib/agenda-cache.ts`, `lib/agenda-prefetch.ts` | `tests/calendar.test.mjs`, `tests/calendar-worker.test.mjs`, `tests/agenda-cache.test.mjs` |
| CRM/abonos/Sheets | `app/crm-panel.tsx`, `app/crm-workspace.tsx`, `app/crm-contact-input.tsx`, `lib/crm*.ts` | `tests/crm*.test.mjs`, incluidos archivos, workspace y Workerd |
| Contratos/RUT | `app/crm-contract-*.tsx`, `lib/contract-*.ts`, `lib/rut-*.ts` | `tests/contracts*.test.mjs`, `tests/rut*.test.mjs` |
| Avisos/pases/gastos de viaje | `lib/notifications.ts`, `lib/notifications-core.ts`, `lib/travel-expenses.ts`, `app/travel-expenses-panel.tsx` | `tests/notifications*.test.mjs`, rutas móviles y fixtures nativos |
| Fotografía actual | `app/media-panel.tsx`, `lib/media-r2*.ts`, `lib/media-upload*.ts`, `lib/media-image*.ts` | `tests/media*.test.mjs`; los de Drive son regresión histórica, no autorización para reactivarlo |
| Nativo compartido | `ios/JACNomina/PayrollClient.swift`, `SessionStore.swift`, `CalendarView.swift`, `CRMView.swift`, `NoticesView.swift`, `DocumentsView.swift`, `ExpenseReceipt.swift`, `Media*.swift` | `ios/README.md`, pruebas nativas y fixtures `.invalid` |
| Mac | `macos/JACMac/MacWorkspaceViews.swift`, `MacPlatform.swift`, fuentes compartidas iOS | `macos/README.md`, pruebas Mac |
| Producción y despliegue | `deploy/cloudflare/wrangler.json`, `worker/cloudflare.ts` | `docs/CLOUDFLARE_MIGRATION.md`, `tests/cloudflare-deployment.test.mjs` |

Esta tabla orienta, no sustituye leer la implementación/rutas/pruebas del cambio. No ejecutar todas las suites por un ajuste visual mínimo. Elegir las afectadas y las obligatorias de AGENTS; pruebas con D1 local desechable, fakes y `.invalid`, nunca servicios/datos reales de producción.

## 14. Instrucciones para continuar sin reconstruir la conversación

1. Leer esta guía y las reglas actuales antes de proponer algo que ya existe. Para «fotos», ir a la galería R2; para «abono», al CRM; para «gastos», usar el contexto show frente a reintegro y aclarar solo si sigue siendo ambiguo.
2. Las decisiones posteriores de Camilo prevalecen sobre esta fecha. Si el código discrepa con una decisión, informar la diferencia y resolverla con evidencia; no declarar implementado algo solo porque esté documentado.
3. No volver a preguntar por decisiones ya fijadas: comisión 5%, promoción, corte Colombia, permisos recientes, R2 sin Drive, nombre del contrato, Wallet aplazado, push suspendido o mismo proyecto Xcode.
4. Mantener web/API y nativos coherentes cuando se pide «todo el ecosistema», con presentación apropiada a cada dispositivo y sin duplicar fórmulas financieras en Swift.
5. Actualizar esta guía al cambiar un flujo, permiso de referencia o decisión. Registrar verificaciones en la documentación técnica sin confundir un build web con un binario nativo instalado.
6. Trabajo desde un único chat Codex Cloud + GitHub privado. Después de agotar los minutos privados, Camilo hizo público el repositorio y pidió retomar Actions. GitHub confirmó la visibilidad pública y las pruebas online se reanudaron automáticamente; el workflow solo ejecuta runners estándar en repositorio público. Mantener la fuente en main, comprobar los resultados y conservar Run en el mismo Xcode para instalar físicamente. Las publicaciones web/API necesarias siguen autorizadas, sin nuevas confirmaciones rutinarias; la API de esta entrega ya está publicada. No configurar control remoto, SSH/VPN ni PR. El acceso GitHub no transfiere accesos Cloudflare ni sesiones.
7. Producción está en **Cloudflare propio, Worker `jac-nomina`**, D1 `jac-nomina`, documentos en `jac-documentos`, fotos/videos en `jac-fotografia`. No volver a Sites, repetir migraciones de traslado, inicializar datos, crear buckets sustitutos ni cambiar DNS.
8. No subir credenciales, bases reales, comprobantes, contratos generados, RUT, fotos privadas, Llavero o firma personal al repo. No enviar correos/push/Slack/Calendar ni borrar registros reales como pruebas.

Preparación y accesos: [README.md](README.md) y [PROMPT-PARA-EL-NUEVO-CHAT.txt](PROMPT-PARA-EL-NUEVO-CHAT.txt). El nuevo chat debe leerlos desde el repositorio; **esta conversación no se transfiere automáticamente**.
