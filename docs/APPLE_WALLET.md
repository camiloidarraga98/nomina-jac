# Apple Wallet · pases privados de JAC

Camilo pidió retomar Wallet tras activar Apple Developer de pago. Confirmó la instalación inalámbrica de JAC mediante TestFlight y la recepción de notificaciones en su iPhone. Wallet usa un certificado distinto de la clave APNs; ninguna credencial privada se recibe por chat o se guarda en Git.

## Conexión privada

El Team ID confirmado es `AYHVYN8BJF`. La captura de Apple Developer del23 de octubre muestra que **Apple Wallet → `pass.co.jacmusic.nomina` ya pertenece a la cuenta**. Usar ese identificador original. También existe otro registrado como Pases JAC; no hay que eliminarlo ni cambiar el bundle de la app `co.jacmusic.nomina`.

1. En Apple Developer → Certificates, Identifiers & Profiles → Identifiers, abrir **Apple Wallet**, identificador `pass.co.jacmusic.nomina`, y crear su certificado.
2. En el mismo Mac, crear el CSR desde Acceso a Llaveros → Asistente de Certificados → Solicitar un certificado de una autoridad de certificación → Guardar en disco. Conservar la clave privada que genera.
3. Subir el CSR a Apple, descargar el `.cer` e importarlo en el **mismo llavero que la clave privada**. Si la clave Pases JAC está en Inicio de sesión y el certificado se instaló en Sistema, importar también el `.cer` en Inicio de sesión. En Mis certificados debe poder desplegarse la clave privada debajo del certificado Pass Type ID.
4. Exportar ese certificado junto con su clave privada como **Personal Information Exchange `.p12`**, con una contraseña. Un `.cer` solo o una clave sin certificado no bastan.
5. Descargar el intermedio público [Apple WWDR G4](https://www.apple.com/certificateauthority/AppleWWDRCAG4.cer). No cambiar la confianza del Llavero a «Confiar siempre» para resolver errores.
6. En JAC web, como administrador autorizado de conexiones, abrir **Configuración general → Servicios conectados → Apple Wallet**. Introducir Team ID, Pass Type ID, archivo `.p12`, contraseña y WWDR G4; guardar desde este formulario HTTPS privado. Límite `.p12`64KiB e intermedio16KiB.

Camilo confirmó el23 de octubre que guardó la conexión desde el panel privado publicado. No se leyó ni copió su certificado o contraseña desde herramientas/chat. Camilo confirmó la subida correcta de0.28.0(42) a Apple desde Organizer; el build41 quedó rechazado y sustituido por42. La modificación posterior de menú/datos requiere0.29.0(43), descrita abajo; no se declara comprobación física de Wallet solo por la subida.

El formulario solo devuelve estado, versión, identificador y vencimiento. La contraseña y el PKCS#12 se usan para normalizar el certificado/clave; no se persisten. La clave normalizada se cifra en el almacén de conexiones ya existente, conservando APNs, Slack y Web Push. No se necesitan nuevas tablas, bindings o secretos Cloudflare. Guardar con una versión antigua devuelve conflicto y exige releer; nunca reintenta la escritura automáticamente.

La validación comprueba la clave correspondiente, identificador y Team del certificado, vencimiento y cadena de firma WWDR G4 → raíz Apple. La raíz pública se fija en el código; su SHA256 DER es `b0b1730ecbc7ff4505142c49f1295e6eda6bcaed7e2c68c5be91b5a11001f024`, publicada por Apple. No se descarga una raíz en cada petición ni se admite una raíz enviada por el usuario.

## Uso en iPhone

Desde **Pases → menú ⋯ de cada archivo → Añadir a Apple Wallet**, JAC abre una pantalla de preparación propia. También ofrece la acción en el menú contextual de ese pase. **Mostrar código** conserva únicamente el código original y Abrir pase completo; ya no consulta ni genera Wallet.

La preparación lee el documento privado, detecta sus códigos y permite elegir explícitamente uno si hay varios. Para un BCBP con varios tramos exige escoger el tramo. Revisa seis campos editables: **pasajero, origen, destino, hora del vuelo, hora en sala y silla**. Las sugerencias de pasajero/ruta/silla vienen del tramo válido del código; las horas solo de etiquetas claras del PDF o de OCR acotado en el dispositivo. Los datos ambiguos/no detectados quedan vacíos para completarlos o dejarlos ausentes. No confundir hora de llegada, número de puerta o fecha con las horas pedidas.

El botón oficial de Apple firma después de una acción expresa y presenta su controlador nativo. La extracción no genera un pase automáticamente. Los campos vacíos confirmados se omiten sin reponer sugerencias del servidor. Las horas se muestran como HH:mm locales del documento, sin fabricar zona horaria, UTC o una fecha relevante. No se usa el nombre del perfil JAC como nombre del pasajero. Se necesita0.29.0(43) para este nuevo flujo.

Solo se trasladan QR, PDF417 o Aztec cuyo contenido leído sea ASCII exacto y tenga estructura inicial IATA BCBP compatible. Data Matrix, mensajes binarios/no ASCII, URL y códigos desconocidos conservan el visor y el documento original. No se inventa un código ni se transforma uno desconocido para hacerlo compatible.

La lectura del código ocurre con Vision en el dispositivo. La API valida los datos confirmados como presentación y verifica el destinatario, archivo privado, revisión y SHA256 del mismo original analizado; **no vuelve a decodificar independientemente el código desde el PDF**. Este es el límite de confianza del cliente autenticado. El mensaje exacto viaja al servidor y al pase sin recortes ni normalización de espacios.

El servidor firma un `.pkpass` en memoria, sin URL pública ni copia adicional persistente. Se limita el original a10MiB y el paquete a1MiB. Revalida sesión/permiso, destinatario, revisión/adjunto y versión de la conexión antes de liberar el resultado; el cliente descarta resultados tardíos de otra sesión o revisión. La respuesta privada no se cachea. No existe fallback de generación offline ni tras un403.

El pase es una **copia firmada por JAC**, no un documento emitido por la aerolínea. No garantiza aceptación en el aeropuerto; conservar siempre el original. Se usan únicamente metadatos disponibles, sin fabricar número de vuelo, puerta u hora. Wallet conserva sus propias copias: cerrar sesión, borrar el original o revocar permisos en JAC no elimina un pase ya añadido a Wallet. Esta primera integración no registra actualizaciones automáticas de pases ni su servicio APNs.

Presentar `PKAddPassesViewController` no requiere habilitar gestión de `PKPassLibrary`, App Groups o Associated Domains. iPad/Mac conservan sus funciones existentes si Wallet no está disponible. La conexión web administra el firmante; no convierte Mostrar código en un visor web nuevo.

## Verificación y publicación

Pruebas focales con cadenas/certificados sintéticos, originales ficticios y D1/R2/Workerd desechables. Sin claves personales, pases de pasajeros, servicios de aerolíneas ni envío real APNs. Se comprueban la firma/paquete real en Workerd, autorización y cambios concurrentes, preservación de conexiones y flujo nativo de solicitud. La firma de distribución y la prueba física con Wallet requieren el certificado privado configurado y el nuevo build instalado desde TestFlight.

Verificación local del23 de octubre: TypeScript correcto, build web/Worker correcto;12 casos focales de núcleo, API/almacén y Workerd aprobados. Dos recorridos de navegador de escritorio/móvil con54 comprobaciones aprobados, sin tráfico externo ni credenciales reales. Los dos fallos iniciales se corrigieron y se repitió únicamente cada caso afectado; se conservan los otros resultados. Evidencia local ignorada en `work/local/wallet-*.log` y `work/local/wallet-settings-browser/`.

La CI `apple-wallet` ejecuta únicamente las cuatro pruebas nativas nuevas, Release iPhone y compilación Mac por los archivos compartidos. Las otras suites ya comprobadas no se repiten. El antiguo fallo UI de navegación/PDF documentado en APPLE_PAID_SETUP.md queda fuera de este alcance y no se declara resuelto. Web/API publicado el23 de octubre en el Worker `jac-nomina`: versión `428f41cf-8e64-4d97-9925-7ed70769cdae`, despliegue `a76607a9-3798-4e5e-ba41-0b1e183d3d69` activo al100%,14 bindings/secretos conservados y ambos crons intactos. Sin migraciones, cargas de certificados, envíos ni datos reales de prueba. Fuente funcional `de65d2e` en main. CI Apple [39878134115](https://github.com/camiloidarraga98/nomina-jac/actions/runs/39878134115) sobre `de65d2e` terminó correctamente: cuatro pruebas Wallet ejecutadas, cero fallos, Release iPhone y compilación Mac correctos; ninguna repetición. El proyecto iPhone quedó en0.28.0(41), mismo Team/bundle y push habilitado. Camilo guardó la conexión privada; falta instalar ese nuevo build desde TestFlight y comprobar físicamente que Wallet lo añade. No confundir las pruebas sintéticas con un pase aceptado por Wallet o por una aerolínea.

Referencias: [identificadores y certificados Wallet](https://developer.apple.com/help/account/capabilities/create-wallet-identifiers-and-certificates), [intermedios WWDR](https://developer.apple.com/help/account/certificates/wwdr-intermediate-certificates), [PKI Apple](https://www.apple.com/certificateauthority/), [raíz publicada por Apple](https://support.apple.com/en-us/126047).

## Pull de Xcode y cambios locales

Durante el Pull, Xcode reaplicó un stash y dejó conflicto únicamente en `ios/JACNomina.xcodeproj/project.pbxproj`. Camilo guardó una copia del archivo en su Escritorio y restauró ese archivo desde HEAD, que ya era `de65d2e`. Confirmó estado sin conflictos y main/origin/main en esa versión. Se conservaron sus cambios locales de `ios/JACNomina/Info.plist` y su carpeta `project.xcworkspace`; no se borró el stash ni se hizo reset general. Estos cambios locales no están en el repositorio Cloud. Para futuros conflictos identificar primero los archivos y conservar una copia antes de elegir una versión.

## Validación de App Store Connect ·22 de octubre de2026 (Colombia)

La carga del build41 devolvió orientación genérica incompleta para multitarea iPad y aviso de configuración de documentos. La fuente Info.plist ya tenía las cuatro orientaciones `~ipad` y apertura in-place, pero Camilo conservaba ese archivo local modificado; no se inspeccionó el Archive privado y no se atribuye su contenido exacto a la fuente.

El build **0.28.0(42)** fija en Debug/Release las cuatro orientaciones genéricas, incluida PortraitUpsideDown, y `INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace=YES`. Conserva multitarea/iPad, importación de audio, Team, push y bundle. No activa UIDocumentBrowser ni exige pantalla completa. La CI `ios-bundle` ejecuta únicamente Release iOS y comprueba ambas configuraciones en el Info.plist real del `.app`, guardando `bundle-config.json`; omite simulador, suites ya aprobadas y Mac. CI [39879564577](https://github.com/camiloidarraga98/nomina-jac/actions/runs/39879564577), fuente `9d5c091`, terminó correctamente el22 de octubre a las19:44 de Colombia: único job Release iPhone ejecutado y aprobado; simulador y Mac omitidos. El Info.plist del producto real confirma0.28.0(42), cuatro orientaciones genéricas y cuatro de iPad, y apertura de documentos como booleano true. Sin repeticiones de suites anteriores, cambios web/API ni despliegue Cloudflare. Evidencia local ignorada en `work/local/ios-bundle-ci/`. La validación y subida firmadas de Apple siguen en el Mac de Camilo. Se requiere crear y subir un Archive nuevo; volver a subir el Archive41 conserva el error.

## Menú y datos de Wallet ·22 de octubre de2026 (Colombia)

Camilo pidió mover la acción desde Mostrar código al menú de cada pase e incluir pasajero, origen/destino, hora de vuelo, hora en sala y silla. Nuevo payload opcional `details` con esos seis campos y `legIndex` para selección de tramo; cada blanco explícito se conserva como ausencia. Se mantiene compatibilidad con clientes42 sin esos campos: ante varios tramos muestra una copia mínima, sin elegir una ruta/silla ambigua. El código original viaja intacto, las sugerencias nunca lo reconstruyen y los campos revisados no equivalen a validación de la aerolínea. El serial del mismo primer tramo conserva el existente; otros tramos tienen serial propio y editar datos no crea otro identificador. Certificados/conexiones existentes se conservan.

Modelos/extractor Swift compartidos registrados en iOS y Mac; extracción de un solo documento/página, con límites de bytes, píxeles, páginas y texto, fuera del hilo de interfaz. Verificación local focal:8 casos de parser/paquete firmado/Workerd y7 de creación/API privada aprobados, TypeScript y build correctos. No se repitieron las suites de credenciales ni otros módulos ya comprobados. CI Apple, fuente final y despliegue pendientes de cerrar esta entrega.
