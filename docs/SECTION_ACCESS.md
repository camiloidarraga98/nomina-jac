# Accesos por sección y subida de administradores

16 de octubre de 2026. Continuidad del mismo Site y proyectos nativos.

## Uso

En **Configuración → Usuarios → Editar** se eligen por separado Nómina y quincenas, Agenda, Itinerarios, Alertas, Pases de abordar y Fotografía. Mi cuenta permanece disponible. **Crear carpetas y subir fotos o videos** requiere Fotografía y se elige aparte de la lectura. Las acciones de nómina siguen siendo independientes de su consulta. CRM, usuarios y conexiones conservan su restricción administrativa; conectar Drive sigue siendo exclusivo del propietario Camilo.

Camilo pidió que los administradores también puedan subir: Camilo y `jac` tienen lectura, creación de carpetas y subida por su rol de control total. No necesitan cambiar la conexión de Drive. Los pases siguen siendo privados de un destinatario, incluso entre administradores.

La cuenta real de Anderson no se modifica durante esta entrega: conserva Fotografía y subida hasta que Camilo guarde las secciones concretas que quiera darle. Cambiar permisos cierra las sesiones anteriores y exige iniciar sesión de nuevo; no se restablece la contraseña ni se envía una invitación automáticamente.

## Compatibilidad y autorización

Migración aditiva **0023_user_section_access.sql**: añade `payroll_users.section_access`, texto JSON nullable. No cambia datos existentes. NULL conserva los perfiles anteriores; el array explícito concede exclusivamente secciones conocidas. Un array vacío deja Mi cuenta. Valores desconocidos o no válidos se rechazan o se resuelven sin accesos. Subir requiere también leer Fotografía; CRM no puede concederse a un no administrador.

Los clientes modernos priorizan `sections`. Los indicadores históricos `mediaOnly`/`itinerariesOnly` permanecen en las respuestas para impedir que clientes antiguos descarguen nómina de cuentas restringidas. Un editor antiguo que omite `sections` conserva el acceso guardado. El perfil antiguo exclusivo de Fotografía sigue bloqueando los demás módulos hasta una edición explícita. Los administradores válidos reciben todas las secciones; se mantiene la defensa ante perfiles antiguos inconsistentes.

Las comprobaciones se aplican en las API, filtros de destinatarios/entregas y condiciones SQL de escritura. Sesión, revisión de usuario, pertenencia de documentos, conexión y concurrencia se revalidan alrededor de las operaciones. La página inicial vuelve a comprobar la identidad tras sus lecturas antes de serializar datos. Elegir Agenda permite consulta; no amplía la lista existente de personas que editan Calendar. Los gastos de viaje siguen ligados a Itinerarios y su revisión financiera sigue siendo administrativa.

Web, iPhone y Mac filtran navegación y contenido por la misma selección. La copia nativa elimina información/documentos del módulo revocado, conservando la sesión y el contenido permitido ante simples fallos de red. Una denegación 403 no activa el fallback. Los avisos y sus archivos se filtran por tipo; solo se pide o registra push si hay al menos un módulo de avisos permitido. APNs nativo continúa suspendido.

## Verificación

En este Mac con Node 24: TypeScript y build web; pruebas de permisos, nómina, autenticación, correo, móvil/OAuth, Agenda, CRM, navegación, Drive y avisos. Workerd local intercepta todas las salidas a servicios. Se conservaron las comprobaciones anteriores y se añadieron casos de módulos combinados, aislados, denegación concurrente, compatibilidad y subida administrativa. Informes `work/local/section-access-*.log` y `work/local/sections-*.log`.

La revisión visual local guardó Fotografía + subida + Itinerarios + Alertas en una cuenta `.invalid`, sin Nómina; captura `outputs/permisos-secciones-local.png`. No se guardaron permisos reales de Anderson ni se subieron fotos reales como prueba. Los resultados nativos se registran al completarse.

La revisión de integración añadió una revalidación final de `GET /api/notices` después de leer adjuntos/configuración/recibos. Se comprueban feed, detalle y pases con cambio de permisos y sesión eliminada durante esa espera; responden 403 sin datos ni importaciones pendientes. Las 54 pruebas de avisos pasaron en `sections-notifications-get-verified.log`; ocho pruebas de cliente/SW y siete Workerd de avisos pasaron. Nueve Workerd de Fotografía incluyen subida administrativa por bloques, con todos los servicios simulados. TypeScript final correcto y build exacto del Site aprobado. Los informes intermedios conservan los diagnósticos y no se retiraron aserciones para ocultar fallos.

## Publicación

Web **v70**, estado **succeeded**, Site existente `appgprj_6aa0260b82a88191a47960614238350a`. Fuente privada `04c9de1979b1881d3351e78118c39160fb436521`, despliegue `appgdep_6ad250ad9fb8819193fbb42035d7cef7`, env_set_revision 2. Archivo de 87 entradas, SHA256 `9b73e220a04e262ab40d94e056c2ec357bf17b103ef580caa4818e2085ac505e`. Flujo autenticado oficial de Sites con Node24; sin GitHub ni tareas Cloud. Migración 0023 solo añade la columna nullable, sin reconfigurar usuarios existentes. Se conservan dominio, audiencia, hosting.json, DB/BUCKET, secretos y conexiones. La fuente nativa sigue siendo local.
