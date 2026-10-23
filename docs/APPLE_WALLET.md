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

El formulario solo devuelve estado, versión, identificador y vencimiento. La contraseña y el PKCS#12 se usan para normalizar el certificado/clave; no se persisten. La clave normalizada se cifra en el almacén de conexiones ya existente, conservando APNs, Slack y Web Push. No se necesitan nuevas tablas, bindings o secretos Cloudflare. Guardar con una versión antigua devuelve conflicto y exige releer; nunca reintenta la escritura automáticamente.

La validación comprueba la clave correspondiente, identificador y Team del certificado, vencimiento y cadena de firma WWDR G4 → raíz Apple. La raíz pública se fija en el código; su SHA256 DER es `b0b1730ecbc7ff4505142c49f1295e6eda6bcaed7e2c68c5be91b5a11001f024`, publicada por Apple. No se descarga una raíz en cada petición ni se admite una raíz enviada por el usuario.

## Uso en iPhone

En **Pases → pase propio → Mostrar código**, JAC conserva el código original extraído del PDF/imagen y la selección explícita cuando hay varios. Cuando Wallet está conectado, el código es compatible y el dispositivo permite añadir pases, ofrece **Añadir a Apple Wallet** mediante el controlador nativo de Apple. Se necesita la nueva compilación de JAC: el build40 instalado anteriormente no incluye esta integración.

Solo se trasladan QR, PDF417 o Aztec cuyo contenido leído sea ASCII exacto y tenga estructura inicial IATA BCBP compatible. Data Matrix, mensajes binarios/no ASCII, URL y códigos desconocidos conservan el visor y el documento original. No se inventa un código ni se transforma uno desconocido para hacerlo compatible.

La lectura del código ocurre con Vision en el dispositivo. La API verifica el destinatario, archivo privado, revisión y SHA256 del mismo original analizado; **no vuelve a decodificar independientemente el código desde el PDF**. Este es el límite de confianza del cliente autenticado. El mensaje exacto viaja al servidor y al pase sin recortes ni normalización de espacios.

El servidor firma un `.pkpass` en memoria, sin URL pública ni copia adicional persistente. Se limita el original a10MiB y el paquete a1MiB. Revalida sesión/permiso, destinatario, revisión/adjunto y versión de la conexión antes de liberar el resultado; el cliente descarta resultados tardíos de otra sesión o revisión. La respuesta privada no se cachea. No existe fallback de generación offline ni tras un403.

El pase es una **copia firmada por JAC**, no un documento emitido por la aerolínea. No garantiza aceptación en el aeropuerto; conservar siempre el original. Se usan únicamente metadatos disponibles, sin fabricar número de vuelo, puerta u hora. Wallet conserva sus propias copias: cerrar sesión, borrar el original o revocar permisos en JAC no elimina un pase ya añadido a Wallet. Esta primera integración no registra actualizaciones automáticas de pases ni su servicio APNs.

Presentar `PKAddPassesViewController` no requiere habilitar gestión de `PKPassLibrary`, App Groups o Associated Domains. iPad/Mac conservan sus funciones existentes si Wallet no está disponible. La conexión web administra el firmante; no convierte Mostrar código en un visor web nuevo.

## Verificación y publicación

Pruebas focales con cadenas/certificados sintéticos, originales ficticios y D1/R2/Workerd desechables. Sin claves personales, pases de pasajeros, servicios de aerolíneas ni envío real APNs. Se comprueban la firma/paquete real en Workerd, autorización y cambios concurrentes, preservación de conexiones y flujo nativo de solicitud. La firma de distribución y la prueba física con Wallet requieren el certificado privado configurado y el nuevo build instalado desde TestFlight.

Verificación local del23 de octubre: TypeScript correcto, build web/Worker correcto;12 casos focales de núcleo, API/almacén y Workerd aprobados. Dos recorridos de navegador de escritorio/móvil con54 comprobaciones aprobados, sin tráfico externo ni credenciales reales. Los dos fallos iniciales se corrigieron y se repitió únicamente cada caso afectado; se conservan los otros resultados. Evidencia local ignorada en `work/local/wallet-*.log` y `work/local/wallet-settings-browser/`.

La CI `apple-wallet` ejecuta únicamente las cuatro pruebas nativas nuevas, Release iPhone y compilación Mac por los archivos compartidos. Las otras suites ya comprobadas no se repiten. Publicación, resultado Apple y activación física pendientes de cerrar esta entrega. No confundir las pruebas sintéticas con un pase aceptado por Wallet o por una aerolínea.

Referencias: [identificadores y certificados Wallet](https://developer.apple.com/help/account/capabilities/create-wallet-identifiers-and-certificates), [intermedios WWDR](https://developer.apple.com/help/account/certificates/wwdr-intermediate-certificates), [PKI Apple](https://www.apple.com/certificateauthority/), [raíz publicada por Apple](https://support.apple.com/en-us/126047).
