const messages={
 browser_guard:'La autorización no corresponde a este navegador. Abre Agenda → Conexión y vuelve a conectar desde la misma pestaña.',
 web_session:'La sesión de JAC cambió durante la autorización. Inicia sesión y vuelve a conectar Agenda desde la misma pestaña.',
 authorization_used:'Esta autorización ya se utilizó. Vuelve a conectar Agenda.',
 expired:'La autorización venció. Abre Agenda → Conexión y vuelve a conectar.',
 session_revoked:'La sesión de JAC venció o fue revocada. Inicia sesión y vuelve a conectar Agenda.',
 configuration_changed:'La configuración de Google o de Agenda cambió durante la autorización. Actualiza Agenda y vuelve a conectar.',
 google_denied:'Google no concedió la autorización. Vuelve a conectar Agenda y acepta el acceso de lectura al calendario.',
 missing_code:'Google no devolvió una autorización válida. Vuelve a conectar Agenda.',
 google_token:'No pudimos completar la autorización con Google. Espera un momento y vuelve a conectar Agenda.',
 google_code_expired:'Google rechazó una autorización vencida o ya utilizada. Abre Agenda → Conexión y comienza una autorización nueva.',
 google_client:'Google rechazó la configuración de la aplicación. Revisa el cliente OAuth configurado en Correos antes de volver a conectar Agenda.',
 google_scope:'Google rechazó el permiso solicitado para Calendar. Revisa los permisos de Calendar en el proyecto de Google utilizado por JAC.',
 calendar_scope:'Google no concedió el permiso de lectura del calendario. Vuelve a conectar y marca la casilla que permite consultar tus calendarios antes de continuar.',
 missing_refresh_token:'Google no entregó el permiso para mantener Agenda conectada. Vuelve a conectar y acepta los permisos solicitados; conserva la conexión de Gmail.',
 account_verification:'No pudimos verificar la cuenta con Google. Espera un momento y vuelve a conectar Agenda.',
 wrong_account:'Google autorizó una cuenta distinta. Vuelve a conectar Agenda y elige jacmusicestudios@gmail.com.',
 connection_storage:'No pudimos guardar la conexión de Agenda. Actualiza la página y vuelve a conectar.',
} as const;
export type CalendarOAuthReason=keyof typeof messages;
export function calendarOAuthMessage(reason:string|null|undefined){
 return reason&&Object.hasOwn(messages,reason)?messages[reason as CalendarOAuthReason]:'No se pudo completar la conexión de Agenda. Abre Conexión y vuelve a intentarlo.';
}
