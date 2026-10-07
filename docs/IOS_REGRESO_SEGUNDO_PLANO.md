# Regreso desde segundo plano — diagnóstico local

Comprobación en el Mac de Camilo, Xcode 27.0 (27A266a), iOS 27.0 (24A434), iPhone 18 Pro simulado. No se usaron datos ni conexiones reales y no se publicó ningún cambio.

## Causa y comparación controlada

Se revisó `work/local/ios-clean-simulator.xcresult` y su salida de aplicación extraída. La excepción es `NSInternalInconsistencyException` en `UINavigationBar.layoutSubviews`: el mismo `UINavigationItem`, con título «Nómina JAC», pertenece a una barra distinta de la que intenta distribuirlo. La pila pasa por el seguimiento del teclado, la recarga de vistas de entrada y la renuncia al primer respondedor.

Los tiempos de la salida sitúan la excepción al pulsar Home con el campo enfocado; `activate()` puede volver a abrir la app y mostrar el acceso, por lo que comprobar solo que vuelve a estar visible no basta. XCTest detecta el cierre al terminar el caso original. No hay dos `NavigationStack` anidadas en el acceso: su destino de activación tampoco crea otra. El mensaje de UIKit ofrece el anidamiento como posibilidad, no como diagnóstico de esta aplicación.

El alcance de `.privacySensitive()` era toda la jerarquía raíz, incluidas `NavigationStack` y `TabView`. En el simulador nuevo `7E6D630D-1C0E-4475-BC5D-6856CA267A68` se comparó la misma prueba original, sin eliminar comprobaciones:

| Variante | Resultado | Evidencia bajo `work/local/` |
| --- | --- | --- |
| Leer `scenePhase` solo en una vista de cubierta, conservando el marcado de la raíz | Mismo cierre, misma excepción | `ios-resume-cover.xcresult` y `ios-resume-cover-diagnostics/` |
| Retirar temporalmente solo el marcado de la raíz, con cubierta y navegación originales | Pasa | `ios-resume-redaction-diagnostic.xcresult` |
| Marcar el contenido mediante `jacSurface()`, conservando cubierta y navegación originales | Pasa | `ios-resume-content-privacy.xcresult` |

Esto identifica el marcado de los contenedores de navegación como desencadenante reproducible en este runtime. La duplicación de barras durante la preparación de la instantánea de privacidad es la explicación compatible con esa comparación y la pila; no se dispone del código interno de SwiftUI/UIKit para atribuirles una implementación concreta. El cambio experimental de `scenePhase` y la retirada temporal del marcado no forman parte de la solución final.

## Corrección

- `ios/JACNomina/JACNominaApp.swift`: el marcado de privacidad se aplica a las superficies de contenido, mediante `jacSurface()`, en lugar de envolver los contenedores de navegación. Formularios, listas y sus datos siguen marcados. La cubierta opaca y el logo al estar inactiva o en segundo plano se conservan. Un anclaje UIKit añade además una cubierta a la ventana de esa escena para quedar por encima de sus hojas. Usa notificaciones públicas de `UIScene`, retira la cubierta al activarse y limpia los observadores al desmontarse. Oculta el teclado al desactivarse para excluir sugerencias de la captura, sin vaciar campos ni cerrar editores. El anclaje invisible no intercepta pulsaciones mientras se usa la app.
- `ios/JACNomina/NoticesView.swift`: se marca directamente el contenido de la vista previa de itinerarios, que no usa `jacSurface()`.
- `ios/JACNominaUITests/LaunchTests.swift`: se mantienen todas las pruebas y comprobaciones originales. Se comprueba además la conservación del texto después de tres ciclos, la ruta de activación con contraseña enfocada y la cubierta del selector de apps con un borrador de nómina simulado.

No se cambian rutas, destinos, sesiones de Llavero, cálculo, permisos, APIs, datos, conexiones, proyecto/esquema de Xcode, identificador `co.jacmusic.nomina`, nombre ni logo JAC. No se desactiva el depurador ni se interceptan excepciones para aparentar éxito. Se conservan las 8 pruebas de interfaz anteriores y sus 47 comprobaciones originales; se añaden dos casos y más comprobaciones al caso de acceso.

La prueba de acceso no envía credenciales; se ejecuta sin sesión guardada. Las pruebas de nómina/Agenda/documentos/alertas usan `https://ui-fixture.example.invalid`, sesión en memoria y `URLProtocol`; los documentos son ficticios. Las pruebas unitarias usan sus servicios simulados y una cuenta temporal `.invalid` de Llavero.

