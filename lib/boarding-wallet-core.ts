import { Buffer } from 'node:buffer';
import forge from 'node-forge';
import { PKPass, PassType } from 'passkit-generator';
import { NoticeFailure } from './notifications-core';
import { validBoardingDate } from './boarding-passes';
import { walletIconBase64 } from './boarding-wallet-assets';
import { APPLE_WALLET_ROOT_CA_PEM } from './boarding-wallet-trust';

export type WalletCredentials = {
  teamId: string;
  passTypeId: string;
  certificate: string;
  privateKey: string;
  wwdr: string;
  expiresAt: string;
};
export type WalletBarcode = {
  format: 'PKBarcodeFormatQR' | 'PKBarcodeFormatPDF417' | 'PKBarcodeFormatAztec';
  message: string;
};
export type WalletCredentialInput = {
  teamId: string;
  passTypeId: string;
  p12: string;
  password: string;
  wwdr: string;
};
export type BoardingWalletInput = {
  serialNumber: string;
  description: string;
  passenger?: string;
  origin?: string;
  destination?: string;
  departureTime?: string;
  boardingTime?: string;
  seat?: string;
  travelDate?: string;
  barcode: WalletBarcode;
};

export const MAX_WALLET_P12_BYTES = 64 * 1024;
export const MAX_WALLET_WWDR_BYTES = 16 * 1024;
export const MAX_WALLET_PASSWORD_LENGTH = 256;
const MAX_P12_ITERATIONS = 100_000;
const UID = '0.9.2342.19200300.100.1.1';
const OU = '2.5.4.11';
const O = '2.5.4.10';
const CN = '2.5.4.3';

function failure(message: string): never { throw new NoticeFailure(message); }
function identifiers(teamId: unknown, passTypeId: unknown) {
  if (typeof teamId !== 'string' || !/^[A-Z0-9]{10}$/.test(teamId)) failure('El Team ID debe tener 10 letras mayúsculas o números.');
  if (typeof passTypeId !== 'string' || passTypeId.length > 180 || !/^pass\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$/.test(passTypeId)) failure('El Pass Type ID no es válido.');
}
function base64Bytes(value: unknown, max: number, message: string) {
  if (typeof value !== 'string' || !value || value.length > Math.ceil(max / 3) * 4 || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) failure(message);
  const bytes = Buffer.from(value, 'base64');
  if (!bytes.length || bytes.length > max || bytes.toString('base64') !== value) failure(message);
  return bytes;
}
function certificate(value: unknown, max: number): forge.pki.Certificate {
  if (typeof value !== 'string') failure('El certificado no es válido.');
  if (value.startsWith('-----BEGIN CERTIFICATE-----')) {
    if (value.length > Math.ceil(max / 3) * 4 + 200 || !/^-----BEGIN CERTIFICATE-----\r?\n[A-Za-z0-9+/=\r\n]+\r?\n-----END CERTIFICATE-----\s*$/.test(value)) failure('El certificado no es válido.');
    return forge.pki.certificateFromPem(value, true);
  }
  const bytes = base64Bytes(value, max, 'El certificado no es válido.');
  // The upload form sends base64 for both .cer and .pem files.
  if (bytes.subarray(0, 27).toString('ascii') === '-----BEGIN CERTIFICATE-----') return certificate(bytes.toString('ascii'), max);
  return forge.pki.certificateFromAsn1(forge.asn1.fromDer(bytes.toString('binary'), true), true);
}
function subjectIs(cert: forge.pki.Certificate, oid: string, expected: string) {
  const attributes = cert.subject.attributes.filter(attribute => attribute.type === oid);
  return attributes.length === 1 && attributes[0].value === expected;
}
function currentCertificate(cert: forge.pki.Certificate, now: number) {
  if (!Number.isFinite(cert.validity.notBefore.valueOf()) || !Number.isFinite(cert.validity.notAfter.valueOf()) || cert.validity.notBefore.valueOf() > now || cert.validity.notAfter.valueOf() <= now) failure('El certificado de Wallet ha vencido o todavía no está vigente.');
}
function certificateIsCA(cert: forge.pki.Certificate) {
  return (cert.getExtension('basicConstraints') as { cA?: boolean } | null)?.cA === true && (cert.getExtension('keyUsage') as { keyCertSign?: boolean } | null)?.keyCertSign === true;
}
function verifyCertificate(issuer: forge.pki.Certificate, subject: forge.pki.Certificate) {
  try { return issuer.verify(subject); } catch { return false; }
}
function rsaPublicKey(cert: forge.pki.Certificate) {
  const key = cert.publicKey;
  if (!key || !('n' in key) || !('e' in key) || key.n.bitLength() < 2048 || key.n.bitLength() > 4096) failure('El certificado de Wallet debe usar una clave RSA válida.');
  return key as forge.pki.rsa.PublicKey;
}
function matchingKey(key: forge.pki.rsa.PrivateKey, cert: forge.pki.Certificate) {
  const publicKey = rsaPublicKey(cert);
  return key?.n?.compareTo(publicKey.n) === 0 && key?.e?.compareTo(publicKey.e) === 0;
}

