# Versión nativa de JAC para Mac — 15 de octubre de 2026

La distribución posterior **1.1.0 (2)** incorpora CRM directo en la barra lateral, tabla de escritorio y Configuración reorganizada. Ver `docs/MAC_UX.md`. El registro de abajo corresponde a la entrega inicial 1.0.0.

La nueva app se desarrolla en esta misma carpeta del Mac y utiliza el servicio existente. No modifica producción, sus DB/BUCKET, secretos ni DNS. La web sigue publicada en el Site `appgprj_6aa0260b82a88191a47960614238350a`. No se crea otro Site y no se ejecuta un despliegue durante este trabajo.

## Fuente y alcance

`macos/JACMac.xcodeproj`, esquema `JACMac`, producto **JAC Music.app**, macOS 14+. Ventana SwiftUI de escritorio, barra lateral, atajos, vista previa Quick Look y adaptadores AppKit/AVFoundation. Se compilan directamente los archivos compartidos con el iPhone; no hay copias divergentes de cálculos o formularios.

| Área | Correspondencia en Mac |
|---|---|
| Nómina y comisión | Quincenas, shows/promocionales, honorarios, kilómetros, novedades, horas/salarios, gastos por show, liquidación y comisión revisable del servidor |
| Históricos y personal | Cierres, reapertura/corrección, archivo, condiciones, tarifas, conceptos, usuarios y permisos existentes |
| CRM | Shows, empresario/autocompletar, precios, abonos/recibos, creación de día único, preparación, presupuesto/rentabilidad, semana y documentos privados |
| Agenda | Calendario, próximos eventos, detalles y edición autorizada; caché y actualización compartidas con web/iPhone |
| Itinerarios y alertas | Slack y creación manual, adjuntos, confirmaciones por revisión, actualización, borrado confirmado y destinatarios |
| Pases | Privacidad por destinatario, hoy/mañana y su prioridad, próximos/historial, apertura directa del archivo, borrado autorizado |
| Gastos y OCR | Comprobantes, archivo/fotos/cámara, OCR local, revisión editable, borrador cifrado, envío/revisión/incorporación existentes |
| Documentos y correo | PDF/Excel/ZIP, guardar/compartir, impresión PDF, autorización Gmail y comandos de correo originales |
| Cuenta y offline | Llavero, sesión persistente opcional, contraseñas/activación, copia cifrada, permisos y revocación sin reutilizar copias denegadas |

La configuración inicial de Slack/APNs y Sheets conserva su flujo web. La app utiliza las conexiones existentes; Gmail y Agenda mantienen ASWebAuthenticationSession y validación estricta del nonce. Push sigue suspendido y su reactivación nativa en Mac requiere la configuración y firma correspondientes después de la aprobación de Apple.

## Archivos compartidos que cambian

Adaptadores de importación UIKit/AppKit, imagen por plataforma, colocación de herramientas y teclado, presentación de títulos, nombre de dispositivo y colores dinámicos. Los archivos temporales/caché usan permisos 0700/0600 en Mac y mantienen protección completa en iOS, además del cifrado AES-GCM existente. Los formularios permiten arrastrar archivos locales validados en Mac; la lectura de recibos incorpora el selector de archivo de escritorio. Las pruebas existentes se conservan y se compilan para ambos sistemas.

La configuración personal y el esquema del proyecto iPhone se comparan con la copia previa al trabajo; no se reemplazan. No se cambian las API, migraciones, dependencias, lockfile ni reglas financieras del servidor.

## Verificación

Comprobado en este Mac con Xcode 27 y macOS 27:

- **69 pruebas de Mac aprobadas**: las 66 pruebas compartidas, incluidas Vision real, autenticación/OAuth, concurrencia, CRM, permisos, privacidad de adjuntos y caché cifrada; tres pruebas específicas de restricciones de navegación, archivos del Finder y lectura local de recibos. Informe `work/local/mac-native-unit-final.xcresult`.
- **Cuatro recorridos UI Mac aprobados** con los márgenes finales: nómina/Agenda/CRM/PDF, protección de ventanas y hojas al desactivar, relanzamiento completo sin red con pase privado y Agenda, y permisos de consulta. Informe `work/local/mac-native-desktop-final.xcresult`; capturas en `outputs/jac-mac-*.png`.
- **iPhone**: 65 pruebas compartidas aprobadas y una comprobación conservada para cifrado físico, omitida por CoreSimulator. Privacidad de nómina/edición, CRM con abono/adjunto/rentabilidad/preparación, relanzamiento completo sin internet y OCR con concepto estilizado aprobados. Informes `work/local/mac-iphone-regression.xcresult` y `work/local/mac-iphone-crm-offline.xcresult`.
- **Release Mac** universal compilado para Apple Silicon e Intel; ejecución de pruebas en Apple Silicon. Firma local ad hoc. **Release iPhone** compilado sin firma, con push suspendido. Los logs están en `work/local/mac-native-package.log` y `work/local/mac-iphone-release.log`.
- Comparación binaria del proyecto y esquema personales del iPhone con `work/local/mac-baseline/`: se conservan exactamente. El motor de nómina, API y archivos web no cambian; se reutiliza su verificación anterior porque sus entradas no cambiaron.

Los informes de intentos anteriores también se conservan: primero se adaptó el ejecutor UI a firma local, después las consultas de controles y texto a la accesibilidad de macOS. No se omitieron comprobaciones para aprobar. Las repeticiones citadas arriba aprobaron. Xcode terminó las tres pruebas adicionales de iPhone correctamente; se cerró únicamente su recopilador `simctl diagnose` atascado después de terminar los tests, manteniendo resultados y capturas.

Las pruebas usan fixtures `.invalid`, archivos ficticios y servicios interceptados. Las pruebas de Llavero emplean entradas aleatorias de prueba y las eliminan; el anfitrión de pruebas de Mac también utiliza un cliente ficticio. No se crean/eliminan eventos reales, no se envían alertas/correos/PDF reales y no se alteran quincenas de producción. Cámara física, impresión en una impresora real y autorizaciones con cuentas reales quedan para el uso de Camilo.

## Intervención de Camilo

Iniciar sesión en la app con su cuenta habitual, dejar terminar la primera descarga y conceder Cámara si quiere fotografiar comprobantes. Las conexiones existentes no necesitan recrearse. Las autorizaciones reales y el uso de cámara física no se prueban con la cuenta de producción. La distribución notarizada a otros Macs y la activación de push dependen de la aprobación de Apple y de la firma correspondiente.
