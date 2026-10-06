// Explicit owner allowlist; sign-in alone never grants access to registrations.
export function isAdminEmail(email: string | null | undefined): boolean {
  return email?.trim().toLowerCase() === 'camilo@mac2you.co';
}
export function csvCell(value: unknown): string {
  let text = String(value ?? '');
  if (/^[\s]*[=+@-]/.test(text) || /^[\t\r\n]/.test(text)) text = "'" + text;
  return '"' + text.replaceAll('"', '""') + '"';
}