// Inspect unencrypted PKCS#12 parameters before Forge performs password derivation.
// The archive size alone does not bound malicious PBKDF iteration counts.
function boundDerivation(asn1: forge.asn1.Asn1, depth = 0) {
  if (depth > 24) failure('El archivo .p12 no es válido.');
  if (!Array.isArray(asn1.value)) return;
  const values = asn1.value;
  if (values[0]?.type === forge.asn1.Type.OID && typeof values[0].value === 'string') {
    const oid = forge.asn1.derToOid(values[0].value);
    if (oid === '1.2.840.113549.1.5.12' || oid.startsWith('1.2.840.113549.1.12.1.')) {
      const parameters = values[1];
      const iteration = Array.isArray(parameters?.value) ? parameters.value[1] : null;
      const salt = Array.isArray(parameters?.value) ? parameters.value[0] : null;
      if (!salt || salt.type !== forge.asn1.Type.OCTETSTRING || typeof salt.value !== 'string' || salt.value.length > 64) failure('El archivo .p12 no es válido.');
      if (!iteration || iteration.type !== forge.asn1.Type.INTEGER || typeof iteration.value !== 'string' || iteration.value.length > 4) failure('El archivo .p12 no es válido.');
      const count = forge.asn1.derToInteger(iteration.value);
      if (count < 1 || count > MAX_P12_ITERATIONS) failure('Exporta el .p12 con un máximo de 100.000 iteraciones.');
    }
  }
  for (const child of values) {
    boundDerivation(child, depth + 1);
    // AuthenticatedSafe/EncryptedPrivateKeyInfo are wrapped in OCTET STRINGs.
    if (child.type === forge.asn1.Type.OCTETSTRING && typeof child.value === 'string' && child.value.charCodeAt(0) === 0x30) {
      try { boundDerivation(forge.asn1.fromDer(child.value, true), depth + 1); } catch (error) { if (error instanceof NoticeFailure) throw error; }
    }
  }
}
function asn1Values(value: forge.asn1.Asn1 | undefined): forge.asn1.Asn1[] {
  if (!value || !Array.isArray(value.value)) failure('El archivo .p12 no es válido.');
  return value.value;
}
function asn1Octets(value: forge.asn1.Asn1 | undefined): string {
  if (!value) failure('El archivo .p12 no es válido.');
  if (typeof value.value === 'string') return value.value;
  return value.value.map(asn1Octets).join('');
}
function boundEncryptedSafes(archive: forge.asn1.Asn1, password: string) {
  const authInfo = asn1Values(asn1Values(archive)[1]);
  const authData = asn1Values(authInfo[1])[0];
  const safes = asn1Values(forge.asn1.fromDer(asn1Octets(authData), true));
  if (safes.length > 8) failure('El archivo .p12 contiene demasiados contenedores.');
  for (const safe of safes) {
    const info = asn1Values(safe);
    if (typeof info[0]?.value !== 'string' || forge.asn1.derToOid(info[0].value) !== forge.pki.oids.encryptedData) continue;
    const encryptedData = asn1Values(asn1Values(info[1])[0]);
    const encryptedContentInfo = asn1Values(encryptedData[1]);
    const algorithm = asn1Values(encryptedContentInfo[1]);
    if (typeof algorithm[0]?.value !== 'string' || !algorithm[1]) failure('El archivo .p12 no es válido.');
    // A key bag may itself be password-encrypted inside this encrypted safe.
    // Bound the inner KDF before the complete PKCS#12 parser can execute it.
    const pbe = forge.pki as typeof forge.pki & { pbe: { getCipher(oid: string, parameters: forge.asn1.Asn1, password: string): forge.cipher.BlockCipher } };
    const cipher = pbe.pbe.getCipher(forge.asn1.derToOid(algorithm[0].value), algorithm[1], password);
    cipher.update(forge.util.createBuffer(asn1Octets(encryptedContentInfo[2])));
    if (!cipher.finish()) failure('No se pudo abrir el .p12. Revisa el archivo y su contraseña.');
    const decoded = cipher.output.getBytes();
    if (decoded.length > MAX_WALLET_P12_BYTES) failure('El archivo .p12 no es válido.');
    const contents = forge.asn1.fromDer(decoded, true);
    if (asn1Values(contents).length > 16) failure('El archivo .p12 contiene demasiados elementos.');
    boundDerivation(contents);
  }
}
function p12Certificates(input: WalletCredentialInput) {
  if (typeof input.password !== 'string' || input.password.length > MAX_WALLET_PASSWORD_LENGTH) failure('La contraseña del .p12 supera el límite permitido.');
  const archive = forge.asn1.fromDer(base64Bytes(input.p12, MAX_WALLET_P12_BYTES, 'El archivo .p12 debe ser válido y pesar como máximo 64 KB.').toString('binary'), true);
  boundDerivation(archive);
  const contents = Array.isArray(archive.value) ? archive.value : [];
  const mac = contents[2];
  if (mac && Array.isArray(mac.value) && (typeof mac.value[1]?.value !== 'string' || mac.value[1].value.length > 64)) failure('El archivo .p12 no es válido.');
  if (mac && Array.isArray(mac.value) && mac.value[2]) {
    const iteration = mac.value[2];
    if (iteration.type !== forge.asn1.Type.INTEGER || typeof iteration.value !== 'string' || iteration.value.length > 4) failure('El archivo .p12 no es válido.');
    const count = forge.asn1.derToInteger(iteration.value);
    if (count < 1 || count > MAX_P12_ITERATIONS) failure('Exporta el .p12 con un máximo de 100.000 iteraciones.');
  }
  boundEncryptedSafes(archive, input.password);
  const pfx = forge.pkcs12.pkcs12FromAsn1(archive, true, input.password);
  const bags = pfx.safeContents.flatMap(content => content.safeBags);
  const keys = bags.flatMap(bag => bag.key ? [bag.key] : []);
  const certs = bags.flatMap(bag => bag.cert ? [bag.cert] : []);
  if (keys.length !== 1 || !keys[0]?.n || !keys[0]?.e || !keys[0]?.d || !keys[0]?.p || !keys[0]?.q) failure('El .p12 debe contener un certificado de pase y su única clave privada.');
  const matches = certs.filter(cert => matchingKey(keys[0], cert));
  if (matches.length !== 1) failure('El .p12 no contiene un certificado y una clave privada que coincidan.');
  return { key: keys[0], signer: matches[0] };
}

