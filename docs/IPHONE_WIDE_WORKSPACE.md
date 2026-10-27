# Pantalla horizontal y apertura directa de itinerarios

Camilo aprobó las cinco maquetas de Agenda, Fotografía, Pases, Música y CRM y pidió aplicarlas, además de abrir el PDF del itinerario directamente al tocar su ficha. La adaptación depende del espacio útil de la ventana, no de un nombre de dispositivo ni de dimensiones supuestas de iPhone Duo.

## Distribución

- En iPhone, ancho útil mínimo740pt, alto mínimo300pt y ancho mayor que alto activan la distribución amplia. El menú compacto ocupa80pt; el resto se reparte entre dos paneles. Dynamic Type de accesibilidad mantiene una columna y el menú desplegable. Las áreas seguras quedan fuera de la medición.
- El contenedor de las secciones visitadas conserva su identidad al girar. La barra lateral compacta ofrece Agenda, Pases o Itinerarios según permisos, Fotos, Música y Más; Más conserva CRM, Quincenas, Itinerarios, Alertas y Gestión cuando correspondan. El avatar abre Gestión. En vertical sigue el menú y gesto de borde existentes.
- Agenda mantiene el mes y la selección a la izquierda y los eventos del día a la derecha. Una ficha despliega sus datos dentro del panel, con acceso al detalle completo y edición existente.
- Fotografía conserva carpetas/cuadrícula a la izquierda y muestra el visor existente a la derecha. Incluye ampliación, miniaturas que cambian la foto durante el arrastre, zoom, guardado directo, calidad/caché adaptativa y salida vertical. Las secciones ocultas detienen el trabajo de la vista previa; no acceden al Llavero durante el dibujo. Selección múltiple, descargas y subidas conservan sus controladores.
- Pases mantiene tarjetas con silla/salida/en sala/código y su menú Wallet, junto al documento original. No se recrean pases, códigos, aerolíneas o datos ausentes.
- Música mantiene las cuatro playlists junto a sus pistas y el reproductor existente. Búsqueda, permisos, importación y descargas siguen usando las funciones reales; no se inventan duraciones ni historial.
- CRM mantiene el listado de shows junto a Cuenta/Rentabilidad/Preparación del seleccionado, usando los mismos formularios y datos del servidor. Las consultas se pausan al ocultar la sección. No incorpora importes ni contactos de las maquetas.

## Itinerarios

Tocar una ficha con PDF abre el primer PDF directamente. En vertical se presenta el documento; en horizontal aparece junto al listado. Ampliar y girar reutilizan el documento temporal ya abierto. El menú ofrece Información y confirmación, otros adjuntos y Compartir; las confirmaciones explícitas, actualización y borrado administrativo permanecen en la ficha informativa. Los itinerarios sin PDF y las alertas mantienen sus detalles.

Los documentos históricos sin `attachments` conservan `/api/notices/pdf`; los adjuntos modernos conservan `/api/notices/file`. El panel está vinculado al destinatario, sesión, archivo y revisión actuales; revalida antes/después de obtener bytes y retira el temporal ante cambio de autorización/revisión o cierre. Leer no confirma recepción automáticamente. Las notificaciones que abren un itinerario aplican la misma apertura directa.

## Entrega y comprobaciones

App/widget0.39.0, build fuente58. Se conserva Team AYHVYN8BJF, bundle IDs, AppGroup, APNs por entorno, orientación universal y declaración de cifrado exento. Xcode Cloud puede asignar un número de distribución distinto. No se requiere despliegue web/API, migración ni cambiar servicios o cuentas reales.

El scope `wide-workspace` comprueba seis recorridos nuevos de las cinco secciones y rotación/apertura de itinerario, lector sin permisos administrativos, navegación vertical, confirmación/actualización explícita y cuatro regresiones del visor completo: trece UI seleccionadas. Incluye identidad privada del documento,250 revalidaciones calientes sin I/O/cripto/JSON/Llavero en la interfaz, pausa/reanudación sin revivir una sesión revocada, modelo/tira existentes y las seis guardas de fluidez. Release iPhone/widget y Mac comprueban las fuentes compartidas. Capturas y pruebas usan únicamente fixtures `.invalid` sin notificaciones, archivos o datos de producción.

Estado inicial: implementación terminada; compilaciones, ejecución de las pruebas y capturas nativas pendientes de verificar en el SHA final. La revisión de sintaxis local no equivale a compilar Swift/UIKit. Registrar aquí los resultados reales antes de anunciar validación o distribución física.
