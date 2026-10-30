/** Visual identity from the approved JAC contract. Shared by generated documents. */
export const documentBrand = {
  navy: '22394B',
  ink: '1F2B34',
  cyan: '299ED3',
  pale: 'D6EFF9',
  line: 'D5E0E7',
  muted: '5B7184',
  canvas: 'F5F9FC',
  email: 'jacmusicestudios@gmail.com',
  phone: '+57 3125064091',
  address: 'Avenida 30 de agosto # 105-40 piso 2 · Pereira - Risaralda',
  social: '@jacmusicestudios / @jhonalexcastano',
  logoPath: '/document-jac-logo.png',
} as const;

export function documentDate(value: string) {
  return new Date(value).toLocaleString('es-CO', {
    timeZone: 'America/Bogota', day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit', hour12: true,
  });
}