export function validateWalletBarcode(value: unknown): WalletBarcode {
  const barcode = value as Partial<WalletBarcode> | null;
  if (!barcode || !['PKBarcodeFormatQR', 'PKBarcodeFormatPDF417', 'PKBarcodeFormatAztec'].includes(barcode.format ?? '') || typeof barcode.message !== 'string' || barcode.message.length < 60 || barcode.message.length > 4096 || !/^M[1-4]/.test(barcode.message) || /[^\x20-\x7e]/.test(barcode.message)) failure('No se detectó un código IATA de embarque compatible. Abre el documento original.');
  // Whitespace is part of BCBP. Do not trim, decode, normalize or rebuild it.
  return { format: barcode.format as WalletBarcode['format'], message: barcode.message };
}
function display(value: unknown, label: string, max: number, optional = false) {
  if (optional && value === undefined) return undefined;
  if (typeof value !== 'string' || !value.trim() || value.length > max || /\p{C}/u.test(value)) failure(`El campo ${label} no es válido.`);
  return value;
}

/** Pure PKI boundary. Production exports below always use Apple's fixed trust anchor.
 * The factory permits synthetic certificate chains in isolated tests; HTTP/store
 * input must never control this argument or expose an alternative trust root.
 */
export function createWalletCrypto(trustedRootPem: string) {
  const root = certificate(trustedRootPem, MAX_WALLET_WWDR_BYTES);
  if (!certificateIsCA(root) || !verifyCertificate(root, root)) throw new Error('Invalid Wallet trust anchor.');

  function validateSigner(teamId: string, passTypeId: string, signer: forge.pki.Certificate, key: forge.pki.rsa.PrivateKey, wwdr: forge.pki.Certificate) {
    identifiers(teamId, passTypeId);
    const now = Date.now();
    currentCertificate(root, now); currentCertificate(wwdr, now); currentCertificate(signer, now);
    if (!subjectIs(wwdr, O, 'Apple Inc.') || !subjectIs(wwdr, CN, 'Apple Worldwide Developer Relations Certification Authority') || !subjectIs(wwdr, OU, 'G4') || !certificateIsCA(wwdr) || !verifyCertificate(root, wwdr)) failure('El intermedio debe ser el certificado WWDR G4 original de Apple.');
    if (!subjectIs(signer, UID, passTypeId) || !subjectIs(signer, OU, teamId)) failure('El certificado de pase no corresponde al Team ID y Pass Type ID indicados.');
    if ((signer.getExtension('basicConstraints') as { cA?: boolean } | null)?.cA === true || (signer.getExtension('keyUsage') as { digitalSignature?: boolean } | null)?.digitalSignature !== true || !verifyCertificate(wwdr, signer)) failure('El certificado de pase no está emitido por WWDR G4 de Apple.');
    if (!matchingKey(key, signer)) failure('La clave privada no corresponde al certificado de pase.');
    const digest = forge.md.sha256.create().update('JAC Wallet signing key validation', 'utf8');
    if (!rsaPublicKey(signer).verify(digest.digest().getBytes(), key.sign(digest))) failure('La clave privada de Wallet no es válida.');
    return new Date(Math.min(signer.validity.notAfter.valueOf(), wwdr.validity.notAfter.valueOf(), root.validity.notAfter.valueOf())).toISOString();
  }

  async function normalizeWalletCredentials(input: WalletCredentialInput): Promise<WalletCredentials> {
    try {
      identifiers(input?.teamId, input?.passTypeId);
      const { key, signer } = p12Certificates(input);
      const wwdr = certificate(input.wwdr, MAX_WALLET_WWDR_BYTES);
      const expiresAt = validateSigner(input.teamId, input.passTypeId, signer, key, wwdr);
      return { teamId: input.teamId, passTypeId: input.passTypeId, certificate: forge.pki.certificateToPem(signer), privateKey: forge.pki.privateKeyToPem(key), wwdr: forge.pki.certificateToPem(wwdr), expiresAt };
    } catch (error) {
      if (error instanceof NoticeFailure) throw error;
      failure('No se pudo abrir el .p12. Revisa el archivo y su contraseña.');
    }
  }

  async function buildBoardingWalletPass(credentials: WalletCredentials, input: BoardingWalletInput): Promise<Uint8Array> {
    try {
      identifiers(credentials?.teamId, credentials?.passTypeId);
      const signer = certificate(credentials.certificate, MAX_WALLET_WWDR_BYTES), wwdr = certificate(credentials.wwdr, MAX_WALLET_WWDR_BYTES);
      if (typeof credentials.privateKey !== 'string' || credentials.privateKey.length > 16 * 1024) failure('La clave privada de Wallet no es válida.');
      const key = forge.pki.privateKeyFromPem(credentials.privateKey);
      validateSigner(credentials.teamId, credentials.passTypeId, signer, key, wwdr);
      const barcode = validateWalletBarcode(input?.barcode);
      if (typeof input.serialNumber !== 'string' || !/^[A-Za-z0-9_-]{1,180}$/.test(input.serialNumber)) failure('El identificador del pase no es válido.');
      const description = display(input.description, 'descripción', 200)!;
      const passenger = display(input.passenger, 'pasajero', 120, true);
      const origin = display(input.origin, 'origen', 100, true), destination = display(input.destination, 'destino', 100, true);
      const departureTime = display(input.departureTime, 'hora del vuelo', 5, true), boardingTime = display(input.boardingTime, 'hora en sala', 5, true);
      for (const time of [departureTime, boardingTime]) if (time !== undefined && !/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(time)) failure('Las horas del pase deben tener formato HH:mm.');
      const seat = display(input.seat, 'silla', 6, true);
      if (seat !== undefined && !/^(?=.*[1-9A-Z])[A-Z0-9]{1,6}$/.test(seat)) failure('La silla del pase no es válida.');
      if (input.travelDate !== undefined && (typeof input.travelDate !== 'string' || !validBoardingDate(input.travelDate))) failure('La fecha del pase no es válida.');
      const pass = new PKPass(Object.fromEntries(Object.entries(walletIconBase64).map(([name, data]) => [name, Buffer.from(data, 'base64')])), {
        signerCert: credentials.certificate, signerKey: credentials.privateKey, wwdr: credentials.wwdr,
      }, {
        formatVersion: 1, serialNumber: input.serialNumber, passTypeIdentifier: credentials.passTypeId, teamIdentifier: credentials.teamId,
        organizationName: 'JAC', description, logoText: 'JAC · Copia de tu pase', sharingProhibited: true,
        backgroundColor: 'rgb(8, 48, 70)', foregroundColor: 'rgb(255, 255, 255)', labelColor: 'rgb(183, 225, 244)',
      });
      const boarding = new PassType('boardingPass');
      boarding.transitType = 'PKTransitTypeAir';
      if (origin) boarding.primaryFields.push({ key: 'origin', label: 'ORIGEN', value: origin });
      if (destination) boarding.primaryFields.push({ key: 'destination', label: 'DESTINO', value: destination });
      if (seat) boarding.headerFields.push({ key: 'seat', label: 'SILLA', value: seat });
      if (passenger) boarding.secondaryFields.push({ key: 'passenger', label: 'PASAJERO', value: passenger });
      // These are civil display times read/reviewed from the original. Do not
      // assign a timezone or turn an unzoned time into a fabricated Date.
      if (departureTime) boarding.auxiliaryFields.push({ key: 'departureTime', label: 'HORA DEL VUELO', value: departureTime });
      if (boardingTime) boarding.auxiliaryFields.push({ key: 'boardingTime', label: 'EN SALA', value: boardingTime });
      if (input.travelDate) boarding.auxiliaryFields.push({ key: 'travelDate', label: 'FECHA', value: input.travelDate });
      boarding.backFields.push({ key: 'original', label: 'Copia en JAC', value: 'Código copiado del documento original de la aerolínea. JAC no emite ni actualiza el pase de abordar. Conserva el documento original y consulta los cambios con la aerolínea.' });
      pass.types.push(boarding);
      pass.setBarcodes({ ...barcode, messageEncoding: 'iso-8859-1' });
      const bytes = pass.getAsBuffer();
      if (!bytes.length || bytes.length > 1024 * 1024) failure('No se pudo preparar el pase de Wallet.');
      return new Uint8Array(bytes);
    } catch (error) {
      if (error instanceof NoticeFailure) throw error;
      failure('No se pudo firmar el pase de Wallet. Revisa la conexión de Wallet e inténtalo de nuevo.');
    }
  }
  return { normalizeWalletCredentials, buildBoardingWalletPass };
}

const appleWallet = createWalletCrypto(APPLE_WALLET_ROOT_CA_PEM);
export const normalizeWalletCredentials = appleWallet.normalizeWalletCredentials;
export const buildBoardingWalletPass = appleWallet.buildBoardingWalletPass;
