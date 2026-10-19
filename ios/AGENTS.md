# Firma persistente solicitada por Camilo

Camilo pidió conservar «Camilo Idarraga» en Signing → Team después de cada pull y proporcionó expresamente el Team ID `AYHVYN8BJF` para guardarlo en GitHub. Mantener `DEVELOPMENT_TEAM = AYHVYN8BJF` en las configuraciones de proyecto Debug y Release de `JACNomina.xcodeproj`; app, pruebas unitarias y UI lo heredan. Esta petición posterior sustituye, únicamente para este identificador, las instrucciones históricas de omitir el Team personal del proyecto portable. No retirarlo al actualizar/exportar fuentes.

El identificador no contiene certificados ni claves. Certificados, claves privadas, perfiles y cuentas Apple permanecen en el Mac/Llavero; no incorporarlos al repositorio. Conservar bundle IDs, firma automática, entitlements y `JAC_PUSH_ENABLED=NO`. La firma ad hoc del Mac conserva su configuración independiente. CI sigue usando sus overrides de prueba, sin certificados personales.

Preferencia vigente: agrupar cambios y verificar al final solo lo modificado y lo directamente afectado, reutilizando resultados válidos. Un ajuste exclusivo del identificador de firma requiere revisar configuración/herencia; no repetir pruebas funcionales ni compilaciones de entradas de aplicación sin cambios. La resolución real de la cuenta y la firma del dispositivo se comprueban en el Xcode de Camilo, no en Linux.
