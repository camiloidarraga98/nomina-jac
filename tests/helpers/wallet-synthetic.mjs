// Synthetic PKI only. No Apple/customer certificates, identities or barcodes.
import assert from 'node:assert/strict';
import { createHash, generateKeyPair, verify } from 'node:crypto';
import { promisify } from 'node:util';
import forge from 'node-forge';
import { unzipSync } from 'fflate';

const keyPair = promisify(generateKeyPair);
let fixtureKeys;
async function keys() {
  fixtureKeys ??= Promise.all(Array.from({ length: 3 }, async () => {
    const pair = await keyPair('rsa', { modulusLength: 2048, publicExponent: 0x10001,
      publicKeyEncoding: { type: 'spki', format: 'pem' }, privateKeyEncoding: { type: 'pkcs1', format: 'pem' } });
    return { publicKey: forge.pki.publicKeyFromPem(pair.publicKey), privateKey: forge.pki.privateKeyFromPem(pair.privateKey) };
  }));
  return fixtureKeys;
}
const oid = { uid: '0.9.2342.19200300.100.1.1', ou: '2.5.4.11', o: '2.5.4.10', cn: '2.5.4.3' };
function makeCertificate(publicKey, subject, issuer, signingKey, serial, { validity = 'current', ca = false, certSign = false, digitalSignature = false } = {}) {
  const certificate = forge.pki.createCertificate();
  certificate.publicKey = publicKey; certificate.serialNumber = serial;
  certificate.validity.notBefore = new Date(Date.now() - 60_000);
  certificate.validity.notAfter = new Date(Date.now() + 86400_000);
  if (validity === 'expired') { certificate.validity.notBefore = new Date(Date.now() - 3 * 86400_000); certificate.validity.notAfter = new Date(Date.now() - 86400_000); }
  if (validity === 'future') certificate.validity.notBefore = new Date(Date.now() + 3600_000);
  certificate.setSubject(subject); certificate.setIssuer(issuer ?? subject);
  certificate.setExtensions([{ name: 'basicConstraints', critical: true, cA: ca },
    { name: 'keyUsage', critical: true, keyCertSign: certSign, cRLSign: certSign, digitalSignature }]);
  certificate.sign(signingKey, forge.md.sha256.create());
  return certificate;
}

export async function createWalletFixture(options = {}) {
  const [rootKey, intermediateKey, leafKey] = await keys();
  const teamId = options.teamId ?? 'TESTTEAM01', passTypeId = options.passTypeId ?? 'pass.co.jacmusic.fixture';
  const root = makeCertificate(rootKey.publicKey, [{ type: oid.cn, value: 'Synthetic Wallet Root - example.invalid' }], null, rootKey.privateKey, '01', { ca: true, certSign: true, validity: options.rootValidity });
  const wwdr = makeCertificate(intermediateKey.publicKey, [{ type: oid.o, value: options.wwdrOrganization ?? 'Apple Inc.' },
    { type: oid.cn, value: 'Apple Worldwide Developer Relations Certification Authority' }, { type: oid.ou, value: options.wwdrUnit ?? 'G4' }], root.subject.attributes,
  options.foreignIntermediateSignature ? leafKey.privateKey : rootKey.privateKey, '02', { ca: options.wwdrCA ?? true, certSign: options.wwdrCertSign ?? true, validity: options.wwdrValidity });
  const signer = makeCertificate(leafKey.publicKey, [{ type: oid.uid, value: options.signerPassTypeId ?? passTypeId },
    { type: oid.ou, value: options.signerTeamId ?? teamId }, { type: oid.cn, value: 'Synthetic Wallet signing fixture' }], wwdr.subject.attributes,
  options.foreignLeafSignature ? rootKey.privateKey : intermediateKey.privateKey, '03', { digitalSignature: options.signerDigitalSignature ?? true, ca: options.signerCA ?? false, validity: options.signerValidity });
  const password = 'synthetic-fixture-only';
  const pfx = forge.pkcs12.toPkcs12Asn1(options.privateKeyMismatch ? rootKey.privateKey : leafKey.privateKey, [signer, wwdr], password,
    { algorithm: '3des', count: options.iterations ?? 64, friendlyName: 'example.invalid fixture', generateLocalKeyId: true });
  const rootPem = forge.pki.certificateToPem(root), wwdrPem = forge.pki.certificateToPem(wwdr), signerPem = forge.pki.certificateToPem(signer);
  // Fixed widths and trailing blanks deliberately exercise exact BCBP retention.
  const message = 'M1FIXTURE/TRAVELLER    EDEMO123BOGMDEXX 0123 123Y001A0001 100   ';
  const barcode = { format: options.barcodeFormat ?? 'PKBarcodeFormatPDF417', message };
  return {
    rootPem, wwdrPem, signerPem, signer, wwdr, root,
    input: { teamId, passTypeId, p12: Buffer.from(forge.asn1.toDer(pfx).getBytes(), 'binary').toString('base64'), password,
      wwdr: Buffer.from(forge.asn1.toDer(forge.pki.certificateToAsn1(wwdr)).getBytes(), 'binary').toString('base64') },
    barcode,
    passInput: { serialNumber: 'synthetic-example-invalid-r1', description: 'JAC · Copia de pase ficticio', passenger: 'Fixture Traveller', origin: 'BOG', destination: 'MDE', travelDate: '2027-04-10', barcode },
  };
}

export function verifyWalletPackage(bytes, fixture) {
  const files = unzipSync(new Uint8Array(bytes));
  assert.deepEqual(Object.keys(files).sort(), ['icon.png', 'icon@2x.png', 'icon@3x.png', 'manifest.json', 'pass.json', 'signature']);
  const manifest = JSON.parse(Buffer.from(files['manifest.json']).toString('utf8'));
  for (const [name, expectedHash] of Object.entries(manifest)) assert.equal(createHash('sha1').update(files[name]).digest('hex'), expectedHash, `manifest hash: ${name}`);
  assert.deepEqual(Object.keys(manifest).sort(), ['icon.png', 'icon@2x.png', 'icon@3x.png', 'pass.json']);

  const cms = forge.asn1.fromDer(Buffer.from(files.signature).toString('binary'), true);
  const signedData = cms.value[1].value[0];
  const signerInfo = signedData.value.at(-1).value[0];
  const attrs = signerInfo.value[3];
  assert.equal(attrs.tagClass, forge.asn1.Class.CONTEXT_SPECIFIC);
  const digestAttribute = attrs.value.find(attribute => forge.asn1.derToOid(attribute.value[0].value) === forge.pki.oids.messageDigest);
  assert.equal(Buffer.from(digestAttribute.value[1].value[0].value, 'binary').toString('hex'), createHash('sha1').update(files['manifest.json']).digest('hex'));
  assert(attrs.value.some(attribute => forge.asn1.derToOid(attribute.value[0].value) === forge.pki.oids.signingTime));
  const signedAttributes = forge.asn1.create(forge.asn1.Class.UNIVERSAL, forge.asn1.Type.SET, true, attrs.value);
  assert(verify('sha1', Buffer.from(forge.asn1.toDer(signedAttributes).getBytes(), 'binary'), fixture.signerPem, Buffer.from(signerInfo.value[5].value, 'binary')), 'detached CMS signature verifies with fixture leaf certificate');
  assert.equal(signedData.value[2].value.length, 1, 'detached content is absent');
  assert.equal(signedData.value[3].value.length, 2, 'signer and WWDR certificates are embedded');
  const pass = JSON.parse(Buffer.from(files['pass.json']).toString('utf8'));
  return { files, manifest, pass };
}