## Verificación final

Las tres regresiones seleccionadas pasan en `ios-resume-regression.xcresult`. Se inspeccionó visualmente la captura `privacidad-en-selector-de-apps`: la tarjeta muestra solo fondo opaco y logo JAC. El caso de tres regresos conserva el texto; en una activación XCTest esperó 60 segundos por inactividad de la automatización, sin cierre ni pérdida de estado. Una muestra del proceso mostraba el bucle principal atendiendo eventos y consultas de accesibilidad, no un bloqueo de aplicación. No se redujeron esperas ni se omitieron aserciones.

La primera suite completa, `ios-resume-final.xcresult`, registra 33/33 aprobadas, sin fallos ni omisiones, en `934588DD-BEFE-4061-9950-9BACCC6F0487`. Xcode quedó esperando a su recolector `simctl diagnose` después de terminar los casos; se interrumpió únicamente ese recolector, se cerró `xcodebuild` con código 0 y `xcresulttool` confirmó el resumen. No se interrumpieron casos de prueba.

La comprobación adicional `ios-resume-modal-privacy.xcresult` pasó pero su captura mostró una limitación: una hoja queda por encima de la cubierta raíz SwiftUI. El texto del borrador estaba redactado, pero la fecha y sugerencias del teclado permanecían visibles. Esa evidencia motivó la cubierta de ventana descrita arriba. El arreglo del fallo ya había pasado independientemente antes de añadir el ocultamiento del teclado; no se usa este para esconder la causa de navegación.

`ios-resume-window-privacy.xcresult` pasó las tres regresiones con la cubierta de ventana. Se inspeccionaron las capturas de la pantalla principal y del borrador abierto como hoja: ambas muestran solo fondo opaco y logo, sin contenido ni teclado. Se conservan la contraseña de prueba, la ruta de activación y el borrador al regresar. Los tres ciclos de acceso terminaron sin la espera adicional de 60 segundos. Esta ejecución también necesitó cerrar únicamente su recolector automático `simctl diagnose` tras terminar los casos; `xcodebuild` salió con código 0. Las capturas y los resultados de los casos permanecen en el paquete.

**Resultado final:** `work/local/ios-resume-verified.xcresult`, en otro simulador nuevo `C57ED926-8D7F-408F-A91D-82C79F09E61F`, **JAC regreso - corrección verificada**. Compilación correcta, 23/23 pruebas unitarias y 10/10 de interfaz. `xcresulttool` confirma `Passed`, 33 aprobadas, 0 fallos, 0 omisiones y ninguna prueba marcada como fallo esperado. La firma es ad hoc local; no usa certificados Apple Developer.

```sh
xcodebuild -project ios/JACNomina.xcodeproj -scheme JACNomina \
  -destination 'platform=iOS Simulator,id=C57ED926-8D7F-408F-A91D-82C79F09E61F' \
  -derivedDataPath work/ios-build -resultBundlePath work/local/ios-resume-verified.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
```

El acceso conserva el texto después de tres ciclos de segundo plano y regreso (15 segundos para el caso completo). Las capturas finales de pantalla principal y hoja abierta muestran únicamente el fondo opaco y el logo JAC, sin teclado. La salida de aplicación extraída no contiene `NSInternalInconsistencyException` ni terminaciones por excepción sin capturar. Se conservan el log, el paquete, las capturas y los diagnósticos en `work/local/ios-resume-verified*`.

Al concluir los 33 casos, también hubo que interrumpir únicamente el recolector automático `simctl diagnose` que esperaba Xcode; `xcodebuild` salió con código 0 y después se leyó el resumen cerrado. No se cancelaron ni omitieron pruebas. El resultado conserva tres avisos `Invalid frame dimension (negative or non-finite)`; esa clase de aviso ya aparecía en el informe original (dos) y la suite anterior a la cubierta de ventana (tres). No se han ocultado ni se confunden con la excepción corregida.

La documentación de continuidad se actualiza en `ios/README.md`, `docs/PROJECT_CONTEXT.md` y `docs/MAC_LOCAL_VERIFICADO.md`. El ZIP nativo se genera desde el commit local, incluyendo la fuente y estas guías, sin estado del simulador, compilaciones, claves ni configuración personal de Xcode. La instalación física sigue pendiente de la aprobación legal de Apple Developer; no se ha probado en el iPhone ni se ha publicado en el Site.
